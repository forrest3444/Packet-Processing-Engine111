// -----------------------------------------------------------------------------
// File       : tb_top.sv
// Author     : Codex
// Description: PPE UVM testbench top.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

`include "ppe_if.sv"
`include "ppe_tb_pkg.sv"

module tb_top;
    import uvm_pkg::*;
    import ppe_tb_pkg::*;

    logic clk;
    logic rst_n;

    ppe_if #(PACKET_W) pif (
        .clk   (clk),
        .rst_n (rst_n)
    );

    ppe_top dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_valid0   (pif.in_valid0),
        .in_packet0  (pif.in_packet0),
        .in_desc0    (pif.in_desc0),
        .in_valid1   (pif.in_valid1),
        .in_packet1  (pif.in_packet1),
        .in_desc1    (pif.in_desc1),
        .in_valid2   (pif.in_valid2),
        .in_packet2  (pif.in_packet2),
        .in_desc2    (pif.in_desc2),
        .in_valid3   (pif.in_valid3),
        .in_packet3  (pif.in_packet3),
        .in_desc3    (pif.in_desc3),
        .bkps        (pif.bkps),
        .out_valid0  (pif.out_valid0),
        .out_packet0 (pif.out_packet0),
        .out_valid1  (pif.out_valid1),
        .out_packet1 (pif.out_packet1),
        .out_valid2  (pif.out_valid2),
        .out_packet2 (pif.out_packet2),
        .out_valid3  (pif.out_valid3),
        .out_packet3 (pif.out_packet3)
    );

    assign pif.dbg_wb_valid          = dut.u_dispatch.wb_valid;
    assign pif.dbg_wb_seq_tag        = dut.u_dispatch.wb_seq_tag;
    assign pif.dbg_fallback_valid    = dut.u_dispatch.fallback_valid;
    assign pif.dbg_fallback_ready    = dut.u_dispatch.fallback_ready;
    assign pif.dbg_fallback_from_d3  = dut.u_dispatch.fallback_from_d3;
    assign pif.dbg_fallback_seq_tag  = dut.u_dispatch.fallback_seq_tag;
    assign pif.dbg_fallback_rob_id   = dut.u_dispatch.fallback_rob_id;
    assign pif.dbg_fallback_residue  = dut.u_dispatch.fallback_residue;
    assign pif.dbg_cache0_valid      = dut.u_dispatch.dep_cache_valid[0];
    assign pif.dbg_cache0_seq_tag    = dut.u_dispatch.dep_cache_seq_tag[0];
    assign pif.dbg_entry1_state      = dut.u_dispatch.entry_state[1];
    assign pif.dbg_rob0_valid        = dut.u_reorder.rob_valid[0];
    assign pif.dbg_rob0_seq_tag      = dut.u_reorder.rob_seq_tag[0];
    assign pif.dbg_result0_valid     = dut.u_reorder.result_valid[0];
    assign pif.dbg_result0_seq_tag   = dut.u_reorder.result_seq_tag[0];
    assign pif.dbg_head_ptr          = dut.u_reorder.head_ptr;
    assign pif.dbg_fallback_lookup_hit = dut.u_reorder.fallback_lookup[PACKET_W];
    assign pif.dbg_fe_in_valid       = dut.fe_in_valid;
    assign pif.dbg_fe_busy           = {dut.u_dispatch.fe_busy3,
                                        dut.u_dispatch.fe_busy2,
                                        dut.u_dispatch.fe_busy1,
                                        dut.u_dispatch.fe_busy0};
    assign pif.dbg_rob_occupancy     = dut.u_reorder.occupancy;

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
        uvm_config_db #(ppe_vif_t)::set(null, "uvm_test_top.env.master_agent.*", "vif", pif);
        uvm_config_db #(ppe_vif_t)::set(null, "uvm_test_top.env.slave_agent.*", "vif", pif);
        run_test("ppe_basic_test");
    end
endmodule
