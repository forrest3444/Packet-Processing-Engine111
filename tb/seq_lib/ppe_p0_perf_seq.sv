// -----------------------------------------------------------------------------
// P0 peak-throughput stimulus: full input width, no dependency, zero delay.
// -----------------------------------------------------------------------------

`ifndef PPE_P0_PERF_SEQ_SV
`define PPE_P0_PERF_SEQ_SV

class ppe_p0_perf_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_p0_perf_seq)

    localparam int unsigned PACKET_COUNT = 1024;
    localparam int unsigned BATCH_COUNT = PACKET_COUNT / 4;

    function new(string name = "ppe_p0_perf_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned batch;
        int unsigned base_seq;

        for (batch = 0; batch < BATCH_COUNT; batch++) begin
            base_seq = batch * 4;
            tr = ppe_item::type_id::create($sformatf("p0_batch_%0d", batch));
            start_item(tr);
            tr.valid = '{1'b1, 1'b1, 1'b1, 1'b1};
            tr.seq = '{base_seq, base_seq + 1, base_seq + 2, base_seq + 3};
            tr.packet = '{make_packet(base_seq), make_packet(base_seq + 1),
                          make_packet(base_seq + 2), make_packet(base_seq + 3)};
            tr.desc = '{5'b000_00, 5'b000_00, 5'b000_00, 5'b000_00};
            finish_item(tr);
        end
    endtask

    function bit [127:0] make_packet(bit [31:0] seq);
        make_packet = {32'h900d_0000 ^ seq,
                       32'h1357_0000 + seq,
                       32'h2468_0000 ^ (seq << 1),
                       seq};
    endfunction
endclass

`endif
