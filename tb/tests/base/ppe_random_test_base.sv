// -----------------------------------------------------------------------------
// File       : ppe_random_test_base.sv
// Description: Common runner and lightweight performance counters for random tests.
// -----------------------------------------------------------------------------

`ifndef PPE_RANDOM_TEST_BASE_SV
`define PPE_RANDOM_TEST_BASE_SV

class ppe_random_test_base extends ppe_test_base;
    `uvm_component_utils(ppe_random_test_base)

    ppe_random_seq_base random_seq;
    bit                sequence_done;
    bit                completed;

    int unsigned cycle_count;
    int unsigned accepted_count;
    int unsigned issued_count;
    int unsigned retired_count;
    int unsigned offered_cycles;
    int unsigned bkps_cycles;
    int unsigned occupancy_sum;
    int unsigned occupancy_peak;
    int unsigned latency_sum;
    int unsigned latency_max;
    int unsigned issue_width_hist[TB_N+1];
    int unsigned fe_issue_count[TB_N];
    int unsigned accept_cycle_q[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        sequence_done = 1'b0;
        completed = 1'b0;
    endfunction

    virtual function ppe_random_seq_base create_random_sequence();
        return ppe_random_seq_base::type_id::create("random_seq");
    endfunction

    virtual function void configure_random_sequence(
        ppe_random_seq_base seq);
    endfunction

    virtual task run_phase(uvm_phase phase);
        random_seq = create_random_sequence();
        if (random_seq == null) begin
            `uvm_fatal("NO_RANDOM_SEQ",
                       "derived random test did not create a sequence")
        end
        configure_random_sequence(random_seq);
        if (!random_seq.randomize()) begin
            `uvm_fatal("RANDOMIZE", "random sequence configuration failed")
        end

        phase.raise_objection(this);
        fork
            begin
                random_seq.start(env.master_agent.seqr);
                sequence_done = 1'b1;
            end
            collect_metrics();
        join
        @(negedge vif.clk);
        check_random_results();
        report_random_results();
        phase.drop_objection(this);
    endtask

    virtual task collect_metrics();
        int unsigned accepted_now;
        int unsigned issued_now;
        int unsigned retired_now;
        int unsigned latency;

        for (int unsigned cycle = 0; cycle < drain_timeout_cycles; cycle++) begin
            @(posedge vif.clk);
            cycle_count++;
            accepted_now = !vif.bkps ? count_n(vif.in_valid) : 0;
            issued_now = count_n(vif.dbg_fe_in_valid);
            retired_now = count_n(vif.out_valid);

            if (vif.in_valid != '0) begin
                offered_cycles++;
                if (vif.bkps) bkps_cycles++;
            end
            accepted_count += accepted_now;
            issued_count += issued_now;
            retired_count += retired_now;
            issue_width_hist[issued_now]++;
            occupancy_sum += vif.dbg_rob_occupancy;
            if (vif.dbg_rob_occupancy > occupancy_peak)
                occupancy_peak = vif.dbg_rob_occupancy;

            for (int unsigned lane = 0; lane < TB_N; lane++) begin
                if (vif.dbg_fe_in_valid[lane]) fe_issue_count[lane]++;
                if (!vif.bkps && vif.in_valid[lane])
                    accept_cycle_q.push_back(cycle_count);
            end

            repeat (retired_now) begin
                if (accept_cycle_q.size() == 0) begin
                    `uvm_error("RANDOM_LATENCY", "missing acceptance timestamp")
                end else begin
                    latency = cycle_count - accept_cycle_q.pop_front();
                    latency_sum += latency;
                    if (latency > latency_max) latency_max = latency;
                end
            end

            if (sequence_done
                && (env.scb.got_total == env.scb.exp_total)
                && (accept_cycle_q.size() == 0)) begin
                completed = 1'b1;
                break;
            end
        end
        if (!completed) begin
            `uvm_error("RANDOM_TIMEOUT", $sformatf(
                "generated=%0d expected=%0d received=%0d",
                random_seq.generated_packet_count, env.scb.exp_total,
                env.scb.got_total))
        end
    endtask

    function int unsigned count_n(bit [TB_N-1:0] value);
        count_n = 0;
        for (int unsigned lane = 0; lane < TB_N; lane++) begin
            count_n += value[lane];
        end
    endfunction

    virtual function void check_random_results();
        if (accepted_count != random_seq.generated_packet_count) begin
            `uvm_error("RANDOM_ACCEPT", $sformatf(
                "accepted=%0d generated=%0d", accepted_count,
                random_seq.generated_packet_count))
        end
        if ((issued_count != random_seq.generated_packet_count)
            || (retired_count != random_seq.generated_packet_count)) begin
            `uvm_error("RANDOM_COUNT", $sformatf(
                "issued=%0d retired=%0d generated=%0d", issued_count,
                retired_count, random_seq.generated_packet_count))
        end
        check_sequence_results(random_seq);
        check_random_specific();
    endfunction

    virtual function void check_random_specific();
    endfunction

    virtual function void report_random_results();
        real accept_rate;
        real issue_rate;
        real retire_rate;
        real bkps_ratio;
        real avg_latency;
        real avg_occupancy;

        accept_rate = (cycle_count == 0) ? 0.0
                                        : $itor(accepted_count) / $itor(cycle_count);
        issue_rate = (cycle_count == 0) ? 0.0
                                       : $itor(issued_count) / $itor(cycle_count);
        retire_rate = (cycle_count == 0) ? 0.0
                                        : $itor(retired_count) / $itor(cycle_count);
        bkps_ratio = (offered_cycles == 0) ? 0.0
                                          : $itor(bkps_cycles) / $itor(offered_cycles);
        avg_latency = (retired_count == 0) ? 0.0
                                          : $itor(latency_sum) / $itor(retired_count);
        avg_occupancy = (cycle_count == 0) ? 0.0
                                           : $itor(occupancy_sum) / $itor(cycle_count);

        `uvm_info("RANDOM_PERF", $sformatf(
            "batches=%0d packets=%0d cycles=%0d accept_rate=%.4f issue_rate=%.4f retire_rate=%.4f",
            random_seq.generated_batch_count,
            random_seq.generated_packet_count, cycle_count,
            accept_rate, issue_rate, retire_rate), UVM_NONE)
        `uvm_info("RANDOM_PERF", $sformatf(
            "bkps_ratio=%.4f rob_avg=%.2f rob_peak=%0d latency_avg=%.2f latency_max=%0d",
            bkps_ratio, avg_occupancy, occupancy_peak,
            avg_latency, latency_max), UVM_NONE)
        for (int unsigned width = 0; width <= TB_N; width++) begin
            `uvm_info("RANDOM_PERF", $sformatf(
                "issue_width_%0d=%0d", width, issue_width_hist[width]),
                UVM_NONE)
        end
        report_random_specific();
    endfunction

    virtual function void report_random_specific();
    endfunction
endclass

`endif
