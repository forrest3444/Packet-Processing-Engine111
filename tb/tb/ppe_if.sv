// -----------------------------------------------------------------------------
// File       : ppe_if.sv
// Author     : Codex
// Description: PPE verification interface.
// -----------------------------------------------------------------------------

`ifndef PPE_IF_SV
`define PPE_IF_SV

interface ppe_if #(
    parameter int PACKET_W    = 128,
    parameter int DBG_SEQ_W   = 5,
    parameter int DBG_ROB_ID_W = 4,
    parameter int DBG_OCC_W   = 5
) (
    input logic clk,
    input logic rst_n
);

    logic                 in_valid0;
    logic [PACKET_W-1:0] in_packet0;
    logic [4:0]          in_desc0;
    logic                 in_valid1;
    logic [PACKET_W-1:0] in_packet1;
    logic [4:0]          in_desc1;
    logic                 in_valid2;
    logic [PACKET_W-1:0] in_packet2;
    logic [4:0]          in_desc2;
    logic                 in_valid3;
    logic [PACKET_W-1:0] in_packet3;
    logic [4:0]          in_desc3;
    logic                 bkps;

    logic                 out_valid0;
    logic [PACKET_W-1:0] out_packet0;
    logic                 out_valid1;
    logic [PACKET_W-1:0] out_packet1;
    logic                 out_valid2;
    logic [PACKET_W-1:0] out_packet2;
    logic                 out_valid3;
    logic [PACKET_W-1:0] out_packet3;

    // Verification-only visibility for directed and performance checks.
    logic [3:0]           dbg_wb_valid;
    logic [(4*DBG_SEQ_W)-1:0] dbg_wb_seq_tag;
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
    logic [3:0]           dbg_fe_in_valid;
    logic [DBG_OCC_W-1:0] dbg_rob_occupancy;

    logic                 fe_probe_in_valid;
    logic [PACKET_W-1:0]  fe_probe_in_data;
    logic                 fe_probe_dep_valid;
    logic [PACKET_W-1:0]  fe_probe_dep_data;
    logic [1:0]           fe_probe_delay;
    logic                 fe_probe_out_valid;
    logic [PACKET_W-1:0]  fe_probe_out_data;

    task clear_inputs();
        in_valid0  <= 1'b0;
        in_packet0 <= '0;
        in_desc0   <= '0;
        in_valid1  <= 1'b0;
        in_packet1 <= '0;
        in_desc1   <= '0;
        in_valid2  <= 1'b0;
        in_packet2 <= '0;
        in_desc2   <= '0;
        in_valid3  <= 1'b0;
        in_packet3 <= '0;
        in_desc3   <= '0;
        fe_probe_in_valid <= 1'b0;
        fe_probe_in_data <= '0;
        fe_probe_dep_valid <= 1'b0;
        fe_probe_dep_data <= '0;
        fe_probe_delay <= '0;
    endtask

endinterface

`endif
