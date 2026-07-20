`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_ingress.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Frontend / Ingress
//
// Description :
//   Implements the PPE external input-register boundary with a two-entry,
//   whole-batch skid FIFO. Raw top-level inputs are used only when capturing a
//   FIFO entry. All sequence allocation, descriptor decoding, and dependency
//   target calculation use the registered FIFO head.
//
//   The registered bkps output reserves room for the maximum batch that may
//   arrive before backpressure takes effect. The ROB returns one whole-batch
//   allocation permission for the registered head. A successful permission
//   generates the accepted allocation event consumed by the issue table.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 2.3, 3, and 4
//   - doc/hld.txt, Sections 3.2, 4.1, 4.6, and 5.1
//   - doc/lld.txt, Sections 3.2, 5.0, 5.1, 6, and 14
//
// Clock/reset :
//   Sequential state is clocked by clk_i. rst_ni is the shared active-low
//   internal reset. Reset clears FIFO control/valid state, sequence state, and
//   forces registered backpressure high. Wide packet/descriptor arrays are not
//   reset because FIFO count and lane-valid state qualify their contents.
//------------------------------------------------------------------------------

module ppe_ingress #(
    parameter int unsigned PACKET_W = 128,
    parameter int unsigned DESC_W   = 5
) (
    // Clock and reset
    input  logic                                      clk_i,
    input  logic                                      rst_ni,

    // Raw PPE inputs. These signals are used only by FIFO capture state.
    input  logic [ppe_types_pkg::N-1:0]               in_valid_i,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] in_packet_i,
    input  logic [ppe_types_pkg::N-1:0][DESC_W-1:0]   in_desc_i,

    // Registered PPE-wide input backpressure.
    output logic                                      bkps_o,

    // Registered FIFO-head request to the ROB. Request lanes and metadata
    // remain stable while alloc_ready_i is low.
    output logic [ppe_types_pkg::N-1:0]               alloc_req_valid_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]           alloc_seq_tag_o,
    input  logic                                      alloc_ready_i,

    // Accepted allocation event and decoded metadata for the issue table.
    output logic [ppe_types_pkg::N-1:0]               issue_alloc_valid_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]           alloc_target_seq_tag_o,
    output logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] alloc_packet_o,
    output logic [ppe_types_pkg::N-1:0][1:0]          alloc_delay_o,
    output logic [ppe_types_pkg::N-1:0]               alloc_dep_required_o
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Local parameters and state
    //--------------------------------------------------------------------------

    localparam int unsigned FIFO_DEPTH   = 2;
    localparam int unsigned FIFO_COUNT_W = $clog2(FIFO_DEPTH + 1);
    localparam int unsigned LANE_COUNT_W = $clog2(N + 1);
    localparam int unsigned DEP_MSB      = 4;
    localparam int unsigned DEP_LSB      = 2;

    logic [FIFO_DEPTH-1:0][N-1:0]               fifo_lane_valid_q;
    logic [FIFO_DEPTH-1:0][N-1:0][PACKET_W-1:0] fifo_packet_q;
    logic [FIFO_DEPTH-1:0][N-1:0][DESC_W-1:0]   fifo_desc_q;

    logic                       fifo_rd_ptr_q;
    logic                       fifo_wr_ptr_q;
    logic [FIFO_COUNT_W-1:0]    fifo_count_q;
    logic [SEQ_W-1:0]           next_seq_tag_q;
    logic                       bkps_q;
    logic                       bkps_d;

    logic                       enqueue_batch;
    logic                       dequeue_batch;
    logic [FIFO_COUNT_W:0]      reserved_count_next;
    logic [LANE_COUNT_W-1:0]    head_packet_count;
    logic [N-1:0][LANE_COUNT_W-1:0] lane_rank;

    //--------------------------------------------------------------------------
    // FIFO-head request and registered backpressure prediction
    //--------------------------------------------------------------------------

    always_comb begin
        alloc_req_valid_o = '0;
        if (fifo_count_q != '0) begin
            alloc_req_valid_o = fifo_lane_valid_q[fifo_rd_ptr_q];
        end
    end

    assign dequeue_batch = (|alloc_req_valid_o) && alloc_ready_i;
    assign enqueue_batch = !bkps_q && (|in_valid_i);

    // possible enqueue deliberately depends only on the registered bkps state,
    // not on current raw input valid. It reserves one worst-case incoming batch
    // whenever the external interface is open.
    always_comb begin
        reserved_count_next = (FIFO_COUNT_W + 1)'(fifo_count_q)
                              - (FIFO_COUNT_W + 1)'(dequeue_batch)
                              + (FIFO_COUNT_W + 1)'(!bkps_q);
        bkps_d = (reserved_count_next >= (FIFO_COUNT_W + 1)'(FIFO_DEPTH));
    end

    assign bkps_o = bkps_q;

    //--------------------------------------------------------------------------
    // Registered-head rank, sequence, and descriptor decode
    //--------------------------------------------------------------------------

    always_comb begin
        head_packet_count      = '0;
        lane_rank              = '0;
        alloc_seq_tag_o        = '0;
        alloc_target_seq_tag_o = '0;
        alloc_packet_o         = '0;
        alloc_delay_o          = '0;
        alloc_dep_required_o   = '0;

        for (int unsigned lane_idx = 0; lane_idx < N; lane_idx++) begin
            lane_rank[lane_idx] = head_packet_count;

            if (alloc_req_valid_o[lane_idx]) begin
                alloc_seq_tag_o[lane_idx] =
                    next_seq_tag_q + SEQ_W'(lane_rank[lane_idx]);
                alloc_packet_o[lane_idx] =
                    fifo_packet_q[fifo_rd_ptr_q][lane_idx];
                alloc_delay_o[lane_idx] =
                    fifo_desc_q[fifo_rd_ptr_q][lane_idx][1:0];

                if (fifo_desc_q[fifo_rd_ptr_q][lane_idx][DEP_MSB:DEP_LSB]
                    != '0) begin
                    alloc_dep_required_o[lane_idx] = 1'b1;
                    alloc_target_seq_tag_o[lane_idx] =
                        alloc_seq_tag_o[lane_idx]
                        - SEQ_W'(fifo_desc_q[fifo_rd_ptr_q][lane_idx]
                                 [DEP_MSB:DEP_LSB]);
                end

                head_packet_count =
                    head_packet_count + LANE_COUNT_W'(1);
            end
        end
    end

    assign issue_alloc_valid_o =
        alloc_req_valid_o & {N{alloc_ready_i}};

    //--------------------------------------------------------------------------
    // FIFO, sequence, and registered-backpressure state update
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            fifo_lane_valid_q <= '0;
            fifo_rd_ptr_q     <= 1'b0;
            fifo_wr_ptr_q     <= 1'b0;
            fifo_count_q      <= '0;
            next_seq_tag_q    <= '0;
            bkps_q            <= 1'b1;
        end else begin
            bkps_q <= bkps_d;

            if (enqueue_batch) begin
                fifo_lane_valid_q[fifo_wr_ptr_q] <= in_valid_i;
                for (int unsigned lane_idx = 0; lane_idx < N; lane_idx++) begin
                    if (in_valid_i[lane_idx]) begin
                        fifo_packet_q[fifo_wr_ptr_q][lane_idx] <=
                            in_packet_i[lane_idx];
                        fifo_desc_q[fifo_wr_ptr_q][lane_idx] <=
                            in_desc_i[lane_idx];
                    end
                end
                fifo_wr_ptr_q <= ~fifo_wr_ptr_q;
            end

            if (dequeue_batch) begin
                fifo_lane_valid_q[fifo_rd_ptr_q] <= '0;
                fifo_rd_ptr_q  <= ~fifo_rd_ptr_q;
                next_seq_tag_q <=
                    next_seq_tag_q + SEQ_W'(head_packet_count);
            end

            unique case ({enqueue_batch, dequeue_batch})
                2'b10: fifo_count_q <= fifo_count_q + FIFO_COUNT_W'(1);
                2'b01: fifo_count_q <= fifo_count_q - FIFO_COUNT_W'(1);
                default: begin
                    // Hold count for no transfer or simultaneous replacement.
                end
            endcase
        end
    end

endmodule : ppe_ingress

`default_nettype wire
