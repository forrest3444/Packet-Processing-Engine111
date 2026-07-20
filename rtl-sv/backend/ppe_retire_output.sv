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
    parameter int unsigned PACKET_W = 128
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

    localparam int unsigned LANE_ID_W = (N > 1) ? $clog2(N) : 1;
    localparam int unsigned RETIRE_COUNT_W = $clog2(N + 1);

    typedef logic [LANE_ID_W-1:0]      lane_id_t;
    typedef logic [RETIRE_COUNT_W-1:0] retire_count_t;

    function automatic lane_id_t lane_add(
        input lane_id_t      base,
        input retire_count_t offset
    );
        logic [RETIRE_COUNT_W:0] sum;
        begin
            sum = (RETIRE_COUNT_W + 1)'(base)
                  + (RETIRE_COUNT_W + 1)'(offset);
            if (sum >= (RETIRE_COUNT_W + 1)'(N)) begin
                sum = sum - (RETIRE_COUNT_W + 1)'(N);
            end
            lane_add = lane_id_t'(sum);
        end
    endfunction

    lane_id_t start_lane_q;
    retire_count_t retire_count;

    logic [N-1:0]               mapped_valid;
    logic [N-1:0][PACKET_W-1:0] mapped_data;

    //--------------------------------------------------------------------------
    // Logical-retirement to physical-lane mapping
    //--------------------------------------------------------------------------

    always_comb begin
        retire_count = '0;
        mapped_valid = '0;
        mapped_data  = '0;

        for (int unsigned retire_idx = 0; retire_idx < N; retire_idx++) begin
            lane_id_t physical_lane;

            physical_lane = lane_add(
                start_lane_q, retire_count_t'(retire_idx));

            if (retire_valid_i[retire_idx]) begin
                mapped_valid[physical_lane] = 1'b1;
                mapped_data[physical_lane]  = retire_data_i[retire_idx];
                retire_count = retire_count + retire_count_t'(1);
            end
        end
    end

    //--------------------------------------------------------------------------
    // Registered output update
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            start_lane_q <= '0;
            out_valid_o  <= '0;
        end else begin
            out_valid_o <= mapped_valid;

            for (int unsigned lane_idx = 0; lane_idx < N; lane_idx++) begin
                if (mapped_valid[lane_idx]) begin
                    out_packet_o[lane_idx] <= mapped_data[lane_idx];
                end
            end

            if (retire_count != '0) begin
                start_lane_q <= lane_add(start_lane_q, retire_count);
            end
        end
    end

endmodule : ppe_retire_output

`default_nettype wire
