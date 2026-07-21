`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_retire_output.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Backend / Retire Output
//
// Description :
//   Maps the ROB's dense, in-order logical retirement bundle onto the rotating
//   physical output lanes. This block owns the output start-lane pointer and
//   the registered top-level output valid/data signals.
//
//   retire_valid_i is a dense prefix beginning at slot zero. Slot order is
//   packet order, not physical lane order. The interface has no ready because
//   loading the output registers is the architectural retirement event.
//   The local retire count is derived from the valid prefix; no duplicate
//   count, sequence tag, ROB ID, or acknowledgement crosses this boundary.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 8 through 10
//   - doc/hld.txt, Sections 3.5 and 4.5
//   - doc/lld.txt, Sections 4.4 and 13.2 through 13.3
//
// Implementation status:
//   Complete. Physical lane mapping, start-lane state, and registered external
//   output behavior are implemented without a downstream handshake.
//------------------------------------------------------------------------------

module ppe_retire_output #(
    parameter int PACKET_W = ppe_types_pkg::DEFAULT_PACKET_W
) (
    // Clock and reset
    input  logic                                      clk_i,
    input  logic                                      rst_ni,

    // Irrevocable logical retirement event from ppe_rob. Valid slots form a
    // dense prefix; retire_data_i is meaningful only for valid slots. ROB
    // releases the same entries on this capture edge, so there is no ready.
    input  logic [ppe_types_pkg::N-1:0]               retire_valid_i,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] retire_data_i,

    // Registered physical output lanes. out_valid_o is cleared for lanes not
    // written by the current event; invalid out_packet_o lanes may hold data.
    output logic [ppe_types_pkg::N-1:0]               out_valid_o,
    output logic [ppe_types_pkg::N-1:0][PACKET_W-1:0] out_packet_o
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Local types and output start-lane state
    //--------------------------------------------------------------------------

    localparam int LANE_ID_W      = (N > 1) ? $clog2(N) : 1;
    localparam int RETIRE_COUNT_W = $clog2(N + 1);

    typedef logic [LANE_ID_W-1:0]      lane_id_t;
    typedef logic [RETIRE_COUNT_W-1:0] retire_count_t;

    lane_id_t start_lane_q;
    retire_count_t retire_count;

    logic [N-1:0]               rotate_one_valid;
    logic [N-1:0][PACKET_W-1:0] rotate_one_data;
    logic [N-1:0]               mapped_valid;
    logic [N-1:0][PACKET_W-1:0] mapped_data;

    //--------------------------------------------------------------------------
    // Logical-retirement to physical-lane mapping
    //--------------------------------------------------------------------------

    always_comb begin : retirement_lane_mapping
        // Stage one optionally rotates the logical bundle by one lane.
        rotate_one_valid = retire_valid_i;
        rotate_one_data  = retire_data_i;
        if (start_lane_q[0]) begin
            rotate_one_valid = {retire_valid_i[2:0], retire_valid_i[3]};
            rotate_one_data  = {retire_data_i[2:0], retire_data_i[3]};
        end

        // Stage two optionally rotates the stage-one bundle by two lanes.
        mapped_valid = rotate_one_valid;
        mapped_data  = rotate_one_data;
        if (start_lane_q[1]) begin
            mapped_valid = {rotate_one_valid[1:0], rotate_one_valid[3:2]};
            mapped_data  = {rotate_one_data[1:0], rotate_one_data[3:2]};
        end

        // retire_valid_i is contractually a dense prefix from logical slot 0.
        unique case (retire_valid_i)
            4'b0000: retire_count = RETIRE_COUNT_W'(0);
            4'b0001: retire_count = RETIRE_COUNT_W'(1);
            4'b0011: retire_count = RETIRE_COUNT_W'(2);
            4'b0111: retire_count = RETIRE_COUNT_W'(3);
            4'b1111: retire_count = RETIRE_COUNT_W'(4);
            default: retire_count = '0;
        endcase
    end

    //--------------------------------------------------------------------------
    // Registered output update
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin : output_state_update
        if (!rst_ni) begin
            start_lane_q <= '0;
            out_valid_o  <= '0;
        end else begin
            out_valid_o <= mapped_valid;

            for (int lane_idx = 0; lane_idx < N; lane_idx++) begin
                if (mapped_valid[lane_idx]) begin
                    out_packet_o[lane_idx] <= mapped_data[lane_idx];
                end
            end

            if (retire_count != '0) begin
                // N is fixed at four; truncation implements modulo-four wrap.
                start_lane_q <= start_lane_q + lane_id_t'(retire_count);
            end
        end
    end

endmodule : ppe_retire_output

`default_nettype wire
