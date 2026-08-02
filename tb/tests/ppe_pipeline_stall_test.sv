// -----------------------------------------------------------------------------
// Mixed-load end-to-end test with verification-only pipeline blockage probing.
// -----------------------------------------------------------------------------

`ifndef PPE_PIPELINE_STALL_TEST_SV
`define PPE_PIPELINE_STALL_TEST_SV

class ppe_pipeline_stall_test extends ppe_load_mix_perf_test;
    `uvm_component_utils(ppe_pipeline_stall_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

`endif
