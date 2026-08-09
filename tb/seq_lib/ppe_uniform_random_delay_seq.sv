// -----------------------------------------------------------------------------
// N-wide, dependency-free traffic with independent uniform random delays.
// -----------------------------------------------------------------------------

`ifndef PPE_UNIFORM_RANDOM_DELAY_SEQ_SV
`define PPE_UNIFORM_RANDOM_DELAY_SEQ_SV

class ppe_uniform_random_delay_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_uniform_random_delay_seq)

    localparam int unsigned PACKET_COUNT = 8192;

    function new(string name = "ppe_uniform_random_delay_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned sent;
        int unsigned beat;
        int unsigned lane;
        bit [1:0] delay;
        bit       balanced_delay;

        balanced_delay = $test$plusargs("BALANCED_DELAY");

        while (sent < PACKET_COUNT) begin
            tr = ppe_item::type_id::create(
                $sformatf("uniform_delay_beat_%0d", beat));
            start_item(tr);
            tr.valid  = '{default: 1'b0};
            tr.seq    = '{default: '0};
            tr.packet = '{default: '0};
            tr.desc   = '{default: '0};

            for (lane = 0; lane < TB_N; lane++) begin
                if (sent < PACKET_COUNT) begin
                    delay = balanced_delay ? (lane % TB_DELAY_CLASSES)
                                            : $urandom_range(
                                                  TB_DELAY_CLASSES - 1, 0);
                    tr.valid[lane]  = 1'b1;
                    tr.seq[lane]    = sent;
                    tr.packet[lane] = make_packet(sent);
                    tr.desc[lane]   = {3'd0, delay};
                    sent++;
                end
            end
            finish_item(tr);
            beat++;
        end
    endtask

    function bit [127:0] make_packet(bit [31:0] seq);
        make_packet = {32'h55aa_0000 ^ seq,
                       32'h1020_0000 + seq,
                       32'hc33c_0000 ^ (seq << 1),
                       seq};
    endfunction
endclass

`endif
