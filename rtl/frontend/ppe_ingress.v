`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// Two-slot elastic whole-batch input boundary and sequence allocator.
//------------------------------------------------------------------------------
module PPE_INGRESS #(
    parameter integer PACKET_W = `PPE_DEFAULT_PACKET_W,
    parameter integer DESC_W   = `PPE_DEFAULT_DESC_W
) (
    input  wire                              clk_i,
    input  wire                              rst_ni,
    input  wire [`PPE_N-1:0]                 in_valid_i,
    input  wire [PACKET_W-1:0]               in_packet_i [0:`PPE_N-1],
    input  wire [DESC_W-1:0]                 in_desc_i [0:`PPE_N-1],
    output wire                              bkps_o,
    output reg  [`PPE_N-1:0]                 alloc_reserve_valid_o,
    input  wire                              alloc_reserve_ready_i,
    output wire [`PPE_N-1:0]                 alloc_commit_valid_o,
    output wire [`PPE_SEQ_W-1:0]             alloc_seq_tag_o [0:`PPE_N-1],
    output wire [`PPE_SEQ_W-1:0]             alloc_target_seq_tag_o [0:`PPE_N-1],
    output reg  [PACKET_W-1:0]               alloc_packet_o [0:`PPE_N-1],
    output wire [`PPE_DELAY_W-1:0]           alloc_delay_o [0:`PPE_N-1],
    output wire [`PPE_N-1:0]                 alloc_dep_required_o
);

    localparam integer N            = `PPE_N;
    localparam integer SEQ_W        = `PPE_SEQ_W;
    localparam integer DELAY_W      = `PPE_DELAY_W;
    localparam integer SLOT_DEPTH   = 2;
    localparam integer SLOT_COUNT_W = 2;
    localparam integer LANE_COUNT_W = 3;
    localparam integer DEP_OFFSET_W = DESC_W - DELAY_W;
    localparam integer DELTA_W      = DEP_OFFSET_W + 1;
    localparam integer DEP_LSB      = DELAY_W;

    reg [N-1:0]                          slot_lane_valid_q [0:SLOT_DEPTH-1];
    reg [PACKET_W-1:0]                   slot_packet_q [0:SLOT_DEPTH-1][0:N-1];
    reg [DESC_W-1:0]                     slot_desc_q [0:SLOT_DEPTH-1][0:N-1];
    reg                                  slot_rd_ptr_q;
    reg                                  slot_wr_ptr_q;
    reg [SLOT_COUNT_W-1:0]               slot_count_q;
    reg [SLOT_COUNT_W-1:0]               slot_count_d;
    reg [SEQ_W-1:0]                      next_seq_tag_q;
    reg                                  bkps_q;
    reg                                  bkps_d;

    wire                                 capture_batch;
    wire                                 slot_bank0_write;
    wire                                 slot_bank1_write;
    wire                                 head_nonempty;
    wire                                 head_release;
    wire                                 reserve_batch;

    reg [LANE_COUNT_W-1:0]               slot_packet_count [0:SLOT_DEPTH-1];
    reg [SEQ_W-1:0]                      slot_seq_tag [0:SLOT_DEPTH-1][0:N-1];
    reg [SEQ_W-1:0]                      slot_target_seq_tag [0:SLOT_DEPTH-1][0:N-1];
    reg [DELAY_W-1:0]                    slot_delay [0:SLOT_DEPTH-1][0:N-1];
    reg [N-1:0]                          slot_dep_required [0:SLOT_DEPTH-1];

    reg [N-1:0]                          head_lane_valid;
    reg [LANE_COUNT_W-1:0]               head_packet_count;
    reg [SEQ_W-1:0]                      head_seq_tag [0:N-1];
    reg [SEQ_W-1:0]                      head_target_seq_tag [0:N-1];
    reg [DELAY_W-1:0]                    head_delay [0:N-1];
    reg [N-1:0]                          head_dep_required;

    reg [N-1:0]                          alloc_commit_valid_q;
    reg [SEQ_W-1:0]                      alloc_commit_seq_tag_q [0:N-1];
    reg [SEQ_W-1:0]                      alloc_commit_target_seq_tag_q [0:N-1];
    reg [DELAY_W-1:0]                    alloc_commit_delay_q [0:N-1];
    reg [N-1:0]                          alloc_commit_dep_required_q;
    reg                                  alloc_commit_slot_q;

    always @* begin : slot_head_select
        integer lane_idx;

        head_lane_valid       = {N{1'b0}};
        head_packet_count     = {LANE_COUNT_W{1'b0}};
        head_dep_required     = {N{1'b0}};
        for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
            head_seq_tag[lane_idx]        = {SEQ_W{1'b0}};
            head_target_seq_tag[lane_idx] = {SEQ_W{1'b0}};
            head_delay[lane_idx]          = {DELAY_W{1'b0}};
        end

        if (slot_count_q != {SLOT_COUNT_W{1'b0}}) begin
            head_lane_valid   = slot_lane_valid_q[slot_rd_ptr_q];
            head_packet_count = slot_packet_count[slot_rd_ptr_q];
            head_dep_required = slot_dep_required[slot_rd_ptr_q];
            for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                head_seq_tag[lane_idx] =
                    slot_seq_tag[slot_rd_ptr_q][lane_idx];
                head_target_seq_tag[lane_idx] =
                    slot_target_seq_tag[slot_rd_ptr_q][lane_idx];
                head_delay[lane_idx] =
                    slot_delay[slot_rd_ptr_q][lane_idx];
            end
        end

        alloc_reserve_valid_o = head_lane_valid;
    end

    assign head_nonempty = |alloc_reserve_valid_o;
    assign reserve_batch = (slot_count_q != {SLOT_COUNT_W{1'b0}})
                           && head_nonempty
                           && alloc_reserve_ready_i;
    assign head_release  = (slot_count_q != {SLOT_COUNT_W{1'b0}})
                           && (!head_nonempty
                               || alloc_reserve_ready_i);
    assign capture_batch   = !bkps_q;
    assign slot_bank0_write = capture_batch && !slot_wr_ptr_q;
    assign slot_bank1_write = capture_batch &&  slot_wr_ptr_q;

    always @* begin : occupancy_and_backpressure
        slot_count_d = slot_count_q;
        case ({capture_batch, head_release})
            2'b10: slot_count_d = slot_count_q + 2'd1;
            2'b01: slot_count_d = slot_count_q - 2'd1;
            default: begin
                slot_count_d = slot_count_q;
            end
        endcase
        bkps_d = (slot_count_d == 2'd2);
    end

    assign bkps_o = bkps_q;

    always @* begin : per_slot_metadata_decode
        integer slot_idx;
        integer lane_idx;
        reg [LANE_COUNT_W-1:0] lower_count;
        reg [LANE_COUNT_W-1:0] upper_count;
        reg [LANE_COUNT_W-1:0] lane_rank;
        reg [DELTA_W-1:0]      target_delta;
        reg [DEP_OFFSET_W-1:0] dep_offset;

        lower_count           = {LANE_COUNT_W{1'b0}};
        upper_count           = {LANE_COUNT_W{1'b0}};
        lane_rank             = {LANE_COUNT_W{1'b0}};
        target_delta          = {DELTA_W{1'b0}};
        dep_offset            = {DEP_OFFSET_W{1'b0}};

        for (slot_idx = 0;
             slot_idx < SLOT_DEPTH;
             slot_idx = slot_idx + 1) begin
            slot_packet_count[slot_idx] = {LANE_COUNT_W{1'b0}};
            slot_dep_required[slot_idx] = {N{1'b0}};
            for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                slot_seq_tag[slot_idx][lane_idx] = {SEQ_W{1'b0}};
                slot_target_seq_tag[slot_idx][lane_idx] = {SEQ_W{1'b0}};
                slot_delay[slot_idx][lane_idx] = {DELAY_W{1'b0}};
            end
            lower_count =
                {{(LANE_COUNT_W-1){1'b0}},
                  slot_lane_valid_q[slot_idx][0]}
                + {{(LANE_COUNT_W-1){1'b0}},
                    slot_lane_valid_q[slot_idx][1]};
            upper_count =
                {{(LANE_COUNT_W-1){1'b0}},
                  slot_lane_valid_q[slot_idx][2]}
                + {{(LANE_COUNT_W-1){1'b0}},
                    slot_lane_valid_q[slot_idx][3]};
            slot_packet_count[slot_idx] = lower_count + upper_count;

            for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                case (lane_idx)
                    0: lane_rank = {LANE_COUNT_W{1'b0}};
                    1: lane_rank =
                        {{(LANE_COUNT_W-1){1'b0}},
                          slot_lane_valid_q[slot_idx][0]};
                    2: lane_rank = lower_count;
                    default: lane_rank =
                        lower_count
                        + {{(LANE_COUNT_W-1){1'b0}},
                            slot_lane_valid_q[slot_idx][2]};
                endcase
                if (slot_lane_valid_q[slot_idx][lane_idx]) begin
                    slot_seq_tag[slot_idx][lane_idx] =
                        next_seq_tag_q
                        + {{(SEQ_W-LANE_COUNT_W){1'b0}}, lane_rank};
                    slot_delay[slot_idx][lane_idx] =
                        slot_desc_q[slot_idx][lane_idx][DELAY_W-1:0];
                    dep_offset =
                        slot_desc_q[slot_idx][lane_idx][
                            DEP_LSB +: DEP_OFFSET_W];
                    if (dep_offset != {DEP_OFFSET_W{1'b0}}) begin
                        slot_dep_required[slot_idx][lane_idx] = 1'b1;
                        target_delta =
                            {{(DELTA_W-LANE_COUNT_W){1'b0}}, lane_rank}
                            - {{(DELTA_W-DEP_OFFSET_W){1'b0}},
                                dep_offset};
                        slot_target_seq_tag[slot_idx][lane_idx] =
                            next_seq_tag_q
                            + {{(SEQ_W-DELTA_W){
                                    target_delta[DELTA_W-1]}},
                                target_delta};
                    end
                end
            end
        end
    end

    always @* begin : allocation_commit_outputs
        integer lane_idx;

        for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
            alloc_packet_o[lane_idx] = {PACKET_W{1'b0}};
            if (alloc_commit_valid_q[lane_idx]) begin
                alloc_packet_o[lane_idx] =
                    slot_packet_q[alloc_commit_slot_q][lane_idx];
            end
        end
    end

    assign alloc_commit_valid_o       = alloc_commit_valid_q;
    assign alloc_dep_required_o       = alloc_commit_dep_required_q;

    generate
        genvar output_lane;
        for (output_lane = 0; output_lane < N;
             output_lane = output_lane + 1) begin : allocation_metadata_outputs
            assign alloc_seq_tag_o[output_lane] =
                alloc_commit_seq_tag_q[output_lane];
            assign alloc_target_seq_tag_o[output_lane] =
                alloc_commit_target_seq_tag_q[output_lane];
            assign alloc_delay_o[output_lane] =
                alloc_commit_delay_q[output_lane];
        end
    endgenerate

    always @(posedge clk_i or negedge rst_ni) begin : slot_state_update
        integer lane_idx;

        if (!rst_ni) begin
            slot_lane_valid_q[0] <= {N{1'b0}};
            slot_lane_valid_q[1] <= {N{1'b0}};
            slot_rd_ptr_q     <= 1'b0;
            slot_wr_ptr_q     <= 1'b0;
            slot_count_q      <= {SLOT_COUNT_W{1'b0}};
        end else begin
            if (slot_bank0_write) begin
                slot_lane_valid_q[0] <= in_valid_i;
                for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                    slot_packet_q[0][lane_idx] <= in_packet_i[lane_idx];
                    slot_desc_q[0][lane_idx] <= in_desc_i[lane_idx];
                end
            end
            if (slot_bank1_write) begin
                slot_lane_valid_q[1] <= in_valid_i;
                for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                    slot_packet_q[1][lane_idx] <= in_packet_i[lane_idx];
                    slot_desc_q[1][lane_idx] <= in_desc_i[lane_idx];
                end
            end
            if (capture_batch) begin
                slot_wr_ptr_q <= ~slot_wr_ptr_q;
            end
            if (head_release) begin
                slot_rd_ptr_q <= ~slot_rd_ptr_q;
            end
            slot_count_q <= slot_count_d;
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : sequence_state_update
        if (!rst_ni) begin
            next_seq_tag_q <= {SEQ_W{1'b0}};
        end else if (reserve_batch) begin
            next_seq_tag_q <= next_seq_tag_q
                              + {{(SEQ_W-LANE_COUNT_W){1'b0}},
                                  head_packet_count};
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : allocation_commit_state
        integer lane_idx;

        if (!rst_ni) begin
            alloc_commit_valid_q <= {N{1'b0}};
        end else begin
            alloc_commit_valid_q <=
                alloc_reserve_valid_o & {N{reserve_batch}};
            if (slot_count_q != {SLOT_COUNT_W{1'b0}}) begin
                for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                    alloc_commit_seq_tag_q[lane_idx] <= head_seq_tag[lane_idx];
                    alloc_commit_target_seq_tag_q[lane_idx] <=
                        head_target_seq_tag[lane_idx];
                    alloc_commit_delay_q[lane_idx] <= head_delay[lane_idx];
                end
                alloc_commit_dep_required_q   <= head_dep_required;
                alloc_commit_slot_q           <= slot_rd_ptr_q;
            end
        end
    end

    always @(posedge clk_i or negedge rst_ni) begin : bkps_state_update
        if (!rst_ni) begin
            bkps_q <= 1'b1;
        end else begin
            bkps_q <= bkps_d;
        end
    end

endmodule

`default_nettype wire
