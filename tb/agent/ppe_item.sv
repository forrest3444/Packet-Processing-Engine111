// -----------------------------------------------------------------------------
// File       : ppe_item.sv
// Author     : Codex
// Description: PPE agent transactions.
// -----------------------------------------------------------------------------

`ifndef PPE_ITEM_SV
`define PPE_ITEM_SV

class ppe_item extends uvm_sequence_item;
    rand bit        valid[4];
    rand bit [31:0] seq[4];
    rand bit [127:0] packet[4];
    rand bit [4:0]  desc[4];

    `uvm_object_utils_begin(ppe_item)
        `uvm_field_sarray_int(valid, UVM_DEFAULT)
        `uvm_field_sarray_int(seq,   UVM_DEFAULT)
        `uvm_field_sarray_int(packet, UVM_DEFAULT)
        `uvm_field_sarray_int(desc,  UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ppe_item");
        super.new(name);
    endfunction
endclass

class ppe_out_item extends uvm_sequence_item;
    bit [1:0]  lane;
    bit [127:0] packet;

    `uvm_object_utils_begin(ppe_out_item)
        `uvm_field_int(lane, UVM_DEFAULT)
        `uvm_field_int(packet, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ppe_out_item");
        super.new(name);
    endfunction
endclass

`endif
