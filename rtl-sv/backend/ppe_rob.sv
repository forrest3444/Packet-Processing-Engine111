`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_rob.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Backend / Reorder Buffer
//
// Description :
//   Owns all in-flight ordering and result state. The block allocates ROB
//   entries from the registered ingress FIFO head, accepts tagged FE
//   completions, resolves
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
    parameter int PACKET_W = ppe_types_pkg::DEFAULT_PACKET_W
) (
    // Clock and reset
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    // Registered FIFO-head request from ingress. alloc_ready_o accepts or
    // stalls the complete batch; allocation is never accepted per lane.
    input  logic [ppe_types_pkg::N-1:0]                    alloc_req_valid_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_seq_tag_i,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]      alloc_packet_i,
    output logic                                           alloc_ready_o,

    // D0 dependency-status queries. "available" means that result data can be
    // obtained now; it is neither handshake ready nor a tag-only hit.
    input  logic [ppe_types_pkg::N-1:0]                    dep_status_valid_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_status_target_seq_tag_i,
    output logic [ppe_types_pkg::N-1:0]                    dep_status_available_o,

    // D3 dependency-data gather. data_valid reports that authoritative result
    // data was resolved; it does not apply backpressure to the request.
    input  logic [ppe_types_pkg::ISSUE_WIDTH-1:0]          dep_gather_valid_i,
    input  logic [ppe_types_pkg::ISSUE_WIDTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_gather_target_seq_tag_i,
    output logic [ppe_types_pkg::ISSUE_WIDTH-1:0]          dep_gather_data_valid_o,
    output logic [ppe_types_pkg::ISSUE_WIDTH-1:0]
                 [PACKET_W-1:0]                            dep_gather_data_o,

    // D3 source-packet read. A valid response denotes the original allocation
    // packet; result_valid distinguishes it from an overwritten FE result.
    input  logic [ppe_types_pkg::ISSUE_WIDTH-1:0]          issue_read_valid_i,
    input  logic [ppe_types_pkg::ISSUE_WIDTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                issue_read_seq_tag_i,
    output logic [ppe_types_pkg::ISSUE_WIDTH-1:0]          issue_read_data_valid_o,
    output logic [ppe_types_pkg::ISSUE_WIDTH-1:0]
                 [PACKET_W-1:0]                            issue_read_data_o,

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

    localparam int LANE_COUNT_W = $clog2(N + 1);
    localparam int OCCUPANCY_W  = $clog2(ROB_DEPTH + 1);
    localparam int PTR_SUM_W    = ROB_ID_W + 1;
    localparam int DATA_BANK_NUM = N;
    localparam int DATA_BANK_W   = $clog2(DATA_BANK_NUM);
    localparam int DATA_ROW_NUM  = ROB_DEPTH / DATA_BANK_NUM;
    localparam int DATA_ROW_W    = $clog2(DATA_ROW_NUM);
    localparam int ROB_TAG_HI_W  = SEQ_W - ROB_ID_W;
    localparam int HISTORY_TAG_HI_W = SEQ_W - HISTORY_ID_W;

    typedef logic [LANE_COUNT_W-1:0] lane_count_t;
    typedef logic [DATA_BANK_W-1:0]  data_bank_t;
    typedef logic [DATA_ROW_W-1:0]   data_row_t;

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

    logic [ROB_DEPTH-1:0]                  rob_valid_q;
    logic [ROB_DEPTH-1:0]                  rob_result_valid_q;
    logic [ROB_DEPTH-1:0][ROB_TAG_HI_W-1:0] rob_tag_hi_q;
    logic [ROB_DEPTH-1:0][SEQ_W-1:0]       rob_seq_tag_q;

    logic [DATA_BANK_NUM-1:0][DATA_ROW_NUM-1:0]
          [PACKET_W-1:0] rob_data_q;

    logic [RESULT_BANKS-1:0] history_valid_q;
    logic [RESULT_BANKS-1:0][HISTORY_TAG_HI_W-1:0]
          history_tag_hi_q;
    logic [RESULT_BANKS-1:0][SEQ_W-1:0] history_seq_tag_q;
    logic [RESULT_BANKS-1:0][PACKET_W-1:0] history_data_q;

    // Full-tag views preserve debug visibility without duplicating state.
    for (genvar entry_idx = 0;
         entry_idx < ROB_DEPTH;
         entry_idx++) begin : gen_rob_tag_view
        assign rob_seq_tag_q[entry_idx] = {
            rob_tag_hi_q[entry_idx],
            ROB_ID_W'(entry_idx)
        };
    end

    for (genvar history_idx = 0;
         history_idx < RESULT_BANKS;
         history_idx++) begin : gen_history_tag_view
        assign history_seq_tag_q[history_idx] = {
            history_tag_hi_q[history_idx],
            HISTORY_ID_W'(history_idx)
        };
    end

    //--------------------------------------------------------------------------
    // Global state and per-cycle events
    //--------------------------------------------------------------------------

    rob_id_t                head_ptr_q;
    logic [OCCUPANCY_W-1:0] occupancy_q;

    lane_count_t request_count;
    lane_count_t alloc_count;
    lane_count_t retire_count;

    logic [OCCUPANCY_W-1:0] free_count;

    logic [FE_NUM-1:0] wb_commit;
    logic [FE_NUM-1:0][ROB_ID_W-1:0] wb_rob_id;

    logic [N-1:0][ROB_ID_W-1:0] alloc_rob_id;
    logic [N-1:0][ROB_ID_W-1:0] retire_rob_id;
    logic [N-1:0][SEQ_W-1:0]    retire_seq_tag;
    logic [N-1:0]               alloc_fire;

    logic [ROB_DEPTH-1:0][FE_NUM-1:0]      wb_entry_commit;
    logic [ROB_DEPTH-1:0]                  data_entry_write_en;
    logic [ROB_DEPTH-1:0][PACKET_W-1:0]    data_entry_write_data;

    logic [DATA_BANK_NUM-1:0]               alloc_data_valid_q;
    logic [DATA_BANK_NUM-1:0][DATA_ROW_W-1:0]
                                                alloc_data_row_q;
    logic [DATA_BANK_NUM-1:0][PACKET_W-1:0] alloc_data_q;
    logic [DATA_BANK_NUM-1:0]               alloc_data_capture_valid;
    logic [DATA_BANK_NUM-1:0][DATA_ROW_W-1:0]
                                                alloc_data_capture_row;
    logic [DATA_BANK_NUM-1:0][PACKET_W-1:0]
                                                alloc_data_capture;

    logic [RESULT_BANKS-1:0]               history_write_en;
    logic [RESULT_BANKS-1:0][SEQ_W-1:0]    history_write_seq_tag;
    logic [RESULT_BANKS-1:0][PACKET_W-1:0] history_write_data;

    logic [DATA_BANK_NUM-1:0][PACKET_W-1:0] retire_bank_data;
    logic [DATA_BANK_NUM-1:0][PACKET_W-1:0] retire_rotate_one_data;

    logic [N-1:0]             dep_status_active_match;
    logic [N-1:0]             dep_status_active_available;
    logic [N-1:0]             dep_status_history_match;
    logic [ISSUE_WIDTH-1:0]   dep_gather_active_match;
    logic [ISSUE_WIDTH-1:0]   dep_gather_active_available;
    logic [ISSUE_WIDTH-1:0]   dep_gather_history_match;
    logic [ISSUE_WIDTH-1:0][PACKET_W-1:0] dep_gather_active_data;
    logic [ISSUE_WIDTH-1:0][PACKET_W-1:0] dep_gather_history_data;

    logic [DATA_BANK_NUM-1:0] source_bank_req_valid;
    logic [DATA_BANK_NUM-1:0][DATA_ROW_W-1:0] source_bank_req_row;
    logic [DATA_BANK_NUM-1:0][ROB_TAG_HI_W-1:0]
          source_bank_req_tag_hi;
    logic [DATA_BANK_NUM-1:0] source_bank_data_valid;
    logic [DATA_BANK_NUM-1:0][PACKET_W-1:0] source_bank_data;

    function automatic logic [PACKET_W-1:0] rob_data_read(
        input rob_id_t rob_id
    );
        rob_data_read = rob_data_q[rob_id[DATA_BANK_W-1:0]]
                                  [rob_id[ROB_ID_W-1:DATA_BANK_W]];
    endfunction

    //--------------------------------------------------------------------------
    // Local allocation request decode
    //--------------------------------------------------------------------------

    always_comb begin : allocation_request_decode
        request_count  = '0;
        alloc_rob_id   = '0;

        for (int lane_idx = 0; lane_idx < N; lane_idx++) begin
            if (alloc_req_valid_i[lane_idx]) begin
                request_count = request_count + lane_count_t'(1);
                alloc_rob_id[lane_idx] = rob_id_t'(
                    alloc_seq_tag_i[lane_idx][ROB_ID_W-1:0]);
            end
        end
    end

    assign alloc_fire = alloc_req_valid_i & {N{alloc_ready_o}};

    always_comb begin : allocation_count_decode
        alloc_count = alloc_ready_o ? request_count : '0;
    end

    // Allocation tags are dense, so a batch contains at most one destination
    // in each low-bit data bank. Capture one local write per bank for A1.
    always_comb begin : allocation_data_capture
        alloc_data_capture_valid = '0;
        alloc_data_capture_row   = '0;
        alloc_data_capture       = '0;

        for (int alloc_idx = 0; alloc_idx < N; alloc_idx++) begin
            data_bank_t alloc_bank;

            alloc_bank = data_bank_t'(
                alloc_rob_id[alloc_idx][DATA_BANK_W-1:0]);
            if (alloc_fire[alloc_idx]) begin
                alloc_data_capture_valid[alloc_bank] = 1'b1;
                alloc_data_capture_row[alloc_bank] =
                    data_row_t'(alloc_rob_id[alloc_idx]
                                [ROB_ID_W-1:DATA_BANK_W]);
                alloc_data_capture[alloc_bank] = alloc_packet_i[alloc_idx];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Writeback qualification and completion-bypass event generation
    //--------------------------------------------------------------------------

    always_comb begin : writeback_qualification
        wb_commit          = '0;
        wb_rob_id          = '0;
        wb_entry_commit    = '0;
        data_entry_write_en   = '0;
        data_entry_write_data = '0;

        for (int wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
            wb_rob_id[wb_idx] = rob_id_t'(
                wb_seq_tag_i[wb_idx][ROB_ID_W-1:0]);

            for (int entry_idx = 0;
                 entry_idx < ROB_DEPTH;
                 entry_idx++) begin
                if (wb_valid_i[wb_idx]
                    && (wb_rob_id[wb_idx] == rob_id_t'(entry_idx))
                    && rob_valid_q[entry_idx]
                    && (rob_tag_hi_q[entry_idx]
                        == wb_seq_tag_i[wb_idx][SEQ_W-1:ROB_ID_W])
                    && !rob_result_valid_q[entry_idx]) begin
                    wb_entry_commit[entry_idx][wb_idx] = 1'b1;
                    wb_commit[wb_idx] = 1'b1;
                end
            end
        end

        for (int entry_idx = 0;
             entry_idx < ROB_DEPTH;
             entry_idx++) begin
            for (int wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
                if (wb_entry_commit[entry_idx][wb_idx]) begin
                    data_entry_write_en[entry_idx] = 1'b1;
                    data_entry_write_data[entry_idx] = wb_data_i[wb_idx];
                end
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
        retire_rob_id  = '0;
        retire_seq_tag = '0;
        retire_count   = '0;
        prefix_done    = 1'b1;
        scan_rob_id    = '0;

        for (int retire_idx = 0; retire_idx < N; retire_idx++) begin
            scan_rob_id = rob_ptr_add(head_ptr_q, lane_count_t'(retire_idx));

            if (prefix_done
                && rob_valid_q[scan_rob_id]
                && rob_result_valid_q[scan_rob_id]) begin
                retire_valid_o[retire_idx] = 1'b1;
                retire_rob_id[retire_idx]  = scan_rob_id;
                retire_seq_tag[retire_idx] = {
                    rob_tag_hi_q[scan_rob_id],
                    scan_rob_id
                };
                retire_count = retire_count + lane_count_t'(1);
            end else begin
                prefix_done = 1'b0;
            end
        end
    end

    always_comb begin : retirement_data_read
        data_row_t bank_row;

        retire_bank_data       = '0;
        retire_rotate_one_data = '0;
        retire_data_o          = '0;
        bank_row               = '0;

        // Four consecutive ROB IDs touch each low-two-bit bank exactly once.
        for (int bank_idx = 0;
             bank_idx < DATA_BANK_NUM;
             bank_idx++) begin
            bank_row = data_row_t'(head_ptr_q[ROB_ID_W-1:DATA_BANK_W]);
            if (data_bank_t'(bank_idx)
                < head_ptr_q[DATA_BANK_W-1:0]) begin
                bank_row = bank_row + data_row_t'(1);
            end
            retire_bank_data[bank_idx] = rob_data_q[bank_idx][bank_row];
        end

        // Rotate bank order into logical retirement order head, head+1, ... .
        retire_rotate_one_data = retire_bank_data;
        if (head_ptr_q[0]) begin
            retire_rotate_one_data = {
                retire_bank_data[0], retire_bank_data[3:1]
            };
        end

        retire_data_o = retire_rotate_one_data;
        if (head_ptr_q[1]) begin
            retire_data_o = {
                retire_rotate_one_data[1:0], retire_rotate_one_data[3:2]
            };
        end
    end

    // Convert retirement history updates to local bank enables.
    always_comb begin : history_write_decode
        history_write_en      = '0;
        history_write_seq_tag = '0;
        history_write_data    = '0;

        for (int history_idx = 0;
             history_idx < RESULT_BANKS;
             history_idx++) begin
            for (int retire_idx = 0; retire_idx < N; retire_idx++) begin
                if (retire_valid_o[retire_idx]
                    && (retire_seq_tag[retire_idx][HISTORY_ID_W-1:0]
                        == HISTORY_ID_W'(history_idx))) begin
                    history_write_en[history_idx] = 1'b1;
                    history_write_seq_tag[history_idx] =
                        retire_seq_tag[retire_idx];
                    history_write_data[history_idx] =
                        retire_data_o[retire_idx];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Registered-head allocation capacity
    //--------------------------------------------------------------------------

    always_comb begin : allocation_capacity
        free_count = OCCUPANCY_W'(ROB_DEPTH) - occupancy_q;

        // Do not borrow slots from the current retirement prefix. Released
        // credits become visible through occupancy_q in the following cycle,
        // removing retirement scan logic from the allocation write path.
        alloc_ready_o = (request_count != '0)
                        && (free_count >= OCCUPANCY_W'(request_count));

    end

    //--------------------------------------------------------------------------
    // D3 original-packet read
    //--------------------------------------------------------------------------

    always_comb begin : issue_source_read
        source_bank_req_valid  = '0;
        source_bank_req_row    = '0;
        source_bank_req_tag_hi = '0;
        source_bank_data_valid = '0;
        source_bank_data       = '0;
        issue_read_data_valid_o = '0;
        issue_read_data_o       = '0;

        // D2A emits at most one request from each low-two-bit issue bank.
        // Select one row per data bank, then share that 8:1 read before
        // routing the result back to the FE-indexed response.
        for (int bank_idx = 0;
             bank_idx < DATA_BANK_NUM;
             bank_idx++) begin
            for (int read_idx = 0;
                 read_idx < ISSUE_WIDTH;
                 read_idx++) begin
                if (issue_read_valid_i[read_idx]
                    && (issue_read_seq_tag_i[read_idx]
                        [DATA_BANK_W-1:0] == data_bank_t'(bank_idx))) begin
                    source_bank_req_valid[bank_idx] = 1'b1;
                    source_bank_req_row[bank_idx] =
                        issue_read_seq_tag_i[read_idx]
                        [ROB_ID_W-1:DATA_BANK_W];
                    source_bank_req_tag_hi[bank_idx] =
                        issue_read_seq_tag_i[read_idx]
                        [SEQ_W-1:ROB_ID_W];
                end
            end
        end

        for (int bank_idx = 0;
             bank_idx < DATA_BANK_NUM;
             bank_idx++) begin
            rob_id_t source_rob_id;

            source_rob_id = '0;
            source_rob_id[DATA_BANK_W-1:0] = data_bank_t'(bank_idx);
            source_rob_id[ROB_ID_W-1:DATA_BANK_W] =
                source_bank_req_row[bank_idx];

            if (source_bank_req_valid[bank_idx]
                && rob_valid_q[source_rob_id]
                && (rob_tag_hi_q[source_rob_id]
                    == source_bank_req_tag_hi[bank_idx])
                && !rob_result_valid_q[source_rob_id]) begin
                source_bank_data_valid[bank_idx] = 1'b1;
                source_bank_data[bank_idx] =
                    rob_data_q[bank_idx][source_bank_req_row[bank_idx]];
            end
        end

        for (int read_idx = 0;
             read_idx < ISSUE_WIDTH;
             read_idx++) begin
            data_bank_t source_bank;

            source_bank = data_bank_t'(
                issue_read_seq_tag_i[read_idx][DATA_BANK_W-1:0]);
            if (issue_read_valid_i[read_idx]) begin
                issue_read_data_valid_o[read_idx] =
                    source_bank_data_valid[source_bank];
                if (source_bank_data_valid[source_bank]) begin
                    issue_read_data_o[read_idx] =
                        source_bank_data[source_bank];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Shared per-query active-ROB and history lookup metadata
    //--------------------------------------------------------------------------

    always_comb begin : dependency_lookup_decode
        dep_status_active_match       = '0;
        dep_status_active_available   = '0;
        dep_status_history_match      = '0;
        dep_gather_active_match       = '0;
        dep_gather_active_available   = '0;
        dep_gather_history_match      = '0;
        dep_gather_active_data        = '0;
        dep_gather_history_data       = '0;

        for (int query_idx = 0; query_idx < N; query_idx++) begin
            rob_id_t                 target_rob_id;
            logic [HISTORY_ID_W-1:0] history_id;

            target_rob_id = rob_id_t'(
                dep_status_target_seq_tag_i[query_idx][ROB_ID_W-1:0]);
            history_id = dep_status_target_seq_tag_i[query_idx]
                         [HISTORY_ID_W-1:0];

            if (dep_status_valid_i[query_idx]) begin
                if (rob_valid_q[target_rob_id]
                    && (rob_tag_hi_q[target_rob_id]
                        == dep_status_target_seq_tag_i[query_idx]
                           [SEQ_W-1:ROB_ID_W])) begin
                    dep_status_active_match[query_idx] = 1'b1;
                    dep_status_active_available[query_idx] =
                        rob_result_valid_q[target_rob_id];
                end

                if (history_valid_q[history_id]
                    && (history_tag_hi_q[history_id]
                        == dep_status_target_seq_tag_i[query_idx]
                           [SEQ_W-1:HISTORY_ID_W])) begin
                    dep_status_history_match[query_idx] = 1'b1;
                end
            end
        end

        for (int query_idx = 0;
             query_idx < ISSUE_WIDTH;
             query_idx++) begin
            rob_id_t                 target_rob_id;
            logic [HISTORY_ID_W-1:0] history_id;

            target_rob_id = rob_id_t'(
                dep_gather_target_seq_tag_i[query_idx][ROB_ID_W-1:0]);
            history_id = dep_gather_target_seq_tag_i[query_idx]
                         [HISTORY_ID_W-1:0];

            if (dep_gather_valid_i[query_idx]) begin
                if (rob_valid_q[target_rob_id]
                    && (rob_tag_hi_q[target_rob_id]
                        == dep_gather_target_seq_tag_i[query_idx]
                           [SEQ_W-1:ROB_ID_W])) begin
                    dep_gather_active_match[query_idx] = 1'b1;
                    dep_gather_active_available[query_idx] =
                        rob_result_valid_q[target_rob_id];
                    if (rob_result_valid_q[target_rob_id]) begin
                        dep_gather_active_data[query_idx] =
                            rob_data_read(target_rob_id);
                    end
                end

                if (history_valid_q[history_id]
                    && (history_tag_hi_q[history_id]
                        == dep_gather_target_seq_tag_i[query_idx]
                           [SEQ_W-1:HISTORY_ID_W])) begin
                    dep_gather_history_match[query_idx] = 1'b1;
                    dep_gather_history_data[query_idx] =
                        history_data_q[history_id];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // D0 dependency-status resolution
    //--------------------------------------------------------------------------

    always_comb begin : dependency_status_resolve
        dep_status_available_o = '0;

        for (int query_idx = 0; query_idx < N; query_idx++) begin
            logic    source_resolved;
            rob_id_t target_rob_id;

            source_resolved = 1'b0;
            target_rob_id = rob_id_t'(
                dep_status_target_seq_tag_i[query_idx][ROB_ID_W-1:0]);

            if (dep_status_valid_i[query_idx]) begin
                // 1) Completion bypass.
                for (int wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
                    if (!source_resolved
                        && wb_commit[wb_idx]
                        && (wb_rob_id[wb_idx] == target_rob_id)
                        && (wb_seq_tag_i[wb_idx]
                            == dep_status_target_seq_tag_i[query_idx])) begin
                        source_resolved = 1'b1;
                        dep_status_available_o[query_idx] = 1'b1;
                    end
                end

                // 2) Active ROB. A retirement-prefix entry is still active
                // before the sampling edge, so this path also implements the
                // retirement-bypass value without a duplicate head compare.
                if (!source_resolved
                    && dep_status_active_match[query_idx]) begin
                    source_resolved = 1'b1;
                    dep_status_available_o[query_idx] =
                        dep_status_active_available[query_idx];
                end

                // 3) Retired history.
                if (!source_resolved
                    && dep_status_history_match[query_idx]) begin
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

        for (int query_idx = 0;
             query_idx < ISSUE_WIDTH;
             query_idx++) begin
            logic    source_resolved;
            rob_id_t target_rob_id;

            source_resolved = 1'b0;
            target_rob_id = rob_id_t'(
                dep_gather_target_seq_tag_i[query_idx][ROB_ID_W-1:0]);

            if (dep_gather_valid_i[query_idx]) begin
                // 1) Completion bypass.
                for (int wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
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

                // 2) Active ROB, including the authoritative pending case and
                // the pre-edge value of an entry retiring on this edge.
                if (!source_resolved
                    && dep_gather_active_match[query_idx]) begin
                    source_resolved = 1'b1;
                    dep_gather_data_valid_o[query_idx] =
                        dep_gather_active_available[query_idx];
                    if (dep_gather_active_available[query_idx]) begin
                        dep_gather_data_o[query_idx] =
                            dep_gather_active_data[query_idx];
                    end
                end

                // 3) Retired history.
                if (!source_resolved
                    && dep_gather_history_match[query_idx]) begin
                    dep_gather_data_valid_o[query_idx] = 1'b1;
                    dep_gather_data_o[query_idx] =
                        dep_gather_history_data[query_idx];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Concurrent state update
    //--------------------------------------------------------------------------

    // Within one edge the effective metadata priority is writeback,
    // retirement, then allocation. Allocation therefore owns the final state
    // of a slot reused from the retirement prefix on that edge.
    always_ff @(posedge clk_i or negedge rst_ni) begin : rob_metadata_update
        if (!rst_ni) begin
            rob_valid_q        <= '0;
            rob_result_valid_q <= '0;
        end else begin
            for (int wb_idx = 0; wb_idx < FE_NUM; wb_idx++) begin
                if (wb_commit[wb_idx]) begin
                    rob_result_valid_q[wb_rob_id[wb_idx]] <= 1'b1;
                end
            end

            for (int retire_idx = 0; retire_idx < N; retire_idx++) begin
                if (retire_valid_o[retire_idx]) begin
                    rob_valid_q[retire_rob_id[retire_idx]] <= 1'b0;
                    rob_result_valid_q[retire_rob_id[retire_idx]] <= 1'b0;
                end
            end

            for (int alloc_idx = 0; alloc_idx < N; alloc_idx++) begin
                if (alloc_fire[alloc_idx]) begin
                    rob_valid_q[alloc_rob_id[alloc_idx]] <= 1'b1;
                    rob_tag_hi_q[alloc_rob_id[alloc_idx]] <=
                        alloc_seq_tag_i[alloc_idx][SEQ_W-1:ROB_ID_W];
                    rob_result_valid_q[alloc_rob_id[alloc_idx]] <= 1'b0;
                end
            end
        end
    end

    // A0 captures allocation payload by data bank. The A1 write is safely
    // complete before the earliest D3 source read for the new entry.
    always_ff @(posedge clk_i or negedge rst_ni) begin : alloc_data_control
        if (!rst_ni) begin
            alloc_data_valid_q <= '0;
        end else begin
            alloc_data_valid_q <= alloc_data_capture_valid;
            for (int bank_idx = 0;
                 bank_idx < DATA_BANK_NUM;
                 bank_idx++) begin
                if (alloc_data_capture_valid[bank_idx]) begin
                    alloc_data_row_q[bank_idx] <=
                        alloc_data_capture_row[bank_idx];
                end
            end
        end
    end

    always_ff @(posedge clk_i) begin : alloc_data_payload
        for (int bank_idx = 0;
             bank_idx < DATA_BANK_NUM;
             bank_idx++) begin
            if (alloc_data_capture_valid[bank_idx]) begin
                alloc_data_q[bank_idx] <= alloc_data_capture[bank_idx];
            end
        end
    end

    // Unified original/result data has bank-local allocation input and
    // entry-local completion write enable. Wide data is not reset.
    always_ff @(posedge clk_i) begin : rob_data_update
        for (int bank_idx = 0;
             bank_idx < DATA_BANK_NUM;
             bank_idx++) begin
            for (int row_idx = 0;
                 row_idx < DATA_ROW_NUM;
                 row_idx++) begin
                if (data_entry_write_en[
                        (row_idx * DATA_BANK_NUM) + bank_idx]) begin
                    rob_data_q[bank_idx][row_idx] <=
                        data_entry_write_data[
                            (row_idx * DATA_BANK_NUM) + bank_idx];
                end
                if (alloc_data_valid_q[bank_idx]
                    && (alloc_data_row_q[bank_idx]
                        == data_row_t'(row_idx))) begin
                    rob_data_q[bank_idx][row_idx] <=
                        alloc_data_q[bank_idx];
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : history_metadata_update
        if (!rst_ni) begin
            history_valid_q <= '0;
        end else begin
            for (int history_idx = 0;
                 history_idx < RESULT_BANKS;
                 history_idx++) begin
                if (history_write_en[history_idx]) begin
                    history_valid_q[history_idx] <= 1'b1;
                    history_tag_hi_q[history_idx] <=
                        history_write_seq_tag[history_idx]
                        [SEQ_W-1:HISTORY_ID_W];
                end
            end
        end
    end

    // History data is architecturally ignored while its valid bit is clear.
    always_ff @(posedge clk_i) begin : history_data_update
        for (int history_idx = 0;
             history_idx < RESULT_BANKS;
             history_idx++) begin
            if (history_write_en[history_idx]) begin
                history_data_q[history_idx] <= history_write_data[history_idx];
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : rob_control_update
        if (!rst_ni) begin
            head_ptr_q  <= '0;
            occupancy_q <= '0;
        end else begin
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
