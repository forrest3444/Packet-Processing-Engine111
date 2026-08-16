// -----------------------------------------------------------------------------
// P0 peak-throughput stimulus: full input width, no dependency, zero delay.
// -----------------------------------------------------------------------------

`ifndef PPE_P0_PERF_SEQ_SV
`define PPE_P0_PERF_SEQ_SV

class ppe_p0_perf_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_p0_perf_seq)

    localparam int unsigned PACKET_COUNT = 20480;
    localparam int unsigned BATCH_COUNT = PACKET_COUNT / TB_N;

    function new(string name = "ppe_p0_perf_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned batch;
        int unsigned base_seq;
        int unsigned lane;

        for (batch = 0; batch < BATCH_COUNT; batch++) begin
            base_seq = batch * TB_N;
            tr = ppe_item::type_id::create($sformatf("p0_batch_%0d", batch));
            start_item(tr);
            for (lane = 0; lane < TB_N; lane++) begin
                tr.valid[lane] = 1'b1;
                tr.seq[lane] = base_seq + lane;
                tr.packet[lane] = make_packet(tr.seq[lane]);
                tr.desc[lane] = 5'b000_00;
            end
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
