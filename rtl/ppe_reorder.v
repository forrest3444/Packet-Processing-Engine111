`timescale 1ns/1ps

module ppe_reorder #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,
    input      [3:0]            in_valid,
    output                      bkps,

    input      [3:0]            alloc_valid,
    input      [19:0]           alloc_seq_tag,
    input      [11:0]           alloc_seq_residue,
    output     [15:0]           alloc_rob_id,

    input                       fallback_valid,
    input      [3:0]            fallback_rob_id,
    input      [4:0]            fallback_seq_tag,
    input      [2:0]            fallback_residue,
    output                      fallback_ready,
    output     [PACKET_W-1:0]   fallback_data,

    input      [3:0]            wb_valid,
    input      [15:0]           wb_rob_id,
    input      [19:0]           wb_seq_tag,
    input      [4*PACKET_W-1:0] wb_data,

    output     [3:0]            out_valid,
    output     [4*PACKET_W-1:0] out_packet
);

    wire       in_valid0 = in_valid[0];
    wire       in_valid1 = in_valid[1];
    wire       in_valid2 = in_valid[2];
    wire       in_valid3 = in_valid[3];
    wire       alloc_valid0 = alloc_valid[0];
    wire [4:0] alloc_seq_tag0 = alloc_seq_tag[0*5 +: 5];
    wire [2:0] alloc_seq_residue0 = alloc_seq_residue[0*3 +: 3];
    wire       alloc_valid1 = alloc_valid[1];
    wire [4:0] alloc_seq_tag1 = alloc_seq_tag[1*5 +: 5];
    wire [2:0] alloc_seq_residue1 = alloc_seq_residue[1*3 +: 3];
    wire       alloc_valid2 = alloc_valid[2];
    wire [4:0] alloc_seq_tag2 = alloc_seq_tag[2*5 +: 5];
    wire [2:0] alloc_seq_residue2 = alloc_seq_residue[2*3 +: 3];
    wire       alloc_valid3 = alloc_valid[3];
    wire [4:0] alloc_seq_tag3 = alloc_seq_tag[3*5 +: 5];
    wire [2:0] alloc_seq_residue3 = alloc_seq_residue[3*3 +: 3];
    wire [3:0] alloc_rob_id0;
    wire [3:0] alloc_rob_id1;
    wire [3:0] alloc_rob_id2;
    wire [3:0] alloc_rob_id3;

    wire       wb_valid0 = wb_valid[0];
    wire [3:0] wb_rob_id0 = wb_rob_id[0*4 +: 4];
    wire [4:0] wb_seq_tag0 = wb_seq_tag[0*5 +: 5];
    wire [PACKET_W-1:0] wb_data0 = wb_data[0*PACKET_W +: PACKET_W];
    wire       wb_valid1 = wb_valid[1];
    wire [3:0] wb_rob_id1 = wb_rob_id[1*4 +: 4];
    wire [4:0] wb_seq_tag1 = wb_seq_tag[1*5 +: 5];
    wire [PACKET_W-1:0] wb_data1 = wb_data[1*PACKET_W +: PACKET_W];
    wire       wb_valid2 = wb_valid[2];
    wire [3:0] wb_rob_id2 = wb_rob_id[2*4 +: 4];
    wire [4:0] wb_seq_tag2 = wb_seq_tag[2*5 +: 5];
    wire [PACKET_W-1:0] wb_data2 = wb_data[2*PACKET_W +: PACKET_W];
    wire       wb_valid3 = wb_valid[3];
    wire [3:0] wb_rob_id3 = wb_rob_id[3*4 +: 4];
    wire [4:0] wb_seq_tag3 = wb_seq_tag[3*5 +: 5];
    wire [PACKET_W-1:0] wb_data3 = wb_data[3*PACKET_W +: PACKET_W];

    reg        out_valid0;
    reg [PACKET_W-1:0] out_packet0;
    reg        out_valid1;
    reg [PACKET_W-1:0] out_packet1;
    reg        out_valid2;
    reg [PACKET_W-1:0] out_packet2;
    reg        out_valid3;
    reg [PACKET_W-1:0] out_packet3;

    reg                       rob_valid [0:15];
    reg [4:0]                 rob_seq_tag [0:15];
    reg [2:0]                 rob_seq_residue [0:15];
    reg                       rob_result_valid [0:15];
    reg [PACKET_W-1:0]        rob_data [0:15];

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

    assign input_count = {2'b00, in_valid0} + {2'b00, in_valid1} +
                         {2'b00, in_valid2} + {2'b00, in_valid3};
    assign alloc_count = {2'b00, alloc_valid0} + {2'b00, alloc_valid1} +
                         {2'b00, alloc_valid2} + {2'b00, alloc_valid3};
    assign free_count = 5'd16 - occupancy;
    assign bkps = (!rst_n) || (free_count < {2'b00, input_count});

    assign alloc_rob_id0 = tail_ptr;
    assign alloc_rob_id1 = tail_ptr + {3'b000, alloc_valid0};
    assign alloc_rob_id2 = tail_ptr + {3'b000, alloc_valid0} +
                                      {3'b000, alloc_valid1};
    assign alloc_rob_id3 = tail_ptr + {3'b000, alloc_valid0} +
                                      {3'b000, alloc_valid1} +
                                      {3'b000, alloc_valid2};

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

    assign fallback_ready = fallback_valid && fallback_lookup[PACKET_W];
    assign fallback_data = fallback_lookup[PACKET_W-1:0];
    assign alloc_rob_id = {alloc_rob_id3, alloc_rob_id2,
                           alloc_rob_id1, alloc_rob_id0};
    assign out_valid = {out_valid3, out_valid2, out_valid1, out_valid0};
    assign out_packet = {out_packet3, out_packet2, out_packet1, out_packet0};

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

            head_ptr <= head_ptr + {1'b0, retire_count};
            tail_ptr <= tail_ptr + {1'b0, alloc_count};
            occupancy <= occupancy + {2'b00, alloc_count} -
                         {2'b00, retire_count};
            start_lane <= start_lane + retire_count[1:0];
        end
    end

endmodule
