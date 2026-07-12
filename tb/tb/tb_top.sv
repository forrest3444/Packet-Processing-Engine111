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
        uvm_config_db #(ppe_vif_t)::set(null, "uvm_test_top.env.master_agent.*", "vif", pif);
        uvm_config_db #(ppe_vif_t)::set(null, "uvm_test_top.env.slave_agent.*", "vif", pif);
        run_test("ppe_basic_test");
    end
endmodule
