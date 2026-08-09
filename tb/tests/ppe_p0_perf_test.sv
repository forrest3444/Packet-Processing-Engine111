// -----------------------------------------------------------------------------
// P0 baseline performance measurement with end-to-end data checking enabled.
// -----------------------------------------------------------------------------

`ifndef PPE_P0_PERF_TEST_SV
`define PPE_P0_PERF_TEST_SV

class ppe_p0_perf_test extends uvm_test;
    `uvm_component_utils(ppe_p0_perf_test)

    localparam int unsigned PACKET_COUNT = 1024;
    localparam int unsigned TIMEOUT_CYCLES = 20000;

    ppe_env   env;
    ppe_vif_t vif;

    int unsigned cycle_count;
    int unsigned measurement_cycles;
    int unsigned accepted_count;
    int unsigned issued_count;
    int unsigned retired_count;
    int unsigned fallback_cycles;
    int unsigned bkps_cycles;
    int unsigned occupancy_sum;
    int unsigned occupancy_peak;
    int unsigned issue_lane_cycles[TB_N];
    int unsigned first_accept_cycle;
    int unsigned last_accept_cycle;
    int unsigned latency_sum;
    int unsigned latency_max;
    int unsigned accept_cycle_q[$];
    bit          measuring;
    bit          completed;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = ppe_env::type_id::create("env", this);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_p0_perf_test cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_p0_perf_seq seq;

        phase.raise_objection(this);
        seq = ppe_p0_perf_seq::type_id::create("seq");
        fork
            seq.start(env.master_agent.seqr);
            collect_metrics();
        join

        @(negedge vif.clk);
        check_results();
        report_metrics();
        phase.drop_objection(this);
    endtask

    task collect_metrics();
        int unsigned accepted_now;
        int unsigned issued_now;
        int unsigned retired_now;
        int unsigned lane;
        int unsigned latency;

        repeat (TIMEOUT_CYCLES) begin
            @(posedge vif.clk);
            cycle_count++;
            accepted_now = !vif.bkps ? count_n(vif.in_valid) : 0;
            issued_now = count_n(vif.dbg_fe_in_valid);
            retired_now = count_n(vif.out_valid);

            if (!measuring && (accepted_now != 0)) begin
                measuring = 1'b1;
                first_accept_cycle = cycle_count;
            end

            if (measuring) begin
                measurement_cycles++;
                accepted_count += accepted_now;
                issued_count += issued_now;
                retired_count += retired_now;
                if (vif.bkps) begin
                    bkps_cycles++;
                end
                if (vif.dbg_fallback_valid) begin
                    fallback_cycles++;
                end
                occupancy_sum += vif.dbg_rob_occupancy;
                if (vif.dbg_rob_occupancy > occupancy_peak) begin
                    occupancy_peak = vif.dbg_rob_occupancy;
                end
                for (lane = 0; lane < TB_N; lane++) begin
                    if (vif.dbg_fe_in_valid[lane]) begin
                        issue_lane_cycles[lane]++;
                    end
                end

                if (accepted_now != 0) begin
                    last_accept_cycle = cycle_count;
                    repeat (accepted_now) begin
                        accept_cycle_q.push_back(cycle_count);
                    end
                end
                repeat (retired_now) begin
                    if (accept_cycle_q.size() == 0) begin
                        `uvm_error("P0_LATENCY", "output has no matching acceptance timestamp")
                    end else begin
                        latency = cycle_count - accept_cycle_q.pop_front();
                        latency_sum += latency;
                        if (latency > latency_max) begin
                            latency_max = latency;
                        end
                    end
                end

                if (retired_count >= PACKET_COUNT) begin
                    completed = 1'b1;
                    break;
                end
            end
        end
    endtask

    function int unsigned count_n(bit [TB_N-1:0] value);
        count_n = 0;
        for (int unsigned lane = 0; lane < TB_N; lane++) begin
            count_n += value[lane];
        end
    endfunction

    task check_results();
        if (!completed) begin
            `uvm_error("P0_TIMEOUT", $sformatf(
                "retired %0d of %0d packets", retired_count, PACKET_COUNT))
        end
        if ((accepted_count != PACKET_COUNT) || (issued_count != PACKET_COUNT) ||
            (retired_count != PACKET_COUNT)) begin
            `uvm_error("P0_COUNT", $sformatf(
                "accepted=%0d issued=%0d retired=%0d expected=%0d",
                accepted_count, issued_count, retired_count, PACKET_COUNT))
        end
        if (fallback_cycles != 0) begin
            `uvm_error("P0_FALLBACK", $sformatf(
                "no-dependency baseline observed %0d fallback cycles", fallback_cycles))
        end
        if (bkps_cycles != 0) begin
            `uvm_error("P0_BKPS", $sformatf(
                "full-width zero-delay baseline observed %0d backpressure cycles",
                bkps_cycles))
        end
        if (accept_cycle_q.size() != 0) begin
            `uvm_error("P0_PENDING", $sformatf(
                "%0d accepted timestamps remain", accept_cycle_q.size()))
        end
        if ((env.scb.exp_total != PACKET_COUNT) ||
            (env.scb.got_total != PACKET_COUNT)) begin
            `uvm_error("P0_SCOREBOARD", $sformatf(
                "scoreboard expected=%0d received=%0d", env.scb.exp_total,
                env.scb.got_total))
        end
    endtask

    task report_metrics();
        int unsigned accept_window_cycles;
        real accept_rate;
        real issue_rate;
        real retire_rate;
        real avg_latency;
        real bkps_ratio;
        real avg_occupancy;
        real fe_util[TB_N];
        int unsigned lane;

        accept_window_cycles = last_accept_cycle - first_accept_cycle + 1;
        accept_rate = $itor(accepted_count) / $itor(accept_window_cycles);
        issue_rate = $itor(issued_count) / $itor(measurement_cycles);
        retire_rate = $itor(retired_count) / $itor(measurement_cycles);
        avg_latency = $itor(latency_sum) / $itor(retired_count);
        bkps_ratio = $itor(bkps_cycles) / $itor(measurement_cycles);
        avg_occupancy = $itor(occupancy_sum) / $itor(measurement_cycles);
        for (lane = 0; lane < TB_N; lane++) begin
            fe_util[lane] = $itor(issue_lane_cycles[lane]) /
                            $itor(measurement_cycles);
        end

        `uvm_info("P0_PERF", $sformatf(
            "packets=%0d measurement_cycles=%0d accept_window_cycles=%0d",
            PACKET_COUNT, measurement_cycles, accept_window_cycles), UVM_NONE)
        `uvm_info("P0_PERF", $sformatf(
            "accept_rate=%.4f issue_rate=%.4f retire_rate=%.4f packets/cycle",
            accept_rate, issue_rate, retire_rate), UVM_NONE)
        `uvm_info("P0_PERF", $sformatf(
            "latency_avg=%.2f latency_max=%0d cycles bkps_ratio=%.4f",
            avg_latency, latency_max, bkps_ratio), UVM_NONE)
        `uvm_info("P0_PERF", $sformatf(
            "rob_occupancy_avg=%.2f rob_occupancy_peak=%0d fallback_cycles=%0d",
            avg_occupancy, occupancy_peak, fallback_cycles), UVM_NONE)
        for (lane = 0; lane < TB_N; lane++) begin
            `uvm_info("P0_PERF", $sformatf(
                "fe%0d_utilization=%.4f", lane, fe_util[lane]), UVM_NONE)
        end
    endtask
endclass

`endif
