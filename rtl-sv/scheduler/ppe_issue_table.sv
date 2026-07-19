`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_issue_table.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Scheduler / Issue Table
//
// Description :
//   Owns packets accepted by ingress until they are issued to an FE. Entries
//   are indexed directly by ROB ID and store one packet copy, sequence metadata,
//   delay, dependency state, and unified issue state. READY-queue membership is
//   maintained as separate bookkeeping rather than part of the entry payload.
//
//   This block also owns READY discovery and four delay-class ID FIFOs. It
//   exposes only registered FIFO head windows to the combinational candidate
//   selector; packet-width data is read later through the D3 issue bundle.
//
//   Dependency result data is never stored here. This block directly drives
//   ROB status/gather queries and compares FE completion tags for wakeup.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 4 through 7
//   - doc/hld.txt, Sections 3.2, 3.3, 4.1 through 4.3, and 5.1
//   - doc/lld.txt, Sections 3.1, 3.3, 3.6, 5.1 through 5.4, and 7 through 9
//
// Clock/reset :
//   State is clocked by clk_i. rst_ni is the shared active-low internal reset.
//   Reset clears entry state, queued bits, queue counts, and control pointers;
//   packet and metadata arrays need not be reset while their entry is FREE.
//
// Implementation status:
//   Entry state, dependency control, READY FIFOs, candidate windows,
//   irrevocable selection, D3 issue, and automatic release are implemented.
//------------------------------------------------------------------------------

module ppe_issue_table #(
    parameter int unsigned PACKET_W          = 128,
    parameter int unsigned DELAY_CLASS_NUM   = 4,
    parameter int unsigned CAND_WINDOW_DEPTH = 4
) (
    // Clock and reset
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    // D0 allocation bundle. Lane positions remain physical input-lane indices.
    // The physical issue-entry index is derived from the complete sequence tag.
    input  logic [ppe_types_pkg::N-1:0]                    alloc_valid_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_seq_tag_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_target_seq_tag_i,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]      alloc_packet_i,
    input  logic [ppe_types_pkg::N-1:0][1:0]               alloc_delay_i,
    input  logic [ppe_types_pkg::N-1:0]                    alloc_dep_required_i,

    // D0 status-only dependency query directly connected to ppe_rob.
    output logic [ppe_types_pkg::N-1:0]                    dep_status_valid_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_status_target_seq_tag_o,
    input  logic [ppe_types_pkg::N-1:0]                    dep_status_available_i,

    // Completion tags used to wake every matching ISSUE_WAIT_DEP entry. The
    // target ROB ID prefilter is derived from the complete tag locally.
    input  logic [ppe_types_pkg::FE_NUM-1:0]               completion_valid_i,
    input  logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                completion_seq_tag_i,

    // Registered delay-class FIFO head windows. Class index equals desc_delay;
    // window slot zero is the oldest queued READY entry in that class.
    output logic [DELAY_CLASS_NUM-1:0]
                 [CAND_WINDOW_DEPTH-1:0]                   candidate_valid_o,
    output logic [DELAY_CLASS_NUM-1:0]
                 [CAND_WINDOW_DEPTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                candidate_seq_tag_o,

    // Irrevocable D2 selections indexed by destination FE. ppe_fe_scheduler may
    // assert a selection only after dependency and return-slot legality checks;
    // the local entry index is derived from select_seq_tag_i low bits.
    input  logic [ppe_types_pkg::FE_NUM-1:0]               select_valid_i,
    input  logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                select_seq_tag_i,

    // D3 authoritative dependency-data gather directly connected to ppe_rob.
    output logic [ppe_types_pkg::FE_NUM-1:0]               dep_gather_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_gather_target_seq_tag_o,
    input  logic [ppe_types_pkg::FE_NUM-1:0]               dep_gather_data_valid_i,
    input  logic [ppe_types_pkg::FE_NUM-1:0][PACKET_W-1:0] dep_gather_data_i,

    // Registered-control D3 issue bundle indexed by FE. Selection is
    // irrevocable, so issue_valid does not depend on gather data_valid.
    output logic [ppe_types_pkg::FE_NUM-1:0]               issue_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0][PACKET_W-1:0] issue_packet_o,
    output logic [ppe_types_pkg::FE_NUM-1:0][1:0]          issue_delay_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]               issue_dep_required_o,
    output logic [ppe_types_pkg::FE_NUM-1:0][PACKET_W-1:0] issue_dep_data_o
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Local parameters and unified entry-state encoding
    //--------------------------------------------------------------------------

    typedef enum logic [1:0] {
        ISSUE_FREE,
        ISSUE_WAIT_DEP,
        ISSUE_READY,
        ISSUE_SELECTED
    } issue_state_e;

    typedef struct packed {
        issue_state_e        state;
        logic [SEQ_W-1:0]    seq_tag;
        logic [SEQ_W-1:0]    target_seq_tag;
        logic [1:0]          delay;
        logic                dep_required;
        logic                dep_satisfied;
        logic [PACKET_W-1:0] packet;
    } issue_entry_t;

    localparam int unsigned READY_ENQUEUE_WIDTH = 4;
    localparam int unsigned QUEUE_COUNT_W = $clog2(ISSUE_DEPTH + 1);
    localparam int unsigned PTR_SUM_W = ROB_ID_W + 1;

    typedef logic [ROB_ID_W-1:0] rob_id_t;

    function automatic rob_id_t issue_ptr_add(
        input rob_id_t base,
        input rob_id_t offset
    );
        logic [PTR_SUM_W-1:0] sum;
        begin
            sum = PTR_SUM_W'(base) + PTR_SUM_W'(offset);
            if (sum >= PTR_SUM_W'(ISSUE_DEPTH)) begin
                sum = sum - PTR_SUM_W'(ISSUE_DEPTH);
            end
            issue_ptr_add = rob_id_t'(sum);
        end
    endfunction


    //--------------------------------------------------------------------------
    // Issue-entry payload and metadata storage
    //--------------------------------------------------------------------------

    issue_entry_t issue_entry_q [ISSUE_DEPTH];
    logic [ISSUE_DEPTH-1:0] queued_q;

    logic [DELAY_CLASS_NUM-1:0][ISSUE_DEPTH-1:0]
          [ROB_ID_W-1:0] ready_q_id_q;
    logic [DELAY_CLASS_NUM-1:0][ISSUE_DEPTH-1:0]
          [ROB_ID_W-1:0] ready_q_id_d;
    logic [DELAY_CLASS_NUM-1:0][QUEUE_COUNT_W-1:0]
          ready_q_count_q;
    logic [DELAY_CLASS_NUM-1:0][QUEUE_COUNT_W-1:0]
          ready_q_count_d;

    rob_id_t enqueue_rr_ptr_q;
    rob_id_t enqueue_rr_ptr_d;

    logic [FE_NUM-1:0]            selected_valid_q;
    logic [FE_NUM-1:0][SEQ_W-1:0] selected_seq_tag_q;

    //--------------------------------------------------------------------------
    // D0 status-query generation and completion wakeup detection
    //--------------------------------------------------------------------------

    logic [ISSUE_DEPTH-1:0] wake_hit;

    always_comb begin
        dep_status_valid_o          = '0;
        dep_status_target_seq_tag_o = '0;

        for (int unsigned lane_idx = 0; lane_idx < N; lane_idx++) begin
            if (alloc_valid_i[lane_idx]
                && alloc_dep_required_i[lane_idx]) begin
                dep_status_valid_o[lane_idx] = 1'b1;
                dep_status_target_seq_tag_o[lane_idx] =
                    alloc_target_seq_tag_i[lane_idx];
            end
        end
    end

    always_comb begin
        wake_hit = '0;

        for (int unsigned entry_idx = 0;
             entry_idx < ISSUE_DEPTH;
             entry_idx++) begin
            if (issue_entry_q[entry_idx].state == ISSUE_WAIT_DEP) begin
                for (int unsigned comp_idx = 0;
                     comp_idx < FE_NUM;
                     comp_idx++) begin
                    if (completion_valid_i[comp_idx]
                        && (issue_entry_q[entry_idx].target_seq_tag
                            [ROB_ID_W-1:0]
                            == completion_seq_tag_i[comp_idx]
                               [ROB_ID_W-1:0])
                        && (issue_entry_q[entry_idx].target_seq_tag
                            == completion_seq_tag_i[comp_idx])) begin
                        wake_hit[entry_idx] = 1'b1;
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // READY discovery, queued tracking, and delay-class FIFO state
    //--------------------------------------------------------------------------

    logic [ISSUE_DEPTH-1:0] alloc_hit;
    logic [ISSUE_DEPTH-1:0] alloc_ready;
    logic [ISSUE_DEPTH-1:0][1:0] alloc_delay_by_id;

    logic [ISSUE_DEPTH-1:0] existing_ready_unqueued;
    logic [ISSUE_DEPTH-1:0] new_alloc_ready;

    logic [READY_ENQUEUE_WIDTH-1:0]               enqueue_valid;
    logic [READY_ENQUEUE_WIDTH-1:0][ROB_ID_W-1:0] enqueue_rob_id;
    logic [READY_ENQUEUE_WIDTH-1:0][1:0]          enqueue_delay;
    logic [ISSUE_DEPTH-1:0]                       enqueue_hit;

    always_comb begin
        alloc_hit         = '0;
        alloc_ready       = '0;
        alloc_delay_by_id = '0;

        for (int unsigned lane_idx = 0; lane_idx < N; lane_idx++) begin
            rob_id_t alloc_rob_id;

            alloc_rob_id = rob_id_t'(
                alloc_seq_tag_i[lane_idx][ROB_ID_W-1:0]);
            if (alloc_valid_i[lane_idx]) begin
                alloc_hit[alloc_rob_id] = 1'b1;
                alloc_delay_by_id[alloc_rob_id] =
                    alloc_delay_i[lane_idx];
                alloc_ready[alloc_rob_id] =
                    !alloc_dep_required_i[lane_idx]
                    || dep_status_available_i[lane_idx];
            end
        end
    end

    always_comb begin
        existing_ready_unqueued = '0;
        new_alloc_ready         = '0;

        for (int unsigned entry_idx = 0;
             entry_idx < ISSUE_DEPTH;
             entry_idx++) begin
            // Allocation replaces the old identity at the same physical ID,
            // so the old entry must not be discovered on this edge.
            if (!alloc_hit[entry_idx]) begin
                existing_ready_unqueued[entry_idx] =
                    ((issue_entry_q[entry_idx].state == ISSUE_READY)
                     && !queued_q[entry_idx])
                    || wake_hit[entry_idx];
            end

            new_alloc_ready[entry_idx] =
                alloc_hit[entry_idx] && alloc_ready[entry_idx];
        end
    end

    // Existing READY entries and same-edge wakeups have priority over new D0
    // allocations. Both passes scan from the same rotating fairness pointer.
    always_comb begin : ready_discovery
        integer selected_count;
        rob_id_t scan_rob_id;
        rob_id_t last_rob_id;

        enqueue_valid    = '0;
        enqueue_rob_id   = '0;
        enqueue_delay    = '0;
        enqueue_rr_ptr_d = enqueue_rr_ptr_q;
        selected_count   = 0;
        scan_rob_id      = '0;
        last_rob_id      = enqueue_rr_ptr_q;

        for (int unsigned scan_offset = 0;
             scan_offset < ISSUE_DEPTH;
             scan_offset++) begin
            scan_rob_id = issue_ptr_add(
                enqueue_rr_ptr_q, rob_id_t'(scan_offset));
            if ((selected_count < READY_ENQUEUE_WIDTH)
                && existing_ready_unqueued[scan_rob_id]) begin
                enqueue_valid[selected_count]  = 1'b1;
                enqueue_rob_id[selected_count] = scan_rob_id;
                enqueue_delay[selected_count]  =
                    issue_entry_q[scan_rob_id].delay;
                last_rob_id = scan_rob_id;
                selected_count = selected_count + 1;
            end
        end

        for (int unsigned scan_offset = 0;
             scan_offset < ISSUE_DEPTH;
             scan_offset++) begin
            scan_rob_id = issue_ptr_add(
                enqueue_rr_ptr_q, rob_id_t'(scan_offset));
            if ((selected_count < READY_ENQUEUE_WIDTH)
                && new_alloc_ready[scan_rob_id]) begin
                enqueue_valid[selected_count]  = 1'b1;
                enqueue_rob_id[selected_count] = scan_rob_id;
                enqueue_delay[selected_count]  =
                    alloc_delay_by_id[scan_rob_id];
                last_rob_id = scan_rob_id;
                selected_count = selected_count + 1;
            end
        end

        if (selected_count != 0) begin
            enqueue_rr_ptr_d = issue_ptr_add(last_rob_id, rob_id_t'(1));
        end
    end

    always_comb begin
        enqueue_hit = '0;
        for (int unsigned enqueue_idx = 0;
             enqueue_idx < READY_ENQUEUE_WIDTH;
             enqueue_idx++) begin
            if (enqueue_valid[enqueue_idx]) begin
                enqueue_hit[enqueue_rob_id[enqueue_idx]] = 1'b1;
            end
        end
    end

    //--------------------------------------------------------------------------
    // READY-only candidate windows and irrevocable D2 selection
    //--------------------------------------------------------------------------

    logic queue_update;

    always_comb begin : ready_queue_update
        integer selected_in_class;
        integer remaining_count;
        integer append_position;
        integer source_position;

        ready_q_id_d    = '0;
        ready_q_count_d = '0;
        queue_update    = (|select_valid_i) || (|enqueue_valid);

        for (int unsigned class_idx = 0;
             class_idx < DELAY_CLASS_NUM;
             class_idx++) begin
            selected_in_class = 0;

            for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                rob_id_t select_rob_id;

                select_rob_id = rob_id_t'(
                    select_seq_tag_i[fe_idx][ROB_ID_W-1:0]);
                if (select_valid_i[fe_idx]
                    && (issue_entry_q[select_rob_id].delay
                        == 2'(class_idx))) begin
                    selected_in_class = selected_in_class + 1;
                end
            end

            remaining_count = integer'(ready_q_count_q[class_idx])
                              - selected_in_class;

            for (int unsigned queue_pos = 0;
                 queue_pos < ISSUE_DEPTH;
                 queue_pos++) begin
                source_position = queue_pos + selected_in_class;
                if ((queue_pos < remaining_count)
                    && (source_position < ISSUE_DEPTH)) begin
                    ready_q_id_d[class_idx][queue_pos] =
                        ready_q_id_q[class_idx][source_position];
                end
            end

            append_position = remaining_count;
            for (int unsigned enqueue_idx = 0;
                 enqueue_idx < READY_ENQUEUE_WIDTH;
                 enqueue_idx++) begin
                if (enqueue_valid[enqueue_idx]
                    && (enqueue_delay[enqueue_idx] == 2'(class_idx))
                    && (append_position < ISSUE_DEPTH)) begin
                    ready_q_id_d[class_idx][append_position] =
                        enqueue_rob_id[enqueue_idx];
                    append_position = append_position + 1;
                end
            end

            ready_q_count_d[class_idx] = QUEUE_COUNT_W'(append_position);
        end
    end

    always_comb begin
        candidate_valid_o   = '0;
        candidate_seq_tag_o = '0;

        for (int unsigned class_idx = 0;
             class_idx < DELAY_CLASS_NUM;
             class_idx++) begin
            for (int unsigned window_idx = 0;
                 window_idx < CAND_WINDOW_DEPTH;
                 window_idx++) begin
                if ((QUEUE_COUNT_W'(window_idx)
                     < ready_q_count_q[class_idx])
                    && (issue_entry_q[
                        ready_q_id_q[class_idx][window_idx]].state
                        == ISSUE_READY)
                    && queued_q[ready_q_id_q[class_idx][window_idx]]) begin
                    candidate_valid_o[class_idx][window_idx] = 1'b1;
                    candidate_seq_tag_o[class_idx][window_idx] =
                        issue_entry_q[
                            ready_q_id_q[class_idx][window_idx]].seq_tag;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Per-FE selected-tag pipeline, D3 issue bundle, and automatic release
    //--------------------------------------------------------------------------

    always_comb begin
        dep_gather_valid_o          = '0;
        dep_gather_target_seq_tag_o = '0;
        issue_valid_o               = selected_valid_q;
        issue_packet_o              = '0;
        issue_delay_o               = '0;
        issue_dep_required_o        = '0;
        issue_dep_data_o            = '0;

        for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
            rob_id_t selected_rob_id;

            selected_rob_id = rob_id_t'(
                selected_seq_tag_q[fe_idx][ROB_ID_W-1:0]);
            if (selected_valid_q[fe_idx]) begin
                issue_packet_o[fe_idx] =
                    issue_entry_q[selected_rob_id].packet;
                issue_delay_o[fe_idx] =
                    issue_entry_q[selected_rob_id].delay;
                issue_dep_required_o[fe_idx] =
                    issue_entry_q[selected_rob_id].dep_required;

                if (issue_entry_q[selected_rob_id].dep_required) begin
                    dep_gather_valid_o[fe_idx] = 1'b1;
                    dep_gather_target_seq_tag_o[fe_idx] =
                        issue_entry_q[selected_rob_id].target_seq_tag;

                    // data_valid is a legal-operation invariant, not a release
                    // or rollback condition for an irrevocable selection.
                    if (dep_gather_data_valid_i[fe_idx]) begin
                        issue_dep_data_o[fe_idx] =
                            dep_gather_data_i[fe_idx];
                    end
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Concurrent next-state merge and sequential state update
    //--------------------------------------------------------------------------

    // Effective entry priority is D3 release, completion wakeup, D2 select,
    // queue-membership update, then D0 allocation. Allocation therefore owns
    // the final identity and state of a same-edge reused physical entry.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            queued_q         <= '0;
            ready_q_count_q  <= '0;
            enqueue_rr_ptr_q <= '0;
            selected_valid_q <= '0;

            for (int unsigned entry_idx = 0;
                 entry_idx < ISSUE_DEPTH;
                 entry_idx++) begin
                issue_entry_q[entry_idx].state <= ISSUE_FREE;
            end
        end else begin
            // The prior cycle's irrevocable selections enter their FEs now.
            for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                rob_id_t selected_rob_id;

                selected_rob_id = rob_id_t'(
                    selected_seq_tag_q[fe_idx][ROB_ID_W-1:0]);
                if (selected_valid_q[fe_idx]) begin
                    issue_entry_q[selected_rob_id].state <= ISSUE_FREE;
                    queued_q[selected_rob_id] <= 1'b0;
                end
            end

            // Completion wakeup changes only small dependency/control fields.
            for (int unsigned entry_idx = 0;
                 entry_idx < ISSUE_DEPTH;
                 entry_idx++) begin
                if (wake_hit[entry_idx]) begin
                    issue_entry_q[entry_idx].state <= ISSUE_READY;
                    issue_entry_q[entry_idx].dep_satisfied <= 1'b1;
                end
            end

            // FE-scheduler selections are final and remove READY IDs from queues.
            for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                rob_id_t select_rob_id;

                select_rob_id = rob_id_t'(
                    select_seq_tag_i[fe_idx][ROB_ID_W-1:0]);
                if (select_valid_i[fe_idx]) begin
                    issue_entry_q[select_rob_id].state <= ISSUE_SELECTED;
                    queued_q[select_rob_id] <= 1'b0;
                end
            end

            for (int unsigned enqueue_idx = 0;
                 enqueue_idx < READY_ENQUEUE_WIDTH;
                 enqueue_idx++) begin
                if (enqueue_valid[enqueue_idx]) begin
                    queued_q[enqueue_rob_id[enqueue_idx]] <= 1'b1;
                end
            end

            // D0 allocation is the final writer for a reused issue entry.
            for (int unsigned lane_idx = 0; lane_idx < N; lane_idx++) begin
                rob_id_t alloc_rob_id;

                alloc_rob_id = rob_id_t'(
                    alloc_seq_tag_i[lane_idx][ROB_ID_W-1:0]);
                if (alloc_valid_i[lane_idx]) begin
                    if (!alloc_dep_required_i[lane_idx]
                        || dep_status_available_i[lane_idx]) begin
                        issue_entry_q[alloc_rob_id].state <= ISSUE_READY;
                    end else begin
                        issue_entry_q[alloc_rob_id].state <= ISSUE_WAIT_DEP;
                    end

                    issue_entry_q[alloc_rob_id].seq_tag <=
                        alloc_seq_tag_i[lane_idx];
                    issue_entry_q[alloc_rob_id].target_seq_tag <=
                        alloc_target_seq_tag_i[lane_idx];
                    issue_entry_q[alloc_rob_id].delay <=
                        alloc_delay_i[lane_idx];
                    issue_entry_q[alloc_rob_id].dep_required <=
                        alloc_dep_required_i[lane_idx];
                    issue_entry_q[alloc_rob_id].dep_satisfied <=
                        !alloc_dep_required_i[lane_idx]
                        || dep_status_available_i[lane_idx];
                    issue_entry_q[alloc_rob_id].packet <=
                        alloc_packet_i[lane_idx];
                    queued_q[alloc_rob_id] <= enqueue_hit[alloc_rob_id];
                end
            end

            // Per-FE selected-tag registers are consumed and refilled every
            // cycle, allowing one new selection per FE without bubbles.
            selected_valid_q <= select_valid_i;
            for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                if (select_valid_i[fe_idx]) begin
                    selected_seq_tag_q[fe_idx] <= select_seq_tag_i[fe_idx];
                end
            end

            if (queue_update) begin
                ready_q_id_q    <= ready_q_id_d;
                ready_q_count_q <= ready_q_count_d;
            end

            if (|enqueue_valid) begin
                enqueue_rr_ptr_q <= enqueue_rr_ptr_d;
            end
        end
    end

endmodule : ppe_issue_table

`default_nettype wire
