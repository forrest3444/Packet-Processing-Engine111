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
    input  wire [`PPE_N*PACKET_W-1:0]        in_packet_i,
    input  wire [`PPE_N*DESC_W-1:0]          in_desc_i,
    output wire                              bkps_o,
    output reg  [`PPE_N-1:0]                 alloc_reserve_valid_o,
    input  wire                              alloc_reserve_ready_i,
    output wire [`PPE_N-1:0]                 alloc_commit_valid_o,
    output wire [`PPE_N*`PPE_SEQ_W-1:0]      alloc_seq_tag_o,
    output wire [`PPE_N*`PPE_SEQ_W-1:0]      alloc_target_seq_tag_o,
    output reg  [`PPE_N*PACKET_W-1:0]        alloc_packet_o,
    output wire [`PPE_N*`PPE_DELAY_W-1:0]    alloc_delay_o,
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

    reg [SLOT_DEPTH*N-1:0]               slot_lane_valid_q;
    reg [SLOT_DEPTH*N*PACKET_W-1:0]      slot_packet_q;
    reg [SLOT_DEPTH*N*DESC_W-1:0]        slot_desc_q;
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

    reg [SLOT_DEPTH*LANE_COUNT_W-1:0]    slot_packet_count;
    reg [SLOT_DEPTH*N*SEQ_W-1:0]         slot_seq_tag;
    reg [SLOT_DEPTH*N*SEQ_W-1:0]         slot_target_seq_tag;
    reg [SLOT_DEPTH*N*DELAY_W-1:0]       slot_delay;
    reg [SLOT_DEPTH*N-1:0]               slot_dep_required;

    reg [N-1:0]                          head_lane_valid;
    reg [LANE_COUNT_W-1:0]               head_packet_count;
    reg [N*SEQ_W-1:0]                    head_seq_tag;
    reg [N*SEQ_W-1:0]                    head_target_seq_tag;
    reg [N*DELAY_W-1:0]                  head_delay;
    reg [N-1:0]                          head_dep_required;

    reg [N-1:0]                          alloc_commit_valid_q;
    reg [N*SEQ_W-1:0]                    alloc_commit_seq_tag_q;
    reg [N*SEQ_W-1:0]                    alloc_commit_target_seq_tag_q;
    reg [N*DELAY_W-1:0]                  alloc_commit_delay_q;
    reg [N-1:0]                          alloc_commit_dep_required_q;
    reg                                  alloc_commit_slot_q;

    always @* begin : slot_head_select
        head_lane_valid       = {N{1'b0}};
        head_packet_count     = {LANE_COUNT_W{1'b0}};
        head_seq_tag          = {N*SEQ_W{1'b0}};
        head_target_seq_tag   = {N*SEQ_W{1'b0}};
        head_delay            = {N*DELAY_W{1'b0}};
        head_dep_required     = {N{1'b0}};

        if (slot_count_q != {SLOT_COUNT_W{1'b0}}) begin
            if (slot_rd_ptr_q) begin
                head_lane_valid = slot_lane_valid_q[N +: N];
                head_packet_count =
                    slot_packet_count[LANE_COUNT_W +: LANE_COUNT_W];
                head_seq_tag =
                    slot_seq_tag[N*SEQ_W +: N*SEQ_W];
                head_target_seq_tag =
                    slot_target_seq_tag[N*SEQ_W +: N*SEQ_W];
                head_delay =
                    slot_delay[N*DELAY_W +: N*DELAY_W];
                head_dep_required =
                    slot_dep_required[N +: N];
            end else begin
                head_lane_valid = slot_lane_valid_q[0 +: N];
                head_packet_count =
                    slot_packet_count[0 +: LANE_COUNT_W];
                head_seq_tag =
                    slot_seq_tag[0 +: N*SEQ_W];
                head_target_seq_tag =
                    slot_target_seq_tag[0 +: N*SEQ_W];
                head_delay =
                    slot_delay[0 +: N*DELAY_W];
                head_dep_required =
                    slot_dep_required[0 +: N];
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
        integer lane_base;
        reg [LANE_COUNT_W-1:0] lower_count;
        reg [LANE_COUNT_W-1:0] upper_count;
        reg [LANE_COUNT_W-1:0] lane_rank;
        reg [DELTA_W-1:0]      target_delta;
        reg [DEP_OFFSET_W-1:0] dep_offset;

        slot_packet_count     = {SLOT_DEPTH*LANE_COUNT_W{1'b0}};
        slot_seq_tag          = {SLOT_DEPTH*N*SEQ_W{1'b0}};
        slot_target_seq_tag   = {SLOT_DEPTH*N*SEQ_W{1'b0}};
        slot_delay            = {SLOT_DEPTH*N*DELAY_W{1'b0}};
        slot_dep_required     = {SLOT_DEPTH*N{1'b0}};
        lower_count           = {LANE_COUNT_W{1'b0}};
        upper_count           = {LANE_COUNT_W{1'b0}};
        lane_rank             = {LANE_COUNT_W{1'b0}};
        target_delta          = {DELTA_W{1'b0}};
        dep_offset            = {DEP_OFFSET_W{1'b0}};

        for (slot_idx = 0;
             slot_idx < SLOT_DEPTH;
             slot_idx = slot_idx + 1) begin
            lower_count =
                {{(LANE_COUNT_W-1){1'b0}},
                  slot_lane_valid_q[slot_idx*N+0]}
                + {{(LANE_COUNT_W-1){1'b0}},
                    slot_lane_valid_q[slot_idx*N+1]};
            upper_count =
                {{(LANE_COUNT_W-1){1'b0}},
                  slot_lane_valid_q[slot_idx*N+2]}
                + {{(LANE_COUNT_W-1){1'b0}},
                    slot_lane_valid_q[slot_idx*N+3]};
            slot_packet_count[
                slot_idx*LANE_COUNT_W +: LANE_COUNT_W] =
                lower_count + upper_count;

            for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                lane_base = slot_idx*N + lane_idx;
                case (lane_idx)
                    0: lane_rank = {LANE_COUNT_W{1'b0}};
                    1: lane_rank =
                        {{(LANE_COUNT_W-1){1'b0}},
                          slot_lane_valid_q[slot_idx*N+0]};
                    2: lane_rank = lower_count;
                    default: lane_rank =
                        lower_count
                        + {{(LANE_COUNT_W-1){1'b0}},
                            slot_lane_valid_q[slot_idx*N+2]};
                endcase
                if (slot_lane_valid_q[lane_base]) begin
                    slot_seq_tag[lane_base*SEQ_W +: SEQ_W] =
                        next_seq_tag_q
                        + {{(SEQ_W-LANE_COUNT_W){1'b0}}, lane_rank};
                    slot_delay[lane_base*DELAY_W +: DELAY_W] =
                        slot_desc_q[lane_base*DESC_W +: DELAY_W];
                    dep_offset =
                        slot_desc_q[
                            lane_base*DESC_W+DEP_LSB +: DEP_OFFSET_W];
                    if (dep_offset != {DEP_OFFSET_W{1'b0}}) begin
                        slot_dep_required[lane_base] = 1'b1;
                        target_delta =
                            {{(DELTA_W-LANE_COUNT_W){1'b0}}, lane_rank}
                            - {{(DELTA_W-DEP_OFFSET_W){1'b0}},
                                dep_offset};
                        slot_target_seq_tag[
                            lane_base*SEQ_W +: SEQ_W] =
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
        alloc_packet_o = {N*PACKET_W{1'b0}};
        if (|alloc_commit_valid_q) begin
            if (alloc_commit_slot_q) begin
                alloc_packet_o =
                    slot_packet_q[N*PACKET_W +: N*PACKET_W];
            end else begin
                alloc_packet_o =
                    slot_packet_q[0 +: N*PACKET_W];
            end
        end
    end

    assign alloc_commit_valid_o       = alloc_commit_valid_q;
    assign alloc_seq_tag_o            = alloc_commit_seq_tag_q;
    assign alloc_target_seq_tag_o     = alloc_commit_target_seq_tag_q;
    assign alloc_delay_o              = alloc_commit_delay_q;
    assign alloc_dep_required_o       = alloc_commit_dep_required_q;

    always @(posedge clk_i or negedge rst_ni) begin : slot_state_update
        if (!rst_ni) begin
            slot_lane_valid_q <= {SLOT_DEPTH*N{1'b0}};
            slot_rd_ptr_q     <= 1'b0;
            slot_wr_ptr_q     <= 1'b0;
            slot_count_q      <= {SLOT_COUNT_W{1'b0}};
        end else begin
            if (slot_bank0_write) begin
                slot_lane_valid_q[0 +: N] <= in_valid_i;
                slot_packet_q[0 +: N*PACKET_W] <= in_packet_i;
                slot_desc_q[0 +: N*DESC_W] <= in_desc_i;
            end
            if (slot_bank1_write) begin
                slot_lane_valid_q[N +: N] <= in_valid_i;
                slot_packet_q[N*PACKET_W +: N*PACKET_W] <= in_packet_i;
                slot_desc_q[N*DESC_W +: N*DESC_W] <= in_desc_i;
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
        if (!rst_ni) begin
            alloc_commit_valid_q <= {N{1'b0}};
        end else begin
            alloc_commit_valid_q <=
                alloc_reserve_valid_o & {N{reserve_batch}};
            if (slot_count_q != {SLOT_COUNT_W{1'b0}}) begin
                alloc_commit_seq_tag_q        <= head_seq_tag;
                alloc_commit_target_seq_tag_q <= head_target_seq_tag;
                alloc_commit_delay_q          <= head_delay;
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
