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

`ifdef PPE_SV_ARCH
    parameter int TB_SEQ_W    = ppe_types_pkg::SEQ_W;
    parameter int TB_ROB_ID_W = ppe_types_pkg::ROB_ID_W;
    parameter int TB_OCC_W    = $clog2(ppe_types_pkg::ROB_DEPTH + 1);
`else
    parameter int TB_SEQ_W    = 5;
    parameter int TB_ROB_ID_W = 4;
    parameter int TB_OCC_W    = 5;
`endif

    typedef virtual ppe_if #(PACKET_W, TB_SEQ_W, TB_ROB_ID_W, TB_OCC_W)
            ppe_vif_t;

    `include "ppe_item.sv"
    `include "ppe_driver.sv"
    `include "ppe_in_monitor.sv"
    `include "ppe_master_agent.sv"
    `include "ppe_out_monitor.sv"
    `include "ppe_slave_agent.sv"
    `include "ppe_fe_vip.sv"
    `include "ppe_scoreboard.sv"
    `include "ppe_env.sv"
    `include "ppe_basic_seq.sv"
    `include "ppe_dep_loss_seq.sv"
    `include "ppe_p0_perf_seq.sv"
    `include "ppe_perf_seq.sv"
    `include "ppe_load_mix_perf_seq.sv"
    `include "ppe_fe_pipeline_seq.sv"
    `include "ppe_rob32_wrap_seq.sv"
    `include "ppe_basic_test.sv"
    `include "ppe_dep_loss_test.sv"
    `include "ppe_p0_perf_test.sv"
    `include "ppe_perf_test.sv"
    `include "ppe_load_mix_perf_test.sv"
    `include "ppe_fe_pipeline_test.sv"
    `include "ppe_rob32_wrap_test.sv"

endpackage

`endif
