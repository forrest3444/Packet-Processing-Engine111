// -----------------------------------------------------------------------------
// Verification-only pipeline utilization and blockage probe.
// -----------------------------------------------------------------------------

`ifndef PPE_PIPELINE_STALL_PROBE_SV
`define PPE_PIPELINE_STALL_PROBE_SV

`include "rtl/common/ppe_config.vh"

module ppe_pipeline_stall_probe #(
    parameter int EXPECTED_PACKETS = 1134,
    parameter int LANES            = `PPE_N,
    parameter int ROB_DEPTH        = `PPE_ROB_DEPTH,
    parameter int ISSUE_DEPTH      = `PPE_ISSUE_DEPTH,
    parameter int CAND_DEPTH       = `PPE_CAND_WINDOW_DEPTH
) (
    input logic        clk,
    input logic        rst_n,
    input logic [LANES-1:0] in_valid,
    input logic        bkps,
    input logic [LANES-1:0] issue_valid,
    input logic [LANES-1:0] completion_valid,
    input logic [LANES-1:0] retire_valid,
    input logic [LANES-1:0] out_valid,
    input logic [5:0]  rob_occupancy,
    input logic [4:0]  rob_head_ptr,
    input logic [ROB_DEPTH-1:0] rob_valid,
    input logic [ROB_DEPTH-1:0] rob_result_valid,
    input logic [(ISSUE_DEPTH*2)-1:0] issue_state,
    input logic [CAND_DEPTH-1:0] candidate_valid,
    input logic [CAND_DEPTH-1:0] candidate_pending,
    input logic [(CAND_DEPTH*2)-1:0] candidate_legal,
    input logic [LANES-1:0] shortlist_valid,
    input logic [LANES-1:0] grant_valid
);

    localparam logic [1:0] ISSUE_WAIT_DEP = 2'd1;
    localparam logic [1:0] ISSUE_READY    = 2'd2;
    localparam logic [1:0] ISSUE_SELECTED = 2'd3;

    bit enabled;
    bit measuring;
    bit reported;
    int expected_packets;
    string testname;

    longint unsigned cycles;
    longint unsigned accepted_packets;
    longint unsigned issued_packets;
    longint unsigned completed_packets;
    longint unsigned retired_packets;
    longint unsigned output_packets;
    longint unsigned ingress_backpressure_cycles;
    longint unsigned rob_full_cycles;
    longint unsigned rob_head_wait_cycles;
    longint unsigned ready_empty_cycles;
    longint unsigned candidate_empty_cycles;
    longint unsigned calendar_blocked_candidate_slots;
    longint unsigned matcher_ungranted_shortlists;
    longint unsigned wait_dep_entry_cycles;
    longint unsigned ready_entry_cycles;
    longint unsigned selected_entry_cycles;
    longint unsigned candidate_entry_cycles;
    longint unsigned grant_width_hist [0:LANES];
    longint unsigned issue_width_hist [0:LANES];
    longint unsigned retire_width_hist [0:LANES];

    function automatic int unsigned popcount_lanes(
        input logic [LANES-1:0] value);
        popcount_lanes = 0;
        for (int unsigned index = 0; index < LANES; index++) begin
            popcount_lanes += value[index];
        end
    endfunction

    function automatic int unsigned popcount_candidates(
        input logic [CAND_DEPTH-1:0] value);
        int unsigned index;
        begin
            popcount_candidates = 0;
            for (index = 0; index < CAND_DEPTH; index++) begin
                popcount_candidates += value[index];
            end
        end
    endfunction

    task automatic reset_metrics;
        int unsigned width;
        begin
            measuring = 1'b0;
            reported = 1'b0;
            cycles = 0;
            accepted_packets = 0;
            issued_packets = 0;
            completed_packets = 0;
            retired_packets = 0;
            output_packets = 0;
            ingress_backpressure_cycles = 0;
            rob_full_cycles = 0;
            rob_head_wait_cycles = 0;
            ready_empty_cycles = 0;
            candidate_empty_cycles = 0;
            calendar_blocked_candidate_slots = 0;
            matcher_ungranted_shortlists = 0;
            wait_dep_entry_cycles = 0;
            ready_entry_cycles = 0;
            selected_entry_cycles = 0;
            candidate_entry_cycles = 0;
            for (width = 0; width <= LANES; width++) begin
                grant_width_hist[width] = 0;
                issue_width_hist[width] = 0;
                retire_width_hist[width] = 0;
            end
        end
    endtask

    task automatic report_probe;
        real issue_rate;
        real retire_rate;
        begin
            if (cycles != 0) begin
                issue_rate = $itor(issued_packets) / $itor(cycles);
                retire_rate = $itor(output_packets) / $itor(cycles);
            end else begin
                issue_rate = 0.0;
                retire_rate = 0.0;
            end
            $display("PIPE_STALL summary cycles=%0d accepted=%0d issued=%0d completed=%0d rob_retired=%0d output=%0d issue_rate=%.4f output_rate=%.4f",
                     cycles, accepted_packets, issued_packets,
                     completed_packets, retired_packets, output_packets,
                     issue_rate, retire_rate);
            $display("PIPE_STALL pressure ingress_backpressure_cycles=%0d rob_full_cycles=%0d rob_head_wait_cycles=%0d ready_empty_cycles=%0d candidate_empty_cycles=%0d",
                     ingress_backpressure_cycles, rob_full_cycles,
                     rob_head_wait_cycles, ready_empty_cycles,
                     candidate_empty_cycles);
            $display("PIPE_STALL scheduler calendar_blocked_candidate_slots=%0d matcher_ungranted_shortlists=%0d entry_cycles={wait_dep:%0d ready:%0d selected:%0d candidate:%0d}",
                     calendar_blocked_candidate_slots,
                     matcher_ungranted_shortlists, wait_dep_entry_cycles,
                     ready_entry_cycles, selected_entry_cycles,
                     candidate_entry_cycles);
            for (int unsigned width = 0; width <= LANES; width++) begin
                $display("PIPE_STALL width=%0d grant=%0d issue=%0d rob_retire=%0d",
                         width, grant_width_hist[width],
                         issue_width_hist[width], retire_width_hist[width]);
            end
        end
    endtask

    initial begin
        enabled = $test$plusargs("PIPELINE_PROBE");
        expected_packets = EXPECTED_PACKETS;
        reset_metrics();
        if ($value$plusargs("UVM_TESTNAME=%s", testname)
            && (testname == "ppe_pipeline_stall_test")) begin
            enabled = 1'b1;
        end
        void'($value$plusargs("PROBE_PACKETS=%d", expected_packets));
    end

    always @(negedge clk or negedge rst_n) begin : collect_pipeline_metrics
        int unsigned entry;
        int unsigned slot;
        int unsigned accepted_now;
        int unsigned issued_now;
        int unsigned completed_now;
        int unsigned retired_now;
        int unsigned output_now;
        int unsigned wait_dep_now;
        int unsigned ready_now;
        int unsigned selected_now;
        int unsigned candidate_now;
        int unsigned shortlist_now;
        int unsigned grant_now;
        logic [CAND_DEPTH-1:0] candidate_available;

        if (!rst_n) begin
            reset_metrics();
        end else if (enabled && !reported) begin
            accepted_now = bkps ? 0 : popcount_lanes(in_valid);
            issued_now = popcount_lanes(issue_valid);
            completed_now = popcount_lanes(completion_valid);
            retired_now = popcount_lanes(retire_valid);
            output_now = popcount_lanes(out_valid);

            if (!measuring && (accepted_now != 0)) begin
                measuring = 1'b1;
            end

            if (measuring || (accepted_now != 0)) begin
                cycles++;
                accepted_packets += accepted_now;
                issued_packets += issued_now;
                completed_packets += completed_now;
                retired_packets += retired_now;
                output_packets += output_now;
                ingress_backpressure_cycles += bkps;
                rob_full_cycles += (rob_occupancy == 6'd32);
                rob_head_wait_cycles += (rob_occupancy != 0)
                    && rob_valid[rob_head_ptr]
                    && !rob_result_valid[rob_head_ptr];

                wait_dep_now = 0;
                ready_now = 0;
                selected_now = 0;
                for (entry = 0; entry < ISSUE_DEPTH; entry++) begin
                    case (issue_state[entry*2 +: 2])
                        ISSUE_WAIT_DEP: wait_dep_now++;
                        ISSUE_READY:    ready_now++;
                        ISSUE_SELECTED: selected_now++;
                        default: ;
                    endcase
                end
                wait_dep_entry_cycles += wait_dep_now;
                ready_entry_cycles += ready_now;
                selected_entry_cycles += selected_now;
                ready_empty_cycles += (ready_now == 0);

                candidate_available = candidate_valid & ~candidate_pending;
                candidate_now = popcount_candidates(candidate_available);
                candidate_entry_cycles += candidate_now;
                candidate_empty_cycles += (candidate_now == 0);
                for (slot = 0; slot < CAND_DEPTH; slot++) begin
                    if (candidate_available[slot]
                        && (candidate_legal[slot*2 +: 2] == 2'b00)) begin
                        calendar_blocked_candidate_slots++;
                    end
                end

                shortlist_now = popcount_lanes(shortlist_valid);
                grant_now = popcount_lanes(grant_valid);
                if (shortlist_now > grant_now) begin
                    matcher_ungranted_shortlists += shortlist_now - grant_now;
                end
                grant_width_hist[grant_now]++;
                issue_width_hist[issued_now]++;
                retire_width_hist[retired_now]++;

                if (output_packets >= expected_packets) begin
                    report_probe();
                    reported = 1'b1;
                    measuring = 1'b0;
                end
            end
        end
    end

    final begin
        if (enabled && measuring && !reported) begin
            $display("PIPE_STALL partial report: simulation ended before %0d outputs",
                     expected_packets);
            report_probe();
        end
    end

endmodule

`endif
