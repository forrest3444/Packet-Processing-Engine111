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
//   The registered FIFO head requests one whole-batch ROB allocation. Empty
//   batches are recognized only after capture and are released without an
//   allocation. Bank-local conditional updates expose common clock-enable
//   behavior without instantiating gated clocks.
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

    output logic [ppe_types_pkg::N-1:0]               alloc_req_valid_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]           alloc_seq_tag_o,
    input  logic                                      alloc_ready_i,

    output logic [ppe_types_pkg::N-1:0]               issue_alloc_valid_o,
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
    logic                      allocation_batch;

    logic [LANE_COUNT_W-1:0]   lower_pair_count;
    logic [LANE_COUNT_W-1:0]   upper_pair_count;
    logic [LANE_COUNT_W-1:0]   head_packet_count;
    logic [N-1:0][LANE_COUNT_W-1:0] lane_rank;

    //--------------------------------------------------------------------------
    // Registered head, elastic transfer, and registered backpressure
    //--------------------------------------------------------------------------

    always_comb begin : slot_head_request
        alloc_req_valid_o = '0;
        if (slot_count_q != '0) begin
            alloc_req_valid_o = slot_lane_valid_q[slot_rd_ptr_q];
        end
    end

    assign head_nonempty = |alloc_req_valid_o;
    assign allocation_batch = (slot_count_q != '0)
                              && head_nonempty
                              && alloc_ready_i;
    assign head_release = (slot_count_q != '0)
                          && (!head_nonempty || alloc_ready_i);

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
    // Registered-head rank, sequence, and descriptor decode
    //--------------------------------------------------------------------------

    always_comb begin : allocation_metadata_decode
        lane_rank              = '0;
        alloc_seq_tag_o        = '0;
        alloc_target_seq_tag_o = '0;
        alloc_packet_o         = '0;
        alloc_delay_o          = '0;
        alloc_dep_required_o   = '0;

        lower_pair_count = LANE_COUNT_W'(alloc_req_valid_o[0])
                           + LANE_COUNT_W'(alloc_req_valid_o[1]);
        upper_pair_count = LANE_COUNT_W'(alloc_req_valid_o[2])
                           + LANE_COUNT_W'(alloc_req_valid_o[3]);

        lane_rank[0] = '0;
        lane_rank[1] = LANE_COUNT_W'(alloc_req_valid_o[0]);
        lane_rank[2] = lower_pair_count;
        lane_rank[3] = lower_pair_count
                       + LANE_COUNT_W'(alloc_req_valid_o[2]);
        head_packet_count = lower_pair_count + upper_pair_count;

        for (int lane_idx = 0; lane_idx < N; lane_idx++) begin
            if (alloc_req_valid_o[lane_idx]) begin
                alloc_seq_tag_o[lane_idx] =
                    next_seq_tag_q + SEQ_W'(lane_rank[lane_idx]);
                alloc_packet_o[lane_idx] =
                    slot_packet_q[slot_rd_ptr_q][lane_idx];
                alloc_delay_o[lane_idx] =
                    slot_desc_q[slot_rd_ptr_q][lane_idx][DELAY_W-1:0];

                if (slot_desc_q[slot_rd_ptr_q][lane_idx][DEP_MSB:DEP_LSB]
                    != '0) begin
                    alloc_dep_required_o[lane_idx] = 1'b1;
                    alloc_target_seq_tag_o[lane_idx] =
                        alloc_seq_tag_o[lane_idx]
                        - SEQ_W'(slot_desc_q[slot_rd_ptr_q][lane_idx]
                                 [DEP_MSB:DEP_LSB]);
                end
            end
        end
    end

    assign issue_alloc_valid_o =
        alloc_req_valid_o & {N{allocation_batch}};

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
        end else if (allocation_batch) begin
            next_seq_tag_q <= next_seq_tag_q + SEQ_W'(head_packet_count);
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
