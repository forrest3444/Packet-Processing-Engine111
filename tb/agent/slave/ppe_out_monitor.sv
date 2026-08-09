// -----------------------------------------------------------------------------
// File       : ppe_out_monitor.sv
// Author     : Codex
// Description: PPE slave output monitor.
// -----------------------------------------------------------------------------

`ifndef PPE_OUT_MONITOR_SV
`define PPE_OUT_MONITOR_SV

class ppe_out_monitor extends uvm_component;
    `uvm_component_utils(ppe_out_monitor)

    ppe_vif_t vif;
    uvm_analysis_port #(ppe_out_item) out_ap;
    bit [TB_LANE_W-1:0] start_lane;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        out_ap = new("out_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_out_monitor cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        int unsigned valid_count;
        int unsigned index;
        bit [TB_LANE_W-1:0] lane;

        @(posedge vif.rst_n);
        start_lane = '0;
        forever begin
            @(posedge vif.clk);
            valid_count = 0;
            for (int unsigned lane_idx = 0; lane_idx < TB_N; lane_idx++) begin
                valid_count += vif.out_valid[lane_idx];
            end
            for (index = 0; index < valid_count; index++) begin
                lane = start_lane + index;
                if (lane >= TB_N) begin
                    lane -= TB_N;
                end
                sample_lane(lane, vif.out_valid[lane], vif.out_packet[lane]);
            end
            start_lane += valid_count;
            if (start_lane >= TB_N) begin
                start_lane -= TB_N;
            end
        end
    endtask

    task sample_lane(bit [TB_LANE_W-1:0] lane, bit valid,
                     bit [PACKET_W-1:0] packet);
        ppe_out_item item;
        if (valid) begin
            item = ppe_out_item::type_id::create("item");
            item.lane = lane;
            item.packet = packet;
            out_ap.write(item);
        end else begin
            `uvm_error("OUT_HOLE", $sformatf("missing output at logical lane %0d", lane))
        end
    endtask
endclass

`endif
