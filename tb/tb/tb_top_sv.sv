//------------------------------------------------------------------------------
// File        : tb_top_sv.sv
// Description : UVM top for the maintained four-FE PPE implementation.
//------------------------------------------------------------------------------

`timescale 1ns/1ps
`include "rtl/common/ppe_config.vh"

`include "ppe_if.sv"
`include "ppe_tb_pkg.sv"

module tb_top_sv;
    import uvm_pkg::*;
    import ppe_tb_pkg::*;

    logic clk;
    logic rst_n;
    wire [PACKET_W-1:0] dut_in_packet [0:`PPE_N-1];
    wire [4:0] dut_in_desc [0:`PPE_N-1];
    wire [PACKET_W-1:0] dut_out_packet [0:`PPE_N-1];

    assign dut_in_packet[0] = pif.in_packet0;
    assign dut_in_packet[1] = pif.in_packet1;
    assign dut_in_packet[2] = pif.in_packet2;
    assign dut_in_packet[3] = pif.in_packet3;
    assign dut_in_desc[0] = pif.in_desc0;
    assign dut_in_desc[1] = pif.in_desc1;
    assign dut_in_desc[2] = pif.in_desc2;
    assign dut_in_desc[3] = pif.in_desc3;
    assign pif.out_packet0 = dut_out_packet[0];
    assign pif.out_packet1 = dut_out_packet[1];
    assign pif.out_packet2 = dut_out_packet[2];
    assign pif.out_packet3 = dut_out_packet[3];

    // Verification-only baseline parameter consistency checks.
    initial begin
        if (`PPE_ROB_DEPTH != `PPE_ISSUE_DEPTH) begin
            $fatal(1, "ROB_DEPTH must equal ISSUE_DEPTH");
        end
        if ((`PPE_ROB_DEPTH < `PPE_N)
            || ((`PPE_ROB_DEPTH & (`PPE_ROB_DEPTH - 1)) != 0)) begin
            $fatal(1, "ROB_DEPTH must be a power of two and at least N");
        end
        if ((1 << `PPE_SEQ_W)
            < (`PPE_ROB_DEPTH + `PPE_MAX_DEP)) begin
            $fatal(1, "SEQ_W does not cover the active and dependency window");
        end
    end

    ppe_if #(PACKET_W, TB_SEQ_W, TB_ROB_ID_W, TB_OCC_W) pif (
        .clk   (clk),
        .rst_n (rst_n)
    );

    PPE_TOP_SV #(
        .PACKET_W (PACKET_W),
        .DESC_W   (5)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_valid    ({pif.in_valid3, pif.in_valid2,
                       pif.in_valid1, pif.in_valid0}),
        .in_packet   (dut_in_packet),
        .in_desc     (dut_in_desc),
        .bkps        (pif.bkps),
        .out_valid   ({pif.out_valid3, pif.out_valid2,
                       pif.out_valid1, pif.out_valid0}),
        .out_packet  (dut_out_packet)
    );

    wire [63:0] probe_issue_state;
    wire [15:0] probe_candidate_legal;
    wire [(4*TB_SEQ_W)-1:0] probe_completion_seq_tag;
    genvar probe_entry;
    generate
        for (probe_entry = 0; probe_entry < 32;
             probe_entry = probe_entry + 1) begin : gen_probe_issue_state
            assign probe_issue_state[probe_entry*2 +: 2] =
                dut.u_scheduler.issue_state_q[probe_entry];
        end
    endgenerate

    genvar probe_candidate;
    generate
        for (probe_candidate = 0; probe_candidate < 8;
             probe_candidate = probe_candidate + 1) begin : gen_probe_candidate
            assign probe_candidate_legal[probe_candidate*2 +: 2] =
                dut.u_scheduler.candidate_legal[probe_candidate];
        end
    endgenerate

    genvar probe_fe;
    generate
        for (probe_fe = 0; probe_fe < 4;
             probe_fe = probe_fe + 1) begin : gen_probe_completion
            assign probe_completion_seq_tag[probe_fe*TB_SEQ_W +: TB_SEQ_W] =
                dut.completion_seq_tag[probe_fe];
        end
    endgenerate

    ppe_pipeline_stall_probe u_pipeline_stall_probe (
        .clk             (clk),
        .rst_n           (dut.internal_rst_n),
        .in_valid        (dut.in_valid),
        .bkps            (dut.bkps),
        .issue_valid     (dut.issue_valid),
        .completion_valid(dut.completion_valid),
        .retire_valid    (dut.retire_valid),
        .out_valid       (dut.out_valid),
        .rob_occupancy   (dut.u_rob.occupancy_q),
        .rob_head_ptr    (dut.u_rob.head_ptr_q),
        .rob_valid       (dut.u_rob.rob_valid_q),
        .rob_result_valid(dut.u_rob.rob_result_valid_q),
        .issue_state     (probe_issue_state),
        .candidate_valid (dut.u_scheduler.candidate_valid_q),
        .candidate_pending(dut.u_scheduler.candidate_pending),
        .candidate_legal (probe_candidate_legal),
        .shortlist_valid (dut.u_scheduler.shortlist_valid_d),
        .grant_valid     (dut.u_scheduler.grant_valid_d)
    );

    // Shared performance/debug probes with direct equivalents in the new RTL.
    assign pif.dbg_wb_valid      = dut.completion_valid;
    assign pif.dbg_wb_seq_tag    = probe_completion_seq_tag;
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
        unique case (dut.u_scheduler.issue_state_q[1])
            2'd0: pif.dbg_entry1_state = 3'd0;
            2'd1: pif.dbg_entry1_state = 3'd2;
            2'd2: pif.dbg_entry1_state =
                      dut.u_scheduler.issue_dep_required_q[1]
                      ? 3'd4 : 3'd3;
            default: pif.dbg_entry1_state =
                         dut.u_scheduler.issue_dep_required_q[1]
                         ? 3'd6 : 3'd5;
        endcase
    end

    // Verification-only return-table consistency. A protocol-valid FE return
    // must exactly coincide with the scheduler's current relative slot zero.
    always @(posedge clk) begin
        if (dut.internal_rst_n) begin
            for (int unsigned fe_idx = 0; fe_idx < 4; fe_idx++) begin
                if (dut.fe_out_valid[fe_idx] !==
                    dut.u_scheduler.future_valid_q[fe_idx][0]) begin
                    `uvm_error("FE_CALENDAR", $sformatf(
                        "FE%0d return valid=%0b future_slot0=%0b",
                        fe_idx, dut.fe_out_valid[fe_idx],
                        dut.u_scheduler.future_valid_q[fe_idx][0]))
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

`ifdef PPE_FSDB
    initial begin : fsdb_dump_control
        string fsdb_file;
        if ($test$plusargs("FSDB")) begin
            fsdb_file = "waves.fsdb";
            void'($value$plusargs("FSDB_FILE=%s", fsdb_file));
            $fsdbDumpfile(fsdb_file);
            $fsdbDumpvars(0, tb_top_sv);
            $fsdbDumpMDA();
        end
    end
`endif

endmodule : tb_top_sv
