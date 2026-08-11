// -----------------------------------------------------------------------------
// File       : ppe_random_seq_base.sv
// Description: Configurable random-batch sequence base.
// -----------------------------------------------------------------------------

`ifndef PPE_RANDOM_SEQ_BASE_SV
`define PPE_RANDOM_SEQ_BASE_SV

class ppe_random_seq_base extends ppe_seq_base;
    `uvm_object_utils(ppe_random_seq_base)

    // The default workload is deliberately bounded for repeatable regressions.
    rand int unsigned batch_count;
    rand int unsigned min_valid_lanes;
    rand int unsigned max_valid_lanes;
    rand int unsigned dependency_percent;

    // Derived sequences can set these before randomize(). Plusargs override
    // them when explicitly supplied by a test invocation.
    bit allow_empty_batches;
    bit dependencies_enabled;
    bit balanced_delay;

    localparam int unsigned MAX_DEPENDENCY = `PPE_MAX_DEP;

    bit          config_randomized;
    bit          batch_count_override_valid;
    int unsigned batch_count_override;

    constraint c_batch_count {
        batch_count inside {[1000:3000]};
        if (batch_count_override_valid) batch_count == batch_count_override;
    }

    constraint c_valid_lanes {
        min_valid_lanes <= max_valid_lanes;
        max_valid_lanes <= TB_N;
        if (!allow_empty_batches) min_valid_lanes >= 1;
    }

    constraint c_dependency_percent {
        dependency_percent <= 100;
        if (!dependencies_enabled) dependency_percent == 0;
    }

    function new(string name = "ppe_random_seq_base");
        super.new(name);
        allow_empty_batches = 1'b0;
        dependencies_enabled = 1'b0;
        balanced_delay = 1'b0;
        config_randomized = 1'b0;
        batch_count_override_valid = 1'b0;
        batch_count_override = 0;
    endfunction

    function void pre_randomize();
        int requested_batch_count;
        int requested_empty_mode;
        int requested_dependency_mode;
        int requested_balance_mode;

        super.pre_randomize();

        if ($value$plusargs("PPE_BATCH_COUNT=%d", requested_batch_count)) begin
            if ((requested_batch_count < 1000)
                || (requested_batch_count > 3000)) begin
                `uvm_fatal("SEQ_CONFIG", $sformatf(
                    "PPE_BATCH_COUNT=%0d is outside 1000..3000",
                    requested_batch_count))
            end
            batch_count_override_valid = 1'b1;
            batch_count_override = requested_batch_count;
        end
        if ($value$plusargs("PPE_ALLOW_EMPTY=%d", requested_empty_mode)) begin
            allow_empty_batches = (requested_empty_mode != 0);
        end
        if ($value$plusargs("PPE_DEPENDENCIES=%d", requested_dependency_mode)) begin
            dependencies_enabled = (requested_dependency_mode != 0);
        end
        if ($value$plusargs("PPE_BALANCED_DELAY=%d", requested_balance_mode)) begin
            balanced_delay = (requested_balance_mode != 0);
        end
    endfunction

    function void post_randomize();
        super.post_randomize();
        config_randomized = 1'b1;
    endfunction

    virtual task body();
        ppe_item tr;

        if (!config_randomized && !randomize()) begin
            `uvm_fatal("SEQ_CONFIG", "random sequence configuration failed")
        end
        reset_generation_state();

        for (int unsigned batch = 0; batch < batch_count; batch++) begin
            tr = ppe_item::type_id::create($sformatf("random_batch_%0d", batch));
            start_item(tr);
            randomize_batch(tr, batch);
            finish_item(tr);
        end
    endtask

    // Batch generation is a hook rather than an inline body so derived tests
    // can preserve the common configuration and replace only traffic policy.
    virtual function void randomize_batch(ppe_item tr,
                                          int unsigned batch_index);
        int unsigned valid_count;
        bit [TB_N-1:0] lane_mask;

        pre_batch_randomize(tr, batch_index);
        clear_item(tr);
        valid_count = $urandom_range(max_valid_lanes, min_valid_lanes);
        lane_mask = choose_lane_mask(valid_count);
        for (int unsigned lane = 0; lane < TB_N; lane++) begin
            if (lane_mask[lane]) begin
                fill_valid_lane(tr, lane, generated_packet_count,
                                choose_dependency_offset(
                                    generated_packet_count),
                                choose_delay_class(lane, batch_index));
            end
        end
        generated_batch_count++;
        post_batch_randomize(tr, batch_index);
    endfunction

    virtual function void pre_batch_randomize(ppe_item tr,
                                              int unsigned batch_index);
    endfunction

    virtual function void post_batch_randomize(ppe_item tr,
                                               int unsigned batch_index);
    endfunction

    function bit [TB_N-1:0] choose_lane_mask(int unsigned valid_count);
        bit [TB_N-1:0] mask;
        int unsigned lane;
        int unsigned picked;

        if (valid_count > TB_N) begin
            `uvm_fatal("SEQ_CONFIG", $sformatf(
                "valid_count=%0d exceeds configured width=%0d",
                valid_count, TB_N))
        end
        mask = '0;
        picked = 0;
        while (picked < valid_count) begin
            lane = $urandom_range(TB_N - 1, 0);
            if (!mask[lane]) begin
                mask[lane] = 1'b1;
                picked++;
            end
        end
        return mask;
    endfunction

    function bit [2:0] choose_dependency_offset(int unsigned history_count);
        int unsigned max_offset;

        choose_dependency_offset = 3'd0;
        if (!dependencies_enabled || (dependency_percent == 0)
            || (history_count == 0)) begin
            return choose_dependency_offset;
        end
        if ($urandom_range(99, 0) >= dependency_percent) begin
            return choose_dependency_offset;
        end

        max_offset = history_count;
        if (max_offset > MAX_DEPENDENCY) max_offset = MAX_DEPENDENCY;
        if (max_offset != 0) begin
            choose_dependency_offset = $urandom_range(max_offset, 1);
        end
    endfunction

    function bit [1:0] choose_delay_class(int unsigned lane,
                                          int unsigned batch_index);
        if (balanced_delay) begin
            choose_delay_class = (lane + batch_index) % TB_DELAY_CLASSES;
        end else begin
            choose_delay_class = $urandom_range(TB_DELAY_CLASSES - 1, 0);
        end
    endfunction
endclass

`endif
