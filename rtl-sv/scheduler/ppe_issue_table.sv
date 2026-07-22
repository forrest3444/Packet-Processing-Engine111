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
//   This block also owns READY discovery and four delay-class tag FIFOs. It
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
    parameter int PACKET_W = ppe_types_pkg::DEFAULT_PACKET_W
) (
    // Clock and reset
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    // Accepted D0 allocation event. The ROB has already accepted every valid
    // lane; the physical issue index is derived from the complete sequence tag.
    input  logic [ppe_types_pkg::N-1:0]                    issue_alloc_valid_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_seq_tag_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_target_seq_tag_i,
    input  logic [ppe_types_pkg::N-1:0][PACKET_W-1:0]      alloc_packet_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::DELAY_W-1:0]              alloc_delay_i,
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
    output logic [ppe_types_pkg::DELAY_CLASS_NUM-1:0]
                 [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]    candidate_valid_o,
    output logic [ppe_types_pkg::DELAY_CLASS_NUM-1:0]
                 [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
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
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::DELAY_W-1:0]              issue_delay_o,
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

    localparam int QUEUE_COUNT_W = $clog2(ISSUE_DEPTH + 1);
    localparam int ENQUEUE_COUNT_W = $clog2(READY_ENQUEUE_WIDTH + 1);
    localparam int PREFIX_STAGE_NUM = $clog2(ISSUE_DEPTH);
    localparam int ROTATE_INDEX_W = $clog2(2 * ISSUE_DEPTH);

    function automatic logic [ENQUEUE_COUNT_W-1:0] saturated_count_add(
        input logic [ENQUEUE_COUNT_W-1:0] lhs,
        input logic [ENQUEUE_COUNT_W-1:0] rhs
    );
        logic [ENQUEUE_COUNT_W:0] sum;
        begin
            sum = {1'b0, lhs} + {1'b0, rhs};
            if (sum[ENQUEUE_COUNT_W]
                || (sum[ENQUEUE_COUNT_W-1:0]
                    > ENQUEUE_COUNT_W'(READY_ENQUEUE_WIDTH))) begin
                saturated_count_add =
                    ENQUEUE_COUNT_W'(READY_ENQUEUE_WIDTH);
            end else begin
                saturated_count_add = ENQUEUE_COUNT_W'(sum);
            end
        end
    endfunction


    //--------------------------------------------------------------------------
    // Issue-entry payload and metadata storage
    //--------------------------------------------------------------------------

    issue_state_e issue_state_q [ISSUE_DEPTH];
    logic [ISSUE_DEPTH-1:0][SEQ_W-1:0]    issue_seq_tag_q;
    logic [ISSUE_DEPTH-1:0][SEQ_W-1:0]    issue_target_seq_tag_q;
    logic [ISSUE_DEPTH-1:0][DELAY_W-1:0]  issue_delay_q;
    logic [ISSUE_DEPTH-1:0]               issue_dep_required_q;
    logic [ISSUE_DEPTH-1:0][PACKET_W-1:0] issue_packet_q;
    logic [ISSUE_DEPTH-1:0]               queued_q;

    logic [ISSUE_DEPTH-1:0]               packet_write_en;
    logic [ISSUE_DEPTH-1:0][PACKET_W-1:0] packet_write_data;

    logic [DELAY_CLASS_NUM-1:0][ISSUE_DEPTH-1:0]
          [SEQ_W-1:0] ready_q_seq_tag_q;
    logic [DELAY_CLASS_NUM-1:0][ROB_ID_W-1:0] ready_q_head_q;
    logic [DELAY_CLASS_NUM-1:0][ROB_ID_W-1:0] ready_q_tail_q;
    logic [DELAY_CLASS_NUM-1:0][QUEUE_COUNT_W-1:0]
          ready_q_count_q;

    logic [DELAY_CLASS_NUM-1:0][ENQUEUE_COUNT_W-1:0]
          ready_pop_count;
    logic [DELAY_CLASS_NUM-1:0][ENQUEUE_COUNT_W-1:0]
          ready_push_count;
    logic [DELAY_CLASS_NUM-1:0][ISSUE_DEPTH-1:0]
          ready_write_en;
    logic [DELAY_CLASS_NUM-1:0][ISSUE_DEPTH-1:0][SEQ_W-1:0]
          ready_write_seq_tag;
    logic [READY_ENQUEUE_WIDTH-1:0][ENQUEUE_COUNT_W-1:0]
          enqueue_rank_in_class;
    logic [READY_ENQUEUE_WIDTH-1:0][ROB_ID_W-1:0]
          enqueue_write_position;

    rob_id_t enqueue_rr_ptr_q;
    rob_id_t enqueue_rr_ptr_d;

    logic [FE_NUM-1:0]            selected_valid_q;
    logic [FE_NUM-1:0][SEQ_W-1:0] selected_seq_tag_q;

    //--------------------------------------------------------------------------
    // D0 status-query generation and completion wakeup detection
    //--------------------------------------------------------------------------

    logic [ISSUE_DEPTH-1:0] wake_hit;

    always_comb begin : dependency_status_request
        dep_status_valid_o          = '0;
        dep_status_target_seq_tag_o = '0;

        for (int lane_idx = 0; lane_idx < N; lane_idx++) begin
            if (issue_alloc_valid_i[lane_idx]
                && alloc_dep_required_i[lane_idx]) begin
                dep_status_valid_o[lane_idx] = 1'b1;
                dep_status_target_seq_tag_o[lane_idx] =
                    alloc_target_seq_tag_i[lane_idx];
            end
        end
    end

    always_comb begin : completion_wakeup_detect
        wake_hit = '0;

        for (int entry_idx = 0;
             entry_idx < ISSUE_DEPTH;
             entry_idx++) begin
            if (issue_state_q[entry_idx] == ISSUE_WAIT_DEP) begin
                for (int comp_idx = 0;
                     comp_idx < FE_NUM;
                     comp_idx++) begin
                    if (completion_valid_i[comp_idx]
                        && (issue_target_seq_tag_q[entry_idx]
                            [ROB_ID_W-1:0]
                            == completion_seq_tag_i[comp_idx]
                               [ROB_ID_W-1:0])
                        && (issue_target_seq_tag_q[entry_idx]
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
    logic [ISSUE_DEPTH-1:0] alloc_entry_ready;
    logic [ISSUE_DEPTH-1:0][SEQ_W-1:0] alloc_seq_tag_by_id;
    logic [ISSUE_DEPTH-1:0][DELAY_W-1:0] alloc_delay_by_id;

    logic [ISSUE_DEPTH-1:0] existing_ready_unqueued;
    logic [ISSUE_DEPTH-1:0] new_ready_allocation;

    logic [READY_ENQUEUE_WIDTH-1:0]               enqueue_valid;
    logic [READY_ENQUEUE_WIDTH-1:0][ROB_ID_W-1:0] enqueue_rob_id;
    logic [READY_ENQUEUE_WIDTH-1:0][SEQ_W-1:0]    enqueue_seq_tag;
    logic [READY_ENQUEUE_WIDTH-1:0][DELAY_W-1:0]  enqueue_delay;
    logic [ISSUE_DEPTH-1:0]                       enqueue_hit;

    logic [ISSUE_DEPTH-1:0] rotated_existing_ready;
    logic [ISSUE_DEPTH-1:0] rotated_new_ready;
    logic [(2*ISSUE_DEPTH)-1:0] doubled_existing_ready;
    logic [(2*ISSUE_DEPTH)-1:0] doubled_new_ready;
    logic [ROTATE_INDEX_W-1:0] rotation_base;

    logic [PREFIX_STAGE_NUM:0][ISSUE_DEPTH-1:0]
          [ENQUEUE_COUNT_W-1:0] existing_prefix_count;
    logic [PREFIX_STAGE_NUM:0][ISSUE_DEPTH-1:0]
          [ENQUEUE_COUNT_W-1:0] new_prefix_count;
    logic [ISSUE_DEPTH-1:0][ENQUEUE_COUNT_W-1:0]
          existing_rank_before;
    logic [ISSUE_DEPTH-1:0][ENQUEUE_COUNT_W-1:0]
          new_rank_before;
    logic [ENQUEUE_COUNT_W-1:0] existing_selected_count;
    logic [ISSUE_DEPTH-1:0][ENQUEUE_COUNT_W-1:0]
          new_combined_rank;

    logic [READY_ENQUEUE_WIDTH-1:0][ISSUE_DEPTH-1:0]
          existing_select_onehot;
    logic [READY_ENQUEUE_WIDTH-1:0][ISSUE_DEPTH-1:0]
          new_select_onehot;
    logic [READY_ENQUEUE_WIDTH-1:0][ISSUE_DEPTH-1:0]
          enqueue_select_onehot;
    logic [READY_ENQUEUE_WIDTH-1:0] enqueue_from_allocation;
    logic [READY_ENQUEUE_WIDTH-1:0][ROB_ID_W-1:0]
          enqueue_rotated_offset;

    always_comb begin : allocation_ready_decode
        alloc_hit         = '0;
        alloc_entry_ready = '0;
        alloc_seq_tag_by_id = '0;
        alloc_delay_by_id = '0;
        packet_write_en   = '0;
        packet_write_data = '0;

        for (int lane_idx = 0; lane_idx < N; lane_idx++) begin
            rob_id_t alloc_rob_id;

            alloc_rob_id = rob_id_t'(
                alloc_seq_tag_i[lane_idx][ROB_ID_W-1:0]);
            if (issue_alloc_valid_i[lane_idx]) begin
                alloc_hit[alloc_rob_id] = 1'b1;
                alloc_seq_tag_by_id[alloc_rob_id] =
                    alloc_seq_tag_i[lane_idx];
                alloc_delay_by_id[alloc_rob_id] =
                    alloc_delay_i[lane_idx];
                alloc_entry_ready[alloc_rob_id] =
                    !alloc_dep_required_i[lane_idx]
                    || dep_status_available_i[lane_idx];
                packet_write_en[alloc_rob_id] = 1'b1;
                packet_write_data[alloc_rob_id] = alloc_packet_i[lane_idx];
            end
        end
    end

    always_comb begin : ready_source_detect
        existing_ready_unqueued = '0;
        new_ready_allocation    = '0;

        for (int entry_idx = 0;
             entry_idx < ISSUE_DEPTH;
             entry_idx++) begin
            // Allocation replaces the old identity at the same physical ID,
            // so the old entry must not be discovered on this edge.
            if (!alloc_hit[entry_idx]) begin
                existing_ready_unqueued[entry_idx] =
                    ((issue_state_q[entry_idx] == ISSUE_READY)
                     && !queued_q[entry_idx])
                    || wake_hit[entry_idx];
            end

            new_ready_allocation[entry_idx] =
                alloc_hit[entry_idx] && alloc_entry_ready[entry_idx];
        end
    end

    // Existing READY entries and same-edge wakeups have priority over new D0
    // allocations. Rotate both event maps once, then use fixed-depth saturated
    // prefix trees to assign ranks zero through three without a serial scan.
    always_comb begin : ready_event_rotation
        doubled_existing_ready = {
            existing_ready_unqueued, existing_ready_unqueued
        };
        doubled_new_ready = {
            new_ready_allocation, new_ready_allocation
        };
        rotation_base = ROTATE_INDEX_W'(enqueue_rr_ptr_q);
        rotated_existing_ready =
            doubled_existing_ready[rotation_base +: ISSUE_DEPTH];
        rotated_new_ready =
            doubled_new_ready[rotation_base +: ISSUE_DEPTH];
    end

    always_comb begin : ready_prefix_select
        existing_prefix_count   = '0;
        new_prefix_count        = '0;
        existing_rank_before    = '0;
        new_rank_before         = '0;
        existing_selected_count = '0;
        new_combined_rank       = '0;
        existing_select_onehot  = '0;
        new_select_onehot       = '0;
        enqueue_select_onehot   = '0;

        for (int prefix_entry = 0;
             prefix_entry < ISSUE_DEPTH;
             prefix_entry++) begin
            existing_prefix_count[0][prefix_entry] =
                ENQUEUE_COUNT_W'(rotated_existing_ready[prefix_entry]);
            new_prefix_count[0][prefix_entry] =
                ENQUEUE_COUNT_W'(rotated_new_ready[prefix_entry]);
        end

        for (int prefix_stage = 1;
             prefix_stage <= PREFIX_STAGE_NUM;
             prefix_stage++) begin
            for (int prefix_entry = 0;
                 prefix_entry < ISSUE_DEPTH;
                 prefix_entry++) begin
                if (prefix_entry < (1 << (prefix_stage - 1))) begin
                    existing_prefix_count[prefix_stage][prefix_entry] =
                        existing_prefix_count[prefix_stage-1][prefix_entry];
                    new_prefix_count[prefix_stage][prefix_entry] =
                        new_prefix_count[prefix_stage-1][prefix_entry];
                end else begin
                    existing_prefix_count[prefix_stage][prefix_entry] =
                        saturated_count_add(
                            existing_prefix_count[prefix_stage-1]
                                                 [prefix_entry],
                            existing_prefix_count[prefix_stage-1]
                                                 [prefix_entry
                                                  - (1 << (prefix_stage - 1))]);
                    new_prefix_count[prefix_stage][prefix_entry] =
                        saturated_count_add(
                            new_prefix_count[prefix_stage-1][prefix_entry],
                            new_prefix_count[prefix_stage-1]
                                            [prefix_entry
                                             - (1 << (prefix_stage - 1))]);
                end
            end
        end

        existing_selected_count =
            existing_prefix_count[PREFIX_STAGE_NUM][ISSUE_DEPTH-1];

        for (int prefix_entry = 0;
             prefix_entry < ISSUE_DEPTH;
             prefix_entry++) begin
            if (prefix_entry == 0) begin
                existing_rank_before[prefix_entry] = '0;
                new_rank_before[prefix_entry] = '0;
            end else begin
                existing_rank_before[prefix_entry] =
                    existing_prefix_count[PREFIX_STAGE_NUM]
                                         [prefix_entry-1];
                new_rank_before[prefix_entry] =
                    new_prefix_count[PREFIX_STAGE_NUM][prefix_entry-1];
            end

            new_combined_rank[prefix_entry] = saturated_count_add(
                existing_selected_count, new_rank_before[prefix_entry]);

            for (int enqueue_rank = 0;
                 enqueue_rank < READY_ENQUEUE_WIDTH;
                 enqueue_rank++) begin
                existing_select_onehot[enqueue_rank][prefix_entry] =
                    rotated_existing_ready[prefix_entry]
                    && (existing_rank_before[prefix_entry]
                        == ENQUEUE_COUNT_W'(enqueue_rank));
                new_select_onehot[enqueue_rank][prefix_entry] =
                    rotated_new_ready[prefix_entry]
                    && (new_combined_rank[prefix_entry]
                        == ENQUEUE_COUNT_W'(enqueue_rank));
                enqueue_select_onehot[enqueue_rank][prefix_entry] =
                    existing_select_onehot[enqueue_rank][prefix_entry]
                    || new_select_onehot[enqueue_rank][prefix_entry];
            end
        end
    end

    generate
        for (genvar enqueue_rank = 0;
             enqueue_rank < READY_ENQUEUE_WIDTH;
             enqueue_rank++) begin : ready_offset_encode
            assign enqueue_from_allocation[enqueue_rank] =
                |new_select_onehot[enqueue_rank];
            assign enqueue_rotated_offset[enqueue_rank][0] =
                |(enqueue_select_onehot[enqueue_rank] & 32'haaaa_aaaa);
            assign enqueue_rotated_offset[enqueue_rank][1] =
                |(enqueue_select_onehot[enqueue_rank] & 32'hcccc_cccc);
            assign enqueue_rotated_offset[enqueue_rank][2] =
                |(enqueue_select_onehot[enqueue_rank] & 32'hf0f0_f0f0);
            assign enqueue_rotated_offset[enqueue_rank][3] =
                |(enqueue_select_onehot[enqueue_rank] & 32'hff00_ff00);
            assign enqueue_rotated_offset[enqueue_rank][4] =
                |(enqueue_select_onehot[enqueue_rank] & 32'hffff_0000);
        end
    endgenerate

    always_comb begin : ready_discovery_encode
        enqueue_valid    = '0;
        enqueue_rob_id   = '0;
        enqueue_seq_tag  = '0;
        enqueue_delay    = '0;
        enqueue_rr_ptr_d = enqueue_rr_ptr_q;

        for (int enqueue_idx = 0;
             enqueue_idx < READY_ENQUEUE_WIDTH;
             enqueue_idx++) begin
            enqueue_valid[enqueue_idx] =
                |enqueue_select_onehot[enqueue_idx];
            enqueue_rob_id[enqueue_idx] =
                enqueue_rr_ptr_q + enqueue_rotated_offset[enqueue_idx];

            if (enqueue_valid[enqueue_idx]) begin
                if (enqueue_from_allocation[enqueue_idx]) begin
                    enqueue_seq_tag[enqueue_idx] =
                        alloc_seq_tag_by_id[enqueue_rob_id[enqueue_idx]];
                    enqueue_delay[enqueue_idx] =
                        alloc_delay_by_id[enqueue_rob_id[enqueue_idx]];
                end else begin
                    enqueue_seq_tag[enqueue_idx] =
                        issue_seq_tag_q[enqueue_rob_id[enqueue_idx]];
                    enqueue_delay[enqueue_idx] =
                        issue_delay_q[enqueue_rob_id[enqueue_idx]];
                end
            end
        end

        if (enqueue_valid[3]) begin
            enqueue_rr_ptr_d = enqueue_rob_id[3] + rob_id_t'(1);
        end else if (enqueue_valid[2]) begin
            enqueue_rr_ptr_d = enqueue_rob_id[2] + rob_id_t'(1);
        end else if (enqueue_valid[1]) begin
            enqueue_rr_ptr_d = enqueue_rob_id[1] + rob_id_t'(1);
        end else if (enqueue_valid[0]) begin
            enqueue_rr_ptr_d = enqueue_rob_id[0] + rob_id_t'(1);
        end
    end

    always_comb begin : enqueue_membership_decode
        enqueue_hit = '0;
        for (int enqueue_idx = 0;
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

    always_comb begin : ready_queue_event_decode
        ready_pop_count       = '0;
        ready_push_count      = '0;
        ready_write_en        = '0;
        ready_write_seq_tag   = '0;
        enqueue_rank_in_class = '0;
        enqueue_write_position = '0;

        for (int class_idx = 0;
             class_idx < DELAY_CLASS_NUM;
             class_idx++) begin
            for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                rob_id_t select_rob_id;

                select_rob_id = rob_id_t'(
                    select_seq_tag_i[fe_idx][ROB_ID_W-1:0]);
                if (select_valid_i[fe_idx]
                    && (issue_delay_q[select_rob_id]
                        == DELAY_W'(class_idx))) begin
                    ready_pop_count[class_idx] =
                        ready_pop_count[class_idx]
                        + ENQUEUE_COUNT_W'(1);
                end
            end

            for (int enqueue_idx = 0;
                 enqueue_idx < READY_ENQUEUE_WIDTH;
                 enqueue_idx++) begin
                if (enqueue_valid[enqueue_idx]
                    && (enqueue_delay[enqueue_idx] == DELAY_W'(class_idx))) begin
                    ready_push_count[class_idx] =
                        ready_push_count[class_idx]
                        + ENQUEUE_COUNT_W'(1);
                end
            end
        end

        for (int enqueue_idx = 0;
             enqueue_idx < READY_ENQUEUE_WIDTH;
             enqueue_idx++) begin
            for (int prior_idx = 0;
                 prior_idx < enqueue_idx;
                 prior_idx++) begin
                if (enqueue_valid[prior_idx]
                    && enqueue_valid[enqueue_idx]
                    && (enqueue_delay[prior_idx]
                        == enqueue_delay[enqueue_idx])) begin
                    enqueue_rank_in_class[enqueue_idx] =
                        enqueue_rank_in_class[enqueue_idx]
                        + ENQUEUE_COUNT_W'(1);
                end
            end

            if (enqueue_valid[enqueue_idx]) begin
                enqueue_write_position[enqueue_idx] =
                    ready_q_tail_q[enqueue_delay[enqueue_idx]]
                    + rob_id_t'(enqueue_rank_in_class[enqueue_idx]);
            end
        end

        for (int class_idx = 0;
             class_idx < DELAY_CLASS_NUM;
             class_idx++) begin
            for (int queue_pos = 0;
                 queue_pos < ISSUE_DEPTH;
                 queue_pos++) begin
                for (int enqueue_idx = 0;
                     enqueue_idx < READY_ENQUEUE_WIDTH;
                     enqueue_idx++) begin
                    if (enqueue_valid[enqueue_idx]
                        && (enqueue_delay[enqueue_idx]
                            == DELAY_W'(class_idx))
                        && (enqueue_write_position[enqueue_idx]
                            == rob_id_t'(queue_pos))) begin
                        ready_write_en[class_idx][queue_pos] = 1'b1;
                        ready_write_seq_tag[class_idx][queue_pos] =
                            enqueue_seq_tag[enqueue_idx];
                    end
                end
            end
        end
    end

    always_comb begin : candidate_window_read
        candidate_valid_o   = '0;
        candidate_seq_tag_o = '0;

        for (int class_idx = 0;
             class_idx < DELAY_CLASS_NUM;
             class_idx++) begin
            for (int window_idx = 0;
                 window_idx < CAND_WINDOW_DEPTH;
                 window_idx++) begin
                rob_id_t read_position;

                read_position = ready_q_head_q[class_idx]
                                + rob_id_t'(window_idx);
                if (QUEUE_COUNT_W'(window_idx)
                    < ready_q_count_q[class_idx]) begin
                    candidate_valid_o[class_idx][window_idx] = 1'b1;
                    candidate_seq_tag_o[class_idx][window_idx] =
                        ready_q_seq_tag_q[class_idx][read_position];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Per-FE selected-tag pipeline, D3 issue bundle, and automatic release
    //--------------------------------------------------------------------------

    always_comb begin : issue_bundle_read
        dep_gather_valid_o          = '0;
        dep_gather_target_seq_tag_o = '0;
        issue_valid_o               = selected_valid_q;
        issue_packet_o              = '0;
        issue_delay_o               = '0;
        issue_dep_required_o        = '0;

        for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
            rob_id_t selected_rob_id;

            selected_rob_id = rob_id_t'(
                selected_seq_tag_q[fe_idx][ROB_ID_W-1:0]);
            if (selected_valid_q[fe_idx]) begin
                issue_packet_o[fe_idx] =
                    issue_packet_q[selected_rob_id];
                issue_delay_o[fe_idx] =
                    issue_delay_q[selected_rob_id];
                issue_dep_required_o[fe_idx] =
                    issue_dep_required_q[selected_rob_id];

                if (issue_dep_required_q[selected_rob_id]) begin
                    dep_gather_valid_o[fe_idx] = 1'b1;
                    dep_gather_target_seq_tag_o[fe_idx] =
                        issue_target_seq_tag_q[selected_rob_id];
                end
            end
        end
    end

    // Keep gather-response adaptation separate from request generation. This
    // makes the unidirectional request/response dependency explicit and avoids
    // presenting the integrated design as a combinational feedback process.
    always_comb begin : dependency_data_adapt
        issue_dep_data_o = '0;

        for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
            // data_valid is a legal-operation invariant, not a release or
            // rollback condition for an irrevocable selection.
            if (selected_valid_q[fe_idx]
                && issue_dep_required_o[fe_idx]
                && dep_gather_data_valid_i[fe_idx]) begin
                issue_dep_data_o[fe_idx] = dep_gather_data_i[fe_idx];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Concurrent next-state merge and sequential state update
    //--------------------------------------------------------------------------

    // Effective entry priority is D3 release, completion wakeup, D2 select,
    // queue-membership update, then D0 allocation. Allocation therefore owns
    // the final identity and state of a same-edge reused physical entry.
    always_ff @(posedge clk_i or negedge rst_ni) begin : issue_entry_update
        if (!rst_ni) begin
            queued_q <= '0;

            for (int entry_idx = 0;
                 entry_idx < ISSUE_DEPTH;
                 entry_idx++) begin
                issue_state_q[entry_idx] <= ISSUE_FREE;
            end
        end else begin
            // The prior cycle's irrevocable selections enter their FEs now.
            for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                rob_id_t selected_rob_id;

                selected_rob_id = rob_id_t'(
                    selected_seq_tag_q[fe_idx][ROB_ID_W-1:0]);
                if (selected_valid_q[fe_idx]) begin
                    issue_state_q[selected_rob_id] <= ISSUE_FREE;
                    queued_q[selected_rob_id] <= 1'b0;
                end
            end

            // Completion wakeup changes only small dependency/control fields.
            for (int entry_idx = 0;
                 entry_idx < ISSUE_DEPTH;
                 entry_idx++) begin
                if (wake_hit[entry_idx]) begin
                    issue_state_q[entry_idx] <= ISSUE_READY;
                end
            end

            // FE-scheduler selections are final and remove READY IDs from queues.
            for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                rob_id_t select_rob_id;

                select_rob_id = rob_id_t'(
                    select_seq_tag_i[fe_idx][ROB_ID_W-1:0]);
                if (select_valid_i[fe_idx]) begin
                    issue_state_q[select_rob_id] <= ISSUE_SELECTED;
                    queued_q[select_rob_id] <= 1'b0;
                end
            end

            for (int enqueue_idx = 0;
                 enqueue_idx < READY_ENQUEUE_WIDTH;
                 enqueue_idx++) begin
                if (enqueue_valid[enqueue_idx]) begin
                    queued_q[enqueue_rob_id[enqueue_idx]] <= 1'b1;
                end
            end

            // D0 allocation is the final writer for a reused issue entry.
            for (int lane_idx = 0; lane_idx < N; lane_idx++) begin
                rob_id_t alloc_rob_id;

                alloc_rob_id = rob_id_t'(
                    alloc_seq_tag_i[lane_idx][ROB_ID_W-1:0]);
                if (issue_alloc_valid_i[lane_idx]) begin
                    if (!alloc_dep_required_i[lane_idx]
                        || dep_status_available_i[lane_idx]) begin
                        issue_state_q[alloc_rob_id] <= ISSUE_READY;
                    end else begin
                        issue_state_q[alloc_rob_id] <= ISSUE_WAIT_DEP;
                    end

                    issue_seq_tag_q[alloc_rob_id] <=
                        alloc_seq_tag_i[lane_idx];
                    issue_target_seq_tag_q[alloc_rob_id] <=
                        alloc_target_seq_tag_i[lane_idx];
                    issue_delay_q[alloc_rob_id] <=
                        alloc_delay_i[lane_idx];
                    issue_dep_required_q[alloc_rob_id] <=
                        alloc_dep_required_i[lane_idx];
                    queued_q[alloc_rob_id] <= enqueue_hit[alloc_rob_id];
                end
            end

        end
    end

    // Payload is physically independent from scheduler metadata. It is not
    // reset and changes only when a newly accepted packet owns the entry.
    always_ff @(posedge clk_i) begin : issue_payload_update
        for (int entry_idx = 0;
             entry_idx < ISSUE_DEPTH;
             entry_idx++) begin
            if (packet_write_en[entry_idx]) begin
                issue_packet_q[entry_idx] <= packet_write_data[entry_idx];
            end
        end
    end

    // Per-FE selected-tag registers are consumed and refilled every cycle,
    // allowing one new selection per FE without bubbles.
    always_ff @(posedge clk_i or negedge rst_ni) begin : selected_pipe_update
        if (!rst_ni) begin
            selected_valid_q <= '0;
        end else begin
            selected_valid_q <= select_valid_i;
            for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                if (select_valid_i[fe_idx]) begin
                    selected_seq_tag_q[fe_idx] <= select_seq_tag_i[fe_idx];
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : ready_queue_state_update
        if (!rst_ni) begin
            ready_q_head_q   <= '0;
            ready_q_tail_q   <= '0;
            ready_q_count_q  <= '0;
            enqueue_rr_ptr_q <= '0;
        end else begin
            for (int class_idx = 0;
                 class_idx < DELAY_CLASS_NUM;
                 class_idx++) begin
                if (ready_pop_count[class_idx] != '0) begin
                    ready_q_head_q[class_idx] <=
                        ready_q_head_q[class_idx]
                        + rob_id_t'(ready_pop_count[class_idx]);
                end

                if (ready_push_count[class_idx] != '0) begin
                    ready_q_tail_q[class_idx] <=
                        ready_q_tail_q[class_idx]
                        + rob_id_t'(ready_push_count[class_idx]);
                end

                if ((ready_pop_count[class_idx] != '0)
                    || (ready_push_count[class_idx] != '0)) begin
                    ready_q_count_q[class_idx] <=
                        ready_q_count_q[class_idx]
                        - QUEUE_COUNT_W'(ready_pop_count[class_idx])
                        + QUEUE_COUNT_W'(ready_push_count[class_idx]);
                end
            end

            if (|enqueue_valid) begin
                enqueue_rr_ptr_q <= enqueue_rr_ptr_d;
            end
        end
    end

    // FIFO contents use slot-local write enables. Existing tags hold while
    // head/tail move, avoiding the former full-array relocation network.
    always_ff @(posedge clk_i) begin : ready_queue_tag_update
        for (int class_idx = 0;
             class_idx < DELAY_CLASS_NUM;
             class_idx++) begin
            for (int queue_pos = 0;
                 queue_pos < ISSUE_DEPTH;
                 queue_pos++) begin
                if (ready_write_en[class_idx][queue_pos]) begin
                    ready_q_seq_tag_q[class_idx][queue_pos] <=
                        ready_write_seq_tag[class_idx][queue_pos];
                end
            end
        end
    end

endmodule : ppe_issue_table

`default_nettype wire
