// -----------------------------------------------------------------------------
// File       : ppe_scoreboard.sv
// Author     : Codex
// Description: Full-width end-to-end PPE scoreboard.
// -----------------------------------------------------------------------------

`ifndef PPE_SCOREBOARD_SV
`define PPE_SCOREBOARD_SV

`uvm_analysis_imp_decl(_in)
`uvm_analysis_imp_decl(_out)

class ppe_scoreboard extends uvm_component;
    `uvm_component_utils(ppe_scoreboard)

    uvm_analysis_imp_in #(ppe_item, ppe_scoreboard) in_imp;
    uvm_analysis_imp_out #(ppe_out_item, ppe_scoreboard) out_imp;

    int unsigned exp_total;
    int unsigned got_total;
    bit [127:0] result_history[$];
    bit [127:0] expected_q[$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        in_imp = new("in_imp", this);
        out_imp = new("out_imp", this);
    endfunction

    function void write_in(ppe_item tr);
        int unsigned dep_offset;
        bit [127:0] dep_data;
        bit [127:0] vip_data_in;
        bit [127:0] expected;

        foreach (tr.valid[i]) begin
            if (tr.valid[i]) begin
                dep_offset = tr.desc[i][4:2];
                dep_data = 128'b0;
                if (dep_offset > result_history.size()) begin
                    `uvm_error("INVALID_DEP", $sformatf(
                        "dep_offset=%0d exceeds established history=%0d",
                        dep_offset, result_history.size()))
                end else if (dep_offset != 0) begin
                    dep_data = result_history[result_history.size()-dep_offset];
                end
                vip_data_in = tr.packet[i] ^ dep_data;
                expected = ppe_fe_vip::predict(vip_data_in, tr.desc[i][1:0]);
                result_history.push_back(expected);
                expected_q.push_back(expected);
                exp_total++;
            end
        end
    endfunction

    function void write_out(ppe_out_item item);
        bit [127:0] expected;

        if (expected_q.size() == 0) begin
            `uvm_error("UNEXPECTED", "output observed with an empty expected queue")
            return;
        end
        expected = expected_q.pop_front();

        if (item.packet !== expected) begin
            `uvm_error("DATA", $sformatf("output data mismatch at seq=%0d", got_total))
        end

        if (item.lane !== (got_total % TB_N)) begin
            `uvm_error("LANE", $sformatf("output lane got=%0d expected=%0d",
                       item.lane, got_total % TB_N))
        end

        got_total++;
    endfunction

    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (got_total != exp_total) begin
            `uvm_error("COUNT", $sformatf("output count got=%0d expected=%0d",
                       got_total, exp_total))
        end
        if (expected_q.size() != 0) begin
            `uvm_error("PENDING", $sformatf("expected queue contains %0d packets",
                       expected_q.size()))
        end
    endfunction
endclass

`endif
