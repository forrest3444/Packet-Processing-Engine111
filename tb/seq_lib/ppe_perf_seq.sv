// -----------------------------------------------------------------------------
// Configurable stimulus for P1 through P6 performance characterization.
// -----------------------------------------------------------------------------

`ifndef PPE_PERF_SEQ_SV
`define PPE_PERF_SEQ_SV

class ppe_perf_config extends uvm_object;
    `uvm_object_utils(ppe_perf_config)

    string       scenario;
    int unsigned packet_count = 512;
    int unsigned lane_count = 4;
    bit          mixed_delay;
    int unsigned delay_value;
    int unsigned dep_mode;
    int unsigned dep_value;
    int unsigned dep_quarters;

    function new(string name = "ppe_perf_config");
        super.new(name);
    endfunction
endclass

class ppe_perf_seq extends uvm_sequence #(ppe_item);
    `uvm_object_utils(ppe_perf_seq)

    ppe_perf_config cfg;

    function new(string name = "ppe_perf_seq");
        super.new(name);
    endfunction

    task body();
        ppe_item tr;
        int unsigned sent;
        int unsigned batch;
        int unsigned lane;
        int unsigned seq;
        bit [2:0] dep_offset;
        bit [1:0] delay;

        if (cfg == null) begin
            `uvm_fatal("PERF_CFG", "ppe_perf_seq requires a configuration")
        end

        while (sent < cfg.packet_count) begin
            tr = ppe_item::type_id::create($sformatf("%s_batch_%0d",
                                                     cfg.scenario, batch));
            start_item(tr);
            tr.valid = '{1'b0, 1'b0, 1'b0, 1'b0};
            tr.seq = '{0, 0, 0, 0};
            tr.packet = '{'0, '0, '0, '0};
            tr.desc = '{5'b0, 5'b0, 5'b0, 5'b0};

            for (lane = 0; lane < 4; lane++) begin
                if ((lane < cfg.lane_count) && (sent < cfg.packet_count)) begin
                    seq = sent;
                    dep_offset = choose_dependency(seq);
                    delay = cfg.mixed_delay ? seq[1:0] : cfg.delay_value[1:0];
                    tr.valid[lane] = 1'b1;
                    tr.seq[lane] = seq;
                    tr.packet[lane] = make_packet(seq);
                    tr.desc[lane] = {dep_offset, delay};
                    sent++;
                end
            end
            finish_item(tr);
            batch++;
        end
    endtask

    function bit [2:0] choose_dependency(int unsigned seq);
        int unsigned candidate;

        choose_dependency = 3'd0;
        if (cfg.dep_mode == 1) begin
            if (seq >= cfg.dep_value) begin
                choose_dependency = cfg.dep_value[2:0];
            end
        end else if (cfg.dep_mode == 2) begin
            if ((seq % 4) < cfg.dep_quarters) begin
                candidate = (seq % 7) + 1;
                if (seq >= candidate) begin
                    choose_dependency = candidate[2:0];
                end
            end
        end
    endfunction

    function bit [127:0] make_packet(bit [31:0] seq);
        make_packet = {32'hbeef_0000 ^ seq,
                       32'h3141_0000 + seq,
                       32'h2718_0000 ^ (seq << 1),
                       seq};
    endfunction
endclass

`endif
