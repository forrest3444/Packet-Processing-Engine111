//------------------------------------------------------------------------------
// UVM top for the independent single-FE in-order architecture baseline.
// Existing interfaces, agents, sequences, scoreboard, and tests are reused.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "ppe_if.sv"
`include "ppe_tb_pkg.sv"

module tb_top_single_fe;
    import uvm_pkg::*;
    import ppe_types_pkg::*;
    import ppe_tb_pkg::*;

    logic clk;
    logic rst_n;

    ppe_if #(PACKET_W, TB_SEQ_W, TB_ROB_ID_W, TB_OCC_W) pif (
        .clk   (clk),
        .rst_n (rst_n)
    );

    ppe_single_fe_inorder #(
        .PACKET_W (PACKET_W),
        .DESC_W   (5)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_valid   ({pif.in_valid3, pif.in_valid2,
                      pif.in_valid1, pif.in_valid0}),
        .in_packet  ({pif.in_packet3, pif.in_packet2,
                      pif.in_packet1, pif.in_packet0}),
        .in_desc    ({pif.in_desc3, pif.in_desc2,
                      pif.in_desc1, pif.in_desc0}),
        .bkps       (pif.bkps),
        .out_valid  ({pif.out_valid3, pif.out_valid2,
                      pif.out_valid1, pif.out_valid0}),
        .out_packet ({pif.out_packet3, pif.out_packet2,
                      pif.out_packet1, pif.out_packet0})
    );

    // Verification-only FE protocol probe retained for ppe_fe_pipeline_test.
    fe_mock #(
        .PACKET_W (PACKET_W)
    ) u_fe_probe (
        .clk           (clk),
        .rst_n         (rst_n),
        .fe_in_valid   (pif.fe_probe_in_valid),
        .fe_in_data    (pif.fe_probe_in_data),
        .fe_dep_valid  (pif.fe_probe_dep_valid),
        .fe_dep_data   (pif.fe_probe_dep_data),
        .fe_desc_delay (pif.fe_probe_delay),
        .fe_out_valid  (pif.fe_probe_out_valid),
        .fe_out_data   (pif.fe_probe_out_data)
    );

    assign pif.dbg_wb_valid =
        {3'b000, dut.fe_out_valid && dut.inflight_valid_q};
    assign pif.dbg_wb_seq_tag =
        {{3{TB_SEQ_W'(0)}}, dut.inflight_seq_tag_q};
    assign pif.dbg_fe_in_valid = {3'b000, dut.dispatch_packet};
    assign pif.dbg_rob_occupancy = dut.fifo_count_q;
    assign pif.dbg_head_ptr = dut.fifo_head_ptr_q;

    assign pif.dbg_cache0_valid   = dut.history_valid_q[0];
    assign pif.dbg_cache0_seq_tag = dut.history_seq_tag_q[0];

    assign pif.dbg_rob0_valid =
        (dut.fifo_count_q != '0) && (dut.fifo_head_ptr_q == '0);
    assign pif.dbg_rob0_seq_tag = dut.fifo_seq_tag_q[0];
    assign pif.dbg_result0_valid = dut.history_valid_q[0];
    assign pif.dbg_result0_seq_tag = dut.history_seq_tag_q[0];

    always_comb begin : dependency_debug_state
        logic [2:0] history_id;
        logic       dependency_hit;

        history_id = dut.fifo_target_tag_q[1][2:0];
        dependency_hit = dut.history_valid_q[history_id]
            && (dut.history_seq_tag_q[history_id]
                == dut.fifo_target_tag_q[1]);
        if ((dut.fifo_count_q > 1)
            && dut.fifo_dep_required_q[1]
            && !dependency_hit) begin
            pif.dbg_entry1_state = 3'd2;
        end else begin
            pif.dbg_entry1_state = 3'd0;
        end
    end

    assign pif.dbg_fallback_valid      = 1'b0;
    assign pif.dbg_fallback_ready      = 1'b0;
    assign pif.dbg_fallback_from_d3    = 1'b0;
    assign pif.dbg_fallback_seq_tag    = '0;
    assign pif.dbg_fallback_rob_id     = '0;
    assign pif.dbg_fallback_residue    = '0;
    assign pif.dbg_fallback_lookup_hit = 1'b0;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        pif.clear_inputs();
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        uvm_config_db #(ppe_vif_t)::set(null, "uvm_test_top", "vif", pif);
        uvm_config_db #(ppe_vif_t)::set(
            null, "uvm_test_top.env.master_agent.*", "vif", pif);
        uvm_config_db #(ppe_vif_t)::set(
            null, "uvm_test_top.env.slave_agent.*", "vif", pif);
        run_test();
    end

endmodule : tb_top_single_fe
