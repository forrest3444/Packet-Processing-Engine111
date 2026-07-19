`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_ingress.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Frontend / Ingress
//
// Description :
//   Accepts up to N input lanes as one globally backpressured batch. For each
//   accepted lane, this block calculates its valid-lane rank, assigns a dense
//   global sequence tag, precomputes the dependency target tag, decodes the
//   descriptor into delay/dep-required semantics, and forms allocation metadata
//   captured by the issue table and ROB on the acceptance edge. Each consumer
//   derives its local physical index from the complete sequence tag.
//
//   Output array indices retain the physical input-lane number. Sequence tags
//   are dense across valid lanes in ascending lane order; the packet payload is
//   not compacted into different array positions.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 2.3, 3, and 4
//   - doc/hld.txt, Sections 4.1 and 5.1
//   - doc/lld.txt, Sections 5.1, 5.2, and 6
//
// Clock/reset :
//   Sequential state is clocked by clk_i. rst_ni is the active-low internal
//   reset distributed by ppe_top after asynchronous assertion and synchronized
//   deassertion.
//
// Implementation status:
//   Implements the complete D0 ingress datapath and sequence state. Dependency
//   readiness, issue-table state, ROB state, and FE scheduling are external.
//------------------------------------------------------------------------------

module ppe_ingress #(
    parameter int unsigned PACKET_W = 128,
    parameter int unsigned DESC_W   = 5
) (
    // Clock and reset
    input  logic                                      clk_i,
    input  logic                                      rst_ni,

    // Top-level input lanes. A batch is accepted only when bkps_i is low.
    input  logic [ppe_types_pkg::N-1:0]               in_valid_i,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] in_packet_i,
    input  logic [ppe_types_pkg::N-1:0][DESC_W-1:0]   in_desc_i,
    input  logic                                      bkps_i,

    // Accepted allocation metadata. Outputs retain input-lane indexing. The
    // complete sequence tag is the only cross-module transaction identity.
    output logic [ppe_types_pkg::N-1:0]               alloc_valid_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]           alloc_seq_tag_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]           alloc_target_seq_tag_o,
    output logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] alloc_packet_o,
    output logic [ppe_types_pkg::N-1:0][1:0]          alloc_delay_o,
    output logic [ppe_types_pkg::N-1:0]               alloc_dep_required_o
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Local parameters and type declarations
    //--------------------------------------------------------------------------

    localparam int unsigned LANE_COUNT_W = $clog2(N + 1);
    localparam int unsigned DEP_MSB      = 4;
    localparam int unsigned DEP_LSB      = 2;


    //--------------------------------------------------------------------------
    // Internal signal declarations
    //--------------------------------------------------------------------------

    logic [SEQ_W-1:0] next_seq_tag_q;

    logic                           accept_batch;
    logic [LANE_COUNT_W-1:0]        input_count;
    logic [N-1:0][LANE_COUNT_W-1:0] lane_rank;

    integer rank_idx;
    integer alloc_idx;


    //--------------------------------------------------------------------------
    // Input admission and valid-lane rank calculation
    //--------------------------------------------------------------------------

    always_comb begin
        input_count = '0;
        lane_rank   = '0;

        // The running count before each lane is that lane's dense rank.
        for (rank_idx = 0; rank_idx < N; rank_idx++) begin
            lane_rank[rank_idx] = input_count;

            if (in_valid_i[rank_idx]) begin
                input_count = input_count + LANE_COUNT_W'(1);
            end
        end
    end

    // Backend forces bkps_i high throughout reset. Keeping reset out of this
    // combinational path avoids broadcasting the reset tree into the datapath.
    assign accept_batch = !bkps_i;


    //--------------------------------------------------------------------------
    // Sequence, dependency-target, and allocation metadata generation
    //
    // ROB and history indices are derived downstream from the complete tags.
    // No independently stored or transported residue is generated here.
    //--------------------------------------------------------------------------

    always_comb begin
        alloc_valid_o          = in_valid_i & {N{accept_batch}};
        alloc_seq_tag_o        = '0;
        alloc_target_seq_tag_o = '0;
        alloc_packet_o         = in_packet_i;
        alloc_delay_o          = '0;
        alloc_dep_required_o   = '0;

        // Data buses are qualified only by alloc_valid_o at their consumers.
        // Leaving them ungated removes bkps/reset-controlled wide datapath muxes.
        for (alloc_idx = 0; alloc_idx < N; alloc_idx++) begin
            alloc_seq_tag_o[alloc_idx] =
                next_seq_tag_q + SEQ_W'(lane_rank[alloc_idx]);
            alloc_delay_o[alloc_idx] = in_desc_i[alloc_idx][1:0];

            // A zero dependency offset has no target; keep its tag at zero.
            if (in_desc_i[alloc_idx][DEP_MSB:DEP_LSB] != '0) begin
                alloc_dep_required_o[alloc_idx] = 1'b1;
                alloc_target_seq_tag_o[alloc_idx] =
                    alloc_seq_tag_o[alloc_idx] -
                    SEQ_W'(in_desc_i[alloc_idx][DEP_MSB:DEP_LSB]);
            end
        end
    end


    //--------------------------------------------------------------------------
    // Sequential state update
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            next_seq_tag_q <= '0;
        end else if (accept_batch && (input_count != '0)) begin
            // Explicit enable supports clock-enable or automatic ICG inference.
            next_seq_tag_q <= next_seq_tag_q + SEQ_W'(input_count);
        end
    end


endmodule : ppe_ingress

`default_nettype wire
