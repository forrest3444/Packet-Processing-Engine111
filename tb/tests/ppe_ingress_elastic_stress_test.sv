//------------------------------------------------------------------------------
// Registered-input, empty-batch, full-ROB, and backpressure stress test.
//------------------------------------------------------------------------------

`ifndef PPE_INGRESS_ELASTIC_STRESS_TEST_SV
`define PPE_INGRESS_ELASTIC_STRESS_TEST_SV

class ppe_ingress_elastic_stress_test extends uvm_test;
    `uvm_component_utils(ppe_ingress_elastic_stress_test)

    localparam int unsigned PACKET_COUNT   = 256;
    localparam int unsigned TIMEOUT_CYCLES = 12000;

    ppe_env   env;
    ppe_vif_t vif;

    int unsigned occupancy_peak;
    int unsigned bkps_cycles;
    bit          completed;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = ppe_env::type_id::create("env", this);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_ingress_elastic_stress_test cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_ingress_elastic_stress_seq seq;

        phase.raise_objection(this);
        seq = ppe_ingress_elastic_stress_seq::type_id::create("seq");
        fork
            seq.start(env.master_agent.seqr);
            monitor_progress();
        join

        @(negedge vif.clk);
        if (!completed) begin
            `uvm_error("INGRESS_STRESS_TIMEOUT", $sformatf(
                "received=%0d expected=%0d", env.scb.got_total,
                PACKET_COUNT))
        end
        if (occupancy_peak != 32) begin
            `uvm_error("INGRESS_STRESS_OCC", $sformatf(
                "peak occupancy=%0d expected=32", occupancy_peak))
        end
        if (bkps_cycles == 0) begin
            `uvm_error("INGRESS_STRESS_BKPS",
                       "registered backpressure was never observed")
        end
        if ((env.scb.exp_total != PACKET_COUNT)
            || (env.scb.got_total != PACKET_COUNT)) begin
            `uvm_error("INGRESS_STRESS_SCOREBOARD", $sformatf(
                "expected=%0d received=%0d", env.scb.exp_total,
                env.scb.got_total))
        end

        `uvm_info("INGRESS_STRESS_METRIC", $sformatf(
            "packets=%0d occupancy_peak=%0d bkps_cycles=%0d",
            PACKET_COUNT, occupancy_peak, bkps_cycles), UVM_NONE)
        phase.drop_objection(this);
    endtask

    task monitor_progress();
        repeat (TIMEOUT_CYCLES) begin
            @(posedge vif.clk);
            if (vif.dbg_rob_occupancy > occupancy_peak) begin
                occupancy_peak = vif.dbg_rob_occupancy;
            end
            if (vif.bkps) begin
                bkps_cycles++;
            end
            if (env.scb.got_total >= PACKET_COUNT) begin
                completed = 1'b1;
                break;
            end
        end
    endtask

endclass

`endif
