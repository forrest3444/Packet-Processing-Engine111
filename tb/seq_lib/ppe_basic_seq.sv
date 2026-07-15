// -----------------------------------------------------------------------------
// File       : ppe_basic_seq.sv
// Author     : Codex
// Description: Short smoke sequence for PPE UVM bring-up.
// -----------------------------------------------------------------------------

`ifndef PPE_BASIC_SEQ_SV
`define PPE_BASIC_SEQ_SV

class ppe_basic_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_basic_seq)

    function new(string name = "ppe_basic_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;

        tr = ppe_item::type_id::create("full_batch");
        start_item(tr);
        tr.valid = '{1'b1, 1'b1, 1'b1, 1'b1};
        tr.seq = '{0, 1, 2, 3};
        tr.packet = '{make_packet(0), make_packet(1),
                      make_packet(2), make_packet(3)};
        tr.desc = '{5'b000_11, 5'b001_00, 5'b000_01, 5'b010_00};
        finish_item(tr);

        tr = ppe_item::type_id::create("sparse_batch");
        start_item(tr);
        tr.valid = '{1'b1, 1'b1, 1'b0, 1'b1};
        tr.seq = '{4, 5, 32'hdead, 6};
        tr.packet = '{make_packet(4), make_packet(5),
                      make_packet(32'hdead), make_packet(6)};
        tr.desc = '{5'b001_10, 5'b000_00, 5'b000_00, 5'b010_01};
        finish_item(tr);

        tr = ppe_item::type_id::create("wrap_bank_batch");
        start_item(tr);
        tr.valid = '{1'b1, 1'b0, 1'b1, 1'b0};
        tr.seq = '{7, 32'hbeef, 8, 32'hfeed};
        tr.packet = '{make_packet(7), make_packet(32'hbeef),
                      make_packet(8), make_packet(32'hfeed)};
        tr.desc = '{5'b001_00, 5'b000_00, 5'b000_11, 5'b000_00};
        finish_item(tr);
    endtask

    function bit [127:0] make_packet(bit [31:0] seq);
        make_packet = {32'hcafe_0000 ^ seq,
                       32'h1234_0000 + seq,
                       32'h55aa_0000 ^ (seq << 1),
                       seq};
    endfunction
endclass

`endif
