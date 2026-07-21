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
//   Matching is split across D2A and D2B. D2A captures an irrevocable pending
//   grant; D2B exposes that registered grant to Issue Table and commits its FE
//   return-slot reservation. At the current calendar phase, the saved tag is
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
//   Reset clears grant and calendar valid bits, schedule phase, and fairness
//   state; payload-like tag storage is not reset while its valid bit is clear.
//
// Implementation status:
//   Two-stage matching, return-calendar management, completion association,
//   forced-oldest multi-grant selection, reservation, and fairness updates are
//   implemented.
//------------------------------------------------------------------------------

module ppe_fe_scheduler (
    // Clock and reset
    input  logic                                           clk_i,
    input  logic                                           rst_ni,

    // READY-only FIFO head windows. Within each class, valid candidates form a
    // contiguous prefix and window slot zero is the oldest queued entry.
    input  logic [ppe_types_pkg::DELAY_CLASS_NUM-1:0]
                 [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]    candidate_valid_i,
    input  logic [ppe_types_pkg::DELAY_CLASS_NUM-1:0]
                 [ppe_types_pkg::CAND_WINDOW_DEPTH-1:0]
                 [ppe_types_pkg::SEQ_W-1:0]                candidate_seq_tag_i,

    // Registered irrevocable selections indexed by destination FE. The
    // corresponding return-calendar reservation commits on the same edge on
    // which the Issue Table observes this D2B event.
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

    localparam int RETURN_SLOT_W =
        (RETURN_SLOT_NUM > 1) ? $clog2(RETURN_SLOT_NUM) : 1;
    localparam int CLASS_ID_W =
        (DELAY_CLASS_NUM > 1) ? $clog2(DELAY_CLASS_NUM) : 1;
    localparam int FE_ID_W =
        (FE_NUM > 1) ? $clog2(FE_NUM) : 1;
    localparam int GRANT_COUNT_W = $clog2(FE_NUM + 1);

    typedef logic [RETURN_SLOT_W-1:0] slot_id_t;
    typedef logic [CLASS_ID_W-1:0]    class_id_t;
    typedef logic [FE_ID_W-1:0]       fe_id_t;

    function automatic class_id_t next_class_id(input class_id_t current_id);
        begin
            if (int'(current_id) == (DELAY_CLASS_NUM - 1)) begin
                next_class_id = '0;
            end else begin
                next_class_id = class_id_t'(current_id + CLASS_ID_W'(1));
            end
        end
    endfunction

    function automatic fe_id_t next_fe_id(input fe_id_t current_id);
        begin
            if (int'(current_id) == (FE_NUM - 1)) begin
                next_fe_id = '0;
            end else begin
                next_fe_id = fe_id_t'(current_id + FE_ID_W'(1));
            end
        end
    endfunction

    function automatic slot_id_t next_slot_id(input slot_id_t current_id);
        begin
            if (int'(current_id) == (RETURN_SLOT_NUM - 1)) begin
                next_slot_id = '0;
            end else begin
                next_slot_id = slot_id_t'(
                    current_id + RETURN_SLOT_W'(1));
            end
        end
    endfunction

    // Explicit case selection keeps the calendar lookup as a fixed 8:1 mux
    // instead of a procedural variable array access in the D2A cone.
    function automatic logic calendar_slot_valid(
        input logic [RETURN_SLOT_NUM-1:0] slot_valid,
        input slot_id_t                   slot_id
    );
        begin
            case (slot_id)
                3'd0: calendar_slot_valid = slot_valid[0];
                3'd1: calendar_slot_valid = slot_valid[1];
                3'd2: calendar_slot_valid = slot_valid[2];
                3'd3: calendar_slot_valid = slot_valid[3];
                3'd4: calendar_slot_valid = slot_valid[4];
                3'd5: calendar_slot_valid = slot_valid[5];
                3'd6: calendar_slot_valid = slot_valid[6];
                3'd7: calendar_slot_valid = slot_valid[7];
                default: calendar_slot_valid = 1'b1;
            endcase
        end
    endfunction

    function automatic logic candidate_valid_at_rank(
        input logic [FE_NUM-1:0] candidates,
        input logic [GRANT_COUNT_W-1:0] rank
    );
        begin
            case (rank)
                3'd0: candidate_valid_at_rank = candidates[0];
                3'd1: candidate_valid_at_rank = candidates[1];
                3'd2: candidate_valid_at_rank = candidates[2];
                3'd3: candidate_valid_at_rank = candidates[3];
                default: candidate_valid_at_rank = 1'b0;
            endcase
        end
    endfunction

    function automatic seq_tag_t candidate_tag_at_rank(
        input logic [FE_NUM-1:0][SEQ_W-1:0] candidates,
        input logic [GRANT_COUNT_W-1:0]     rank
    );
        begin
            case (rank)
                3'd0: candidate_tag_at_rank = candidates[0];
                3'd1: candidate_tag_at_rank = candidates[1];
                3'd2: candidate_tag_at_rank = candidates[2];
                3'd3: candidate_tag_at_rank = candidates[3];
                default: candidate_tag_at_rank = '0;
            endcase
        end
    endfunction

    //--------------------------------------------------------------------------
    // Return-calendar, schedule-phase, and fairness state
    //--------------------------------------------------------------------------

    logic [FE_NUM-1:0][RETURN_SLOT_NUM-1:0] return_slot_valid_q;
    logic [FE_NUM-1:0][RETURN_SLOT_NUM-1:0][SEQ_W-1:0]
          return_slot_seq_tag_q;

    slot_id_t  schedule_phase_q;
    class_id_t class_rr_ptr_q;
    fe_id_t    fe_rr_ptr_q;

    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0] fe_legal;
    logic [DELAY_CLASS_NUM-1:0][RETURN_SLOT_W-1:0]
          target_slot_by_class;
    logic [DELAY_CLASS_NUM-1:0][GRANT_COUNT_W-1:0]
          pending_count_by_class;

    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0]
          visible_candidate_valid;
    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0][SEQ_W-1:0]
          visible_candidate_seq_tag;
    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0]
          normalized_candidate_valid;
    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0][SEQ_W-1:0]
          normalized_candidate_seq_tag;
    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0]
          class_rotated_fe_legal;
    logic [DELAY_CLASS_NUM-1:0][FE_NUM-1:0]
          normalized_fe_legal;
    class_id_t normalized_physical_class [DELAY_CLASS_NUM-1:0];
    slot_id_t  normalized_target_slot [DELAY_CLASS_NUM-1:0];

    logic [FE_NUM-1:0][DELAY_CLASS_NUM-1:0] normalized_request;
    logic [FE_NUM-1:0][DELAY_CLASS_NUM-1:0] normalized_nomination;
    logic [FE_NUM-1:0][DELAY_CLASS_NUM-1:0] normalized_accept;
    logic [FE_NUM-1:0][DELAY_CLASS_NUM-1:0][GRANT_COUNT_W-1:0]
          nomination_rank;
    logic [FE_NUM-1:0][DELAY_CLASS_NUM-1:0][SEQ_W-1:0]
          nominated_seq_tag;

    logic [FE_NUM-1:0]                    normalized_grant_valid;
    logic [FE_NUM-1:0][SEQ_W-1:0]         normalized_grant_seq_tag;
    logic [FE_NUM-1:0][CLASS_ID_W-1:0]    normalized_grant_class;
    logic [FE_NUM-1:0][RETURN_SLOT_W-1:0] normalized_grant_target_slot;

    logic [FE_NUM-1:0]                    grant_valid_q;
    logic [FE_NUM-1:0][SEQ_W-1:0]         grant_seq_tag_q;
    logic [FE_NUM-1:0][CLASS_ID_W-1:0]    grant_class_q;
    logic [FE_NUM-1:0][RETURN_SLOT_W-1:0] grant_target_slot_q;

    logic [FE_NUM-1:0]                    grant_valid_d;
    logic [FE_NUM-1:0][SEQ_W-1:0]         grant_seq_tag_d;
    logic [FE_NUM-1:0][CLASS_ID_W-1:0]    grant_class_d;
    logic [FE_NUM-1:0][RETURN_SLOT_W-1:0] grant_target_slot_d;
    logic                                 grant_any_d;
    class_id_t                            class_rr_next_d;
    fe_id_t                               fe_rr_next_d;

    // D2B presents only registered D2A decisions to the Issue Table.
    always_comb begin : d2b_select_output
        select_valid_o   = grant_valid_q;
        select_seq_tag_o = grant_seq_tag_q;
    end

    always_comb begin : return_slot_legality
        slot_id_t predicted_commit_phase;

        target_slot_by_class = '0;
        pending_count_by_class = '0;
        predicted_commit_phase = next_slot_id(schedule_phase_q);

        target_slot_by_class[0] = slot_id_t'(predicted_commit_phase + 3'd2);
        target_slot_by_class[1] = slot_id_t'(predicted_commit_phase + 3'd3);
        target_slot_by_class[2] = slot_id_t'(predicted_commit_phase + 3'd4);
        target_slot_by_class[3] = slot_id_t'(predicted_commit_phase + 3'd5);

        pending_count_by_class[0] =
            GRANT_COUNT_W'(grant_valid_q[0] && (grant_class_q[0] == 2'd0))
            + GRANT_COUNT_W'(grant_valid_q[1] && (grant_class_q[1] == 2'd0))
            + GRANT_COUNT_W'(grant_valid_q[2] && (grant_class_q[2] == 2'd0))
            + GRANT_COUNT_W'(grant_valid_q[3] && (grant_class_q[3] == 2'd0));
        pending_count_by_class[1] =
            GRANT_COUNT_W'(grant_valid_q[0] && (grant_class_q[0] == 2'd1))
            + GRANT_COUNT_W'(grant_valid_q[1] && (grant_class_q[1] == 2'd1))
            + GRANT_COUNT_W'(grant_valid_q[2] && (grant_class_q[2] == 2'd1))
            + GRANT_COUNT_W'(grant_valid_q[3] && (grant_class_q[3] == 2'd1));
        pending_count_by_class[2] =
            GRANT_COUNT_W'(grant_valid_q[0] && (grant_class_q[0] == 2'd2))
            + GRANT_COUNT_W'(grant_valid_q[1] && (grant_class_q[1] == 2'd2))
            + GRANT_COUNT_W'(grant_valid_q[2] && (grant_class_q[2] == 2'd2))
            + GRANT_COUNT_W'(grant_valid_q[3] && (grant_class_q[3] == 2'd2));
        pending_count_by_class[3] =
            GRANT_COUNT_W'(grant_valid_q[0] && (grant_class_q[0] == 2'd3))
            + GRANT_COUNT_W'(grant_valid_q[1] && (grant_class_q[1] == 2'd3))
            + GRANT_COUNT_W'(grant_valid_q[2] && (grant_class_q[2] == 2'd3))
            + GRANT_COUNT_W'(grant_valid_q[3] && (grant_class_q[3] == 2'd3));

    end

    // Each generated bit has constant class and FE indices. A compare against
    // the pending slot replaces the previous variable-index bitmap write.
    generate
        for (genvar legal_class = 0;
             legal_class < DELAY_CLASS_NUM;
             legal_class++) begin : class_legality
            for (genvar legal_fe = 0;
                 legal_fe < FE_NUM;
                 legal_fe++) begin : fe_legality
                always_comb begin
                    fe_legal[legal_class][legal_fe] =
                        !calendar_slot_valid(
                            return_slot_valid_q[legal_fe],
                            target_slot_by_class[legal_class])
                        && !(grant_valid_q[legal_fe]
                             && (grant_target_slot_q[legal_fe]
                                 == target_slot_by_class[legal_class]));
                end
            end
        end
    endgenerate

    //--------------------------------------------------------------------------
    // Candidate legality and multi-grant matching
    //--------------------------------------------------------------------------

    // Explicit five-way shifts remove the pending-prefix variable index from
    // candidate selection. Only four candidates beyond the prefix can be used.
    always_comb begin : pending_prefix_shift
        visible_candidate_valid   = '0;
        visible_candidate_seq_tag = '0;

        case (pending_count_by_class[0])
            3'd0: begin visible_candidate_valid[0] = candidate_valid_i[0][3:0]; visible_candidate_seq_tag[0] = candidate_seq_tag_i[0][3:0]; end
            3'd1: begin visible_candidate_valid[0] = candidate_valid_i[0][4:1]; visible_candidate_seq_tag[0] = candidate_seq_tag_i[0][4:1]; end
            3'd2: begin visible_candidate_valid[0] = candidate_valid_i[0][5:2]; visible_candidate_seq_tag[0] = candidate_seq_tag_i[0][5:2]; end
            3'd3: begin visible_candidate_valid[0] = candidate_valid_i[0][6:3]; visible_candidate_seq_tag[0] = candidate_seq_tag_i[0][6:3]; end
            3'd4: begin visible_candidate_valid[0] = candidate_valid_i[0][7:4]; visible_candidate_seq_tag[0] = candidate_seq_tag_i[0][7:4]; end
            default: begin visible_candidate_valid[0] = '0; visible_candidate_seq_tag[0] = '0; end
        endcase
        case (pending_count_by_class[1])
            3'd0: begin visible_candidate_valid[1] = candidate_valid_i[1][3:0]; visible_candidate_seq_tag[1] = candidate_seq_tag_i[1][3:0]; end
            3'd1: begin visible_candidate_valid[1] = candidate_valid_i[1][4:1]; visible_candidate_seq_tag[1] = candidate_seq_tag_i[1][4:1]; end
            3'd2: begin visible_candidate_valid[1] = candidate_valid_i[1][5:2]; visible_candidate_seq_tag[1] = candidate_seq_tag_i[1][5:2]; end
            3'd3: begin visible_candidate_valid[1] = candidate_valid_i[1][6:3]; visible_candidate_seq_tag[1] = candidate_seq_tag_i[1][6:3]; end
            3'd4: begin visible_candidate_valid[1] = candidate_valid_i[1][7:4]; visible_candidate_seq_tag[1] = candidate_seq_tag_i[1][7:4]; end
            default: begin visible_candidate_valid[1] = '0; visible_candidate_seq_tag[1] = '0; end
        endcase
        case (pending_count_by_class[2])
            3'd0: begin visible_candidate_valid[2] = candidate_valid_i[2][3:0]; visible_candidate_seq_tag[2] = candidate_seq_tag_i[2][3:0]; end
            3'd1: begin visible_candidate_valid[2] = candidate_valid_i[2][4:1]; visible_candidate_seq_tag[2] = candidate_seq_tag_i[2][4:1]; end
            3'd2: begin visible_candidate_valid[2] = candidate_valid_i[2][5:2]; visible_candidate_seq_tag[2] = candidate_seq_tag_i[2][5:2]; end
            3'd3: begin visible_candidate_valid[2] = candidate_valid_i[2][6:3]; visible_candidate_seq_tag[2] = candidate_seq_tag_i[2][6:3]; end
            3'd4: begin visible_candidate_valid[2] = candidate_valid_i[2][7:4]; visible_candidate_seq_tag[2] = candidate_seq_tag_i[2][7:4]; end
            default: begin visible_candidate_valid[2] = '0; visible_candidate_seq_tag[2] = '0; end
        endcase
        case (pending_count_by_class[3])
            3'd0: begin visible_candidate_valid[3] = candidate_valid_i[3][3:0]; visible_candidate_seq_tag[3] = candidate_seq_tag_i[3][3:0]; end
            3'd1: begin visible_candidate_valid[3] = candidate_valid_i[3][4:1]; visible_candidate_seq_tag[3] = candidate_seq_tag_i[3][4:1]; end
            3'd2: begin visible_candidate_valid[3] = candidate_valid_i[3][5:2]; visible_candidate_seq_tag[3] = candidate_seq_tag_i[3][5:2]; end
            3'd3: begin visible_candidate_valid[3] = candidate_valid_i[3][6:3]; visible_candidate_seq_tag[3] = candidate_seq_tag_i[3][6:3]; end
            3'd4: begin visible_candidate_valid[3] = candidate_valid_i[3][7:4]; visible_candidate_seq_tag[3] = candidate_seq_tag_i[3][7:4]; end
            default: begin visible_candidate_valid[3] = '0; visible_candidate_seq_tag[3] = '0; end
        endcase
    end

    // Rotate class and FE dimensions at the network boundary. The core below
    // therefore contains only constant-index wiring and fixed priority gates.
    always_comb begin : rr_normalization
        normalized_candidate_valid   = '0;
        normalized_candidate_seq_tag = '0;
        class_rotated_fe_legal        = '0;
        normalized_fe_legal           = '0;

        case (class_rr_ptr_q)
            2'd0: begin
                normalized_candidate_valid = visible_candidate_valid;
                normalized_candidate_seq_tag = visible_candidate_seq_tag;
                class_rotated_fe_legal = fe_legal;
                normalized_physical_class[0] = 2'd0; normalized_physical_class[1] = 2'd1; normalized_physical_class[2] = 2'd2; normalized_physical_class[3] = 2'd3;
                normalized_target_slot[0] = target_slot_by_class[0]; normalized_target_slot[1] = target_slot_by_class[1]; normalized_target_slot[2] = target_slot_by_class[2]; normalized_target_slot[3] = target_slot_by_class[3];
            end
            2'd1: begin
                normalized_candidate_valid[0] = visible_candidate_valid[1]; normalized_candidate_valid[1] = visible_candidate_valid[2]; normalized_candidate_valid[2] = visible_candidate_valid[3]; normalized_candidate_valid[3] = visible_candidate_valid[0];
                normalized_candidate_seq_tag[0] = visible_candidate_seq_tag[1]; normalized_candidate_seq_tag[1] = visible_candidate_seq_tag[2]; normalized_candidate_seq_tag[2] = visible_candidate_seq_tag[3]; normalized_candidate_seq_tag[3] = visible_candidate_seq_tag[0];
                class_rotated_fe_legal[0] = fe_legal[1]; class_rotated_fe_legal[1] = fe_legal[2]; class_rotated_fe_legal[2] = fe_legal[3]; class_rotated_fe_legal[3] = fe_legal[0];
                normalized_physical_class[0] = 2'd1; normalized_physical_class[1] = 2'd2; normalized_physical_class[2] = 2'd3; normalized_physical_class[3] = 2'd0;
                normalized_target_slot[0] = target_slot_by_class[1]; normalized_target_slot[1] = target_slot_by_class[2]; normalized_target_slot[2] = target_slot_by_class[3]; normalized_target_slot[3] = target_slot_by_class[0];
            end
            2'd2: begin
                normalized_candidate_valid[0] = visible_candidate_valid[2]; normalized_candidate_valid[1] = visible_candidate_valid[3]; normalized_candidate_valid[2] = visible_candidate_valid[0]; normalized_candidate_valid[3] = visible_candidate_valid[1];
                normalized_candidate_seq_tag[0] = visible_candidate_seq_tag[2]; normalized_candidate_seq_tag[1] = visible_candidate_seq_tag[3]; normalized_candidate_seq_tag[2] = visible_candidate_seq_tag[0]; normalized_candidate_seq_tag[3] = visible_candidate_seq_tag[1];
                class_rotated_fe_legal[0] = fe_legal[2]; class_rotated_fe_legal[1] = fe_legal[3]; class_rotated_fe_legal[2] = fe_legal[0]; class_rotated_fe_legal[3] = fe_legal[1];
                normalized_physical_class[0] = 2'd2; normalized_physical_class[1] = 2'd3; normalized_physical_class[2] = 2'd0; normalized_physical_class[3] = 2'd1;
                normalized_target_slot[0] = target_slot_by_class[2]; normalized_target_slot[1] = target_slot_by_class[3]; normalized_target_slot[2] = target_slot_by_class[0]; normalized_target_slot[3] = target_slot_by_class[1];
            end
            default: begin
                normalized_candidate_valid[0] = visible_candidate_valid[3]; normalized_candidate_valid[1] = visible_candidate_valid[0]; normalized_candidate_valid[2] = visible_candidate_valid[1]; normalized_candidate_valid[3] = visible_candidate_valid[2];
                normalized_candidate_seq_tag[0] = visible_candidate_seq_tag[3]; normalized_candidate_seq_tag[1] = visible_candidate_seq_tag[0]; normalized_candidate_seq_tag[2] = visible_candidate_seq_tag[1]; normalized_candidate_seq_tag[3] = visible_candidate_seq_tag[2];
                class_rotated_fe_legal[0] = fe_legal[3]; class_rotated_fe_legal[1] = fe_legal[0]; class_rotated_fe_legal[2] = fe_legal[1]; class_rotated_fe_legal[3] = fe_legal[2];
                normalized_physical_class[0] = 2'd3; normalized_physical_class[1] = 2'd0; normalized_physical_class[2] = 2'd1; normalized_physical_class[3] = 2'd2;
                normalized_target_slot[0] = target_slot_by_class[3]; normalized_target_slot[1] = target_slot_by_class[0]; normalized_target_slot[2] = target_slot_by_class[1]; normalized_target_slot[3] = target_slot_by_class[2];
            end
        endcase

        case (fe_rr_ptr_q)
            2'd0: normalized_fe_legal = class_rotated_fe_legal;
            2'd1: begin
                normalized_fe_legal[0] = {class_rotated_fe_legal[0][0], class_rotated_fe_legal[0][3:1]};
                normalized_fe_legal[1] = {class_rotated_fe_legal[1][0], class_rotated_fe_legal[1][3:1]};
                normalized_fe_legal[2] = {class_rotated_fe_legal[2][0], class_rotated_fe_legal[2][3:1]};
                normalized_fe_legal[3] = {class_rotated_fe_legal[3][0], class_rotated_fe_legal[3][3:1]};
            end
            2'd2: begin
                normalized_fe_legal[0] = {class_rotated_fe_legal[0][1:0], class_rotated_fe_legal[0][3:2]};
                normalized_fe_legal[1] = {class_rotated_fe_legal[1][1:0], class_rotated_fe_legal[1][3:2]};
                normalized_fe_legal[2] = {class_rotated_fe_legal[2][1:0], class_rotated_fe_legal[2][3:2]};
                normalized_fe_legal[3] = {class_rotated_fe_legal[3][1:0], class_rotated_fe_legal[3][3:2]};
            end
            default: begin
                normalized_fe_legal[0] = {class_rotated_fe_legal[0][2:0], class_rotated_fe_legal[0][3]};
                normalized_fe_legal[1] = {class_rotated_fe_legal[1][2:0], class_rotated_fe_legal[1][3]};
                normalized_fe_legal[2] = {class_rotated_fe_legal[2][2:0], class_rotated_fe_legal[2][3]};
                normalized_fe_legal[3] = {class_rotated_fe_legal[3][2:0], class_rotated_fe_legal[3][3]};
            end
        endcase
    end

    always_comb begin : fixed_request_nomination
        normalized_nomination = '0;

        normalized_nomination[0][0] = normalized_request[0][0];
        normalized_nomination[0][1] = !normalized_request[0][0] && normalized_request[0][1];
        normalized_nomination[0][2] = !(|normalized_request[0][1:0]) && normalized_request[0][2];
        normalized_nomination[0][3] = !(|normalized_request[0][2:0]) && normalized_request[0][3];

        normalized_nomination[1][1] = normalized_request[1][1];
        normalized_nomination[1][2] = !normalized_request[1][1] && normalized_request[1][2];
        normalized_nomination[1][3] = !(|normalized_request[1][2:1]) && normalized_request[1][3];
        normalized_nomination[1][0] = !(|normalized_request[1][3:1]) && normalized_request[1][0];

        normalized_nomination[2][2] = normalized_request[2][2];
        normalized_nomination[2][3] = !normalized_request[2][2] && normalized_request[2][3];
        normalized_nomination[2][0] = !(normalized_request[2][2] || normalized_request[2][3]) && normalized_request[2][0];
        normalized_nomination[2][1] = !(normalized_request[2][2] || normalized_request[2][3] || normalized_request[2][0]) && normalized_request[2][1];

        normalized_nomination[3][3] = normalized_request[3][3];
        normalized_nomination[3][0] = !normalized_request[3][3] && normalized_request[3][0];
        normalized_nomination[3][1] = !(normalized_request[3][3] || normalized_request[3][0]) && normalized_request[3][1];
        normalized_nomination[3][2] = !(normalized_request[3][3] || normalized_request[3][0] || normalized_request[3][1]) && normalized_request[3][2];
    end

    generate
        for (genvar request_fe = 0;
             request_fe < FE_NUM;
             request_fe++) begin : fe_request
            for (genvar request_class = 0;
                 request_class < DELAY_CLASS_NUM;
                 request_class++) begin : class_request
                always_comb begin
                    normalized_request[request_fe][request_class] =
                        normalized_candidate_valid[request_class][0]
                        && normalized_fe_legal[request_class][request_fe];
                end
            end
        end
    endgenerate

    generate
        for (genvar class_gen = 0; class_gen < DELAY_CLASS_NUM; class_gen++) begin : class_rank_network
            always_comb begin
                nomination_rank[0][class_gen] = '0;
                nomination_rank[1][class_gen] = GRANT_COUNT_W'(normalized_nomination[0][class_gen]);
                nomination_rank[2][class_gen] = GRANT_COUNT_W'(normalized_nomination[0][class_gen]) + GRANT_COUNT_W'(normalized_nomination[1][class_gen]);
                nomination_rank[3][class_gen] = GRANT_COUNT_W'(normalized_nomination[0][class_gen]) + GRANT_COUNT_W'(normalized_nomination[1][class_gen]) + GRANT_COUNT_W'(normalized_nomination[2][class_gen]);

                normalized_accept[0][class_gen] =
                    normalized_nomination[0][class_gen]
                    && candidate_valid_at_rank(
                        normalized_candidate_valid[class_gen],
                        nomination_rank[0][class_gen]);
                normalized_accept[1][class_gen] =
                    normalized_nomination[1][class_gen]
                    && candidate_valid_at_rank(
                        normalized_candidate_valid[class_gen],
                        nomination_rank[1][class_gen]);
                normalized_accept[2][class_gen] =
                    normalized_nomination[2][class_gen]
                    && candidate_valid_at_rank(
                        normalized_candidate_valid[class_gen],
                        nomination_rank[2][class_gen]);
                normalized_accept[3][class_gen] =
                    normalized_nomination[3][class_gen]
                    && candidate_valid_at_rank(
                        normalized_candidate_valid[class_gen],
                        nomination_rank[3][class_gen]);

                nominated_seq_tag[0][class_gen] =
                    candidate_tag_at_rank(
                        normalized_candidate_seq_tag[class_gen],
                        nomination_rank[0][class_gen]);
                nominated_seq_tag[1][class_gen] =
                    candidate_tag_at_rank(
                        normalized_candidate_seq_tag[class_gen],
                        nomination_rank[1][class_gen]);
                nominated_seq_tag[2][class_gen] =
                    candidate_tag_at_rank(
                        normalized_candidate_seq_tag[class_gen],
                        nomination_rank[2][class_gen]);
                nominated_seq_tag[3][class_gen] =
                    candidate_tag_at_rank(
                        normalized_candidate_seq_tag[class_gen],
                        nomination_rank[3][class_gen]);
            end
        end
    endgenerate

    generate
        for (genvar fe_gen = 0; fe_gen < FE_NUM; fe_gen++) begin : normalized_grant_encode
            always_comb begin
                normalized_grant_valid[fe_gen]       = 1'b0;
                normalized_grant_seq_tag[fe_gen]     = '0;
                normalized_grant_class[fe_gen]       = '0;
                normalized_grant_target_slot[fe_gen] = '0;

                case (1'b1)
                    normalized_accept[fe_gen][0]: begin
                        normalized_grant_valid[fe_gen]       = 1'b1;
                        normalized_grant_seq_tag[fe_gen]     = nominated_seq_tag[fe_gen][0];
                        normalized_grant_class[fe_gen]       = normalized_physical_class[0];
                        normalized_grant_target_slot[fe_gen] = normalized_target_slot[0];
                    end
                    normalized_accept[fe_gen][1]: begin
                        normalized_grant_valid[fe_gen]       = 1'b1;
                        normalized_grant_seq_tag[fe_gen]     = nominated_seq_tag[fe_gen][1];
                        normalized_grant_class[fe_gen]       = normalized_physical_class[1];
                        normalized_grant_target_slot[fe_gen] = normalized_target_slot[1];
                    end
                    normalized_accept[fe_gen][2]: begin
                        normalized_grant_valid[fe_gen]       = 1'b1;
                        normalized_grant_seq_tag[fe_gen]     = nominated_seq_tag[fe_gen][2];
                        normalized_grant_class[fe_gen]       = normalized_physical_class[2];
                        normalized_grant_target_slot[fe_gen] = normalized_target_slot[2];
                    end
                    normalized_accept[fe_gen][3]: begin
                        normalized_grant_valid[fe_gen]       = 1'b1;
                        normalized_grant_seq_tag[fe_gen]     = nominated_seq_tag[fe_gen][3];
                        normalized_grant_class[fe_gen]       = normalized_physical_class[3];
                        normalized_grant_target_slot[fe_gen] = normalized_target_slot[3];
                    end
                    default: begin end
                endcase
            end
        end
    endgenerate

    always_comb begin : grant_denormalization
        grant_valid_d       = '0;
        grant_seq_tag_d     = '0;
        grant_class_d       = '0;
        grant_target_slot_d = '0;

        case (fe_rr_ptr_q)
            2'd0: begin
                grant_valid_d = normalized_grant_valid; grant_seq_tag_d = normalized_grant_seq_tag; grant_class_d = normalized_grant_class; grant_target_slot_d = normalized_grant_target_slot;
            end
            2'd1: begin
                grant_valid_d[1] = normalized_grant_valid[0]; grant_valid_d[2] = normalized_grant_valid[1]; grant_valid_d[3] = normalized_grant_valid[2]; grant_valid_d[0] = normalized_grant_valid[3];
                grant_seq_tag_d[1] = normalized_grant_seq_tag[0]; grant_seq_tag_d[2] = normalized_grant_seq_tag[1]; grant_seq_tag_d[3] = normalized_grant_seq_tag[2]; grant_seq_tag_d[0] = normalized_grant_seq_tag[3];
                grant_class_d[1] = normalized_grant_class[0]; grant_class_d[2] = normalized_grant_class[1]; grant_class_d[3] = normalized_grant_class[2]; grant_class_d[0] = normalized_grant_class[3];
                grant_target_slot_d[1] = normalized_grant_target_slot[0]; grant_target_slot_d[2] = normalized_grant_target_slot[1]; grant_target_slot_d[3] = normalized_grant_target_slot[2]; grant_target_slot_d[0] = normalized_grant_target_slot[3];
            end
            2'd2: begin
                grant_valid_d[2] = normalized_grant_valid[0]; grant_valid_d[3] = normalized_grant_valid[1]; grant_valid_d[0] = normalized_grant_valid[2]; grant_valid_d[1] = normalized_grant_valid[3];
                grant_seq_tag_d[2] = normalized_grant_seq_tag[0]; grant_seq_tag_d[3] = normalized_grant_seq_tag[1]; grant_seq_tag_d[0] = normalized_grant_seq_tag[2]; grant_seq_tag_d[1] = normalized_grant_seq_tag[3];
                grant_class_d[2] = normalized_grant_class[0]; grant_class_d[3] = normalized_grant_class[1]; grant_class_d[0] = normalized_grant_class[2]; grant_class_d[1] = normalized_grant_class[3];
                grant_target_slot_d[2] = normalized_grant_target_slot[0]; grant_target_slot_d[3] = normalized_grant_target_slot[1]; grant_target_slot_d[0] = normalized_grant_target_slot[2]; grant_target_slot_d[1] = normalized_grant_target_slot[3];
            end
            default: begin
                grant_valid_d[3] = normalized_grant_valid[0]; grant_valid_d[0] = normalized_grant_valid[1]; grant_valid_d[1] = normalized_grant_valid[2]; grant_valid_d[2] = normalized_grant_valid[3];
                grant_seq_tag_d[3] = normalized_grant_seq_tag[0]; grant_seq_tag_d[0] = normalized_grant_seq_tag[1]; grant_seq_tag_d[1] = normalized_grant_seq_tag[2]; grant_seq_tag_d[2] = normalized_grant_seq_tag[3];
                grant_class_d[3] = normalized_grant_class[0]; grant_class_d[0] = normalized_grant_class[1]; grant_class_d[1] = normalized_grant_class[2]; grant_class_d[2] = normalized_grant_class[3];
                grant_target_slot_d[3] = normalized_grant_target_slot[0]; grant_target_slot_d[0] = normalized_grant_target_slot[1]; grant_target_slot_d[1] = normalized_grant_target_slot[2]; grant_target_slot_d[2] = normalized_grant_target_slot[3];
            end
        endcase

        grant_any_d     = |grant_valid_d;
        class_rr_next_d = next_class_id(class_rr_ptr_q);
        fe_rr_next_d    = next_fe_id(fe_rr_ptr_q);
    end

    //--------------------------------------------------------------------------
    // D2A grant capture, D2B reservation, and fairness update
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin : grant_pipeline_update
        if (!rst_ni) begin
            grant_valid_q <= '0;
        end else begin
            grant_valid_q <= grant_valid_d;

            for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                if (grant_valid_d[fe_idx]) begin
                    grant_seq_tag_q[fe_idx] <= grant_seq_tag_d[fe_idx];
                    grant_class_q[fe_idx] <= grant_class_d[fe_idx];
                    grant_target_slot_q[fe_idx] <=
                        grant_target_slot_d[fe_idx];
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : return_calendar_update
        if (!rst_ni) begin
            return_slot_valid_q <= '0;
        end else begin
            // Consume the current calendar slot. Protocol mismatches are
            // verification errors and do not create a replay path.
            for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                if (return_slot_valid_q[fe_idx][schedule_phase_q]) begin
                    return_slot_valid_q[fe_idx][schedule_phase_q] <= 1'b0;
                end
            end

            // The registered D2B selection and reservation are one event.
            for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
                if (grant_valid_q[fe_idx]) begin
                    return_slot_valid_q[fe_idx]
                                       [grant_target_slot_q[fe_idx]] <= 1'b1;
                    return_slot_seq_tag_q[fe_idx]
                                         [grant_target_slot_q[fe_idx]] <=
                        grant_seq_tag_q[fe_idx];
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : scheduler_control_update
        if (!rst_ni) begin
            schedule_phase_q <= '0;
            class_rr_ptr_q   <= '0;
            fe_rr_ptr_q      <= '0;
        end else begin
            schedule_phase_q <= next_slot_id(schedule_phase_q);

            if (grant_any_d) begin
                class_rr_ptr_q <= class_rr_next_d;
                fe_rr_ptr_q    <= fe_rr_next_d;
            end
        end
    end

    //--------------------------------------------------------------------------
    // FE return association and calendar advancement
    //--------------------------------------------------------------------------

    always_comb begin : completion_association
        completion_valid_o      = '0;
        completion_seq_tag_o    = '0;

        for (int fe_idx = 0; fe_idx < FE_NUM; fe_idx++) begin
            if (fe_out_valid_i[fe_idx]
                && return_slot_valid_q[fe_idx][schedule_phase_q]) begin
                completion_valid_o[fe_idx] = 1'b1;
                completion_seq_tag_o[fe_idx] =
                    return_slot_seq_tag_q[fe_idx][schedule_phase_q];
            end
        end
    end

endmodule : ppe_fe_scheduler

`default_nettype wire
