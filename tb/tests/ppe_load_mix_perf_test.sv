// -----------------------------------------------------------------------------
// Medium/heavy input-load performance test with end-to-end checking enabled.
// -----------------------------------------------------------------------------

`ifndef PPE_LOAD_MIX_PERF_TEST_SV
`define PPE_LOAD_MIX_PERF_TEST_SV

class ppe_load_mix_perf_test extends uvm_test;
    `uvm_component_utils(ppe_load_mix_perf_test)

    localparam int unsigned MEDIUM_PACKETS = 378;
    localparam int unsigned MEDIUM_BEATS   = 189;
    localparam int unsigned HEAVY_PACKETS  = 756;
    localparam int unsigned HEAVY_BEATS    = 210;
    localparam int unsigned TOTAL_PACKETS  = MEDIUM_PACKETS + HEAVY_PACKETS;
    localparam int unsigned TIMEOUT_CYCLES = 50000;

    ppe_env   env;
    ppe_vif_t vif;

    int unsigned cycle_count;
    int unsigned measurement_cycles;
    int unsigned accepted_count;
    int unsigned issued_count;
    int unsigned retired_count;
    int unsigned medium_input_cycles;
    int unsigned heavy_input_cycles;
    int unsigned medium_accept_beats;
    int unsigned heavy_accept_beats;
    int unsigned medium_bkps_cycles;
    int unsigned heavy_bkps_cycles;
    int unsigned fallback_cycles;
    int unsigned d3_fallback_cycles;
    int unsigned occupancy_sum;
    int unsigned occupancy_peak;
    int unsigned issue_width_hist[5];
    int unsigned dep_hist[8];
    int unsigned delay_hist[4];
    int unsigned latency_sum;
    int unsigned latency_max;
    int unsigned dep_per_21 = 7;
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
            `uvm_fatal("NOVIF", "ppe_load_mix_perf_test cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_load_mix_perf_seq seq;

        phase.raise_objection(this);
        void'($value$plusargs("MIXED_DEP_PER_21=%d", dep_per_21));
        if (dep_per_21 > 21) begin
            `uvm_fatal("LOAD_DEP_CONFIG", $sformatf(
                "MIXED_DEP_PER_21=%0d must be in 0..21", dep_per_21))
        end
        seq = ppe_load_mix_perf_seq::type_id::create("seq");
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
        int unsigned latency;
        int unsigned lane;
        bit [4:0] desc;

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
            end
            if (measuring) begin
                measurement_cycles++;
                issued_count += issued_now;
                retired_count += retired_now;
                issue_width_hist[issued_now]++;
                occupancy_sum += vif.dbg_rob_occupancy;
                if (vif.dbg_rob_occupancy > occupancy_peak) begin
                    occupancy_peak = vif.dbg_rob_occupancy;
                end
                if (vif.dbg_fallback_valid) fallback_cycles++;
                if (vif.dbg_fallback_valid && vif.dbg_fallback_from_d3) begin
                    d3_fallback_cycles++;
                end

                if (accepted_count < MEDIUM_PACKETS) begin
                    medium_input_cycles++;
                    if (vif.bkps) medium_bkps_cycles++;
                end else if (accepted_count < TOTAL_PACKETS) begin
                    heavy_input_cycles++;
                    if (vif.bkps) heavy_bkps_cycles++;
                end

                if (accepted_now != 0) begin
                    if (accepted_count < MEDIUM_PACKETS) begin
                        medium_accept_beats++;
                    end else begin
                        heavy_accept_beats++;
                    end
                    for (lane = 0; lane < 4; lane++) begin
                        if (lane_valid(lane)) begin
                            desc = lane_desc(lane);
                            dep_hist[desc[4:2]]++;
                            delay_hist[desc[1:0]]++;
                            accept_cycle_q.push_back(cycle_count);
                        end
                    end
                    accepted_count += accepted_now;
                end

                repeat (retired_now) begin
                    if (accept_cycle_q.size() == 0) begin
                        `uvm_error("LOAD_LATENCY", "missing acceptance timestamp")
                    end else begin
                        latency = cycle_count - accept_cycle_q.pop_front();
                        latency_sum += latency;
                        if (latency > latency_max) latency_max = latency;
                    end
                end

                if (retired_count >= TOTAL_PACKETS) begin
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
        int unsigned dep;
        int unsigned delay;
        int unsigned expected_dep_count;

        if (!completed) begin
            `uvm_error("LOAD_TIMEOUT", $sformatf(
                "retired=%0d expected=%0d", retired_count, TOTAL_PACKETS))
        end
        if ((accepted_count != TOTAL_PACKETS) ||
            (issued_count != TOTAL_PACKETS) ||
            (retired_count != TOTAL_PACKETS)) begin
            `uvm_error("LOAD_COUNT", $sformatf(
                "accepted=%0d issued=%0d retired=%0d expected=%0d",
                accepted_count, issued_count, retired_count, TOTAL_PACKETS))
        end
        if ((medium_accept_beats != MEDIUM_BEATS) ||
            (heavy_accept_beats != HEAVY_BEATS)) begin
            `uvm_error("LOAD_BEATS", $sformatf(
                "medium=%0d/%0d heavy=%0d/%0d", medium_accept_beats,
                MEDIUM_BEATS, heavy_accept_beats, HEAVY_BEATS))
        end
        expected_dep_count = (21 - dep_per_21) * 54;
        if (dep_hist[0] != expected_dep_count) begin
            `uvm_error("LOAD_DEP_DIST", $sformatf(
                "no-dependency count=%0d expected=%0d", dep_hist[0],
                expected_dep_count))
        end
        for (dep = 1; dep < 8; dep++) begin
            expected_dep_count = 54 * ((dep_per_21 / 7)
                + ((dep <= (dep_per_21 % 7)) ? 1 : 0));
            if (dep_hist[dep] != expected_dep_count) begin
                `uvm_error("LOAD_DEP_DIST", $sformatf(
                    "dep%0d count=%0d expected=%0d", dep,
                    dep_hist[dep], expected_dep_count))
            end
        end
        for (delay = 0; delay < 4; delay++) begin
            if (delay_hist[delay] == 0) begin
                `uvm_error("LOAD_DELAY_DIST", $sformatf(
                    "random delay value %0d was not observed", delay))
            end
        end
        if ((env.scb.exp_total != TOTAL_PACKETS) ||
            (env.scb.got_total != TOTAL_PACKETS) ||
            (accept_cycle_q.size() != 0)) begin
            `uvm_error("LOAD_SCOREBOARD", $sformatf(
                "expected=%0d received=%0d pending_timestamps=%0d",
                env.scb.exp_total, env.scb.got_total, accept_cycle_q.size()))
        end
    endtask

    task report_metrics();
        real medium_port_util;
        real heavy_port_util;
        real medium_accept_rate;
        real heavy_accept_rate;
        real medium_bkps_ratio;
        real heavy_bkps_ratio;
        real issue_rate;
        real retire_rate;
        real avg_latency;
        real avg_occupancy;

        medium_port_util = $itor(MEDIUM_PACKETS) /
                           $itor(MEDIUM_BEATS * 4);
        heavy_port_util = $itor(HEAVY_PACKETS) /
                          $itor(HEAVY_BEATS * 4);
        medium_accept_rate = $itor(MEDIUM_PACKETS) / $itor(medium_input_cycles);
        heavy_accept_rate = $itor(HEAVY_PACKETS) / $itor(heavy_input_cycles);
        medium_bkps_ratio = $itor(medium_bkps_cycles) / $itor(medium_input_cycles);
        heavy_bkps_ratio = $itor(heavy_bkps_cycles) / $itor(heavy_input_cycles);
        issue_rate = $itor(issued_count) / $itor(measurement_cycles);
        retire_rate = $itor(retired_count) / $itor(measurement_cycles);
        avg_latency = $itor(latency_sum) / $itor(retired_count);
        avg_occupancy = $itor(occupancy_sum) / $itor(measurement_cycles);

        `uvm_info("LOAD_PERF", $sformatf(
            "load=medium packets=%0d source_beats=%0d port_util=%.4f accept_rate=%.4f bkps_ratio=%.4f",
            MEDIUM_PACKETS, MEDIUM_BEATS, medium_port_util,
            medium_accept_rate, medium_bkps_ratio), UVM_NONE)
        `uvm_info("LOAD_PERF", $sformatf(
            "load=heavy packets=%0d source_beats=%0d port_util=%.4f accept_rate=%.4f bkps_ratio=%.4f",
            HEAVY_PACKETS, HEAVY_BEATS, heavy_port_util,
            heavy_accept_rate, heavy_bkps_ratio), UVM_NONE)
        `uvm_info("LOAD_PERF", $sformatf(
            "total_packets=%0d cycles=%0d issue_rate=%.4f retire_rate=%.4f latency_avg=%.2f latency_max=%0d",
            TOTAL_PACKETS, measurement_cycles, issue_rate, retire_rate,
            avg_latency, latency_max), UVM_NONE)
        `uvm_info("LOAD_PERF", $sformatf(
            "dep_per_21=%0d dependency_hist={%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d} delay_hist={%0d,%0d,%0d,%0d}",
            dep_per_21,
            dep_hist[0], dep_hist[1], dep_hist[2], dep_hist[3], dep_hist[4],
            dep_hist[5], dep_hist[6], dep_hist[7], delay_hist[0],
            delay_hist[1], delay_hist[2], delay_hist[3]), UVM_NONE)
        `uvm_info("LOAD_PERF", $sformatf(
            "rob_avg=%.2f rob_peak=%0d fallback=%0d d3_fallback=%0d issue_width_hist={%0d,%0d,%0d,%0d,%0d}",
            avg_occupancy, occupancy_peak, fallback_cycles,
            d3_fallback_cycles, issue_width_hist[0], issue_width_hist[1],
            issue_width_hist[2], issue_width_hist[3], issue_width_hist[4]),
            UVM_NONE)
    endtask
endclass

`endif
