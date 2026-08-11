// -----------------------------------------------------------------------------
// File       : ppe_tb_pkg.sv
// Author     : Codex
// Description: PPE minimal UVM package.
// -----------------------------------------------------------------------------

`ifndef PPE_TB_PKG_SV
`define PPE_TB_PKG_SV
`include "rtl/common/ppe_config.vh"

package ppe_tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int PACKET_W = `PPE_DEFAULT_PACKET_W;
    // Verification dimensions are derived from the common design config.
    parameter int TB_N      = `PPE_N;
    parameter int TB_DESC_W = `PPE_DEFAULT_DESC_W;
    parameter int TB_LANE_W = (TB_N <= 1) ? 1 : $clog2(TB_N);
    parameter int TB_DELAY_CLASSES = (1 << `PPE_DELAY_W);

    parameter int TB_SEQ_W    = `PPE_SEQ_W;
    parameter int TB_ROB_ID_W = `PPE_ROB_ID_W;
    parameter int TB_OCC_W    = $clog2(`PPE_ROB_DEPTH + 1);

    typedef virtual ppe_if #(PACKET_W, TB_DESC_W, TB_N,
                             TB_SEQ_W, TB_ROB_ID_W, TB_OCC_W)
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
    `include "ppe_seq_base.sv"
    `include "ppe_random_seq_base.sv"
    `include "ppe_test_base.sv"
    `include "ppe_random_test_base.sv"
    `include "ppe_basic_seq.sv"
    `include "ppe_dep_loss_seq.sv"
    `include "ppe_p0_perf_seq.sv"
    `include "ppe_load_mix_perf_seq.sv"
    `include "ppe_rob32_wrap_seq.sv"
    `include "ppe_ingress_elastic_stress_seq.sv"
    `include "ppe_uniform_random_delay_seq.sv"
    `include "ppe_basic_test.sv"
    `include "ppe_dep_loss_test.sv"
    `include "ppe_p0_perf_test.sv"
    `include "ppe_load_mix_perf_test.sv"
    `include "ppe_pipeline_stall_test.sv"
    `include "ppe_rob32_wrap_test.sv"
    `include "ppe_ingress_elastic_stress_test.sv"
    `include "ppe_uniform_random_delay_test.sv"

endpackage

`endif
