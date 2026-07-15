// -----------------------------------------------------------------------------
// Data reference model matching the contest FE VIP behavior used by this TB.
// -----------------------------------------------------------------------------

`ifndef PPE_FE_VIP_SV
`define PPE_FE_VIP_SV

class ppe_fe_vip extends uvm_object;
    `uvm_object_utils(ppe_fe_vip)

    function new(string name = "ppe_fe_vip");
        super.new(name);
    endfunction

    static function bit [127:0] predict(
        bit [127:0] packet,
        bit         dep_valid,
        bit [127:0] dep_data,
        bit [1:0]   delay
    );
        predict = packet ^ (dep_valid ? dep_data : 128'b0) ^
                  {{126{1'b0}}, delay};
    endfunction
endclass

`endif
