// -----------------------------------------------------------------------------
// File       : ppe_tb_pkg.sv
// Author     : Codex
// Description: PPE minimal UVM package.
// -----------------------------------------------------------------------------

`ifndef PPE_TB_PKG_SV
`define PPE_TB_PKG_SV

package ppe_tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int PACKET_W = 128;

    typedef virtual ppe_if #(PACKET_W) ppe_vif_t;

    `include "ppe_item.sv"
    `include "ppe_driver.sv"
    `include "ppe_master_agent.sv"
    `include "ppe_out_monitor.sv"
    `include "ppe_slave_agent.sv"
    `include "ppe_scoreboard.sv"
    `include "ppe_env.sv"
    `include "ppe_basic_seq.sv"
    `include "ppe_basic_test.sv"

endpackage

`endif
