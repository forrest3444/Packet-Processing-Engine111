`timescale 1ns/1ps

// Back half of the PPE pipeline.
//
// The 16-entry reorder buffer (ROB) accepts allocations in input order, accepts
// up to four FE completions in any order, and retires only a consecutive done
// prefix beginning at head_ptr.  This is what restores program/packet order.
// Retired results are also kept in eight history banks for dependency fallback.
module ppe_reorder #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,
    // Raw input valids are used only to calculate global backpressure.
    input                       in_valid0,
    input                       in_valid1,
    input                       in_valid2,
    input                       in_valid3,
    output                      bkps,

    // Ordered metadata allocation from dispatch, with combinational ROB IDs
    // returned to dispatch for the same accepted input cycle.
    input                       alloc_valid0,
    input      [4:0]            alloc_seq_tag0,
    input      [2:0]            alloc_seq_residue0,
    output     [3:0]            alloc_rob_id0,
    input                       alloc_valid1,
    input      [4:0]            alloc_seq_tag1,
    input      [2:0]            alloc_seq_residue1,
    output     [3:0]            alloc_rob_id1,
    input                       alloc_valid2,
    input      [4:0]            alloc_seq_tag2,
    input      [2:0]            alloc_seq_residue2,
    output     [3:0]            alloc_rob_id2,
    input                       alloc_valid3,
    input      [4:0]            alloc_seq_tag3,
    input      [2:0]            alloc_seq_residue3,
    output     [3:0]            alloc_rob_id3,

    // Single authoritative dependency lookup requested by dispatch.
    input                       fallback_valid,
    input      [3:0]            fallback_rob_id,
    input      [4:0]            fallback_seq_tag,
    input      [2:0]            fallback_residue,
    output                      fallback_ready,
    output     [PACKET_W-1:0]   fallback_data,

    // Up to four independent, out-of-order FE completion events.
    input                       wb_valid0,
    input      [3:0]            wb_rob_id0,
    input      [4:0]            wb_seq_tag0,
    input      [PACKET_W-1:0]   wb_data0,
    input                       wb_valid1,
    input      [3:0]            wb_rob_id1,
    input      [4:0]            wb_seq_tag1,
    input      [PACKET_W-1:0]   wb_data1,
    input                       wb_valid2,
    input      [3:0]            wb_rob_id2,
    input      [4:0]            wb_seq_tag2,
    input      [PACKET_W-1:0]   wb_data2,
    input                       wb_valid3,
    input      [3:0]            wb_rob_id3,
    input      [4:0]            wb_seq_tag3,
    input      [PACKET_W-1:0]   wb_data3,

    // Registered, in-order output lanes.  start_lane rotates the first lane so
    // consecutive retirement batches do not always begin at lane 0.
    output reg                  out_valid0,
    output reg [PACKET_W-1:0]   out_packet0,
    output reg                  out_valid1,
    output reg [PACKET_W-1:0]   out_packet1,
    output reg                  out_valid2,
    output reg [PACKET_W-1:0]   out_packet2,
    output reg                  out_valid3,
    output reg [PACKET_W-1:0]   out_packet3
);

    // ROB metadata is written at allocation.  rob_data becomes meaningful only
    // after a tag-checked FE writeback sets rob_result_valid.
    reg                       rob_valid [0:15];
    reg [4:0]                 rob_seq_tag [0:15];
    reg [2:0]                 rob_seq_residue [0:15];
    reg                       rob_result_valid [0:15];
    reg [PACKET_W-1:0]        rob_data [0:15];

    // Authoritative history for already retired packets.  Bank selection uses
    // seq_tag[2:0], while result_seq_tag rejects stale data after wraparound.
    reg                       result_valid [0:7];
    reg [4:0]                 result_seq_tag [0:7];
    reg [PACKET_W-1:0]        result_data [0:7];

    reg [3:0]                 head_ptr;
    reg [3:0]                 tail_ptr;
    reg [4:0]                 occupancy;
    reg [1:0]                 start_lane;

    wire [2:0] input_count;
    wire [2:0] alloc_count;
    wire [4:0] free_count;
    wire [4:0] available_count;
    wire [3:0] head_idx0;
    wire [3:0] head_idx1;
    wire [3:0] head_idx2;
    wire [3:0] head_idx3;
    wire       done0;
    wire       done1;
    wire       done2;
    wire       done3;
    wire [2:0] retire_count;

    reg [PACKET_W:0] fallback_lookup;

    integer i;

    // Backpressure uses raw input valids and includes the consecutive done
    // prefix that retires on this edge.  This lets a full ROB continuously
    // replace retired entries instead of inserting a conservative empty cycle.
    assign input_count = {2'b00, in_valid0} + {2'b00, in_valid1} +
                         {2'b00, in_valid2} + {2'b00, in_valid3};
    assign alloc_count = {2'b00, alloc_valid0} + {2'b00, alloc_valid1} +
                         {2'b00, alloc_valid2} + {2'b00, alloc_valid3};
    assign free_count = 5'd16 - occupancy;

    // Each valid lower-numbered lane advances the allocation rank.  Therefore
    // simultaneous lanes receive consecutive ROB IDs in lane order.
    assign alloc_rob_id0 = tail_ptr;
    assign alloc_rob_id1 = tail_ptr + {3'b000, alloc_valid0};
    assign alloc_rob_id2 = tail_ptr + {3'b000, alloc_valid0} +
                                      {3'b000, alloc_valid1};
    assign alloc_rob_id3 = tail_ptr + {3'b000, alloc_valid0} +
                                      {3'b000, alloc_valid1} +
                                      {3'b000, alloc_valid2};

    // done1 depends on done0, etc.  This forms the consecutive done prefix:
    // a completed younger packet cannot retire past an incomplete older packet.
    assign head_idx0 = head_ptr;
    assign head_idx1 = head_ptr + 4'd1;
    assign head_idx2 = head_ptr + 4'd2;
    assign head_idx3 = head_ptr + 4'd3;
    assign done0 = rob_valid[head_idx0] && rob_result_valid[head_idx0];
    assign done1 = done0 && rob_valid[head_idx1] && rob_result_valid[head_idx1];
    assign done2 = done1 && rob_valid[head_idx2] && rob_result_valid[head_idx2];
    assign done3 = done2 && rob_valid[head_idx3] && rob_result_valid[head_idx3];
    assign retire_count = {2'b00, done0} + {2'b00, done1} +
                          {2'b00, done2} + {2'b00, done3};
    assign available_count = free_count + {2'b00, retire_count};
    assign bkps = (!rst_n) || (available_count < {2'b00, input_count});

    assign fallback_ready = fallback_valid && fallback_lookup[PACKET_W];
    assign fallback_data = fallback_lookup[PACKET_W-1:0];
    // Authoritative dependency lookup.  If the requested identity is still in
    // the ROB, an unfinished result must wait; history is checked only after the
    // ROB identity no longer matches, meaning that target has already retired.
    always @(*) begin
        fallback_lookup = {(PACKET_W+1){1'b0}};
        if (rob_valid[fallback_rob_id] &&
            (rob_seq_tag[fallback_rob_id] == fallback_seq_tag)) begin
            if (rob_result_valid[fallback_rob_id]) begin
                fallback_lookup = {1'b1, rob_data[fallback_rob_id]};
            end
        end else if (result_valid[fallback_residue] &&
                     (result_seq_tag[fallback_residue] == fallback_seq_tag)) begin
            fallback_lookup = {1'b1, result_data[fallback_residue]};
        end
    end

    // Allocation, writeback, and retirement share one sequential owner so their
    // update priority is explicit.  Wide data arrays are not reset; valid bits
    // prevent uninitialized data from becoming architecturally visible.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= 4'd0;
            tail_ptr <= 4'd0;
            occupancy <= 5'd0;
            start_lane <= 2'd0;
            out_valid0 <= 1'b0;
            out_valid1 <= 1'b0;
            out_valid2 <= 1'b0;
            out_valid3 <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                rob_valid[i] <= 1'b0;
                rob_result_valid[i] <= 1'b0;
            end
            for (i = 0; i < 8; i = i + 1) begin
                result_valid[i] <= 1'b0;
            end
        end else begin
            out_valid0 <= 1'b0;
            out_valid1 <= 1'b0;
            out_valid2 <= 1'b0;
            out_valid3 <= 1'b0;

            // W0: accept out-of-order FE results.  Both ROB ID and full tag are
            // checked so a late response cannot corrupt a reused ROB entry.
            if (wb_valid0 && rob_valid[wb_rob_id0] &&
                (rob_seq_tag[wb_rob_id0] == wb_seq_tag0) &&
                !rob_result_valid[wb_rob_id0]) begin
                rob_data[wb_rob_id0] <= wb_data0;
                rob_result_valid[wb_rob_id0] <= 1'b1;
            end
            if (wb_valid1 && rob_valid[wb_rob_id1] &&
                (rob_seq_tag[wb_rob_id1] == wb_seq_tag1) &&
                !rob_result_valid[wb_rob_id1]) begin
                rob_data[wb_rob_id1] <= wb_data1;
                rob_result_valid[wb_rob_id1] <= 1'b1;
            end
            if (wb_valid2 && rob_valid[wb_rob_id2] &&
                (rob_seq_tag[wb_rob_id2] == wb_seq_tag2) &&
                !rob_result_valid[wb_rob_id2]) begin
                rob_data[wb_rob_id2] <= wb_data2;
                rob_result_valid[wb_rob_id2] <= 1'b1;
            end
            if (wb_valid3 && rob_valid[wb_rob_id3] &&
                (rob_seq_tag[wb_rob_id3] == wb_seq_tag3) &&
                !rob_result_valid[wb_rob_id3]) begin
                rob_data[wb_rob_id3] <= wb_data3;
                rob_result_valid[wb_rob_id3] <= 1'b1;
            end

            // R0: retire up to four consecutive done entries.  Each result is
            // copied to its history bank and routed to rotating output lanes.
            if (done0) begin
                result_valid[rob_seq_residue[head_idx0]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx0]] <= rob_seq_tag[head_idx0];
                result_data[rob_seq_residue[head_idx0]] <= rob_data[head_idx0];
                rob_valid[head_idx0] <= 1'b0;
                rob_result_valid[head_idx0] <= 1'b0;
                case (start_lane)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx0]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx0]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx0]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx0]; end
                endcase
            end
            if (done1) begin
                result_valid[rob_seq_residue[head_idx1]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx1]] <= rob_seq_tag[head_idx1];
                result_data[rob_seq_residue[head_idx1]] <= rob_data[head_idx1];
                rob_valid[head_idx1] <= 1'b0;
                rob_result_valid[head_idx1] <= 1'b0;
                case (start_lane + 2'd1)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx1]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx1]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx1]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx1]; end
                endcase
            end
            if (done2) begin
                result_valid[rob_seq_residue[head_idx2]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx2]] <= rob_seq_tag[head_idx2];
                result_data[rob_seq_residue[head_idx2]] <= rob_data[head_idx2];
                rob_valid[head_idx2] <= 1'b0;
                rob_result_valid[head_idx2] <= 1'b0;
                case (start_lane + 2'd2)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx2]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx2]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx2]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx2]; end
                endcase
            end
            if (done3) begin
                result_valid[rob_seq_residue[head_idx3]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx3]] <= rob_seq_tag[head_idx3];
                result_data[rob_seq_residue[head_idx3]] <= rob_data[head_idx3];
                rob_valid[head_idx3] <= 1'b0;
                rob_result_valid[head_idx3] <= 1'b0;
                case (start_lane + 2'd3)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx3]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx3]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx3]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx3]; end
                endcase
            end

            // A0: allocate after retirement assignments.  When tail overlaps a
            // retiring head entry, nonblocking semantics let R0 consume the old
            // data while these final assignments preserve the new entry state.
            if (alloc_valid0) begin
                rob_valid[alloc_rob_id0] <= 1'b1;
                rob_seq_tag[alloc_rob_id0] <= alloc_seq_tag0;
                rob_seq_residue[alloc_rob_id0] <= alloc_seq_residue0;
                rob_result_valid[alloc_rob_id0] <= 1'b0;
            end
            if (alloc_valid1) begin
                rob_valid[alloc_rob_id1] <= 1'b1;
                rob_seq_tag[alloc_rob_id1] <= alloc_seq_tag1;
                rob_seq_residue[alloc_rob_id1] <= alloc_seq_residue1;
                rob_result_valid[alloc_rob_id1] <= 1'b0;
            end
            if (alloc_valid2) begin
                rob_valid[alloc_rob_id2] <= 1'b1;
                rob_seq_tag[alloc_rob_id2] <= alloc_seq_tag2;
                rob_seq_residue[alloc_rob_id2] <= alloc_seq_residue2;
                rob_result_valid[alloc_rob_id2] <= 1'b0;
            end
            if (alloc_valid3) begin
                rob_valid[alloc_rob_id3] <= 1'b1;
                rob_seq_tag[alloc_rob_id3] <= alloc_seq_tag3;
                rob_seq_residue[alloc_rob_id3] <= alloc_seq_residue3;
                rob_result_valid[alloc_rob_id3] <= 1'b0;
            end

            // Pointers and occupancy describe the state after this edge.
            head_ptr <= head_ptr + {1'b0, retire_count};
            tail_ptr <= tail_ptr + {1'b0, alloc_count};
            occupancy <= occupancy + {2'b00, alloc_count} -
                         {2'b00, retire_count};
            start_lane <= start_lane + retire_count[1:0];
        end
    end

endmodule
