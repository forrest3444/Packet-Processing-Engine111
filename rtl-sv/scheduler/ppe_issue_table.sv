`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_issue_table.sv
// Block       : Scheduler / Issue Table
//
// Description :
//   Tracks ROB-indexed pre-issue metadata, dependency readiness, and membership
//   in an eight-slot sparse candidate window. READY entries that are not
//   visible candidates are admitted through four interleaved local banks.
//
//   Selection is irrevocable. D2B captures complete narrow issue metadata; D3
//   emits that registered bundle and releases the entry after FE acceptance.
//   Packet and dependency-result data remain owned by the ROB.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 4 through 7
//   - doc/hld.txt, Sections 3.3, 4.2, 4.3, and 5.1
//   - doc/lld.txt, Sections 3.1, 3.3, 5.3, 5.4, and 7 through 9
//------------------------------------------------------------------------------

module ppe_issue_table (
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    input  logic [ppe_types_pkg::N-1:0]                    issue_alloc_valid_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_seq_tag_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                alloc_target_seq_tag_i,
    input  logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::DELAY_W-1:0]              alloc_delay_i,
    input  logic [ppe_types_pkg::N-1:0]                    alloc_dep_required_i,

    output logic [ppe_types_pkg::N-1:0]                    dep_status_valid_o,
    output logic [ppe_types_pkg::N-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_status_target_seq_tag_o,
    input  logic [ppe_types_pkg::N-1:0]                    dep_status_available_i,

    input  logic [ppe_types_pkg::FE_NUM-1:0]               completion_valid_i,
    input  logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                completion_seq_tag_i,

    output logic [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]    candidate_valid_o,
    output logic [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                candidate_seq_tag_o,
    output logic [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
                 [ppe_types_pkg::DELAY_W-1:0]              candidate_delay_o,

    input  logic [ppe_types_pkg::FE_NUM-1:0]               select_valid_i,
    input  logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
                                                             select_candidate_onehot_i,

    output logic [ppe_types_pkg::FE_NUM-1:0]               dep_gather_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                dep_gather_target_seq_tag_o,

    output logic [ppe_types_pkg::FE_NUM-1:0]               issue_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                issue_seq_tag_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::DELAY_W-1:0]              issue_delay_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]               issue_dep_required_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                issue_target_seq_tag_o
);

    import ppe_types_pkg::*;

    typedef enum logic [1:0] {
        ISSUE_FREE,
        ISSUE_WAIT_DEP,
        ISSUE_READY,
        ISSUE_SELECTED
    } issue_state_e;

    localparam int CAND_ID_W       = $clog2(CAND_WINDOW_DEPTH);
    localparam int ADMIT_BANKS     = READY_ENQUEUE_WIDTH;
    localparam int ADMIT_BANK_W    = $clog2(ADMIT_BANKS);
    localparam int ADMIT_ROWS      = ISSUE_DEPTH / ADMIT_BANKS;
    localparam int ADMIT_ROW_W     = $clog2(ADMIT_ROWS);

    typedef logic [CAND_ID_W-1:0]       cand_id_t;
    typedef logic [ADMIT_BANK_W-1:0]    admit_bank_id_t;
    typedef logic [ADMIT_ROW_W-1:0]     admit_row_id_t;
    typedef struct packed {
        logic [2:0]      count;
        logic [3:0]      valid;
        logic [3:0][1:0] slot_id;
    } free_half_map_t;

    function automatic free_half_map_t compact_free_half(
        input logic [3:0] free_mask
    );
        free_half_map_t result;

        result = '0;
        case (free_mask)
            4'b0001: begin
                result.count      = 3'd1;
                result.slot_id[0] = 2'd0;
            end
            4'b0010: begin
                result.count      = 3'd1;
                result.slot_id[0] = 2'd1;
            end
            4'b0011: begin
                result.count      = 3'd2;
                result.slot_id[0] = 2'd0;
                result.slot_id[1] = 2'd1;
            end
            4'b0100: begin
                result.count      = 3'd1;
                result.slot_id[0] = 2'd2;
            end
            4'b0101: begin
                result.count      = 3'd2;
                result.slot_id[0] = 2'd0;
                result.slot_id[1] = 2'd2;
            end
            4'b0110: begin
                result.count      = 3'd2;
                result.slot_id[0] = 2'd1;
                result.slot_id[1] = 2'd2;
            end
            4'b0111: begin
                result.count      = 3'd3;
                result.slot_id[0] = 2'd0;
                result.slot_id[1] = 2'd1;
                result.slot_id[2] = 2'd2;
            end
            4'b1000: begin
                result.count      = 3'd1;
                result.slot_id[0] = 2'd3;
            end
            4'b1001: begin
                result.count      = 3'd2;
                result.slot_id[0] = 2'd0;
                result.slot_id[1] = 2'd3;
            end
            4'b1010: begin
                result.count      = 3'd2;
                result.slot_id[0] = 2'd1;
                result.slot_id[1] = 2'd3;
            end
            4'b1011: begin
                result.count      = 3'd3;
                result.slot_id[0] = 2'd0;
                result.slot_id[1] = 2'd1;
                result.slot_id[2] = 2'd3;
            end
            4'b1100: begin
                result.count      = 3'd2;
                result.slot_id[0] = 2'd2;
                result.slot_id[1] = 2'd3;
            end
            4'b1101: begin
                result.count      = 3'd3;
                result.slot_id[0] = 2'd0;
                result.slot_id[1] = 2'd2;
                result.slot_id[2] = 2'd3;
            end
            4'b1110: begin
                result.count      = 3'd3;
                result.slot_id[0] = 2'd1;
                result.slot_id[1] = 2'd2;
                result.slot_id[2] = 2'd3;
            end
            4'b1111: begin
                result.count      = 3'd4;
                result.slot_id[0] = 2'd0;
                result.slot_id[1] = 2'd1;
                result.slot_id[2] = 2'd2;
                result.slot_id[3] = 2'd3;
            end
            default: result = '0;
        endcase
        case (result.count)
            3'd1: result.valid = 4'b0001;
            3'd2: result.valid = 4'b0011;
            3'd3: result.valid = 4'b0111;
            3'd4: result.valid = 4'b1111;
            default: result.valid = '0;
        endcase
        return result;
    endfunction

    issue_state_e                 issue_state_q          [ISSUE_DEPTH];
    seq_tag_t                     issue_seq_tag_q        [ISSUE_DEPTH];
    seq_tag_t                     issue_target_seq_tag_q [ISSUE_DEPTH];
    delay_t                       issue_delay_q          [ISSUE_DEPTH];
    logic                         issue_dep_required_q   [ISSUE_DEPTH];

    logic [ISSUE_DEPTH-1:0]       candidate_present_q;
    logic [ISSUE_DEPTH-1:0]       candidate_present_d;
    logic [CAND_WINDOW_DEPTH-1:0] candidate_valid_q;
    logic [CAND_WINDOW_DEPTH-1:0] candidate_valid_d;
    seq_tag_t                     candidate_seq_tag_q    [CAND_WINDOW_DEPTH];
    seq_tag_t                     candidate_seq_tag_d    [CAND_WINDOW_DEPTH];
    delay_t                       candidate_delay_q      [CAND_WINDOW_DEPTH];
    delay_t                       candidate_delay_d      [CAND_WINDOW_DEPTH];
    logic [READY_ENQUEUE_WIDTH-1:0] refill_plan_valid_q;
    logic [READY_ENQUEUE_WIDTH-1:0] refill_plan_valid_d;
    seq_tag_t                       refill_plan_seq_tag_q[READY_ENQUEUE_WIDTH];
    seq_tag_t                       refill_plan_seq_tag_d[READY_ENQUEUE_WIDTH];
    delay_t                         refill_plan_delay_q[READY_ENQUEUE_WIDTH];
    delay_t                         refill_plan_delay_d[READY_ENQUEUE_WIDTH];
    admit_row_id_t                ready_admit_row_rr_q [ADMIT_BANKS];
    admit_row_id_t                ready_admit_row_rr_d [ADMIT_BANKS];
    admit_bank_id_t               ready_admit_bank_rr_q;
    admit_bank_id_t               ready_admit_bank_rr_d;

    logic [FE_NUM-1:0]            selected_valid_q;
    seq_tag_t                     selected_seq_tag_q       [FE_NUM];
    seq_tag_t                     selected_target_seq_tag_q[FE_NUM];
    delay_t                       selected_delay_q         [FE_NUM];
    logic [FE_NUM-1:0]            selected_dep_required_q;

    logic [ISSUE_DEPTH-1:0]       wake_hit;

    logic [CAND_WINDOW_DEPTH-1:0] candidate_remove;
    logic [ISSUE_DEPTH-1:0]       select_entry_hit;
    logic [ISSUE_DEPTH-1:0]       admit_entry_hit;
    logic [ISSUE_DEPTH-1:0]       eligible_ready;
    logic [ISSUE_DEPTH-1:0]       candidate_present_after_remove;
    logic [ISSUE_DEPTH-1:0]       refill_plan_entry_hit;
    logic [CAND_WINDOW_DEPTH-1:0] candidate_free;
    free_half_map_t               free_half_map[2];
    logic [READY_ENQUEUE_WIDTH-1:0] free_slot_valid;
    cand_id_t                     free_slot_id[READY_ENQUEUE_WIDTH];
    seq_tag_t                     select_seq_tag [FE_NUM];
    rob_id_t                      select_entry_id[FE_NUM];

    logic [ADMIT_BANKS-1:0]       bank_winner_valid;
    seq_tag_t                     bank_winner_seq_tag[ADMIT_BANKS];
    delay_t                       bank_winner_delay[ADMIT_BANKS];
    logic [ADMIT_BANKS-1:0]       rotated_bank_valid;
    admit_bank_id_t               rotated_bank_num[ADMIT_BANKS];
    logic [ADMIT_BANKS-1:0]       compact_bank_valid;
    admit_bank_id_t               compact_bank_num[ADMIT_BANKS];
    logic [READY_ENQUEUE_WIDTH-1:0] admit_valid;
    seq_tag_t                       admit_seq_tag [READY_ENQUEUE_WIDTH];
    delay_t                         admit_delay   [READY_ENQUEUE_WIDTH];

    //--------------------------------------------------------------------------
    // Dependency initialization and bounded completion wakeup
    //--------------------------------------------------------------------------

    always_comb begin : dependency_status_request
        dep_status_valid_o          = '0;
        dep_status_target_seq_tag_o = '0;

        for (int lane = 0; lane < N; lane++) begin
            dep_status_valid_o[lane] =
                issue_alloc_valid_i[lane] && alloc_dep_required_i[lane];
            if (dep_status_valid_o[lane]) begin
                dep_status_target_seq_tag_o[lane] =
                    alloc_target_seq_tag_i[lane];
            end
        end
    end

    always_comb begin : completion_wakeup_scan
        wake_hit = '0;

        for (int entry = 0; entry < ISSUE_DEPTH; entry++) begin
            for (int fe = 0; fe < FE_NUM; fe++) begin
                if (completion_valid_i[fe]
                    && (issue_state_q[entry] == ISSUE_WAIT_DEP)
                    && (issue_target_seq_tag_q[entry]
                        == completion_seq_tag_i[fe])) begin
                    wake_hit[entry] = 1'b1;
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Candidate removal and READY discovery
    //--------------------------------------------------------------------------

    always_comb begin : candidate_removal_decode
        candidate_remove              = '0;
        select_entry_hit              = '0;
        candidate_present_after_remove = candidate_present_q;

        for (int fe = 0; fe < FE_NUM; fe++) begin
            select_seq_tag[fe]  = '0;
            select_entry_id[fe] = '0;
            if (select_valid_i[fe]) begin
                candidate_remove |= select_candidate_onehot_i[fe];
                for (int slot = 0; slot < CAND_WINDOW_DEPTH; slot++) begin
                    if (select_candidate_onehot_i[fe][slot]) begin
                        select_seq_tag[fe] = candidate_seq_tag_q[slot];
                        select_entry_id[fe] =
                            candidate_seq_tag_q[slot][ROB_ID_W-1:0];
                    end
                end
            end
        end

        for (int entry = 0; entry < ISSUE_DEPTH; entry++) begin
            for (int fe = 0; fe < FE_NUM; fe++) begin
                if (select_valid_i[fe]
                    && (select_entry_id[fe] == rob_id_t'(entry))) begin
                    select_entry_hit[entry] = 1'b1;
                end
            end
        end
        candidate_present_after_remove =
            candidate_present_q & ~select_entry_hit;
    end

    always_comb begin : candidate_free_compact
        candidate_free = ~candidate_valid_q;
        free_half_map[0] = compact_free_half(candidate_free[3:0]);
        free_half_map[1] = compact_free_half(candidate_free[7:4]);
        free_slot_valid  = '0;
        for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
            free_slot_id[rank] = '0;
        end

        case (free_half_map[0].count)
            3'd0: begin
                free_slot_valid = free_half_map[1].valid;
                for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
                    free_slot_id[rank] =
                        {1'b1, free_half_map[1].slot_id[rank]};
                end
            end
            3'd1: begin
                free_slot_valid = {free_half_map[1].valid[2:0], 1'b1};
                free_slot_id[0] = {1'b0, free_half_map[0].slot_id[0]};
                for (int rank = 1; rank < READY_ENQUEUE_WIDTH; rank++) begin
                    free_slot_id[rank] =
                        {1'b1, free_half_map[1].slot_id[rank - 1]};
                end
            end
            3'd2: begin
                free_slot_valid = {free_half_map[1].valid[1:0], 2'b11};
                free_slot_id[0] = {1'b0, free_half_map[0].slot_id[0]};
                free_slot_id[1] = {1'b0, free_half_map[0].slot_id[1]};
                free_slot_id[2] = {1'b1, free_half_map[1].slot_id[0]};
                free_slot_id[3] = {1'b1, free_half_map[1].slot_id[1]};
            end
            3'd3: begin
                free_slot_valid = {free_half_map[1].valid[0], 3'b111};
                free_slot_id[0] = {1'b0, free_half_map[0].slot_id[0]};
                free_slot_id[1] = {1'b0, free_half_map[0].slot_id[1]};
                free_slot_id[2] = {1'b0, free_half_map[0].slot_id[2]};
                free_slot_id[3] = {1'b1, free_half_map[1].slot_id[0]};
            end
            default: begin
                free_slot_valid = 4'b1111;
                for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
                    free_slot_id[rank] =
                        {1'b0, free_half_map[0].slot_id[rank]};
                end
            end
        endcase
    end

    always_comb begin : ready_eligibility
        eligible_ready        = '0;
        refill_plan_entry_hit = '0;

        for (int entry = 0; entry < ISSUE_DEPTH; entry++) begin
            for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
                if (refill_plan_valid_q[rank]
                    && (refill_plan_seq_tag_q[rank][ROB_ID_W-1:0]
                        == rob_id_t'(entry))) begin
                    refill_plan_entry_hit[entry] = 1'b1;
                end
            end
            if (!candidate_present_q[entry]
                && !refill_plan_entry_hit[entry]) begin
                eligible_ready[entry] =
                    (issue_state_q[entry] == ISSUE_READY)
                    || wake_hit[entry];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Four-bank READY admission
    //--------------------------------------------------------------------------

    always_comb begin : ready_bank_nomination
        bank_winner_valid = '0;

        for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
            logic found;

            bank_winner_seq_tag[bank] = '0;
            bank_winner_delay[bank]   = '0;
            found = 1'b0;
            for (int offset = 0; offset < ADMIT_ROWS; offset++) begin
                admit_row_id_t scan_row;
                rob_id_t scan_id;

                scan_row = ready_admit_row_rr_q[bank]
                    + admit_row_id_t'(offset);
                scan_id = {scan_row, admit_bank_id_t'(bank)};
                if (!found
                    && eligible_ready[scan_id]) begin
                    bank_winner_valid[bank] = 1'b1;
                    bank_winner_seq_tag[bank] =
                        issue_seq_tag_q[scan_id];
                    bank_winner_delay[bank] =
                        issue_delay_q[scan_id];
                    found                   = 1'b1;
                end
            end
        end
    end

    always_comb begin : ready_admission_select
        admit_valid           = '0;
        ready_admit_bank_rr_d =
            ready_admit_bank_rr_q + admit_bank_id_t'(1);
        for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
            admit_seq_tag[rank] = '0;
            admit_delay[rank]   = '0;
        end
        for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
            ready_admit_row_rr_d[bank] =
                ready_admit_row_rr_q[bank] + admit_row_id_t'(1);
        end

        rotated_bank_valid = '0;
        for (int offset = 0; offset < ADMIT_BANKS; offset++) begin
            rotated_bank_num[offset] = '0;
        end
        case (ready_admit_bank_rr_q)
            2'd0: begin
                rotated_bank_valid  = bank_winner_valid;
                rotated_bank_num[0] = 2'd0;
                rotated_bank_num[1] = 2'd1;
                rotated_bank_num[2] = 2'd2;
                rotated_bank_num[3] = 2'd3;
            end
            2'd1: begin
                rotated_bank_valid = {
                    bank_winner_valid[0],
                    bank_winner_valid[3:1]
                };
                rotated_bank_num[0] = 2'd1;
                rotated_bank_num[1] = 2'd2;
                rotated_bank_num[2] = 2'd3;
                rotated_bank_num[3] = 2'd0;
            end
            2'd2: begin
                rotated_bank_valid = {
                    bank_winner_valid[1:0],
                    bank_winner_valid[3:2]
                };
                rotated_bank_num[0] = 2'd2;
                rotated_bank_num[1] = 2'd3;
                rotated_bank_num[2] = 2'd0;
                rotated_bank_num[3] = 2'd1;
            end
            default: begin
                rotated_bank_valid = {
                    bank_winner_valid[2:0],
                    bank_winner_valid[3]
                };
                rotated_bank_num[0] = 2'd3;
                rotated_bank_num[1] = 2'd0;
                rotated_bank_num[2] = 2'd1;
                rotated_bank_num[3] = 2'd2;
            end
        endcase

        compact_bank_valid = '0;
        for (int rank = 0; rank < ADMIT_BANKS; rank++) begin
            compact_bank_num[rank] = '0;
        end
        case (rotated_bank_valid)
            4'b0001: begin
                compact_bank_valid  = 4'b0001;
                compact_bank_num[0] = rotated_bank_num[0];
            end
            4'b0010: begin
                compact_bank_valid  = 4'b0001;
                compact_bank_num[0] = rotated_bank_num[1];
            end
            4'b0011: begin
                compact_bank_valid  = 4'b0011;
                compact_bank_num[0] = rotated_bank_num[0];
                compact_bank_num[1] = rotated_bank_num[1];
            end
            4'b0100: begin
                compact_bank_valid  = 4'b0001;
                compact_bank_num[0] = rotated_bank_num[2];
            end
            4'b0101: begin
                compact_bank_valid  = 4'b0011;
                compact_bank_num[0] = rotated_bank_num[0];
                compact_bank_num[1] = rotated_bank_num[2];
            end
            4'b0110: begin
                compact_bank_valid  = 4'b0011;
                compact_bank_num[0] = rotated_bank_num[1];
                compact_bank_num[1] = rotated_bank_num[2];
            end
            4'b0111: begin
                compact_bank_valid  = 4'b0111;
                compact_bank_num[0] = rotated_bank_num[0];
                compact_bank_num[1] = rotated_bank_num[1];
                compact_bank_num[2] = rotated_bank_num[2];
            end
            4'b1000: begin
                compact_bank_valid  = 4'b0001;
                compact_bank_num[0] = rotated_bank_num[3];
            end
            4'b1001: begin
                compact_bank_valid  = 4'b0011;
                compact_bank_num[0] = rotated_bank_num[0];
                compact_bank_num[1] = rotated_bank_num[3];
            end
            4'b1010: begin
                compact_bank_valid  = 4'b0011;
                compact_bank_num[0] = rotated_bank_num[1];
                compact_bank_num[1] = rotated_bank_num[3];
            end
            4'b1011: begin
                compact_bank_valid  = 4'b0111;
                compact_bank_num[0] = rotated_bank_num[0];
                compact_bank_num[1] = rotated_bank_num[1];
                compact_bank_num[2] = rotated_bank_num[3];
            end
            4'b1100: begin
                compact_bank_valid  = 4'b0011;
                compact_bank_num[0] = rotated_bank_num[2];
                compact_bank_num[1] = rotated_bank_num[3];
            end
            4'b1101: begin
                compact_bank_valid  = 4'b0111;
                compact_bank_num[0] = rotated_bank_num[0];
                compact_bank_num[1] = rotated_bank_num[2];
                compact_bank_num[2] = rotated_bank_num[3];
            end
            4'b1110: begin
                compact_bank_valid  = 4'b0111;
                compact_bank_num[0] = rotated_bank_num[1];
                compact_bank_num[1] = rotated_bank_num[2];
                compact_bank_num[2] = rotated_bank_num[3];
            end
            4'b1111: begin
                compact_bank_valid  = 4'b1111;
                for (int rank = 0; rank < ADMIT_BANKS; rank++) begin
                    compact_bank_num[rank] = rotated_bank_num[rank];
                end
            end
            default: compact_bank_valid = '0;
        endcase

        for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
            if (compact_bank_valid[rank]) begin
                admit_valid[rank]   = 1'b1;
                admit_seq_tag[rank] =
                    bank_winner_seq_tag[compact_bank_num[rank]];
                admit_delay[rank] =
                    bank_winner_delay[compact_bank_num[rank]];
            end
        end
    end

    always_comb begin : refill_stage_next
        refill_plan_valid_d = admit_valid;
        for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
            refill_plan_seq_tag_d[rank] = admit_seq_tag[rank];
            refill_plan_delay_d[rank]   = admit_delay[rank];
        end
    end

    always_comb begin : candidate_window_next
        candidate_valid_d   = candidate_valid_q;
        candidate_present_d = candidate_present_after_remove;
        admit_entry_hit      = '0;

        for (int slot = 0; slot < CAND_WINDOW_DEPTH; slot++) begin
            candidate_seq_tag_d[slot] = candidate_seq_tag_q[slot];
            candidate_delay_d[slot]   = candidate_delay_q[slot];
            if (candidate_remove[slot]) begin
                candidate_valid_d[slot] = 1'b0;
            end
        end

        for (int slot = 0; slot < CAND_WINDOW_DEPTH; slot++) begin
            for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
                if (free_slot_valid[rank]
                    && refill_plan_valid_q[rank]
                    && (free_slot_id[rank] == cand_id_t'(slot))) begin
                    candidate_valid_d[slot]   = 1'b1;
                    candidate_seq_tag_d[slot] =
                        refill_plan_seq_tag_q[rank];
                    candidate_delay_d[slot] =
                        refill_plan_delay_q[rank];
                end
            end
        end
        for (int entry = 0; entry < ISSUE_DEPTH; entry++) begin
            for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
                if (free_slot_valid[rank]
                    && refill_plan_valid_q[rank]
                    && (refill_plan_seq_tag_q[rank][ROB_ID_W-1:0]
                        == rob_id_t'(entry))) begin
                    admit_entry_hit[entry] = 1'b1;
                end
            end
        end
        candidate_present_d |= admit_entry_hit;
    end

    //--------------------------------------------------------------------------
    // Candidate and D3 registered-metadata outputs
    //--------------------------------------------------------------------------

    always_comb begin : interface_outputs
        candidate_valid_o           = candidate_valid_q;
        candidate_seq_tag_o         = '0;
        candidate_delay_o           = '0;
        dep_gather_valid_o          = '0;
        dep_gather_target_seq_tag_o = '0;
        issue_valid_o               = selected_valid_q;
        issue_seq_tag_o             = '0;
        issue_delay_o               = '0;
        issue_dep_required_o        = '0;
        issue_target_seq_tag_o      = '0;

        for (int slot = 0; slot < CAND_WINDOW_DEPTH; slot++) begin
            if (candidate_valid_q[slot]) begin
                candidate_seq_tag_o[slot] = candidate_seq_tag_q[slot];
                candidate_delay_o[slot]   = candidate_delay_q[slot];
            end
            for (int rank = 0; rank < READY_ENQUEUE_WIDTH; rank++) begin
                if (!candidate_valid_q[slot]
                    && free_slot_valid[rank]
                    && refill_plan_valid_q[rank]
                    && (free_slot_id[rank] == cand_id_t'(slot))) begin
                    candidate_valid_o[slot]   = 1'b1;
                    candidate_seq_tag_o[slot] =
                        refill_plan_seq_tag_q[rank];
                    candidate_delay_o[slot] =
                        refill_plan_delay_q[rank];
                end
            end
        end

        for (int fe = 0; fe < FE_NUM; fe++) begin
            if (selected_valid_q[fe]) begin
                issue_seq_tag_o[fe]        = selected_seq_tag_q[fe];
                issue_delay_o[fe]          = selected_delay_q[fe];
                issue_dep_required_o[fe]   =
                    selected_dep_required_q[fe];
                issue_target_seq_tag_o[fe] =
                    selected_target_seq_tag_q[fe];
                dep_gather_valid_o[fe] =
                    selected_dep_required_q[fe];
                if (selected_dep_required_q[fe]) begin
                    dep_gather_target_seq_tag_o[fe] =
                        selected_target_seq_tag_q[fe];
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Sequential state ownership
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin : issue_entry_state
        if (!rst_ni) begin
            for (int entry = 0; entry < ISSUE_DEPTH; entry++) begin
                issue_state_q[entry] <= ISSUE_FREE;
            end
        end else begin
            for (int fe = 0; fe < FE_NUM; fe++) begin
                if (selected_valid_q[fe]) begin
                    issue_state_q[
                        selected_seq_tag_q[fe][ROB_ID_W-1:0]] <= ISSUE_FREE;
                end
            end

            for (int entry = 0; entry < ISSUE_DEPTH; entry++) begin
                if (wake_hit[entry]) begin
                    issue_state_q[entry] <= ISSUE_READY;
                end
            end

            for (int fe = 0; fe < FE_NUM; fe++) begin
                if (select_valid_i[fe]) begin
                    issue_state_q[select_entry_id[fe]] <= ISSUE_SELECTED;
                end
            end

            for (int lane = 0; lane < N; lane++) begin
                if (issue_alloc_valid_i[lane]) begin
                    rob_id_t allocation_id;

                    allocation_id =
                        alloc_seq_tag_i[lane][ROB_ID_W-1:0];
                    issue_seq_tag_q[allocation_id] <=
                        alloc_seq_tag_i[lane];
                    issue_target_seq_tag_q[allocation_id] <=
                        alloc_target_seq_tag_i[lane];
                    issue_delay_q[allocation_id] <=
                        alloc_delay_i[lane];
                    issue_dep_required_q[allocation_id] <=
                        alloc_dep_required_i[lane];
                    issue_state_q[allocation_id] <=
                        (!alloc_dep_required_i[lane]
                         || dep_status_available_i[lane])
                        ? ISSUE_READY : ISSUE_WAIT_DEP;
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : selected_metadata
        if (!rst_ni) begin
            selected_valid_q <= '0;
        end else begin
            selected_valid_q <= select_valid_i;
            for (int fe = 0; fe < FE_NUM; fe++) begin
                if (select_valid_i[fe]) begin
                    rob_id_t selected_id;

                    selected_id = select_entry_id[fe];
                    selected_seq_tag_q[fe] <= select_seq_tag[fe];
                    selected_target_seq_tag_q[fe] <=
                        issue_target_seq_tag_q[selected_id];
                    selected_delay_q[fe] <= issue_delay_q[selected_id];
                    selected_dep_required_q[fe] <=
                        issue_dep_required_q[selected_id];
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : candidate_state
        if (!rst_ni) begin
            candidate_valid_q      <= '0;
            candidate_present_q    <= '0;
            ready_admit_bank_rr_q  <= '0;
            for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
                ready_admit_row_rr_q[bank] <= '0;
            end
        end else begin
            candidate_valid_q      <= candidate_valid_d;
            candidate_present_q    <= candidate_present_d;
            ready_admit_bank_rr_q  <= ready_admit_bank_rr_d;
            for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
                ready_admit_row_rr_q[bank] <= ready_admit_row_rr_d[bank];
            end
            for (int slot = 0; slot < CAND_WINDOW_DEPTH; slot++) begin
                if (candidate_valid_d[slot]
                    && (!candidate_valid_q[slot]
                        || candidate_remove[slot]
                        || (candidate_seq_tag_d[slot]
                            != candidate_seq_tag_q[slot]))) begin
                    candidate_seq_tag_q[slot] <= candidate_seq_tag_d[slot];
                    candidate_delay_q[slot]   <= candidate_delay_d[slot];
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : refill_plan_state
        if (!rst_ni) begin
            refill_plan_valid_q <= '0;
        end else begin
            refill_plan_valid_q <= refill_plan_valid_d;
            for (int slot = 0; slot < READY_ENQUEUE_WIDTH; slot++) begin
                if (refill_plan_valid_d[slot]
                    && (!refill_plan_valid_q[slot]
                        || (refill_plan_seq_tag_d[slot]
                            != refill_plan_seq_tag_q[slot]))) begin
                    refill_plan_seq_tag_q[slot] <=
                        refill_plan_seq_tag_d[slot];
                    refill_plan_delay_q[slot] <=
                        refill_plan_delay_d[slot];
                end
            end
        end
    end

endmodule : ppe_issue_table

`default_nettype wire
