// -----------------------------------------------------------------------------
// File       : ppe_if.sv
// Author     : Codex
// Description: PPE verification interface.
// -----------------------------------------------------------------------------

`ifndef PPE_IF_SV
`define PPE_IF_SV

`include "rtl/common/ppe_config.vh"

interface ppe_if #(
    parameter int PACKET_W     = `PPE_DEFAULT_PACKET_W,
    parameter int DESC_W       = `PPE_DEFAULT_DESC_W,
    parameter int N            = `PPE_N,
    parameter int DBG_SEQ_W    = `PPE_SEQ_W,
    parameter int DBG_ROB_ID_W = `PPE_ROB_ID_W,
    parameter int DBG_OCC_W    = $clog2(`PPE_ROB_DEPTH + 1)
) (
    input logic clk,
    input logic rst_n
);

    logic [N-1:0]         in_valid;
    logic [PACKET_W-1:0] in_packet [0:N-1];
    logic [DESC_W-1:0]   in_desc   [0:N-1];
    logic                 bkps;

    logic [N-1:0]         out_valid;
    logic [PACKET_W-1:0] out_packet [0:N-1];

    // Verification-only visibility for directed and performance checks.
    logic [N-1:0]         dbg_wb_valid;
    logic [(N*DBG_SEQ_W)-1:0] dbg_wb_seq_tag;
    logic                 dbg_fallback_valid;
    logic                 dbg_fallback_ready;
    logic                 dbg_fallback_from_d3;
    logic [DBG_SEQ_W-1:0] dbg_fallback_seq_tag;
    logic [DBG_ROB_ID_W-1:0] dbg_fallback_rob_id;
    logic [2:0]           dbg_fallback_residue;
    logic                 dbg_cache0_valid;
    logic [DBG_SEQ_W-1:0] dbg_cache0_seq_tag;
    logic [2:0]           dbg_entry1_state;
    logic                 dbg_rob0_valid;
    logic [DBG_SEQ_W-1:0] dbg_rob0_seq_tag;
    logic                 dbg_result0_valid;
    logic [DBG_SEQ_W-1:0] dbg_result0_seq_tag;
    logic [DBG_ROB_ID_W-1:0] dbg_head_ptr;
    logic                 dbg_fallback_lookup_hit;
    logic [N-1:0]         dbg_fe_in_valid;
    logic [DBG_OCC_W-1:0] dbg_rob_occupancy;

    task clear_inputs();
        for (int unsigned lane = 0; lane < N; lane++) begin
            in_valid[lane]  <= 1'b0;
            in_packet[lane] <= '0;
            in_desc[lane]   <= '0;
        end
    endtask

endinterface

`endif
