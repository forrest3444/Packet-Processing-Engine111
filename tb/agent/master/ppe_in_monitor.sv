// -----------------------------------------------------------------------------
// PPE accepted-input monitor.
// -----------------------------------------------------------------------------

`ifndef PPE_IN_MONITOR_SV
`define PPE_IN_MONITOR_SV

class ppe_in_monitor extends uvm_component;
    `uvm_component_utils(ppe_in_monitor)

    ppe_vif_t vif;
    uvm_analysis_port #(ppe_item) ap;
    int unsigned accepted_batches;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(ppe_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "ppe_in_monitor cannot get vif")
        end
    endfunction

    task run_phase(uvm_phase phase);
        ppe_item tr;

        @(posedge vif.rst_n);
        forever begin
            @(posedge vif.clk);
            if (!vif.bkps && (vif.in_valid0 || vif.in_valid1 ||
                              vif.in_valid2 || vif.in_valid3)) begin
                tr = ppe_item::type_id::create(
                    $sformatf("accepted_batch_%0d", accepted_batches));
                tr.valid[0] = vif.in_valid0;
                tr.valid[1] = vif.in_valid1;
                tr.valid[2] = vif.in_valid2;
                tr.valid[3] = vif.in_valid3;
                tr.packet[0] = vif.in_packet0;
                tr.packet[1] = vif.in_packet1;
                tr.packet[2] = vif.in_packet2;
                tr.packet[3] = vif.in_packet3;
                tr.desc[0] = vif.in_desc0;
                tr.desc[1] = vif.in_desc1;
                tr.desc[2] = vif.in_desc2;
                tr.desc[3] = vif.in_desc3;
                tr.seq[0] = '0;
                tr.seq[1] = '0;
                tr.seq[2] = '0;
                tr.seq[3] = '0;
                accepted_batches++;
                ap.write(tr);
            end
        end
    endtask
endclass

`endif
