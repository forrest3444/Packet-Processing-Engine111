//------------------------------------------------------------------------------
// File        : tb_top_sv.sv
// Description : UVM top for the new SystemVerilog PPE implementation.
//
// This top reuses the existing interface, agents, sequences, scoreboard, tests,
// and FE probe. The legacy tb_top and legacy RTL hierarchy remain unchanged.
//------------------------------------------------------------------------------

`timescale 1ns/1ps

`include "ppe_if.sv"
`include "ppe_tb_pkg.sv"

module tb_top_sv;
    import uvm_pkg::*;
    import ppe_types_pkg::*;
    import ppe_tb_pkg::*;

    logic clk;
    logic rst_n;

    // Verification-only baseline parameter consistency checks.
    initial begin
        if (ROB_DEPTH != ISSUE_DEPTH) begin
            $fatal(1, "ROB_DEPTH must equal ISSUE_DEPTH");
        end
        if ((ROB_DEPTH < N) || ((ROB_DEPTH & (ROB_DEPTH - 1)) != 0)) begin
            $fatal(1, "ROB_DEPTH must be a power of two and at least N");
        end
        if ((1 << SEQ_W) < (ROB_DEPTH + MAX_DEP)) begin
            $fatal(1, "SEQ_W does not cover the active and dependency window");
        end
    end

    ppe_if #(PACKET_W, TB_SEQ_W, TB_ROB_ID_W, TB_OCC_W) pif (
        .clk   (clk),
        .rst_n (rst_n)
    );

    ppe_top_sv #(
        .PACKET_W (PACKET_W),
        .DESC_W   (5)
    ) dut (
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

    // Preserve the standalone FE contract test already present in the UVM
    // environment. It is independent from the four FEs inside ppe_top_sv.
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

    // Shared performance/debug probes with direct equivalents in the new RTL.
    assign pif.dbg_wb_valid      = dut.completion_valid;
    assign pif.dbg_wb_seq_tag    = dut.completion_seq_tag;
    assign pif.dbg_fe_in_valid   = dut.issue_valid;
    assign pif.dbg_rob_occupancy = dut.u_rob.occupancy_q;
    assign pif.dbg_rob0_valid    = dut.u_rob.rob_valid_q[0];
    assign pif.dbg_rob0_seq_tag  = dut.u_rob.rob_seq_tag_q[0];
    assign pif.dbg_result0_valid = dut.u_rob.rob_result_valid_q[0];
    assign pif.dbg_result0_seq_tag = dut.u_rob.rob_seq_tag_q[0];
    assign pif.dbg_head_ptr      = dut.u_rob.head_ptr_q;

    // The new architecture has no completion cache fallback/replay path. Map
    // the nearest authoritative retired-history visibility and tie obsolete
    // legacy-only probes inactive.
    assign pif.dbg_cache0_valid       = dut.u_rob.history_valid_q[0];
    assign pif.dbg_cache0_seq_tag     = dut.u_rob.history_seq_tag_q[0];
    assign pif.dbg_fallback_valid     = 1'b0;
    assign pif.dbg_fallback_ready     = 1'b0;
    assign pif.dbg_fallback_from_d3   = 1'b0;
    assign pif.dbg_fallback_seq_tag   = '0;
    assign pif.dbg_fallback_rob_id    = '0;
    assign pif.dbg_fallback_residue   = '0;
    assign pif.dbg_fallback_lookup_hit = 1'b0;

    // Translate the unified two-bit issue state into the closest legacy debug
    // encoding so existing diagnostic messages remain readable.
    always_comb begin
        unique case (dut.u_issue_table.issue_entry_q[1].state)
            2'd0: pif.dbg_entry1_state = 3'd0;
            2'd1: pif.dbg_entry1_state = 3'd2;
            2'd2: pif.dbg_entry1_state =
                      dut.u_issue_table.issue_entry_q[1].dep_required
                      ? 3'd4 : 3'd3;
            default: pif.dbg_entry1_state =
                         dut.u_issue_table.issue_entry_q[1].dep_required
                         ? 3'd6 : 3'd5;
        endcase
    end

    // Verification-only calendar consistency. A protocol-valid FE return must
    // exactly coincide with the scheduler's current reserved return slot.
    always @(posedge clk) begin
        if (dut.internal_rst_n) begin
            for (int unsigned fe_idx = 0; fe_idx < 4; fe_idx++) begin
                if (dut.fe_out_valid[fe_idx] !==
                    dut.u_fe_scheduler.return_slot_valid_q[fe_idx]
                                                    [dut.u_fe_scheduler
                                                        .schedule_phase_q]) begin
                    `uvm_error("FE_CALENDAR", $sformatf(
                        "FE%0d return valid=%0b calendar=%0b phase=%0d",
                        fe_idx, dut.fe_out_valid[fe_idx],
                        dut.u_fe_scheduler.return_slot_valid_q[fe_idx]
                                                       [dut.u_fe_scheduler
                                                           .schedule_phase_q],
                        dut.u_fe_scheduler.schedule_phase_q))
                end
            end
        end
    end

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

endmodule : tb_top_sv
