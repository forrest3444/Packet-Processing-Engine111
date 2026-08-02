// -----------------------------------------------------------------------------
// Verification-only pipeline utilization and blockage probe.
// -----------------------------------------------------------------------------

`ifndef PPE_PIPELINE_STALL_PROBE_SV
`define PPE_PIPELINE_STALL_PROBE_SV

module ppe_pipeline_stall_probe #(
    parameter int EXPECTED_PACKETS = 1134
) (
    input logic        clk,
    input logic        rst_n,
    input logic [3:0]  in_valid,
    input logic        bkps,
    input logic [3:0]  issue_valid,
    input logic [3:0]  completion_valid,
    input logic [3:0]  retire_valid,
    input logic [3:0]  out_valid,
    input logic [5:0]  rob_occupancy,
    input logic [4:0]  rob_head_ptr,
    input logic [31:0] rob_valid,
    input logic [31:0] rob_result_valid,
    input logic [63:0] issue_state,
    input logic [7:0]  candidate_valid,
    input logic [7:0]  candidate_pending,
    input logic [15:0] candidate_legal,
    input logic [3:0]  shortlist_valid,
    input logic [3:0]  grant_valid
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
    longint unsigned grant_width_hist [0:4];
    longint unsigned issue_width_hist [0:4];
    longint unsigned retire_width_hist [0:4];

    function automatic int unsigned popcount4(input logic [3:0] value);
        popcount4 = value[0] + value[1] + value[2] + value[3];
    endfunction

    function automatic int unsigned popcount8(input logic [7:0] value);
        int unsigned index;
        begin
            popcount8 = 0;
            for (index = 0; index < 8; index++) begin
                popcount8 += value[index];
            end
        end
    endfunction

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
            $display("PIPE_STALL widths grant={%0d,%0d,%0d,%0d,%0d} issue={%0d,%0d,%0d,%0d,%0d} rob_retire={%0d,%0d,%0d,%0d,%0d}",
                     grant_width_hist[0], grant_width_hist[1],
                     grant_width_hist[2], grant_width_hist[3],
                     grant_width_hist[4], issue_width_hist[0],
                     issue_width_hist[1], issue_width_hist[2],
                     issue_width_hist[3], issue_width_hist[4],
                     retire_width_hist[0], retire_width_hist[1],
                     retire_width_hist[2], retire_width_hist[3],
                     retire_width_hist[4]);
        end
    endtask

    initial begin
        int unsigned width;

        enabled = $test$plusargs("PIPELINE_PROBE");
        measuring = 1'b0;
        reported = 1'b0;
        expected_packets = EXPECTED_PACKETS;
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
        for (width = 0; width <= 4; width++) begin
            grant_width_hist[width] = 0;
            issue_width_hist[width] = 0;
            retire_width_hist[width] = 0;
        end
        if ($value$plusargs("UVM_TESTNAME=%s", testname)
            && (testname == "ppe_pipeline_stall_test")) begin
            enabled = 1'b1;
        end
        void'($value$plusargs("PROBE_PACKETS=%d", expected_packets));
    end

    always @(negedge clk) begin : collect_pipeline_metrics
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
        logic [7:0] candidate_available;

        if (enabled && rst_n && !reported) begin
            accepted_now = bkps ? 0 : popcount4(in_valid);
            issued_now = popcount4(issue_valid);
            completed_now = popcount4(completion_valid);
            retired_now = popcount4(retire_valid);
            output_now = popcount4(out_valid);

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
                for (entry = 0; entry < 32; entry++) begin
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
                candidate_now = popcount8(candidate_available);
                candidate_entry_cycles += candidate_now;
                candidate_empty_cycles += (candidate_now == 0);
                for (slot = 0; slot < 8; slot++) begin
                    if (candidate_available[slot]
                        && (candidate_legal[slot*2 +: 2] == 2'b00)) begin
                        calendar_blocked_candidate_slots++;
                    end
                end

                shortlist_now = popcount4(shortlist_valid);
                grant_now = popcount4(grant_valid);
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
