// -----------------------------------------------------------------------------
// Saturation test for dependency-free uniform-random delay traffic.
// -----------------------------------------------------------------------------

`ifndef PPE_UNIFORM_RANDOM_DELAY_TEST_SV
`define PPE_UNIFORM_RANDOM_DELAY_TEST_SV

class ppe_uniform_random_delay_test extends uvm_test;
    `uvm_component_utils(ppe_uniform_random_delay_test)

    localparam int unsigned PACKET_COUNT   = 8192;
    localparam int unsigned WARMUP_PACKETS = 512;
    localparam int unsigned TIMEOUT_CYCLES = 100000;

    ppe_env   env;
    ppe_vif_t vif;

    int unsigned cycle_count;
    int unsigned measurement_cycles;
    int unsigned accepted_count;
    int unsigned issued_count;
    int unsigned retired_count;
    int unsigned first_accept_cycle;
    int unsigned last_accept_cycle;
    int unsigned bkps_cycles;
    int unsigned occupancy_sum;
    int unsigned occupancy_peak;
    int unsigned delay_hist[4];
    int unsigned issue_width_hist[5];
    int unsigned fe_issue_count[4];
    int unsigned steady_cycles;
    int unsigned steady_issue_count;
    int unsigned steady_fe_issue_count[4];
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
            `uvm_fatal("NOVIF", "ppe_uniform_random_delay_test cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_uniform_random_delay_seq seq;

        phase.raise_objection(this);
        seq = ppe_uniform_random_delay_seq::type_id::create("seq");
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
        bit          steady_sample;
        bit [4:0]    accepted_desc;

        repeat (TIMEOUT_CYCLES) begin
            @(posedge vif.clk);
            cycle_count++;
            accepted_now = !vif.bkps ? count4(
                {vif.in_valid3, vif.in_valid2,
                 vif.in_valid1, vif.in_valid0}) : 0;
            issued_now = count4(vif.dbg_fe_in_valid);
            retired_now = count4(
                {vif.out_valid3, vif.out_valid2,
                 vif.out_valid1, vif.out_valid0});

            if (!measuring && (accepted_now != 0)) begin
                measuring = 1'b1;
                first_accept_cycle = cycle_count;
            end

            if (measuring) begin
                steady_sample = (accepted_count >= WARMUP_PACKETS)
                    && (accepted_count < (PACKET_COUNT - WARMUP_PACKETS));
                measurement_cycles++;
                accepted_count += accepted_now;
                issued_count += issued_now;
                retired_count += retired_now;
                issue_width_hist[issued_now]++;
                occupancy_sum += vif.dbg_rob_occupancy;
                if (vif.bkps) bkps_cycles++;
                if (vif.dbg_rob_occupancy > occupancy_peak)
                    occupancy_peak = vif.dbg_rob_occupancy;

                for (lane = 0; lane < 4; lane++) begin
                    if (vif.dbg_fe_in_valid[lane])
                        fe_issue_count[lane]++;
                    if (steady_sample && vif.dbg_fe_in_valid[lane])
                        steady_fe_issue_count[lane]++;
                end
                if (steady_sample) begin
                    steady_cycles++;
                    steady_issue_count += issued_now;
                end

                if (accepted_now != 0) begin
                    last_accept_cycle = cycle_count;
                    for (lane = 0; lane < 4; lane++) begin
                        if (lane_valid(lane)) begin
                            accepted_desc = lane_desc(lane);
                            delay_hist[accepted_desc[1:0]]++;
                            accept_cycle_q.push_back(cycle_count);
                        end
                    end
                end

                repeat (retired_now) begin
                    if (accept_cycle_q.size() == 0) begin
                        `uvm_error("UNIFORM_LATENCY",
                                   "missing acceptance timestamp")
                    end else begin
                        latency = cycle_count - accept_cycle_q.pop_front();
                        latency_sum += latency;
                        if (latency > latency_max)
                            latency_max = latency;
                    end
                end

                if (retired_count >= PACKET_COUNT) begin
                    completed = 1'b1;
                    break;
                end
            end
        end
    endtask

    function bit lane_valid(int unsigned lane);
        case (lane)
            0: lane_valid = vif.in_valid0;
            1: lane_valid = vif.in_valid1;
            2: lane_valid = vif.in_valid2;
            default: lane_valid = vif.in_valid3;
        endcase
    endfunction

    function bit [4:0] lane_desc(int unsigned lane);
        case (lane)
            0: lane_desc = vif.in_desc0;
            1: lane_desc = vif.in_desc1;
            2: lane_desc = vif.in_desc2;
            default: lane_desc = vif.in_desc3;
        endcase
    endfunction

    function int unsigned count4(bit [3:0] value);
        count4 = {31'b0, value[0]} + {31'b0, value[1]} +
                 {31'b0, value[2]} + {31'b0, value[3]};
    endfunction

    task check_results();
        int unsigned delay;

        if (!completed) begin
            `uvm_error("UNIFORM_TIMEOUT", $sformatf(
                "retired=%0d expected=%0d", retired_count, PACKET_COUNT))
        end
        if ((accepted_count != PACKET_COUNT)
            || (issued_count != PACKET_COUNT)
            || (retired_count != PACKET_COUNT)) begin
            `uvm_error("UNIFORM_COUNT", $sformatf(
                "accepted=%0d issued=%0d retired=%0d expected=%0d",
                accepted_count, issued_count, retired_count, PACKET_COUNT))
        end
        for (delay = 0; delay < 4; delay++) begin
            if (delay_hist[delay] == 0) begin
                `uvm_error("UNIFORM_DELAY", $sformatf(
                    "delay%0d was not observed", delay))
            end
        end
        if ((env.scb.exp_total != PACKET_COUNT)
            || (env.scb.got_total != PACKET_COUNT)
            || (accept_cycle_q.size() != 0)) begin
            `uvm_error("UNIFORM_SCOREBOARD", $sformatf(
                "expected=%0d received=%0d pending=%0d",
                env.scb.exp_total, env.scb.got_total,
                accept_cycle_q.size()))
        end
    endtask

    task report_metrics();
        int unsigned accept_window_cycles;
        real accept_rate;
        real end_to_end_rate;
        real steady_issue_rate;
        real theoretical_efficiency;
        real bkps_ratio;
        real avg_occupancy;
        real avg_latency;
        real fe_util[4];
        real steady_fe_util[4];
        int unsigned lane;
        string mode;

        accept_window_cycles = last_accept_cycle - first_accept_cycle + 1;
        accept_rate = $itor(accepted_count) / $itor(accept_window_cycles);
        end_to_end_rate = $itor(retired_count) / $itor(measurement_cycles);
        steady_issue_rate = $itor(steady_issue_count) / $itor(steady_cycles);
        theoretical_efficiency = steady_issue_rate / 4.0;
        bkps_ratio = $itor(bkps_cycles) / $itor(measurement_cycles);
        avg_occupancy = $itor(occupancy_sum) / $itor(measurement_cycles);
        avg_latency = $itor(latency_sum) / $itor(retired_count);
        for (lane = 0; lane < 4; lane++) begin
            fe_util[lane] = $itor(fe_issue_count[lane]) /
                            $itor(measurement_cycles);
            steady_fe_util[lane] = $itor(steady_fe_issue_count[lane]) /
                                   $itor(steady_cycles);
        end
        mode = $test$plusargs("BALANCED_DELAY")
             ? "balanced-control" : "uniform-random";

        `uvm_info("UNIFORM_PERF", $sformatf(
            "mode=%s packets=%0d cycles=%0d accept_window=%0d accept_rate=%.4f end_to_end_rate=%.4f",
            mode, PACKET_COUNT, measurement_cycles, accept_window_cycles,
            accept_rate, end_to_end_rate), UVM_NONE)
        `uvm_info("UNIFORM_PERF", $sformatf(
            "steady_cycles=%0d steady_issue_rate=%.4f theoretical_efficiency=%.2f%%",
            steady_cycles, steady_issue_rate,
            theoretical_efficiency * 100.0), UVM_NONE)
        `uvm_info("UNIFORM_PERF", $sformatf(
            "delay_hist={%0d,%0d,%0d,%0d} fe_util={%.4f,%.4f,%.4f,%.4f}",
            delay_hist[0], delay_hist[1], delay_hist[2], delay_hist[3],
            fe_util[0], fe_util[1], fe_util[2], fe_util[3]), UVM_NONE)
        `uvm_info("UNIFORM_PERF", $sformatf(
            "steady_fe_util={%.4f,%.4f,%.4f,%.4f} issue_width_hist={%0d,%0d,%0d,%0d,%0d}",
            steady_fe_util[0], steady_fe_util[1],
            steady_fe_util[2], steady_fe_util[3],
            issue_width_hist[0], issue_width_hist[1], issue_width_hist[2],
            issue_width_hist[3], issue_width_hist[4]), UVM_NONE)
        `uvm_info("UNIFORM_PERF", $sformatf(
            "bkps_ratio=%.4f rob_avg=%.2f rob_peak=%0d latency_avg=%.2f latency_max=%0d",
            bkps_ratio, avg_occupancy, occupancy_peak,
            avg_latency, latency_max), UVM_NONE)
    endtask
endclass

`endif
