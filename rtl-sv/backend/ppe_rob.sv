`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_rob.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Backend / Reorder Buffer
//
// Description :
//   Owns all in-flight ordering and result state. The block allocates ROB
//   entries in dense input order, accepts tagged FE completions, resolves
//   dependencies from authoritative storage, and emits a dense in-order
//   retirement prefix.
//
//   FE completions write only the active ROB. Retirement is the sole writer of
//   the eight-bank retired history. Dependency resolution priority is:
//   completion bypass, retirement bypass, active ROB, then retired history.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 4, 6.2, 8, and 9
//   - doc/hld.txt, Sections 3.4, 4.2, 4.4 through 4.6, and 5.2
//   - doc/lld.txt, Sections 4, 5.0 through 5.7, and 10 through 16
//
// Clock/reset :
//   State is clocked by clk_i. rst_ni is the shared active-low internal reset.
//   Reset clears valid/state bits and pointers. Wide data arrays are not reset
//   because their contents are ignored whenever the associated valid is clear.
//------------------------------------------------------------------------------

module ppe_rob #(
    parameter int unsigned PACKET_W    = 128,
    parameter int unsigned ISSUE_WIDTH = 4
) (
    // Clock and reset
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    // Raw top-level demand, used only by the capacity calculation. These
    // valids are deliberately not qualified by bkps_o.
    input  logic [ppe_types_pkg::N-1:0]                    input_valid_i,
    output logic                                           bkps_o,

    // Accepted allocation event from ingress. Each local physical index is
    // derived from the complete sequence tag; no allocation-ID response exists.
    input  logic [ppe_types_pkg::N-1:0]                    alloc_valid_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_seq_tag_i,

    // D0 dependency-status queries. "available" means that result data can be
    // obtained now; it is neither handshake ready nor a tag-only hit.
    input  logic [ppe_types_pkg::N-1:0]                    dep_status_valid_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_status_target_seq_tag_i,
    output logic [ppe_types_pkg::N-1:0]                    dep_status_available_o,

    // D3 dependency-data gather. data_valid reports that authoritative result
    // data was resolved; it does not apply backpressure to the request.
    input  logic [ISSUE_WIDTH-1:0]                         dep_gather_valid_i,
    input  logic [ISSUE_WIDTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_gather_target_seq_tag_i,
    output logic [ISSUE_WIDTH-1:0]                         dep_gather_data_valid_o,
    output logic [ISSUE_WIDTH-1:0][PACKET_W-1:0]           dep_gather_data_o,

    // Tagged FE completions. There is no ready; every protocol-valid return
    // must be captured in its asserted cycle.
    input  logic [ppe_types_pkg::FE_NUM-1:0]               wb_valid_i,
    input  logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                wb_seq_tag_i,
    input  logic [ppe_types_pkg::FE_NUM-1:0][PACKET_W-1:0] wb_data_i,

    // Logical in-order retirement bundle. Valid slots form a dense prefix
    // beginning at slot zero; ppe_retire_output maps it to physical lanes.
    output logic [ppe_types_pkg::N-1:0]                    retire_valid_o,
    output logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]      retire_data_o
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Local parameters, types, and pointer arithmetic
    //--------------------------------------------------------------------------

    localparam int unsigned LANE_COUNT_W  = $clog2(N + 1);
    localparam int unsigned OCCUPANCY_W   = $clog2(ROB_DEPTH + 1);
    localparam int unsigned HISTORY_DEPTH = 8;
    localparam int unsigned HISTORY_ID_W  = $clog2(HISTORY_DEPTH);
    localparam int unsigned PTR_SUM_W     = ROB_ID_W + 1;

    typedef logic [ROB_ID_W-1:0]     rob_id_t;
    typedef logic [LANE_COUNT_W-1:0] lane_count_t;

    // ROB_DEPTH >= N means adding one batch requires at most one wrap.
    function automatic rob_id_t rob_ptr_add(
        input rob_id_t     base,
        input lane_count_t offset
    );
        logic [PTR_SUM_W-1:0] sum;
        begin
            sum = PTR_SUM_W'(base) + PTR_SUM_W'(offset);
            if (sum >= PTR_SUM_W'(ROB_DEPTH)) begin
                sum = sum - PTR_SUM_W'(ROB_DEPTH);
            end
            rob_ptr_add = rob_id_t'(sum);
        end
    endfunction

    //--------------------------------------------------------------------------
    // Active ROB and retired-history storage
    //--------------------------------------------------------------------------

    logic [ROB_DEPTH-1:0]               rob_valid_q;
    logic [ROB_DEPTH-1:0]               rob_result_valid_q;
    logic [ROB_DEPTH-1:0][SEQ_W-1:0]    rob_seq_tag_q;
    logic [ROB_DEPTH-1:0][PACKET_W-1:0] rob_data_q;

    logic [HISTORY_DEPTH-1:0]               history_valid_q;
    logic [HISTORY_DEPTH-1:0][SEQ_W-1:0]    history_seq_tag_q;
    logic [HISTORY_DEPTH-1:0][PACKET_W-1:0] history_data_q;

    //--------------------------------------------------------------------------
    // Global state and per-cycle events
    //--------------------------------------------------------------------------

    rob_id_t                head_ptr_q;
    logic [OCCUPANCY_W-1:0] occupancy_q;

    lane_count_t input_count;
    lane_count_t alloc_count;
    lane_count_t retire_count;

    logic [OCCUPANCY_W-1:0] free_count;
    logic [OCCUPANCY_W-1:0] available_count;

    logic [FE_NUM-1:0] wb_commit;
    logic [FE_NUM-1:0][ROB_ID_W-1:0] wb_rob_id;

    logic [N-1:0][ROB_ID_W-1:0] alloc_rob_id;
    logic [N-1:0][ROB_ID_W-1:0] retire_rob_id;
    logic [N-1:0][SEQ_W-1:0]    retire_seq_tag;

    //--------------------------------------------------------------------------
    // Local allocation indices and raw input demand
    //--------------------------------------------------------------------------

    always_comb begin
        input_count    = '0;
        alloc_count    = '0;
        alloc_rob_id   = '0;

        for (int unsigned lane_idx = 0; lane_idx < N; lane_idx++) begin
            if (input_valid_i[lane_idx]) begin
                input_count = input_count + lane_count_t'(1);
            end

            if (alloc_valid_i[lane_idx]) begin
                alloc_rob_id[lane_idx] = rob_id_t'(
                    alloc_seq_tag_i[lane_idx][ROB_ID_W-1:0]);
                alloc_count = alloc_count + lane_count_t'(1);
            end
        end
    end

    //--------------------------------------------------------------------------
    // Writeback qualification and completion-bypass event generation
    //--------------------------------------------------------------------------

    always_comb begin
        wb_commit = '0;
        wb_rob_id = '0;

        for (int unsigned wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
            wb_rob_id[wb_idx] = rob_id_t'(
                wb_seq_tag_i[wb_idx][ROB_ID_W-1:0]);
            if (wb_valid_i[wb_idx]
                && rob_valid_q[wb_rob_id[wb_idx]]
                && (rob_seq_tag_q[wb_rob_id[wb_idx]]
                    == wb_seq_tag_i[wb_idx])
                && !rob_result_valid_q[wb_rob_id[wb_idx]]) begin
                wb_commit[wb_idx] = 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Consecutive-DONE scan and logical retirement bundle
    //--------------------------------------------------------------------------

    always_comb begin : retirement_scan
        logic    prefix_done;
        rob_id_t scan_rob_id;

        retire_valid_o = '0;
        retire_data_o  = '0;
        retire_rob_id  = '0;
        retire_seq_tag = '0;
        retire_count   = '0;
        prefix_done    = 1'b1;
        scan_rob_id    = '0;

        for (int unsigned retire_idx = 0; retire_idx < N; retire_idx++) begin
            scan_rob_id = rob_ptr_add(head_ptr_q, lane_count_t'(retire_idx));

            if (prefix_done
                && rob_valid_q[scan_rob_id]
                && rob_result_valid_q[scan_rob_id]) begin
                retire_valid_o[retire_idx] = 1'b1;
                retire_data_o[retire_idx]  = rob_data_q[scan_rob_id];
                retire_rob_id[retire_idx]  = scan_rob_id;
                retire_seq_tag[retire_idx] = rob_seq_tag_q[scan_rob_id];
                retire_count = retire_count + lane_count_t'(1);
            end else begin
                prefix_done = 1'b0;
            end
        end
    end

    //--------------------------------------------------------------------------
    // Global backpressure
    //--------------------------------------------------------------------------

    always_comb begin
        free_count      = OCCUPANCY_W'(ROB_DEPTH) - occupancy_q;
        available_count = free_count + OCCUPANCY_W'(retire_count);

        // Reset only gates admission. Entry and history valids are cleared by
        // the sequential reset rather than broadcasting reset over datapaths.
        bkps_o = !rst_ni
                 || (available_count < OCCUPANCY_W'(input_count));
    end

    //--------------------------------------------------------------------------
    // D0 dependency-status resolution
    //--------------------------------------------------------------------------

    always_comb begin : dependency_status_resolve
        dep_status_available_o = '0;

        for (int unsigned query_idx = 0; query_idx < N; query_idx++) begin
            logic                    source_resolved;
            rob_id_t                 target_rob_id;
            logic [HISTORY_ID_W-1:0] history_id;

            source_resolved = 1'b0;
            target_rob_id = rob_id_t'(
                dep_status_target_seq_tag_i[query_idx][ROB_ID_W-1:0]);
            history_id = dep_status_target_seq_tag_i[query_idx]
                         [HISTORY_ID_W-1:0];

            if (dep_status_valid_i[query_idx]) begin
                // 1) Completion bypass.
                for (int unsigned wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
                    if (!source_resolved
                        && wb_commit[wb_idx]
                        && (wb_rob_id[wb_idx] == target_rob_id)
                        && (wb_seq_tag_i[wb_idx]
                            == dep_status_target_seq_tag_i[query_idx])) begin
                        source_resolved = 1'b1;
                        dep_status_available_o[query_idx] = 1'b1;
                    end
                end

                // 2) Retirement bypass using pre-edge ROB contents.
                for (int unsigned retire_idx = 0;
                     retire_idx < N;
                     retire_idx++) begin
                    if (!source_resolved
                        && retire_valid_o[retire_idx]
                        && (retire_seq_tag[retire_idx]
                            == dep_status_target_seq_tag_i[query_idx])) begin
                        source_resolved = 1'b1;
                        dep_status_available_o[query_idx] = 1'b1;
                    end
                end

                // 3) Active ROB. A pending full-tag match is authoritative and
                // must stop the search before retired history.
                if (!source_resolved
                    && rob_valid_q[target_rob_id]
                    && (rob_seq_tag_q[target_rob_id]
                        == dep_status_target_seq_tag_i[query_idx])) begin
                    source_resolved = 1'b1;
                    dep_status_available_o[query_idx] =
                        rob_result_valid_q[target_rob_id];
                end

                // 4) Retired history.
                if (!source_resolved
                    && history_valid_q[history_id]
                    && (history_seq_tag_q[history_id]
                        == dep_status_target_seq_tag_i[query_idx])) begin
                    dep_status_available_o[query_idx] = 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // D3 dependency-data resolution
    //--------------------------------------------------------------------------

    always_comb begin : dependency_data_resolve
        dep_gather_data_valid_o = '0;
        dep_gather_data_o       = '0;

        for (int unsigned query_idx = 0;
             query_idx < ISSUE_WIDTH;
             query_idx++) begin
            logic                    source_resolved;
            rob_id_t                 target_rob_id;
            logic [HISTORY_ID_W-1:0] history_id;

            source_resolved = 1'b0;
            target_rob_id = rob_id_t'(
                dep_gather_target_seq_tag_i[query_idx][ROB_ID_W-1:0]);
            history_id = dep_gather_target_seq_tag_i[query_idx]
                         [HISTORY_ID_W-1:0];

            if (dep_gather_valid_i[query_idx]) begin
                // 1) Completion bypass.
                for (int unsigned wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
                    if (!source_resolved
                        && wb_commit[wb_idx]
                        && (wb_rob_id[wb_idx] == target_rob_id)
                        && (wb_seq_tag_i[wb_idx]
                            == dep_gather_target_seq_tag_i[query_idx])) begin
                        source_resolved = 1'b1;
                        dep_gather_data_valid_o[query_idx] = 1'b1;
                        dep_gather_data_o[query_idx] = wb_data_i[wb_idx];
                    end
                end

                // 2) Retirement bypass.
                for (int unsigned retire_idx = 0;
                     retire_idx < N;
                     retire_idx++) begin
                    if (!source_resolved
                        && retire_valid_o[retire_idx]
                        && (retire_seq_tag[retire_idx]
                            == dep_gather_target_seq_tag_i[query_idx])) begin
                        source_resolved = 1'b1;
                        dep_gather_data_valid_o[query_idx] = 1'b1;
                        dep_gather_data_o[query_idx] =
                            retire_data_o[retire_idx];
                    end
                end

                // 3) Active ROB, including the authoritative pending case.
                if (!source_resolved
                    && rob_valid_q[target_rob_id]
                    && (rob_seq_tag_q[target_rob_id]
                        == dep_gather_target_seq_tag_i[query_idx])) begin
                    source_resolved = 1'b1;
                    dep_gather_data_valid_o[query_idx] =
                        rob_result_valid_q[target_rob_id];
                    if (rob_result_valid_q[target_rob_id]) begin
                        dep_gather_data_o[query_idx] =
                            rob_data_q[target_rob_id];
                    end
                end

                // 4) Retired history.
                if (!source_resolved
                    && history_valid_q[history_id]
                    && (history_seq_tag_q[history_id]
                        == dep_gather_target_seq_tag_i[query_idx])) begin
                    dep_gather_data_valid_o[query_idx] = 1'b1;
                    dep_gather_data_o[query_idx] = history_data_q[history_id];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Concurrent state update
    //--------------------------------------------------------------------------

    // Within one edge the effective priority is writeback, retirement, then
    // allocation. Allocation therefore owns the final state of a slot reused
    // from the retirement prefix on that edge.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rob_valid_q        <= '0;
            rob_result_valid_q <= '0;
            history_valid_q    <= '0;
            head_ptr_q         <= '0;
            occupancy_q        <= '0;
        end else begin
            // W0: capture all qualified FE completions.
            for (int unsigned wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
                if (wb_commit[wb_idx]) begin
                    rob_data_q[wb_rob_id[wb_idx]] <= wb_data_i[wb_idx];
                    rob_result_valid_q[wb_rob_id[wb_idx]] <= 1'b1;
                end
            end

            // R0: history and output observe pre-edge ROB contents.
            for (int unsigned retire_idx = 0;
                 retire_idx < N;
                 retire_idx++) begin
                if (retire_valid_o[retire_idx]) begin
                    history_valid_q[
                        retire_seq_tag[retire_idx][HISTORY_ID_W-1:0]] <= 1'b1;
                    history_seq_tag_q[
                        retire_seq_tag[retire_idx][HISTORY_ID_W-1:0]] <=
                        retire_seq_tag[retire_idx];
                    history_data_q[
                        retire_seq_tag[retire_idx][HISTORY_ID_W-1:0]] <=
                        retire_data_o[retire_idx];

                    rob_valid_q[retire_rob_id[retire_idx]] <= 1'b0;
                    rob_result_valid_q[retire_rob_id[retire_idx]] <= 1'b0;
                end
            end

            // A0: allocation is the final writer for same-edge slot reuse.
            for (int unsigned alloc_idx = 0; alloc_idx < N; alloc_idx++) begin
                if (alloc_valid_i[alloc_idx]) begin
                    rob_valid_q[alloc_rob_id[alloc_idx]] <= 1'b1;
                    rob_seq_tag_q[alloc_rob_id[alloc_idx]] <=
                        alloc_seq_tag_i[alloc_idx];
                    rob_result_valid_q[alloc_rob_id[alloc_idx]] <= 1'b0;
                end
            end

            if (retire_count != '0) begin
                head_ptr_q <= rob_ptr_add(head_ptr_q, retire_count);
            end

            if ((alloc_count != '0) || (retire_count != '0)) begin
                occupancy_q <= occupancy_q
                               + OCCUPANCY_W'(alloc_count)
                               - OCCUPANCY_W'(retire_count);
            end
        end
    end

endmodule : ppe_rob

`default_nettype wire
