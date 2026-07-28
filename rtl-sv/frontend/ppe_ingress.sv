`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_ingress.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Frontend / Ingress
//
// Description :
//   Implements the PPE external input-register boundary as a two-slot elastic
//   whole-batch FIFO. Both slots are input capture registers. Raw top-level
//   inputs occur only as slot-register D inputs; admission, allocation,
//   descriptor decode, sequence assignment, and backpressure use registered
//   state exclusively.
//
//   The registered FIFO head first reserves whole-batch ROB capacity. Accepted
//   metadata is captured in a narrow commit register and is written to the ROB
//   and issue table on the following cycle. Empty batches are recognized only
//   after capture and are released without a reservation.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 2.3 and 4
//   - doc/hld.txt, Sections 3.2, 4.1, 4.6, and 5.1
//   - doc/lld.txt, Sections 3.2, 5.0, 5.1, 6, and 14
//------------------------------------------------------------------------------

module ppe_ingress #(
    parameter int PACKET_W = ppe_types_pkg::DEFAULT_PACKET_W,
    parameter int DESC_W   = ppe_types_pkg::DEFAULT_DESC_W
) (
    input  logic                                      clk_i,
    input  logic                                      rst_ni,

    input  logic [ppe_types_pkg::N-1:0]               in_valid_i,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] in_packet_i,
    input  logic [ppe_types_pkg::N-1:0][DESC_W-1:0]   in_desc_i,

    output logic                                      bkps_o,

    output logic [ppe_types_pkg::N-1:0]               alloc_reserve_valid_o,
    input  logic                                      alloc_reserve_ready_i,

    output logic [ppe_types_pkg::N-1:0]               alloc_commit_valid_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]           alloc_seq_tag_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]           alloc_target_seq_tag_o,
    output logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] alloc_packet_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::DELAY_W-1:0]         alloc_delay_o,
    output logic [ppe_types_pkg::N-1:0]               alloc_dep_required_o
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Fixed two-slot elastic state
    //--------------------------------------------------------------------------

    localparam int SLOT_DEPTH   = 2;
    localparam int SLOT_COUNT_W = $clog2(SLOT_DEPTH + 1);
    localparam int LANE_COUNT_W = $clog2(N + 1);
    localparam int DEP_OFFSET_W = DESC_W - DELAY_W;
    localparam int DELTA_W      = DEP_OFFSET_W + 1;
    localparam int DEP_MSB      = DESC_W - 1;
    localparam int DEP_LSB      = DELAY_W;
    logic [SLOT_DEPTH-1:0][N-1:0]               slot_lane_valid_q;
    logic [SLOT_DEPTH-1:0][N-1:0][PACKET_W-1:0] slot_packet_q;
    logic [SLOT_DEPTH-1:0][N-1:0][DESC_W-1:0]   slot_desc_q;

    logic                      slot_rd_ptr_q;
    logic                      slot_wr_ptr_q;
    logic [SLOT_COUNT_W-1:0]   slot_count_q;
    logic [SLOT_COUNT_W-1:0]   slot_count_d;
    logic [SEQ_W-1:0]          next_seq_tag_q;
    logic                      bkps_q;
    logic                      bkps_d;

    logic                      capture_batch;
    logic                      slot_bank0_write;
    logic                      slot_bank1_write;
    logic                      head_nonempty;
    logic                      head_release;
    logic                      reserve_batch;

    logic [SLOT_DEPTH-1:0][LANE_COUNT_W-1:0]
                               slot_lower_pair_count;
    logic [SLOT_DEPTH-1:0][LANE_COUNT_W-1:0]
                               slot_upper_pair_count;
    logic [SLOT_DEPTH-1:0][LANE_COUNT_W-1:0]
                               slot_packet_count;
    logic [SLOT_DEPTH-1:0][N-1:0][LANE_COUNT_W-1:0]
                               slot_lane_rank;
    logic [SLOT_DEPTH-1:0][N-1:0][DELTA_W-1:0]
                               slot_target_delta;
    logic [SLOT_DEPTH-1:0][N-1:0][SEQ_W-1:0]
                               slot_seq_tag;
    logic [SLOT_DEPTH-1:0][N-1:0][SEQ_W-1:0]
                               slot_target_seq_tag;
    logic [SLOT_DEPTH-1:0][N-1:0][DELAY_W-1:0]
                               slot_delay;
    logic [SLOT_DEPTH-1:0][N-1:0]
                               slot_dep_required;

    logic [N-1:0]              head_lane_valid;
    logic [LANE_COUNT_W-1:0]   head_packet_count;
    logic [N-1:0][SEQ_W-1:0]   head_seq_tag;
    logic [N-1:0][SEQ_W-1:0]   head_target_seq_tag;
    logic [N-1:0][DELAY_W-1:0] head_delay;
    logic [N-1:0]              head_dep_required;

    logic [N-1:0]              alloc_commit_valid_q;
    logic [N-1:0][SEQ_W-1:0]   alloc_commit_seq_tag_q;
    logic [N-1:0][SEQ_W-1:0]   alloc_commit_target_seq_tag_q;
    logic [N-1:0][DELAY_W-1:0] alloc_commit_delay_q;
    logic [N-1:0]              alloc_commit_dep_required_q;
    logic                      alloc_commit_slot_q;

    //--------------------------------------------------------------------------
    // Registered head, elastic transfer, and registered backpressure
    //--------------------------------------------------------------------------

    always_comb begin : slot_head_select
        head_lane_valid       = '0;
        head_packet_count     = '0;
        head_seq_tag          = '0;
        head_target_seq_tag   = '0;
        head_delay            = '0;
        head_dep_required     = '0;

        if (slot_count_q != '0) begin
            if (slot_rd_ptr_q) begin
                head_lane_valid     = slot_lane_valid_q[1];
                head_packet_count   = slot_packet_count[1];
                head_seq_tag        = slot_seq_tag[1];
                head_target_seq_tag = slot_target_seq_tag[1];
                head_delay          = slot_delay[1];
                head_dep_required   = slot_dep_required[1];
            end else begin
                head_lane_valid     = slot_lane_valid_q[0];
                head_packet_count   = slot_packet_count[0];
                head_seq_tag        = slot_seq_tag[0];
                head_target_seq_tag = slot_target_seq_tag[0];
                head_delay          = slot_delay[0];
                head_dep_required   = slot_dep_required[0];
            end
        end

        alloc_reserve_valid_o = head_lane_valid;
    end

    assign head_nonempty = |alloc_reserve_valid_o;
    assign reserve_batch = (slot_count_q != '0)
                           && head_nonempty
                           && alloc_reserve_ready_i;
    assign head_release = (slot_count_q != '0)
                          && (!head_nonempty || alloc_reserve_ready_i);

    // An open registered interface captures one whole batch regardless of its
    // raw lane-valid pattern. Empty batches are recognized only after capture.
    assign capture_batch = !bkps_q;
    assign slot_bank0_write = capture_batch && !slot_wr_ptr_q;
    assign slot_bank1_write = capture_batch &&  slot_wr_ptr_q;

    always_comb begin : occupancy_and_backpressure
        slot_count_d = slot_count_q;
        unique case ({capture_batch, head_release})
            2'b10: slot_count_d =
                slot_count_q + SLOT_COUNT_W'(1);
            2'b01: slot_count_d =
                slot_count_q - SLOT_COUNT_W'(1);
            default: begin
                // Hold for no transfer or simultaneous head replacement.
            end
        endcase

        // bkps is the registered reservation for the following capture edge.
        bkps_d = (slot_count_d == SLOT_COUNT_W'(SLOT_DEPTH));
    end

    assign bkps_o = bkps_q;

    //--------------------------------------------------------------------------
    // Per-slot rank, sequence, and descriptor decode
    //--------------------------------------------------------------------------

    always_comb begin : per_slot_metadata_decode
        slot_lower_pair_count = '0;
        slot_upper_pair_count = '0;
        slot_packet_count     = '0;
        slot_lane_rank        = '0;
        slot_target_delta     = '0;
        slot_seq_tag          = '0;
        slot_target_seq_tag   = '0;
        slot_delay            = '0;
        slot_dep_required     = '0;

        for (int slot_idx = 0;
             slot_idx < SLOT_DEPTH;
             slot_idx++) begin
            slot_lower_pair_count[slot_idx] =
                LANE_COUNT_W'(slot_lane_valid_q[slot_idx][0])
                + LANE_COUNT_W'(slot_lane_valid_q[slot_idx][1]);
            slot_upper_pair_count[slot_idx] =
                LANE_COUNT_W'(slot_lane_valid_q[slot_idx][2])
                + LANE_COUNT_W'(slot_lane_valid_q[slot_idx][3]);

            slot_lane_rank[slot_idx][0] = '0;
            slot_lane_rank[slot_idx][1] =
                LANE_COUNT_W'(slot_lane_valid_q[slot_idx][0]);
            slot_lane_rank[slot_idx][2] =
                slot_lower_pair_count[slot_idx];
            slot_lane_rank[slot_idx][3] =
                slot_lower_pair_count[slot_idx]
                + LANE_COUNT_W'(slot_lane_valid_q[slot_idx][2]);
            slot_packet_count[slot_idx] =
                slot_lower_pair_count[slot_idx]
                + slot_upper_pair_count[slot_idx];

            for (int lane_idx = 0; lane_idx < N; lane_idx++) begin
                if (slot_lane_valid_q[slot_idx][lane_idx]) begin
                    slot_seq_tag[slot_idx][lane_idx] =
                        next_seq_tag_q
                        + SEQ_W'(slot_lane_rank[slot_idx][lane_idx]);
                    slot_delay[slot_idx][lane_idx] =
                        slot_desc_q[slot_idx][lane_idx][DELAY_W-1:0];

                    if (slot_desc_q[slot_idx][lane_idx]
                        [DEP_MSB:DEP_LSB] != '0) begin
                        slot_dep_required[slot_idx][lane_idx] = 1'b1;
                        slot_target_delta[slot_idx][lane_idx] =
                            DELTA_W'(slot_lane_rank[slot_idx][lane_idx])
                            - DELTA_W'(slot_desc_q[slot_idx][lane_idx]
                                      [DEP_MSB:DEP_LSB]);
                        slot_target_seq_tag[slot_idx][lane_idx] =
                            next_seq_tag_q
                            + {{(SEQ_W-DELTA_W){
                                   slot_target_delta[slot_idx][lane_idx]
                                                    [DELTA_W-1]}},
                               slot_target_delta[slot_idx][lane_idx]};
                    end
                end
            end
        end
    end

    always_comb begin : allocation_commit_outputs
        alloc_commit_valid_o      = alloc_commit_valid_q;
        alloc_seq_tag_o           = alloc_commit_seq_tag_q;
        alloc_target_seq_tag_o    = alloc_commit_target_seq_tag_q;
        alloc_delay_o             = alloc_commit_delay_q;
        alloc_dep_required_o      = alloc_commit_dep_required_q;
        alloc_packet_o            = '0;

        if (|alloc_commit_valid_q) begin
            alloc_packet_o = slot_packet_q[alloc_commit_slot_q];
        end
    end

    //--------------------------------------------------------------------------
    // Slot, sequence, and backpressure state update
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin : slot_state_update
        if (!rst_ni) begin
            slot_lane_valid_q <= '0;
            slot_rd_ptr_q     <= 1'b0;
            slot_wr_ptr_q     <= 1'b0;
            slot_count_q      <= '0;
        end else begin
            // Bank-wide common enables preserve automatic ICG inference
            // opportunities without instantiating or constructing a clock gate.
            if (slot_bank0_write) begin
                slot_lane_valid_q[0] <= in_valid_i;
                slot_packet_q[0]     <= in_packet_i;
                slot_desc_q[0]       <= in_desc_i;
            end

            if (slot_bank1_write) begin
                slot_lane_valid_q[1] <= in_valid_i;
                slot_packet_q[1]     <= in_packet_i;
                slot_desc_q[1]       <= in_desc_i;
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

    always_ff @(posedge clk_i or negedge rst_ni) begin : sequence_state_update
        if (!rst_ni) begin
            next_seq_tag_q <= '0;
        end else if (reserve_batch) begin
            next_seq_tag_q <= next_seq_tag_q + SEQ_W'(head_packet_count);
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : allocation_commit_state
        if (!rst_ni) begin
            alloc_commit_valid_q <= '0;
        end else begin
            alloc_commit_valid_q <=
                alloc_reserve_valid_o & {N{reserve_batch}};

            if (slot_count_q != '0) begin
                alloc_commit_seq_tag_q        <= head_seq_tag;
                alloc_commit_target_seq_tag_q <= head_target_seq_tag;
                alloc_commit_delay_q          <= head_delay;
                alloc_commit_dep_required_q   <= head_dep_required;
                alloc_commit_slot_q           <= slot_rd_ptr_q;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : bkps_state_update
        if (!rst_ni) begin
            bkps_q <= 1'b1;
        end else begin
            bkps_q <= bkps_d;
        end
    end

endmodule : ppe_ingress

`default_nettype wire
