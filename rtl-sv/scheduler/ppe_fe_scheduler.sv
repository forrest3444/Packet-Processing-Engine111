`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_fe_scheduler.sv
// Project     : Packet Processing Engine (PPE)
// Block       : Scheduler / FE Scheduler
//
// Description :
//   Owns candidate-to-FE matching and all state required to make an
//   irrevocable scheduling decision: the per-FE return calendar, shared
//   schedule phase, and class/FE round-robin positions. READY head windows are
//   supplied by ppe_issue_table as complete sequence tags.
//
//   A successful select atomically locks the issue entry and reserves its FE
//   return slot. At the current calendar phase, the saved sequence tag is
//   associated with the corresponding FE return and emitted as a completion
//   event for Issue Table wakeup and ROB writeback. FE result data bypasses this
//   block and connects directly to the ROB datapath.
//
// Governing documents:
//   - doc/ppe_feature_description.txt, Sections 2.2, 6, and 7
//   - doc/hld.txt, Sections 3.3 and 4.3 through 4.4
//   - doc/lld.txt, Sections 3.3 through 3.5, 5.4, 5.6, and 8
//
// Clock/reset :
//   State is clocked by clk_i. rst_ni is the shared active-low internal reset.
//   Reset will clear calendar valid bits, schedule phase, and fairness state;
//   calendar tag storage need not be reset while its valid bit is clear.
//
// Implementation status:
//   Return-calendar management, completion association, forced-oldest
//   multi-grant matching, atomic reservation, and fairness updates are
//   implemented.
//------------------------------------------------------------------------------

module ppe_fe_scheduler #(
    parameter int unsigned DELAY_CLASS_NUM   = 4,
    parameter int unsigned CAND_WINDOW_DEPTH = 4,
    parameter int unsigned RETURN_SLOT_NUM   = 8
) (
    // Clock and reset
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    // READY-only FIFO head windows. Within each class, valid candidates form a
    // contiguous prefix and window slot zero is the oldest queued entry.
    input  logic [DELAY_CLASS_NUM-1:0]
                 [CAND_WINDOW_DEPTH-1:0]                   candidate_valid_i,
    input  logic [DELAY_CLASS_NUM-1:0]
                 [CAND_WINDOW_DEPTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                candidate_seq_tag_i,

    // Irrevocable selections indexed by destination FE. The same internal
    // event reserves the matching return-calendar slot on the selection edge.
    output logic [ppe_types_pkg::FE_NUM-1:0]               select_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                select_seq_tag_o,

    // Physical FE return-valid signals. Result data does not traverse this
    // control block and is connected directly from each FE to ppe_rob.
    input  logic [ppe_types_pkg::FE_NUM-1:0]               fe_out_valid_i,

    // Calendar-qualified completion identity. These outputs jointly drive
    // Issue Table wakeup and ROB writeback tag association.
    output logic [ppe_types_pkg::FE_NUM-1:0]               completion_valid_o,
    output logic [ppe_types_pkg::FE_NUM-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                completion_seq_tag_o
);

    import ppe_types_pkg::*;

    //--------------------------------------------------------------------------
    // Local parameters, types, and helper functions
    //--------------------------------------------------------------------------

    localparam int unsigned RETURN_SLOT_W =
        (RETURN_SLOT_NUM > 1) ? $clog2(RETURN_SLOT_NUM) : 1;
    localparam int unsigned CLASS_ID_W =
        (DELAY_CLASS_NUM > 1) ? $clog2(DELAY_CLASS_NUM) : 1;
    localparam int unsigned FE_ID_W =
        (FE_NUM > 1) ? $clog2(FE_NUM) : 1;
    localparam int unsigned CAND_COUNT_W =
        $clog2(CAND_WINDOW_DEPTH + 1);

    typedef logic [RETURN_SLOT_W-1:0] slot_id_t;
    typedef logic [CLASS_ID_W-1:0]    class_id_t;
    typedef logic [FE_ID_W-1:0]       fe_id_t;

    // Within the documented active window, a forward modular distance smaller
    // than half the sequence space means lhs precedes rhs.
    function automatic logic seq_tag_older(
        input logic [SEQ_W-1:0] lhs,
        input logic [SEQ_W-1:0] rhs
    );
        logic [SEQ_W-1:0] forward_distance;
        begin
            forward_distance = rhs - lhs;
            seq_tag_older = (forward_distance != '0)
                            && !forward_distance[SEQ_W-1];
        end
    endfunction

    function automatic class_id_t next_class_id(input class_id_t current_id);
        begin
            if (integer'(current_id) == (DELAY_CLASS_NUM - 1)) begin
                next_class_id = '0;
            end else begin
                next_class_id = class_id_t'(current_id + CLASS_ID_W'(1));
            end
        end
    endfunction

    function automatic fe_id_t next_fe_id(input fe_id_t current_id);
        begin
            if (integer'(current_id) == (FE_NUM - 1)) begin
                next_fe_id = '0;
            end else begin
                next_fe_id = fe_id_t'(current_id + FE_ID_W'(1));
            end
        end
    endfunction

    function automatic slot_id_t next_slot_id(input slot_id_t current_id);
        begin
            if (integer'(current_id) == (RETURN_SLOT_NUM - 1)) begin
                next_slot_id = '0;
            end else begin
                next_slot_id = slot_id_t'(
                    current_id + RETURN_SLOT_W'(1));
            end
        end
    endfunction

    //--------------------------------------------------------------------------
    // Return-calendar, schedule-phase, and fairness state
    //--------------------------------------------------------------------------

    logic [FE_NUM-1:0][RETURN_SLOT_NUM-1:0] return_valid_q;
    logic [FE_NUM-1:0][RETURN_SLOT_NUM-1:0][SEQ_W-1:0]
          return_seq_tag_q;

    slot_id_t  schedule_phase_q;
    class_id_t class_rr_ptr_q;
    fe_id_t    fe_rr_ptr_q;

    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0] fe_legal;
    logic [DELAY_CLASS_NUM-1:0][RETURN_SLOT_W-1:0]
          target_slot_by_class;

    logic [FE_NUM-1:0][CLASS_ID_W-1:0] select_class;
    logic                              selection_any;
    class_id_t                         class_rr_next;
    fe_id_t                            fe_rr_next;

    always_comb begin
        fe_legal            = '0;
        target_slot_by_class = '0;

        for (int unsigned class_idx = 0;
             class_idx < DELAY_CLASS_NUM;
             class_idx++) begin
            integer target_slot_sum;

            target_slot_sum = integer'(schedule_phase_q) + class_idx + 2;
            target_slot_by_class[class_idx] =
                slot_id_t'(target_slot_sum % RETURN_SLOT_NUM);

            for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                fe_legal[class_idx][fe_idx] =
                    !return_valid_q[fe_idx]
                                   [target_slot_by_class[class_idx]];
            end
        end
    end

    //--------------------------------------------------------------------------
    // Candidate legality and multi-grant matching
    //--------------------------------------------------------------------------

    always_comb begin : candidate_matching
        logic [DELAY_CLASS_NUM-1:0][CAND_COUNT_W-1:0]
              class_consumed;
        logic [FE_NUM-1:0] fe_used;
        logic [SEQ_W-1:0]  oldest_seq_tag;

        integer chosen_class;
        integer chosen_fe;
        integer chosen_class_availability;
        integer chosen_fe_demand;
        integer class_pick_start;
        integer fe_pick_start;
        integer scan_class;
        integer scan_fe;
        integer candidate_pos;
        integer available_fe_count;
        integer fe_demand_count;

        logic chosen_class_valid;
        logic chosen_fe_valid;

        select_valid_o   = '0;
        select_seq_tag_o = '0;
        select_class     = '0;
        selection_any    = 1'b0;
        class_rr_next    = class_rr_ptr_q;
        fe_rr_next       = fe_rr_ptr_q;
        class_consumed   = '0;
        fe_used          = '0;
        oldest_seq_tag   = '0;
        class_pick_start = integer'(class_rr_ptr_q);
        fe_pick_start    = integer'(fe_rr_ptr_q);
        scan_class       = 0;
        scan_fe          = 0;
        candidate_pos    = 0;
        available_fe_count = 0;
        fe_demand_count  = 0;

        // Each pass produces at most one grant. FE_NUM passes therefore cover
        // the maximum legal issue width while allowing repeated service of one
        // delay class through consecutive head-window entries.
        for (int unsigned grant_idx = 0;
             grant_idx < FE_NUM;
             grant_idx++) begin
            chosen_class              = 0;
            chosen_class_availability = FE_NUM + 1;
            chosen_class_valid        = 1'b0;
            oldest_seq_tag            = '0;

            if (grant_idx == 0) begin
                // Forced first: choose the globally oldest schedulable class
                // head before applying rotating fairness to later grants.
                for (int unsigned class_idx = 0;
                     class_idx < DELAY_CLASS_NUM;
                     class_idx++) begin
                    candidate_pos = integer'(class_consumed[class_idx]);
                    available_fe_count = 0;

                    if (candidate_pos < CAND_WINDOW_DEPTH) begin
                        for (int unsigned fe_idx = 0;
                             fe_idx < FE_NUM;
                             fe_idx++) begin
                            if (!fe_used[fe_idx]
                                && fe_legal[class_idx][fe_idx]) begin
                                available_fe_count = available_fe_count + 1;
                            end
                        end

                        if (candidate_valid_i[class_idx][candidate_pos]
                            && (available_fe_count != 0)
                            && (!chosen_class_valid
                                || seq_tag_older(
                                    candidate_seq_tag_i[class_idx]
                                                           [candidate_pos],
                                    oldest_seq_tag))) begin
                            chosen_class_valid = 1'b1;
                            chosen_class = class_idx;
                            chosen_class_availability = available_fe_count;
                            oldest_seq_tag =
                                candidate_seq_tag_i[class_idx][candidate_pos];
                        end
                    end
                end
            end else begin
                // Later grants favor the currently most constrained class.
                // Equal constraints are resolved from the rotating local start.
                for (int unsigned class_offset = 0;
                     class_offset < DELAY_CLASS_NUM;
                     class_offset++) begin
                    scan_class = class_pick_start + class_offset;
                    if (scan_class >= DELAY_CLASS_NUM) begin
                        scan_class = scan_class - DELAY_CLASS_NUM;
                    end

                    candidate_pos = integer'(class_consumed[scan_class]);
                    available_fe_count = 0;

                    if (candidate_pos < CAND_WINDOW_DEPTH) begin
                        for (int unsigned fe_idx = 0;
                             fe_idx < FE_NUM;
                             fe_idx++) begin
                            if (!fe_used[fe_idx]
                                && fe_legal[scan_class][fe_idx]) begin
                                available_fe_count = available_fe_count + 1;
                            end
                        end

                        if (candidate_valid_i[scan_class][candidate_pos]
                            && (available_fe_count != 0)
                            && (!chosen_class_valid
                                || (available_fe_count
                                    < chosen_class_availability))) begin
                            chosen_class_valid = 1'b1;
                            chosen_class = scan_class;
                            chosen_class_availability = available_fe_count;
                        end
                    end
                end
            end

            chosen_fe        = 0;
            chosen_fe_demand = DELAY_CLASS_NUM + 1;
            chosen_fe_valid  = 1'b0;

            if (chosen_class_valid) begin
                // Prefer an FE needed by fewer other active classes. This
                // preserves scarce FEs for constrained classes; ties use RR.
                for (int unsigned fe_offset = 0;
                     fe_offset < FE_NUM;
                     fe_offset++) begin
                    scan_fe = fe_pick_start + fe_offset;
                    if (scan_fe >= FE_NUM) begin
                        scan_fe = scan_fe - FE_NUM;
                    end

                    if (!fe_used[scan_fe]
                        && fe_legal[chosen_class][scan_fe]) begin
                        fe_demand_count = 0;

                        for (int unsigned other_class = 0;
                             other_class < DELAY_CLASS_NUM;
                             other_class++) begin
                            candidate_pos =
                                integer'(class_consumed[other_class]);
                            if ((integer'(other_class) != chosen_class)
                                && (candidate_pos < CAND_WINDOW_DEPTH)
                                && candidate_valid_i[other_class]
                                                    [candidate_pos]
                                && fe_legal[other_class][scan_fe]) begin
                                fe_demand_count = fe_demand_count + 1;
                            end
                        end

                        if (!chosen_fe_valid
                            || (fe_demand_count < chosen_fe_demand)) begin
                            chosen_fe_valid  = 1'b1;
                            chosen_fe        = scan_fe;
                            chosen_fe_demand = fe_demand_count;
                        end
                    end
                end
            end

            if (chosen_class_valid && chosen_fe_valid) begin
                candidate_pos = integer'(class_consumed[chosen_class]);
                select_valid_o[chosen_fe] = 1'b1;
                select_seq_tag_o[chosen_fe] =
                    candidate_seq_tag_i[chosen_class][candidate_pos];
                select_class[chosen_fe] = class_id_t'(chosen_class);

                class_consumed[chosen_class] =
                    class_consumed[chosen_class] + CAND_COUNT_W'(1);
                fe_used[chosen_fe] = 1'b1;
                selection_any = 1'b1;

                class_rr_next = next_class_id(class_id_t'(chosen_class));
                fe_rr_next = next_fe_id(fe_id_t'(chosen_fe));
                fe_pick_start = integer'(next_fe_id(fe_id_t'(chosen_fe)));

                // The first rotating grant starts at the persistent class RR
                // position. Later rotating grants continue after their winner.
                if (grant_idx != 0) begin
                    class_pick_start = integer'(
                        next_class_id(class_id_t'(chosen_class)));
                end
            end
        end
    end

    //--------------------------------------------------------------------------
    // Atomic selection, reservation, and fairness update
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            return_valid_q  <= '0;
            schedule_phase_q <= '0;
            class_rr_ptr_q  <= '0;
            fe_rr_ptr_q     <= '0;
        end else begin
            // Consume the current calendar slot. Protocol mismatches are
            // verification errors and do not create a replay path.
            for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                if (return_valid_q[fe_idx][schedule_phase_q]) begin
                    return_valid_q[fe_idx][schedule_phase_q] <= 1'b0;
                end
            end

            // Selection and return-slot reservation are the same event.
            for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                if (select_valid_o[fe_idx]) begin
                    return_valid_q[fe_idx]
                                  [target_slot_by_class
                                   [select_class[fe_idx]]] <= 1'b1;
                    return_seq_tag_q[fe_idx]
                                    [target_slot_by_class
                                     [select_class[fe_idx]]] <=
                        select_seq_tag_o[fe_idx];
                end
            end

            schedule_phase_q <= next_slot_id(schedule_phase_q);

            if (selection_any) begin
                class_rr_ptr_q <= class_rr_next;
                fe_rr_ptr_q    <= fe_rr_next;
            end
        end
    end

    //--------------------------------------------------------------------------
    // FE return association and calendar advancement
    //--------------------------------------------------------------------------

    always_comb begin
        completion_valid_o      = '0;
        completion_seq_tag_o    = '0;

        for (int unsigned fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
            if (fe_out_valid_i[fe_idx]
                && return_valid_q[fe_idx][schedule_phase_q]) begin
                completion_valid_o[fe_idx] = 1'b1;
                completion_seq_tag_o[fe_idx] =
                    return_seq_tag_q[fe_idx][schedule_phase_q];
            end
        end
    end

endmodule : ppe_fe_scheduler

`default_nettype wire
