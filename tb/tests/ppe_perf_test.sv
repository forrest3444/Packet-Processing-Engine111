// -----------------------------------------------------------------------------
// Configurable P1-P6 performance test. Select with +PERF_CASE=<name>.
// -----------------------------------------------------------------------------

`ifndef PPE_PERF_TEST_SV
`define PPE_PERF_TEST_SV

class ppe_perf_test extends uvm_test;
    `uvm_component_utils(ppe_perf_test)

    localparam int unsigned TIMEOUT_CYCLES = 50000;

    ppe_env         env;
    ppe_vif_t       vif;
    ppe_perf_config cfg;

    int unsigned cycle_count;
    int unsigned measurement_cycles;
    int unsigned accepted_count;
    int unsigned issued_count;
    int unsigned retired_count;
    int unsigned fallback_cycles;
    int unsigned d3_fallback_cycles;
    int unsigned bkps_cycles;
    int unsigned occupancy_sum;
    int unsigned occupancy_peak;
    int unsigned issue_lane_cycles[4];
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
        string scenario;

        super.build_phase(phase);
        env = ppe_env::type_id::create("env", this);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_perf_test cannot get vif")
        end
        if (!$value$plusargs("PERF_CASE=%s", scenario)) begin
            scenario = "P1_DELAY1";
        end
        cfg = ppe_perf_config::type_id::create("cfg");
        configure_case(scenario);
    endfunction

    function void configure_case(string scenario);
        cfg.scenario = scenario;
        cfg.packet_count = 512;
        cfg.lane_count = 4;
        cfg.mixed_delay = 1'b0;
        cfg.delay_value = 0;
        cfg.dep_mode = 0;
        cfg.dep_value = 0;
        cfg.dep_quarters = 0;

        if (scenario == "P1_DELAY1") begin
            cfg.delay_value = 1;
        end else if (scenario == "P1_DELAY2") begin
            cfg.delay_value = 2;
        end else if (scenario == "P1_DELAY3") begin
            cfg.delay_value = 3;
        end else if (scenario == "P2_MIXED_DELAY") begin
            cfg.mixed_delay = 1'b1;
        end else if (scenario == "P3_LANES1") begin
            cfg.lane_count = 1;
        end else if (scenario == "P3_LANES2") begin
            cfg.lane_count = 2;
        end else if (scenario == "P3_LANES3") begin
            cfg.lane_count = 3;
        end else if (scenario == "P4_DEP1_D0") begin
            cfg.dep_mode = 1;
            cfg.dep_value = 1;
        end else if (scenario == "P4_DEP1_D3") begin
            cfg.dep_mode = 1;
            cfg.dep_value = 1;
            cfg.delay_value = 3;
        end else if (scenario == "P5_DEP2") begin
            cfg.dep_mode = 1;
            cfg.dep_value = 2;
        end else if (scenario == "P5_DEP4") begin
            cfg.dep_mode = 1;
            cfg.dep_value = 4;
        end else if (scenario == "P5_DEP7") begin
            cfg.dep_mode = 1;
            cfg.dep_value = 7;
        end else if (scenario == "P6_DEP25") begin
            cfg.dep_mode = 2;
            cfg.dep_quarters = 1;
            cfg.mixed_delay = 1'b1;
        end else if (scenario == "P6_DEP50") begin
            cfg.dep_mode = 2;
            cfg.dep_quarters = 2;
            cfg.mixed_delay = 1'b1;
        end else if (scenario == "P6_DEP75") begin
            cfg.dep_mode = 2;
            cfg.dep_quarters = 3;
            cfg.mixed_delay = 1'b1;
        end else begin
            `uvm_fatal("PERF_CASE", $sformatf("unknown PERF_CASE=%s", scenario))
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_perf_seq seq;

        phase.raise_objection(this);
        seq = ppe_perf_seq::type_id::create("seq");
        seq.cfg = cfg;
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
            accepted_now = !vif.bkps ? count4({vif.in_valid3, vif.in_valid2,
                                               vif.in_valid1, vif.in_valid0}) : 0;
            issued_now = count4(vif.dbg_fe_in_valid);
            retired_now = count4({vif.out_valid3, vif.out_valid2,
                                  vif.out_valid1, vif.out_valid0});

            if (!measuring && (accepted_now != 0)) begin
                measuring = 1'b1;
                first_accept_cycle = cycle_count;
            end
            if (measuring) begin
                measurement_cycles++;
                accepted_count += accepted_now;
                issued_count += issued_now;
                retired_count += retired_now;
                if (vif.bkps) bkps_cycles++;
                if (vif.dbg_fallback_valid) fallback_cycles++;
                if (vif.dbg_fallback_valid && vif.dbg_fallback_from_d3) begin
                    d3_fallback_cycles++;
                end
                occupancy_sum += vif.dbg_rob_occupancy;
                if (vif.dbg_rob_occupancy > occupancy_peak) begin
                    occupancy_peak = vif.dbg_rob_occupancy;
                end
                for (lane = 0; lane < 4; lane++) begin
                    if (vif.dbg_fe_in_valid[lane]) issue_lane_cycles[lane]++;
                end

                if (accepted_now != 0) begin
                    last_accept_cycle = cycle_count;
                    repeat (accepted_now) accept_cycle_q.push_back(cycle_count);
                end
                repeat (retired_now) begin
                    if (accept_cycle_q.size() == 0) begin
                        `uvm_error("PERF_LATENCY", "missing acceptance timestamp")
                    end else begin
                        latency = cycle_count - accept_cycle_q.pop_front();
                        latency_sum += latency;
                        if (latency > latency_max) latency_max = latency;
                    end
                end
                if (retired_count >= cfg.packet_count) begin
                    completed = 1'b1;
                    break;
                end
            end
        end
    endtask

    function int unsigned count4(bit [3:0] value);
        count4 = {31'b0, value[0]} + {31'b0, value[1]} +
                 {31'b0, value[2]} + {31'b0, value[3]};
    endfunction

    task check_results();
        if (!completed) begin
            `uvm_error("PERF_TIMEOUT", $sformatf("%s retired %0d of %0d packets",
                cfg.scenario, retired_count, cfg.packet_count))
        end
        if ((accepted_count != cfg.packet_count) ||
            (issued_count != cfg.packet_count) ||
            (retired_count != cfg.packet_count)) begin
            `uvm_error("PERF_COUNT", $sformatf(
                "%s accepted=%0d issued=%0d retired=%0d expected=%0d",
                cfg.scenario, accepted_count, issued_count, retired_count,
                cfg.packet_count))
        end
        if (accept_cycle_q.size() != 0) begin
            `uvm_error("PERF_PENDING", $sformatf("%s has %0d timestamps pending",
                cfg.scenario, accept_cycle_q.size()))
        end
        if ((env.scb.exp_total != cfg.packet_count) ||
            (env.scb.got_total != cfg.packet_count)) begin
            `uvm_error("PERF_SCOREBOARD", $sformatf(
                "%s scoreboard expected=%0d received=%0d", cfg.scenario,
                env.scb.exp_total, env.scb.got_total))
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
        real fe_util[4];
        int unsigned lane;

        accept_window_cycles = last_accept_cycle - first_accept_cycle + 1;
        accept_rate = $itor(accepted_count) / $itor(accept_window_cycles);
        issue_rate = $itor(issued_count) / $itor(measurement_cycles);
        retire_rate = $itor(retired_count) / $itor(measurement_cycles);
        avg_latency = $itor(latency_sum) / $itor(retired_count);
        bkps_ratio = $itor(bkps_cycles) / $itor(measurement_cycles);
        avg_occupancy = $itor(occupancy_sum) / $itor(measurement_cycles);
        for (lane = 0; lane < 4; lane++) begin
            fe_util[lane] = $itor(issue_lane_cycles[lane]) /
                            $itor(measurement_cycles);
        end

        `uvm_info("PERF_METRIC", $sformatf(
            "case=%s packets=%0d cycles=%0d accept_rate=%.4f issue_rate=%.4f retire_rate=%.4f",
            cfg.scenario, cfg.packet_count, measurement_cycles, accept_rate,
            issue_rate, retire_rate), UVM_NONE)
        `uvm_info("PERF_METRIC", $sformatf(
            "case=%s latency_avg=%.2f latency_max=%0d bkps_ratio=%.4f rob_avg=%.2f rob_peak=%0d",
            cfg.scenario, avg_latency, latency_max, bkps_ratio,
            avg_occupancy, occupancy_peak), UVM_NONE)
        `uvm_info("PERF_METRIC", $sformatf(
            "case=%s fe_util={%.4f,%.4f,%.4f,%.4f} fallback=%0d d3_fallback=%0d",
            cfg.scenario, fe_util[0], fe_util[1], fe_util[2], fe_util[3],
            fallback_cycles, d3_fallback_cycles), UVM_NONE)
    endtask
endclass

`endif
