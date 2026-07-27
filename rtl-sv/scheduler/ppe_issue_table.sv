`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_issue_table.sv
// Block       : Scheduler / Issue Table
//
// Description :
//   Tracks ROB-indexed pre-issue metadata and dependency state. READY entries
//   are statically divided into four eight-entry banks. Each bank nominates at
//   most one entry per cycle into two bank-local registered candidate slots.
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

    localparam int CAND_ID_W    = $clog2(CAND_WINDOW_DEPTH);
    localparam int ADMIT_BANKS  = READY_ENQUEUE_WIDTH;
    localparam int ADMIT_BANK_W = $clog2(ADMIT_BANKS);
    localparam int ADMIT_ROWS   = ISSUE_DEPTH / ADMIT_BANKS;
    localparam int ADMIT_ROW_W  = $clog2(ADMIT_ROWS);

    typedef logic [CAND_ID_W-1:0]    cand_id_t;
    typedef logic [ADMIT_BANK_W-1:0] admit_bank_id_t;
    typedef logic [ADMIT_ROW_W-1:0]  admit_row_id_t;

    issue_state_e                 issue_state_q          [ISSUE_DEPTH];
    seq_tag_t                     issue_seq_tag_q        [ISSUE_DEPTH];
    seq_tag_t                     issue_target_seq_tag_q [ISSUE_DEPTH];
    delay_t                       issue_delay_q          [ISSUE_DEPTH];
    logic                         issue_dep_required_q   [ISSUE_DEPTH];

    logic [CAND_WINDOW_DEPTH-1:0] candidate_valid_q;
    logic [CAND_WINDOW_DEPTH-1:0] candidate_valid_d;
    seq_tag_t                     candidate_seq_tag_q[CAND_WINDOW_DEPTH];
    seq_tag_t                     candidate_seq_tag_d[CAND_WINDOW_DEPTH];
    delay_t                       candidate_delay_q[CAND_WINDOW_DEPTH];
    delay_t                       candidate_delay_d[CAND_WINDOW_DEPTH];
    logic [ISSUE_DEPTH-1:0]       candidate_present_q;
    logic [ISSUE_DEPTH-1:0]       candidate_present_d;
    admit_row_id_t                ready_admit_row_rr_q[ADMIT_BANKS];
    admit_row_id_t                ready_admit_row_rr_d[ADMIT_BANKS];

    logic [FE_NUM-1:0]            selected_valid_q;
    seq_tag_t                     selected_seq_tag_q[FE_NUM];
    seq_tag_t                     selected_target_seq_tag_q[FE_NUM];
    delay_t                       selected_delay_q[FE_NUM];
    logic [FE_NUM-1:0]            selected_dep_required_q;

    logic [ISSUE_DEPTH-1:0]       wake_hit;
    logic [ISSUE_DEPTH-1:0]       eligible_ready;
    logic [CAND_WINDOW_DEPTH-1:0] candidate_remove;
    logic [ISSUE_DEPTH-1:0]       select_entry_hit;
    seq_tag_t                     select_seq_tag[FE_NUM];
    rob_id_t                      select_entry_id[FE_NUM];

    logic [ADMIT_BANKS-1:0]       bank_winner_valid;
    seq_tag_t                     bank_winner_seq_tag[ADMIT_BANKS];
    delay_t                       bank_winner_delay[ADMIT_BANKS];

    //--------------------------------------------------------------------------
    // Dependency initialization and registered-state wakeup
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
    // D2B candidate removal
    //--------------------------------------------------------------------------

    always_comb begin : candidate_removal_decode
        candidate_remove = '0;
        select_entry_hit = '0;

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
    end

    //--------------------------------------------------------------------------
    // Four independent eight-entry READY selectors
    //--------------------------------------------------------------------------

    always_comb begin : ready_eligibility
        eligible_ready = '0;

        for (int entry = 0; entry < ISSUE_DEPTH; entry++) begin
            eligible_ready[entry] =
                (issue_state_q[entry] == ISSUE_READY)
                && !candidate_present_q[entry];
        end
    end

    always_comb begin : ready_bank_nomination
        bank_winner_valid = '0;

        for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
            logic vacancy;
            logic found;
            admit_row_id_t scan_row;
            rob_id_t scan_id;

            vacancy =
                !candidate_valid_q[bank]
                || !candidate_valid_q[ADMIT_BANKS + bank]
                || candidate_remove[bank]
                || candidate_remove[ADMIT_BANKS + bank];
            bank_winner_seq_tag[bank] = '0;
            bank_winner_delay[bank]   = '0;
            found                     = 1'b0;
            scan_row                  = '0;
            scan_id                   = '0;

            if (vacancy) begin
                for (int offset = 0; offset < ADMIT_ROWS; offset++) begin
                    scan_row = ready_admit_row_rr_q[bank]
                        + admit_row_id_t'(offset);
                    scan_id = {scan_row, admit_bank_id_t'(bank)};
                    if (!found && eligible_ready[scan_id]) begin
                        bank_winner_valid[bank]   = 1'b1;
                        bank_winner_seq_tag[bank] =
                            issue_seq_tag_q[scan_id];
                        bank_winner_delay[bank] =
                            issue_delay_q[scan_id];
                        found = 1'b1;
                    end
                end
            end
        end
    end

    always_comb begin : candidate_bank_next
        candidate_valid_d   = candidate_valid_q;
        candidate_present_d = candidate_present_q & ~select_entry_hit;

        for (int slot = 0; slot < CAND_WINDOW_DEPTH; slot++) begin
            candidate_seq_tag_d[slot] = candidate_seq_tag_q[slot];
            candidate_delay_d[slot]   = candidate_delay_q[slot];
            if (candidate_remove[slot]) begin
                candidate_valid_d[slot] = 1'b0;
            end
        end

        for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
            cand_id_t fill_slot;
            logic     fill_valid;

            fill_slot  = cand_id_t'(bank);
            fill_valid = 1'b0;
            ready_admit_row_rr_d[bank] =
                ready_admit_row_rr_q[bank] + admit_row_id_t'(1);

            if (!candidate_valid_q[bank] || candidate_remove[bank]) begin
                fill_slot  = cand_id_t'(bank);
                fill_valid = bank_winner_valid[bank];
            end else if (!candidate_valid_q[ADMIT_BANKS + bank]
                         || candidate_remove[ADMIT_BANKS + bank]) begin
                fill_slot  = cand_id_t'(ADMIT_BANKS + bank);
                fill_valid = bank_winner_valid[bank];
            end

            if (fill_valid) begin
                candidate_valid_d[fill_slot]   = 1'b1;
                candidate_seq_tag_d[fill_slot] =
                    bank_winner_seq_tag[bank];
                candidate_delay_d[fill_slot] =
                    bank_winner_delay[bank];
                candidate_present_d[
                    bank_winner_seq_tag[bank][ROB_ID_W-1:0]] = 1'b1;
            end
        end
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
            candidate_valid_q   <= '0;
            candidate_present_q <= '0;
            for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
                ready_admit_row_rr_q[bank] <= '0;
            end
        end else begin
            candidate_valid_q   <= candidate_valid_d;
            candidate_present_q <= candidate_present_d;
            for (int bank = 0; bank < ADMIT_BANKS; bank++) begin
                ready_admit_row_rr_q[bank] <=
                    ready_admit_row_rr_d[bank];
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

endmodule : ppe_issue_table

`default_nettype wire
