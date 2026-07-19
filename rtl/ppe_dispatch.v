`timescale 1ns/1ps

// Front half of the PPE pipeline.
//
// D0: accept up to four input lanes, assign consecutive sequence tags, and
//     create dispatch/ROB entries.
// D2: choose up to four ready packets and FEs whose future return slots are
//     free, then register one launch per chosen FE.
// D3: read packet/dependency data and issue the registered launches to the FEs.
//
// Dependencies normally hit the local eight-bank fast cache.  A cache miss is
// sent through the single fallback port to reorder, which owns the authoritative
// ROB and retired-result storage.
module ppe_dispatch #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,
    input                       bkps,

    // Four independent ingress lanes.  desc[4:2] is dependency distance and
    // desc[1:0] is FE delay.
    input                       in_valid0,
    input      [PACKET_W-1:0]   in_packet0,
    input      [4:0]            in_desc0,
    input                       in_valid1,
    input      [PACKET_W-1:0]   in_packet1,
    input      [4:0]            in_desc1,
    input                       in_valid2,
    input      [PACKET_W-1:0]   in_packet2,
    input      [4:0]            in_desc2,
    input                       in_valid3,
    input      [PACKET_W-1:0]   in_packet3,
    input      [4:0]            in_desc3,

    // D0 allocation request/response.  Reorder returns each new ROB ID
    // combinationally from its current tail pointer.
    output                      alloc_valid0,
    output     [4:0]            alloc_seq_tag0,
    output     [2:0]            alloc_seq_residue0,
    input      [3:0]            alloc_rob_id0,
    output                      alloc_valid1,
    output     [4:0]            alloc_seq_tag1,
    output     [2:0]            alloc_seq_residue1,
    input      [3:0]            alloc_rob_id1,
    output                      alloc_valid2,
    output     [4:0]            alloc_seq_tag2,
    output     [2:0]            alloc_seq_residue2,
    input      [3:0]            alloc_rob_id2,
    output                      alloc_valid3,
    output     [4:0]            alloc_seq_tag3,
    output     [2:0]            alloc_seq_residue3,
    input      [3:0]            alloc_rob_id3,

    // One authoritative dependency lookup shared by all waiting packets.
    output                      fallback_valid,
    output     [3:0]            fallback_rob_id,
    output     [4:0]            fallback_seq_tag,
    output     [2:0]            fallback_residue,
    input                       fallback_ready,
    input      [PACKET_W-1:0]   fallback_data,

    // Per-FE request and response signals.  FE responses are untagged, so the
    // return calendar below supplies their ROB identity.
    output                      fe_in_valid0,
    output     [PACKET_W-1:0]   fe_in_data0,
    output                      fe_dep_valid0,
    output     [PACKET_W-1:0]   fe_dep_data0,
    output     [1:0]            fe_desc_delay0,
    input                       fe_out_valid0,
    input      [PACKET_W-1:0]   fe_out_data0,
    output                      fe_in_valid1,
    output     [PACKET_W-1:0]   fe_in_data1,
    output                      fe_dep_valid1,
    output     [PACKET_W-1:0]   fe_dep_data1,
    output     [1:0]            fe_desc_delay1,
    input                       fe_out_valid1,
    input      [PACKET_W-1:0]   fe_out_data1,
    output                      fe_in_valid2,
    output     [PACKET_W-1:0]   fe_in_data2,
    output                      fe_dep_valid2,
    output     [PACKET_W-1:0]   fe_dep_data2,
    output     [1:0]            fe_desc_delay2,
    input                       fe_out_valid2,
    input      [PACKET_W-1:0]   fe_out_data2,
    output                      fe_in_valid3,
    output     [PACKET_W-1:0]   fe_in_data3,
    output                      fe_dep_valid3,
    output     [PACKET_W-1:0]   fe_dep_data3,
    output     [1:0]            fe_desc_delay3,
    input                       fe_out_valid3,
    input      [PACKET_W-1:0]   fe_out_data3,

    // Tagged FE completion events sent to reorder and also used locally to
    // refresh the dependency cache and wake waiting entries.
    output                      wb_valid0,
    output     [3:0]            wb_rob_id0,
    output     [4:0]            wb_seq_tag0,
    output     [PACKET_W-1:0]   wb_data0,
    output                      wb_valid1,
    output     [3:0]            wb_rob_id1,
    output     [4:0]            wb_seq_tag1,
    output     [PACKET_W-1:0]   wb_data1,
    output                      wb_valid2,
    output     [3:0]            wb_rob_id2,
    output     [4:0]            wb_seq_tag2,
    output     [PACKET_W-1:0]   wb_data2,
    output                      wb_valid3,
    output     [3:0]            wb_rob_id3,
    output     [4:0]            wb_seq_tag3,
    output     [PACKET_W-1:0]   wb_data3
);

    // One state field carries validity, dependency readiness, and reservation.
    // This avoids contradictory combinations such as valid=0 and selected=1.
    // Typical paths are:
    //   no dependency: FREE -> READY_NODEP -> SELECTED_NODEP -> FREE
    //   cache hit:      FREE -> READY_DEP   -> SELECTED_DEP   -> FREE
    //   cache miss:     FALLBACK -> WAIT_DEP -> READY_DEP -> ...
    //   fallback hit:   FALLBACK/SELECTED_DEP -> REPLAY -> SELECTED_DEP -> FREE
    localparam [2:0] ST_FREE          = 3'd0;
    localparam [2:0] ST_FALLBACK      = 3'd1;
    localparam [2:0] ST_WAIT_DEP      = 3'd2;
    localparam [2:0] ST_READY_NODEP   = 3'd3;
    localparam [2:0] ST_READY_DEP     = 3'd4;
    localparam [2:0] ST_SELECTED_NODEP = 3'd5;
    localparam [2:0] ST_SELECTED_DEP  = 3'd6;
    localparam [2:0] ST_REPLAY        = 3'd7;

    // Dispatch table is indexed directly by ROB ID.  An entry is released as
    // soon as its request is accepted by an FE; reorder then owns its lifetime.
    reg [PACKET_W-1:0]        entry_packet [0:15];
    reg [4:0]                 entry_seq_tag [0:15];
    reg [1:0]                 entry_desc_delay [0:15];
    reg [4:0]                 entry_target_seq_tag [0:15];
    reg [2:0]                 entry_state [0:15];
    reg                       entry_queued [0:15];

    // Four delay-class FIFOs carry only dispatch IDs.  Packet and dependency
    // data remain in the table above, keeping the scheduling path narrow.
    // The first four positions of each class are its multi-grant head window.
    reg [3:0]                 ready_q_id [0:63];
    reg [4:0]                 ready_q_count [0:3];
    reg [3:0]                 ready_q_id_next [0:63];
    reg [4:0]                 ready_q_count_next [0:3];

    // Non-authoritative dependency cache.  Index is seq_tag[2:0], but a hit
    // always compares the complete five-bit tag to reject wrapped/old data.
    reg                       dep_cache_valid [0:7];
    reg [4:0]                 dep_cache_seq_tag [0:7];
    reg [PACKET_W-1:0]        dep_cache_data [0:7];

    // Separate discovery, delay-class, and FE round-robin pointers keep table
    // insertion and FE matching fair without rescanning packet data in D2.
    reg [4:0]                 next_seq_tag;
    reg [3:0]                 enqueue_rr_ptr;
    reg [1:0]                 class_rr_ptr;
    reg [1:0]                 fe_rr_ptr;
    reg                       fallback_class_rr;
    reg [1:0]                 fallback_fe_rr_ptr;
    reg [3:0]                 fallback_entry_rr_ptr;
    reg [2:0]                 schedule_phase;
    // Only one fallback result is buffered because reorder has one lookup port.
    // Replay gets scheduling priority and carries its authoritative wide data.
    reg                       replay_valid;
    reg [3:0]                 replay_rob_id;
    reg [PACKET_W-1:0]        replay_data;

    // D2-to-D3 launch registers.  A register can be consumed by D3 and refilled
    // by D2 on the same edge, so there is no forced bubble between requests.
    reg                       fe_launch_valid0;
    reg [3:0]                 fe_launch_rob_id0;
    reg [2:0]                 fe_launch_return_slot0;
    reg                       fe_launch_replay0;
    reg                       fe_launch_valid1;
    reg [3:0]                 fe_launch_rob_id1;
    reg [2:0]                 fe_launch_return_slot1;
    reg                       fe_launch_replay1;
    reg                       fe_launch_valid2;
    reg [3:0]                 fe_launch_rob_id2;
    reg [2:0]                 fe_launch_return_slot2;
    reg                       fe_launch_replay2;
    reg                       fe_launch_valid3;
    reg [3:0]                 fe_launch_rob_id3;
    reg [2:0]                 fe_launch_return_slot3;
    reg                       fe_launch_replay3;

    // Future-return calendar: index = {fe_id[1:0], slot[2:0]}.
    // schedule_phase names the slot returning now.  A booking stores the ROB ID
    // and full tag needed to associate a later untagged FE response.
    reg                       return_valid [0:31];
    reg [3:0]                 return_rob_id [0:31];
    reg [4:0]                 return_seq_tag [0:31];

    wire [2:0] lane_rank0;
    wire [2:0] lane_rank1;
    wire [2:0] lane_rank2;
    wire [2:0] lane_rank3;
    wire [2:0] accept_count;
    wire [2:0] dep_offset0 = in_desc0[4:2];
    wire [2:0] dep_offset1 = in_desc1[4:2];
    wire [2:0] dep_offset2 = in_desc2[4:2];
    wire [2:0] dep_offset3 = in_desc3[4:2];
    wire [4:0] alloc_target_seq_tag0;
    wire [4:0] alloc_target_seq_tag1;
    wire [4:0] alloc_target_seq_tag2;
    wire [4:0] alloc_target_seq_tag3;
    wire       alloc_dep_resolved0;
    wire       alloc_dep_resolved1;
    wire       alloc_dep_resolved2;
    wire       alloc_dep_resolved3;
    wire       d3_cache_hit0;
    wire       d3_cache_hit1;
    wire       d3_cache_hit2;
    wire       d3_cache_hit3;
    wire [PACKET_W-1:0] d3_cache_data0;
    wire [PACKET_W-1:0] d3_cache_data1;
    wire [PACKET_W-1:0] d3_cache_data2;
    wire [PACKET_W-1:0] d3_cache_data3;

    reg        fallback_valid_r;
    reg [3:0]  fallback_rob_id_r;
    reg [4:0]  fallback_seq_tag_r;
    reg [2:0]  fallback_residue_r;
    reg        fallback_from_d3;
    reg [1:0]  fallback_d3_fe_id;
    reg [3:0]  fallback_entry_id;
    reg        fallback_d3_any;
    reg        fallback_entry_any;
    reg [1:0]  fallback_d3_selected;
    reg [3:0]  fallback_entry_selected;
    reg        fallback_d3_found;
    reg        fallback_entry_found;
    integer    fallback_scan;
    integer    fallback_index;

    reg                       enqueue_valid [0:3];
    reg [3:0]                 enqueue_id [0:3];
    reg [1:0]                 enqueue_class [0:3];
    reg                       alloc_enqueued0;
    reg                       alloc_enqueued1;
    reg                       alloc_enqueued2;
    reg                       alloc_enqueued3;
    integer                   enqueue_count;
    reg [3:0]                 enqueue_last_id;
    integer                   enqueue_scan;
    reg [3:0]                 enqueue_scan_id;
    reg                       enqueue_scan_ready;

    integer d2_round;
    integer d2_class_scan;
    integer d2_fe_scan;
    integer d2_other_class;
    reg [1:0] d2_class_index;
    reg [1:0] d2_fe_index;
    reg [3:0] d2_fe_used;
    reg [2:0] d2_class_take [0:3];
    reg       d2_class_found;
    reg [1:0] d2_chosen_class;
    reg       d2_fe_found;
    reg [1:0] d2_chosen_fe;
    integer   d2_legal_count;
    integer   d2_best_contention;
    integer   d2_contention;
    reg [5:0] d2_queue_index;
    reg [4:0] d2_candidate_age;
    reg [4:0] d2_oldest_age;
    reg [2:0] d2_candidate_slot;
    reg [3:0] d2_candidate_rob_id;
    reg d2_select_valid0;
    reg [3:0] d2_select_rob_id0;
    reg [2:0] d2_select_return_slot0;
    reg       d2_select_replay0;
    reg d2_select_valid1;
    reg [3:0] d2_select_rob_id1;
    reg [2:0] d2_select_return_slot1;
    reg       d2_select_replay1;
    reg d2_select_valid2;
    reg [3:0] d2_select_rob_id2;
    reg [2:0] d2_select_return_slot2;
    reg       d2_select_replay2;
    reg d2_select_valid3;
    reg [3:0] d2_select_rob_id3;
    reg [2:0] d2_select_return_slot3;
    reg       d2_select_replay3;
    integer d2_select_count;
    integer d2_normal_count;
    reg [1:0] d2_last_class;
    reg [1:0] d2_last_fe_id;

    integer i;
    integer q_class;
    integer q_pos;
    integer q_base;
    integer q_remaining;
    integer q_append;

    // D0 lane rank gives each valid lane a consecutive sequence number while
    // preserving lane order.  Invalid lanes consume no sequence number.
    assign lane_rank0 = 3'd0;
    assign lane_rank1 = {2'b00, in_valid0};
    assign lane_rank2 = {2'b00, in_valid0} + {2'b00, in_valid1};
    assign lane_rank3 = {2'b00, in_valid0} + {2'b00, in_valid1} +
                        {2'b00, in_valid2};
    assign accept_count = {2'b00, in_valid0} + {2'b00, in_valid1} +
                          {2'b00, in_valid2} + {2'b00, in_valid3};

    // Admission is all-or-nothing for the input cycle.  Reorder computes bkps
    // from the raw input valids before these allocation valids are generated.
    assign alloc_valid0 = rst_n && !bkps && in_valid0;
    assign alloc_valid1 = rst_n && !bkps && in_valid1;
    assign alloc_valid2 = rst_n && !bkps && in_valid2;
    assign alloc_valid3 = rst_n && !bkps && in_valid3;
    assign alloc_seq_tag0 = next_seq_tag + {2'b00, lane_rank0};
    assign alloc_seq_tag1 = next_seq_tag + {2'b00, lane_rank1};
    assign alloc_seq_tag2 = next_seq_tag + {2'b00, lane_rank2};
    assign alloc_seq_tag3 = next_seq_tag + {2'b00, lane_rank3};
    // Continuous allocation establishes rob_id=seq_tag[3:0].  The dependency
    // cache bank and target ROB ID can therefore be derived from the target tag.
    assign alloc_seq_residue0 = alloc_seq_tag0[2:0];
    assign alloc_seq_residue1 = alloc_seq_tag1[2:0];
    assign alloc_seq_residue2 = alloc_seq_tag2[2:0];
    assign alloc_seq_residue3 = alloc_seq_tag3[2:0];
    assign alloc_target_seq_tag0 = alloc_seq_tag0 - {2'b00, dep_offset0};
    assign alloc_target_seq_tag1 = alloc_seq_tag1 - {2'b00, dep_offset1};
    assign alloc_target_seq_tag2 = alloc_seq_tag2 - {2'b00, dep_offset2};
    assign alloc_target_seq_tag3 = alloc_seq_tag3 - {2'b00, dep_offset3};

    // A new dependent packet may be satisfied by the old cache contents or by
    // an FE writeback occurring on this same edge.  The writeback comparisons
    // are the bypass that avoids an extra dependency-initialization stage.
    assign alloc_dep_resolved0 =
        (dep_cache_valid[alloc_target_seq_tag0[2:0]] &&
         (dep_cache_seq_tag[alloc_target_seq_tag0[2:0]] == alloc_target_seq_tag0)) ||
        (wb_valid0 && (wb_seq_tag0 == alloc_target_seq_tag0)) ||
        (wb_valid1 && (wb_seq_tag1 == alloc_target_seq_tag0)) ||
        (wb_valid2 && (wb_seq_tag2 == alloc_target_seq_tag0)) ||
        (wb_valid3 && (wb_seq_tag3 == alloc_target_seq_tag0));
    assign alloc_dep_resolved1 =
        (dep_cache_valid[alloc_target_seq_tag1[2:0]] &&
         (dep_cache_seq_tag[alloc_target_seq_tag1[2:0]] == alloc_target_seq_tag1)) ||
        (wb_valid0 && (wb_seq_tag0 == alloc_target_seq_tag1)) ||
        (wb_valid1 && (wb_seq_tag1 == alloc_target_seq_tag1)) ||
        (wb_valid2 && (wb_seq_tag2 == alloc_target_seq_tag1)) ||
        (wb_valid3 && (wb_seq_tag3 == alloc_target_seq_tag1));
    assign alloc_dep_resolved2 =
        (dep_cache_valid[alloc_target_seq_tag2[2:0]] &&
         (dep_cache_seq_tag[alloc_target_seq_tag2[2:0]] == alloc_target_seq_tag2)) ||
        (wb_valid0 && (wb_seq_tag0 == alloc_target_seq_tag2)) ||
        (wb_valid1 && (wb_seq_tag1 == alloc_target_seq_tag2)) ||
        (wb_valid2 && (wb_seq_tag2 == alloc_target_seq_tag2)) ||
        (wb_valid3 && (wb_seq_tag3 == alloc_target_seq_tag2));
    assign alloc_dep_resolved3 =
        (dep_cache_valid[alloc_target_seq_tag3[2:0]] &&
         (dep_cache_seq_tag[alloc_target_seq_tag3[2:0]] == alloc_target_seq_tag3)) ||
        (wb_valid0 && (wb_seq_tag0 == alloc_target_seq_tag3)) ||
        (wb_valid1 && (wb_seq_tag1 == alloc_target_seq_tag3)) ||
        (wb_valid2 && (wb_seq_tag2 == alloc_target_seq_tag3)) ||
        (wb_valid3 && (wb_seq_tag3 == alloc_target_seq_tag3));

    // D3 rechecks the cache because another FE may have overwritten the same
    // bank after D2 selected this packet.  A miss cancels issue and falls back.
    assign d3_cache_hit0 = fe_launch_valid0 && !fe_launch_replay0 &&
        (entry_state[fe_launch_rob_id0] == ST_SELECTED_DEP) &&
        dep_cache_valid[entry_target_seq_tag[fe_launch_rob_id0][2:0]] &&
        (dep_cache_seq_tag[entry_target_seq_tag[fe_launch_rob_id0][2:0]] ==
         entry_target_seq_tag[fe_launch_rob_id0]);
    assign d3_cache_hit1 = fe_launch_valid1 && !fe_launch_replay1 &&
        (entry_state[fe_launch_rob_id1] == ST_SELECTED_DEP) &&
        dep_cache_valid[entry_target_seq_tag[fe_launch_rob_id1][2:0]] &&
        (dep_cache_seq_tag[entry_target_seq_tag[fe_launch_rob_id1][2:0]] ==
         entry_target_seq_tag[fe_launch_rob_id1]);
    assign d3_cache_hit2 = fe_launch_valid2 && !fe_launch_replay2 &&
        (entry_state[fe_launch_rob_id2] == ST_SELECTED_DEP) &&
        dep_cache_valid[entry_target_seq_tag[fe_launch_rob_id2][2:0]] &&
        (dep_cache_seq_tag[entry_target_seq_tag[fe_launch_rob_id2][2:0]] ==
         entry_target_seq_tag[fe_launch_rob_id2]);
    assign d3_cache_hit3 = fe_launch_valid3 && !fe_launch_replay3 &&
        (entry_state[fe_launch_rob_id3] == ST_SELECTED_DEP) &&
        dep_cache_valid[entry_target_seq_tag[fe_launch_rob_id3][2:0]] &&
        (dep_cache_seq_tag[entry_target_seq_tag[fe_launch_rob_id3][2:0]] ==
         entry_target_seq_tag[fe_launch_rob_id3]);

    assign d3_cache_data0 = dep_cache_data[entry_target_seq_tag[fe_launch_rob_id0][2:0]];
    assign d3_cache_data1 = dep_cache_data[entry_target_seq_tag[fe_launch_rob_id1][2:0]];
    assign d3_cache_data2 = dep_cache_data[entry_target_seq_tag[fe_launch_rob_id2][2:0]];
    assign d3_cache_data3 = dep_cache_data[entry_target_seq_tag[fe_launch_rob_id3][2:0]];

    // A no-dependency launch always issues.  A dependency launch issues only on
    // a full-tag cache hit, unless replay already carries authoritative data.
    assign fe_in_valid0 = rst_n && fe_launch_valid0 &&
                          (fe_launch_replay0 ||
                           (entry_state[fe_launch_rob_id0] == ST_SELECTED_NODEP) ||
                           d3_cache_hit0);
    assign fe_in_data0 = fe_launch_valid0 ? entry_packet[fe_launch_rob_id0] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid0 = fe_in_valid0 &&
                           (entry_state[fe_launch_rob_id0] == ST_SELECTED_DEP);
    assign fe_dep_data0 = fe_dep_valid0 ?
        (fe_launch_replay0 ? replay_data : d3_cache_data0) : {PACKET_W{1'b0}};
    assign fe_desc_delay0 = fe_launch_valid0 ? entry_desc_delay[fe_launch_rob_id0] : 2'd0;
    assign fe_in_valid1 = rst_n && fe_launch_valid1 &&
                          (fe_launch_replay1 ||
                           (entry_state[fe_launch_rob_id1] == ST_SELECTED_NODEP) ||
                           d3_cache_hit1);
    assign fe_in_data1 = fe_launch_valid1 ? entry_packet[fe_launch_rob_id1] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid1 = fe_in_valid1 &&
                           (entry_state[fe_launch_rob_id1] == ST_SELECTED_DEP);
    assign fe_dep_data1 = fe_dep_valid1 ?
        (fe_launch_replay1 ? replay_data : d3_cache_data1) : {PACKET_W{1'b0}};
    assign fe_desc_delay1 = fe_launch_valid1 ? entry_desc_delay[fe_launch_rob_id1] : 2'd0;
    assign fe_in_valid2 = rst_n && fe_launch_valid2 &&
                          (fe_launch_replay2 ||
                           (entry_state[fe_launch_rob_id2] == ST_SELECTED_NODEP) ||
                           d3_cache_hit2);
    assign fe_in_data2 = fe_launch_valid2 ? entry_packet[fe_launch_rob_id2] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid2 = fe_in_valid2 &&
                           (entry_state[fe_launch_rob_id2] == ST_SELECTED_DEP);
    assign fe_dep_data2 = fe_dep_valid2 ?
        (fe_launch_replay2 ? replay_data : d3_cache_data2) : {PACKET_W{1'b0}};
    assign fe_desc_delay2 = fe_launch_valid2 ? entry_desc_delay[fe_launch_rob_id2] : 2'd0;
    assign fe_in_valid3 = rst_n && fe_launch_valid3 &&
                          (fe_launch_replay3 ||
                           (entry_state[fe_launch_rob_id3] == ST_SELECTED_NODEP) ||
                           d3_cache_hit3);
    assign fe_in_data3 = fe_launch_valid3 ? entry_packet[fe_launch_rob_id3] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid3 = fe_in_valid3 &&
                           (entry_state[fe_launch_rob_id3] == ST_SELECTED_DEP);
    assign fe_dep_data3 = fe_dep_valid3 ?
        (fe_launch_replay3 ? replay_data : d3_cache_data3) : {PACKET_W{1'b0}};
    assign fe_desc_delay3 = fe_launch_valid3 ? entry_desc_delay[fe_launch_rob_id3] : 2'd0;

    // FE responses have no tag.  The calendar entry due in schedule_phase adds
    // the ROB ID and sequence tag before forwarding the response to reorder.
    assign wb_valid0 = fe_out_valid0 && return_valid[{2'd0, schedule_phase}];
    assign wb_rob_id0 = return_rob_id[{2'd0, schedule_phase}];
    assign wb_seq_tag0 = return_seq_tag[{2'd0, schedule_phase}];
    assign wb_data0 = fe_out_data0;
    assign wb_valid1 = fe_out_valid1 && return_valid[{2'd1, schedule_phase}];
    assign wb_rob_id1 = return_rob_id[{2'd1, schedule_phase}];
    assign wb_seq_tag1 = return_seq_tag[{2'd1, schedule_phase}];
    assign wb_data1 = fe_out_data1;
    assign wb_valid2 = fe_out_valid2 && return_valid[{2'd2, schedule_phase}];
    assign wb_rob_id2 = return_rob_id[{2'd2, schedule_phase}];
    assign wb_seq_tag2 = return_seq_tag[{2'd2, schedule_phase}];
    assign wb_data2 = fe_out_data2;
    assign wb_valid3 = fe_out_valid3 && return_valid[{2'd3, schedule_phase}];
    assign wb_rob_id3 = return_rob_id[{2'd3, schedule_phase}];
    assign wb_seq_tag3 = return_seq_tag[{2'd3, schedule_phase}];
    assign wb_data3 = fe_out_data3;

    assign fallback_valid = fallback_valid_r;
    assign fallback_rob_id = fallback_rob_id_r;
    assign fallback_seq_tag = fallback_seq_tag_r;
    assign fallback_residue = fallback_residue_r;

    // Fallback arbitration has two request classes:
    //   1. a D3 launch that just discovered a cache overwrite;
    //   2. an entry already waiting in ST_FALLBACK.
    // Separate RR pointers and fallback_class_rr provide fairness.  No new
    // lookup starts while replay_data is occupied.
    always @(*) begin
        fallback_d3_any = 1'b0;
        fallback_entry_any = 1'b0;
        fallback_d3_selected = fallback_fe_rr_ptr;
        fallback_entry_selected = fallback_entry_rr_ptr;
        fallback_d3_found = 1'b0;
        fallback_entry_found = 1'b0;

        for (fallback_scan = 0; fallback_scan < 4;
             fallback_scan = fallback_scan + 1) begin
            fallback_index = ({30'd0, fallback_fe_rr_ptr} + fallback_scan) & 32'd3;
            if (!fallback_d3_found &&
                (((fallback_index == 0) && fe_launch_valid0 && !fe_launch_replay0 &&
                  (entry_state[fe_launch_rob_id0] == ST_SELECTED_DEP) && !d3_cache_hit0) ||
                 ((fallback_index == 1) && fe_launch_valid1 && !fe_launch_replay1 &&
                  (entry_state[fe_launch_rob_id1] == ST_SELECTED_DEP) && !d3_cache_hit1) ||
                 ((fallback_index == 2) && fe_launch_valid2 && !fe_launch_replay2 &&
                  (entry_state[fe_launch_rob_id2] == ST_SELECTED_DEP) && !d3_cache_hit2) ||
                 ((fallback_index == 3) && fe_launch_valid3 && !fe_launch_replay3 &&
                  (entry_state[fe_launch_rob_id3] == ST_SELECTED_DEP) && !d3_cache_hit3))) begin
                fallback_d3_found = 1'b1;
                fallback_d3_any = 1'b1;
                fallback_d3_selected = fallback_index[1:0];
            end
        end

        for (fallback_scan = 0; fallback_scan < 16;
             fallback_scan = fallback_scan + 1) begin
            fallback_index = ({28'd0, fallback_entry_rr_ptr} + fallback_scan) & 32'd15;
            if (!fallback_entry_found &&
                (entry_state[fallback_index] == ST_FALLBACK) &&
                !(dep_cache_valid[entry_target_seq_tag[fallback_index][2:0]] &&
                  (dep_cache_seq_tag[entry_target_seq_tag[fallback_index][2:0]] ==
                   entry_target_seq_tag[fallback_index]))) begin
                fallback_entry_found = 1'b1;
                fallback_entry_any = 1'b1;
                fallback_entry_selected = fallback_index[3:0];
            end
        end

        fallback_valid_r = 1'b0;
        fallback_rob_id_r = 4'd0;
        fallback_seq_tag_r = 5'd0;
        fallback_residue_r = 3'd0;
        fallback_from_d3 = 1'b0;
        fallback_d3_fe_id = 2'd0;
        fallback_entry_id = 4'd0;

        if (!replay_valid && fallback_d3_any &&
            (!fallback_entry_any || !fallback_class_rr)) begin
            fallback_valid_r = 1'b1;
            fallback_from_d3 = 1'b1;
            fallback_d3_fe_id = fallback_d3_selected;
            case (fallback_d3_selected)
                2'd0: fallback_entry_id = fe_launch_rob_id0;
                2'd1: fallback_entry_id = fe_launch_rob_id1;
                2'd2: fallback_entry_id = fe_launch_rob_id2;
                default: fallback_entry_id = fe_launch_rob_id3;
            endcase
        end else if (!replay_valid && fallback_entry_any) begin
            fallback_valid_r = 1'b1;
            fallback_entry_id = fallback_entry_selected;
        end

        // Reorder accepts a direct index plus a full identity tag.  Low tag
        // bits select the candidate ROB entry/bank; the full tag proves a hit.
        if (fallback_valid_r) begin
            fallback_rob_id_r = entry_target_seq_tag[fallback_entry_id][3:0];
            fallback_seq_tag_r = entry_target_seq_tag[fallback_entry_id];
            fallback_residue_r = entry_target_seq_tag[fallback_entry_id][2:0];
        end
    end

    // Queue next-state permits dequeue and enqueue in the same cycle.  D2 only
    // removes a consecutive prefix, so compaction is a fixed shift per class.
    always @(*) begin
        for (q_class = 0; q_class < 4; q_class = q_class + 1) begin
            q_base = q_class * 16;
            q_remaining = {27'd0, ready_q_count[q_class]} -
                          {29'd0, d2_class_take[q_class]};
            for (q_pos = 0; q_pos < 16; q_pos = q_pos + 1) begin
                ready_q_id_next[q_base + q_pos] =
                    ready_q_id[q_base + q_pos];
                if (q_pos < q_remaining)
                    ready_q_id_next[q_base + q_pos] = ready_q_id[
                        q_base + q_pos + {29'd0, d2_class_take[q_class]}];
            end
            q_append = q_remaining;
            if (enqueue_valid[0] &&
                (enqueue_class[0] == q_class[1:0])) begin
                ready_q_id_next[q_base + q_append] = enqueue_id[0];
                q_append = q_append + 1;
            end
            if (enqueue_valid[1] &&
                (enqueue_class[1] == q_class[1:0])) begin
                ready_q_id_next[q_base + q_append] = enqueue_id[1];
                q_append = q_append + 1;
            end
            if (enqueue_valid[2] &&
                (enqueue_class[2] == q_class[1:0])) begin
                ready_q_id_next[q_base + q_append] = enqueue_id[2];
                q_append = q_append + 1;
            end
            if (enqueue_valid[3] &&
                (enqueue_class[3] == q_class[1:0])) begin
                ready_q_id_next[q_base + q_append] = enqueue_id[3];
                q_append = q_append + 1;
            end
            ready_q_count_next[q_class] = q_append[4:0];
        end
    end


    // READY discovery is separate from D2 matching.  Entries beyond the four
    // insertion slots remain READY and are found by a later fair scan.
    always @(*) begin
        enqueue_count = 0;
        enqueue_last_id = enqueue_rr_ptr;
        alloc_enqueued0 = 1'b0;
        alloc_enqueued1 = 1'b0;
        alloc_enqueued2 = 1'b0;
        alloc_enqueued3 = 1'b0;
        for (enqueue_scan = 0; enqueue_scan < 4;
             enqueue_scan = enqueue_scan + 1) begin
            enqueue_valid[enqueue_scan] = 1'b0;
            enqueue_id[enqueue_scan] = 4'd0;
            enqueue_class[enqueue_scan] = 2'd0;
        end
        for (enqueue_scan = 0; enqueue_scan < 16;
             enqueue_scan = enqueue_scan + 1) begin
            enqueue_scan_id = enqueue_rr_ptr + enqueue_scan[3:0];
            enqueue_scan_ready =
                (entry_state[enqueue_scan_id] == ST_READY_NODEP) ||
                (entry_state[enqueue_scan_id] == ST_READY_DEP) ||
                ((((entry_state[enqueue_scan_id] == ST_WAIT_DEP) ||
                   (entry_state[enqueue_scan_id] == ST_FALLBACK)) &&
                  ((dep_cache_valid[
                        entry_target_seq_tag[enqueue_scan_id][2:0]] &&
                    (dep_cache_seq_tag[
                        entry_target_seq_tag[enqueue_scan_id][2:0]] ==
                     entry_target_seq_tag[enqueue_scan_id])) ||
                   (wb_valid0 && (wb_seq_tag0 ==
                                  entry_target_seq_tag[enqueue_scan_id])) ||
                   (wb_valid1 && (wb_seq_tag1 ==
                                  entry_target_seq_tag[enqueue_scan_id])) ||
                   (wb_valid2 && (wb_seq_tag2 ==
                                  entry_target_seq_tag[enqueue_scan_id])) ||
                   (wb_valid3 && (wb_seq_tag3 ==
                                  entry_target_seq_tag[enqueue_scan_id])))) &&
                 !(fallback_valid_r && fallback_ready &&
                   (fallback_entry_id == enqueue_scan_id)));
            if ((enqueue_count < 4) && !entry_queued[enqueue_scan_id] &&
                enqueue_scan_ready) begin
                enqueue_valid[enqueue_count] = 1'b1;
                enqueue_id[enqueue_count] = enqueue_scan_id;
                enqueue_class[enqueue_count] =
                    entry_desc_delay[enqueue_scan_id];
                enqueue_last_id = enqueue_scan_id;
                enqueue_count = enqueue_count + 1;
            end
        end

        // A D0 allocation whose dependency is already resolved can enter the
        // ID FIFO on its capture edge.  Existing unqueued READY entries retain
        // priority so continuous new traffic cannot starve a wakeup backlog.
        if ((enqueue_count < 4) && alloc_valid0 &&
            ((dep_offset0 == 3'd0) || alloc_dep_resolved0)) begin
            enqueue_valid[enqueue_count] = 1'b1;
            enqueue_id[enqueue_count] = alloc_rob_id0;
            enqueue_class[enqueue_count] = in_desc0[1:0];
            alloc_enqueued0 = 1'b1;
            enqueue_count = enqueue_count + 1;
        end
        if ((enqueue_count < 4) && alloc_valid1 &&
            ((dep_offset1 == 3'd0) || alloc_dep_resolved1)) begin
            enqueue_valid[enqueue_count] = 1'b1;
            enqueue_id[enqueue_count] = alloc_rob_id1;
            enqueue_class[enqueue_count] = in_desc1[1:0];
            alloc_enqueued1 = 1'b1;
            enqueue_count = enqueue_count + 1;
        end
        if ((enqueue_count < 4) && alloc_valid2 &&
            ((dep_offset2 == 3'd0) || alloc_dep_resolved2)) begin
            enqueue_valid[enqueue_count] = 1'b1;
            enqueue_id[enqueue_count] = alloc_rob_id2;
            enqueue_class[enqueue_count] = in_desc2[1:0];
            alloc_enqueued2 = 1'b1;
            enqueue_count = enqueue_count + 1;
        end
        if ((enqueue_count < 4) && alloc_valid3 &&
            ((dep_offset3 == 3'd0) || alloc_dep_resolved3)) begin
            enqueue_valid[enqueue_count] = 1'b1;
            enqueue_id[enqueue_count] = alloc_rob_id3;
            enqueue_class[enqueue_count] = in_desc3[1:0];
            alloc_enqueued3 = 1'b1;
            enqueue_count = enqueue_count + 1;
        end
    end

    // D2 matches four delay classes against four FE return slots.  A class may
    // take several FEs and consumes consecutive IDs from its registered head.
    always @(*) begin
        d2_select_valid0 = 1'b0;
        d2_select_rob_id0 = 4'd0;
        d2_select_return_slot0 = 3'd0;
        d2_select_replay0 = 1'b0;
        d2_select_valid1 = 1'b0;
        d2_select_rob_id1 = 4'd0;
        d2_select_return_slot1 = 3'd0;
        d2_select_replay1 = 1'b0;
        d2_select_valid2 = 1'b0;
        d2_select_rob_id2 = 4'd0;
        d2_select_return_slot2 = 3'd0;
        d2_select_replay2 = 1'b0;
        d2_select_valid3 = 1'b0;
        d2_select_rob_id3 = 4'd0;
        d2_select_return_slot3 = 3'd0;
        d2_select_replay3 = 1'b0;
        d2_fe_used = 4'b0000;
        d2_select_count = 0;
        d2_normal_count = 0;
        d2_last_class = class_rr_ptr;
        d2_last_fe_id = fe_rr_ptr;
        d2_fe_scan = 0;
        d2_other_class = 0;
        d2_class_index = 2'd0;
        d2_fe_index = 2'd0;
        d2_class_found = 1'b0;
        d2_chosen_class = class_rr_ptr;
        d2_fe_found = 1'b0;
        d2_chosen_fe = fe_rr_ptr;
        d2_legal_count = 0;
        d2_best_contention = 0;
        d2_contention = 0;
        d2_queue_index = 6'd0;
        d2_candidate_age = 5'd0;
        d2_oldest_age = 5'd0;
        d2_candidate_slot = 3'd0;
        d2_candidate_rob_id = 4'd0;
        for (d2_class_scan = 0; d2_class_scan < 4;
             d2_class_scan = d2_class_scan + 1)
            d2_class_take[d2_class_scan] = 3'd0;

        // Replay bypasses the normal queues and is prioritized to release the
        // single authoritative dependency buffer.
        if (replay_valid && (entry_state[replay_rob_id] == ST_REPLAY)) begin
            d2_candidate_slot = schedule_phase +
                {1'b0, entry_desc_delay[replay_rob_id]} + 3'd2;
            d2_fe_found = 1'b0;
            for (d2_fe_scan = 0; d2_fe_scan < 4;
                 d2_fe_scan = d2_fe_scan + 1) begin
                d2_fe_index = fe_rr_ptr + d2_fe_scan[1:0];
                if (!d2_fe_found &&
                    !return_valid[{d2_fe_index, d2_candidate_slot}]) begin
                    d2_fe_found = 1'b1;
                    d2_fe_used[d2_fe_index] = 1'b1;
                    d2_last_fe_id = d2_fe_index;
                    d2_select_count = 1;
                    case (d2_fe_index)
                        2'd0: begin d2_select_valid0 = 1'b1;
                            d2_select_rob_id0 = replay_rob_id;
                            d2_select_return_slot0 = d2_candidate_slot;
                            d2_select_replay0 = 1'b1; end
                        2'd1: begin d2_select_valid1 = 1'b1;
                            d2_select_rob_id1 = replay_rob_id;
                            d2_select_return_slot1 = d2_candidate_slot;
                            d2_select_replay1 = 1'b1; end
                        2'd2: begin d2_select_valid2 = 1'b1;
                            d2_select_rob_id2 = replay_rob_id;
                            d2_select_return_slot2 = d2_candidate_slot;
                            d2_select_replay2 = 1'b1; end
                        default: begin d2_select_valid3 = 1'b1;
                            d2_select_rob_id3 = replay_rob_id;
                            d2_select_return_slot3 = d2_candidate_slot;
                            d2_select_replay3 = 1'b1; end
                    endcase
                end
            end
        end

        // Fixed rounds synthesize into bounded matching.  First force the
        // globally oldest schedulable head; later rounds use constrained-first
        // and rotating class priority.
        for (d2_round = 0; d2_round < 4; d2_round = d2_round + 1) begin
            d2_class_found = 1'b0;
            d2_chosen_class = class_rr_ptr;
            if ((d2_select_count < 4) && (d2_normal_count == 0)) begin
                d2_oldest_age = 5'd0;
                for (d2_class_scan = 0; d2_class_scan < 4;
                     d2_class_scan = d2_class_scan + 1) begin
                    d2_legal_count = 0;
                    d2_candidate_slot = schedule_phase +
                        {1'b0, d2_class_scan[1:0]} + 3'd2;
                    for (d2_fe_scan = 0; d2_fe_scan < 4;
                         d2_fe_scan = d2_fe_scan + 1)
                        if (!d2_fe_used[d2_fe_scan] &&
                            !return_valid[{d2_fe_scan[1:0], d2_candidate_slot}])
                            d2_legal_count = d2_legal_count + 1;
                    if (({2'b00, d2_class_take[d2_class_scan]} <
                         ready_q_count[d2_class_scan]) &&
                        (d2_class_take[d2_class_scan] < 3'd4) &&
                        (d2_legal_count != 0)) begin
                        d2_queue_index = {d2_class_scan[1:0], 4'b0000} +
                            {3'b000, d2_class_take[d2_class_scan]};
                        d2_candidate_rob_id = ready_q_id[d2_queue_index];
                        d2_candidate_age = next_seq_tag -
                            entry_seq_tag[d2_candidate_rob_id];
                        if (!d2_class_found ||
                            (d2_candidate_age > d2_oldest_age)) begin
                            d2_class_found = 1'b1;
                            d2_chosen_class = d2_class_scan[1:0];
                            d2_oldest_age = d2_candidate_age;
                        end
                    end
                end
            end else if (d2_select_count < 4) begin
                // Protect a class that has only one remaining FE choice.
                for (d2_class_scan = 0; d2_class_scan < 4;
                     d2_class_scan = d2_class_scan + 1) begin
                    d2_class_index = class_rr_ptr + d2_class_scan[1:0];
                    d2_legal_count = 0;
                    d2_candidate_slot = schedule_phase +
                        {1'b0, d2_class_index} + 3'd2;
                    for (d2_fe_scan = 0; d2_fe_scan < 4;
                         d2_fe_scan = d2_fe_scan + 1)
                        if (!d2_fe_used[d2_fe_scan] &&
                            !return_valid[{d2_fe_scan[1:0], d2_candidate_slot}])
                            d2_legal_count = d2_legal_count + 1;
                    if (!d2_class_found &&
                        ({2'b00, d2_class_take[d2_class_index]} <
                         ready_q_count[d2_class_index]) &&
                        (d2_class_take[d2_class_index] < 3'd4) &&
                        (d2_legal_count == 1)) begin
                        d2_class_found = 1'b1;
                        d2_chosen_class = d2_class_index;
                    end
                end
                if (!d2_class_found) begin
                    for (d2_class_scan = 0; d2_class_scan < 4;
                         d2_class_scan = d2_class_scan + 1) begin
                        d2_class_index = class_rr_ptr + d2_class_scan[1:0];
                        d2_legal_count = 0;
                        d2_candidate_slot = schedule_phase +
                            {1'b0, d2_class_index} + 3'd2;
                        for (d2_fe_scan = 0; d2_fe_scan < 4;
                             d2_fe_scan = d2_fe_scan + 1)
                            if (!d2_fe_used[d2_fe_scan] &&
                                !return_valid[{d2_fe_scan[1:0],
                                               d2_candidate_slot}])
                                d2_legal_count = d2_legal_count + 1;
                        if (!d2_class_found &&
                            ({2'b00, d2_class_take[d2_class_index]} <
                             ready_q_count[d2_class_index]) &&
                            (d2_class_take[d2_class_index] < 3'd4) &&
                            (d2_legal_count != 0)) begin
                            d2_class_found = 1'b1;
                            d2_chosen_class = d2_class_index;
                        end
                    end
                end
            end

            if (d2_class_found && (d2_select_count < 4)) begin
                d2_candidate_slot = schedule_phase +
                    {1'b0, d2_chosen_class} + 3'd2;
                d2_queue_index = {d2_chosen_class, 4'b0000} +
                    {3'b000, d2_class_take[d2_chosen_class]};
                d2_candidate_rob_id = ready_q_id[d2_queue_index];
                d2_fe_found = 1'b0;
                d2_chosen_fe = fe_rr_ptr;
                d2_best_contention = 5;
                for (d2_fe_scan = 0; d2_fe_scan < 4;
                     d2_fe_scan = d2_fe_scan + 1) begin
                    d2_fe_index = fe_rr_ptr + d2_fe_scan[1:0];
                    if (!d2_fe_used[d2_fe_index] &&
                        !return_valid[{d2_fe_index, d2_candidate_slot}]) begin
                        d2_contention = 0;
                        for (d2_other_class = 0; d2_other_class < 4;
                             d2_other_class = d2_other_class + 1)
                            if ((d2_other_class[1:0] != d2_chosen_class) &&
                                ({2'b00, d2_class_take[d2_other_class]} <
                                 ready_q_count[d2_other_class]) &&
                                !return_valid[{d2_fe_index,
                                    (schedule_phase +
                                     {1'b0, d2_other_class[1:0]} + 3'd2)}])
                                d2_contention = d2_contention + 1;
                        if (!d2_fe_found ||
                            (d2_contention < d2_best_contention)) begin
                            d2_fe_found = 1'b1;
                            d2_chosen_fe = d2_fe_index;
                            d2_best_contention = d2_contention;
                        end
                    end
                end
                if (d2_fe_found) begin
                    d2_fe_used[d2_chosen_fe] = 1'b1;
                    d2_class_take[d2_chosen_class] =
                        d2_class_take[d2_chosen_class] + 3'd1;
                    d2_select_count = d2_select_count + 1;
                    d2_normal_count = d2_normal_count + 1;
                    d2_last_class = d2_chosen_class;
                    d2_last_fe_id = d2_chosen_fe;
                    case (d2_chosen_fe)
                        2'd0: begin d2_select_valid0 = 1'b1;
                            d2_select_rob_id0 = d2_candidate_rob_id;
                            d2_select_return_slot0 = d2_candidate_slot; end
                        2'd1: begin d2_select_valid1 = 1'b1;
                            d2_select_rob_id1 = d2_candidate_rob_id;
                            d2_select_return_slot1 = d2_candidate_slot; end
                        2'd2: begin d2_select_valid2 = 1'b1;
                            d2_select_rob_id2 = d2_candidate_rob_id;
                            d2_select_return_slot2 = d2_candidate_slot; end
                        default: begin d2_select_valid3 = 1'b1;
                            d2_select_rob_id3 = d2_candidate_rob_id;
                            d2_select_return_slot3 = d2_candidate_slot; end
                    endcase
                end
            end
        end
    end

    // Sequential state update.  Wide data arrays are not reset because their
    // contents are ignored whenever the corresponding valid/state bit is clear.
    //
    // Ordering inside this block is intentional.  When multiple nonblocking
    // assignments target the same state element, the later assignment wins:
    // D3 completion/miss is applied before a same-edge D2 refill, and a new D0
    // allocation is last because it initializes a newly allocated ROB slot.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_seq_tag <= 5'd0;
            enqueue_rr_ptr <= 4'd0;
            class_rr_ptr <= 2'd0;
            fe_rr_ptr <= 2'd0;
            fallback_class_rr <= 1'b0;
            fallback_fe_rr_ptr <= 2'd0;
            fallback_entry_rr_ptr <= 4'd0;
            schedule_phase <= 3'd0;
            replay_valid <= 1'b0;
            fe_launch_valid0 <= 1'b0;
            fe_launch_valid1 <= 1'b0;
            fe_launch_valid2 <= 1'b0;
            fe_launch_valid3 <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                entry_state[i] <= ST_FREE;
                entry_queued[i] <= 1'b0;
            end
            for (i = 0; i < 4; i = i + 1) begin
                ready_q_count[i] <= 5'd0;
            end
            for (i = 0; i < 8; i = i + 1) begin
                dep_cache_valid[i] <= 1'b0;
            end
            for (i = 0; i < 32; i = i + 1) begin
                return_valid[i] <= 1'b0;
            end
        end else begin
            // Commit the queue next-state computed from simultaneous grants and
            // READY discovery.
            for (q_class = 0; q_class < 4; q_class = q_class + 1) begin
                for (q_pos = 0; q_pos < 16; q_pos = q_pos + 1)
                    ready_q_id[(q_class * 16) + q_pos] <=
                        ready_q_id_next[(q_class * 16) + q_pos];
                ready_q_count[q_class] <= ready_q_count_next[q_class];
            end
            if (enqueue_count != 0)
                enqueue_rr_ptr <= enqueue_last_id + 4'd1;
            for (i = 0; i < 4; i = i + 1) begin
                if (enqueue_valid[i])
                    entry_queued[enqueue_id[i]] <= 1'b1;
            end

            fe_launch_valid0 <= 1'b0;
            fe_launch_valid1 <= 1'b0;
            fe_launch_valid2 <= 1'b0;
            fe_launch_valid3 <= 1'b0;
            // Consume the four calendar slots due now, then advance the shared
            // phase.  A later D2 booking to the same physical element wins.
            return_valid[{2'd0, schedule_phase}] <= 1'b0;
            return_valid[{2'd1, schedule_phase}] <= 1'b0;
            return_valid[{2'd2, schedule_phase}] <= 1'b0;
            return_valid[{2'd3, schedule_phase}] <= 1'b0;
            schedule_phase <= schedule_phase + 3'd1;

            // Capture an authoritative hit into replay, or sleep in WAIT_DEP
            // until the target FE writeback broadcasts its tag.
            if (fallback_valid_r) begin
                if (fallback_from_d3) begin
                    fallback_fe_rr_ptr <= fallback_d3_fe_id + 2'd1;
                end else begin
                    fallback_entry_rr_ptr <= fallback_entry_id + 4'd1;
                end
                entry_state[fallback_entry_id] <= fallback_ready ?
                                                    ST_REPLAY : ST_WAIT_DEP;
                if (fallback_ready) begin
                    replay_valid <= 1'b1;
                    replay_rob_id <= fallback_entry_id;
                    replay_data <= fallback_data;
                    dep_cache_valid[fallback_residue_r] <= 1'b1;
                    dep_cache_seq_tag[fallback_residue_r] <= fallback_seq_tag_r;
                    dep_cache_data[fallback_residue_r] <= fallback_data;
                end
                if (fallback_d3_any && fallback_entry_any) begin
                    fallback_class_rr <= !fallback_class_rr;
                end
            end

            // Waiting entries watch both the cache and all four writeback tags.
            // Only small tags/state are broadcast; 128-bit data stays in cache.
            for (i = 0; i < 16; i = i + 1) begin
                if ((entry_state[i] == ST_FALLBACK) &&
                    dep_cache_valid[entry_target_seq_tag[i][2:0]] &&
                    (dep_cache_seq_tag[entry_target_seq_tag[i][2:0]] ==
                     entry_target_seq_tag[i])) begin
                    entry_state[i] <= ST_READY_DEP;
                end
                if (((entry_state[i] == ST_WAIT_DEP) ||
                     (entry_state[i] == ST_FALLBACK)) &&
                    ((wb_valid0 &&
                      (entry_target_seq_tag[i][3:0] == wb_rob_id0) &&
                      (entry_target_seq_tag[i] == wb_seq_tag0)) ||
                     (wb_valid1 &&
                      (entry_target_seq_tag[i][3:0] == wb_rob_id1) &&
                      (entry_target_seq_tag[i] == wb_seq_tag1)) ||
                     (wb_valid2 &&
                      (entry_target_seq_tag[i][3:0] == wb_rob_id2) &&
                      (entry_target_seq_tag[i] == wb_seq_tag2)) ||
                     (wb_valid3 &&
                      (entry_target_seq_tag[i][3:0] == wb_rob_id3) &&
                      (entry_target_seq_tag[i] == wb_seq_tag3))) &&
                    !(fallback_valid_r && fallback_ready &&
                      (fallback_entry_id == i[3:0]))) begin
                    entry_state[i] <= ST_READY_DEP;
                end
            end

            // Every FE writeback refreshes its residue bank.  Later FE numbers
            // have source-order priority if illegal same-bank writes coincide.
            if (wb_valid0) begin
                dep_cache_valid[wb_seq_tag0[2:0]] <= 1'b1;
                dep_cache_seq_tag[wb_seq_tag0[2:0]] <= wb_seq_tag0;
                dep_cache_data[wb_seq_tag0[2:0]] <= wb_data0;
            end
            if (wb_valid1) begin
                dep_cache_valid[wb_seq_tag1[2:0]] <= 1'b1;
                dep_cache_seq_tag[wb_seq_tag1[2:0]] <= wb_seq_tag1;
                dep_cache_data[wb_seq_tag1[2:0]] <= wb_data1;
            end
            if (wb_valid2) begin
                dep_cache_valid[wb_seq_tag2[2:0]] <= 1'b1;
                dep_cache_seq_tag[wb_seq_tag2[2:0]] <= wb_seq_tag2;
                dep_cache_data[wb_seq_tag2[2:0]] <= wb_data2;
            end
            if (wb_valid3) begin
                dep_cache_valid[wb_seq_tag3[2:0]] <= 1'b1;
                dep_cache_seq_tag[wb_seq_tag3[2:0]] <= wb_seq_tag3;
                dep_cache_data[wb_seq_tag3[2:0]] <= wb_data3;
            end

            // D3 consumes the old launch registers.  Successful issue frees the
            // dispatch entry.  A cache miss restores a waiting state and removes
            // the return booking because no request was sent to the FE.
            if (fe_launch_valid0) begin
                if (fe_in_valid0) begin
                    entry_state[fe_launch_rob_id0] <= ST_FREE;
                    if (fe_launch_replay0) replay_valid <= 1'b0;
                end else begin
                    if (fallback_from_d3 && (fallback_d3_fe_id == 2'd0)) begin
                        entry_state[fe_launch_rob_id0] <= fallback_ready ?
                                                                ST_REPLAY : ST_WAIT_DEP;
                    end else begin
                        entry_state[fe_launch_rob_id0] <= ST_FALLBACK;
                    end
                    return_valid[{2'd0, fe_launch_return_slot0}] <= 1'b0;
                end
            end
            if (fe_launch_valid1) begin
                if (fe_in_valid1) begin
                    entry_state[fe_launch_rob_id1] <= ST_FREE;
                    if (fe_launch_replay1) replay_valid <= 1'b0;
                end else begin
                    if (fallback_from_d3 && (fallback_d3_fe_id == 2'd1)) begin
                        entry_state[fe_launch_rob_id1] <= fallback_ready ?
                                                                ST_REPLAY : ST_WAIT_DEP;
                    end else begin
                        entry_state[fe_launch_rob_id1] <= ST_FALLBACK;
                    end
                    return_valid[{2'd1, fe_launch_return_slot1}] <= 1'b0;
                end
            end
            if (fe_launch_valid2) begin
                if (fe_in_valid2) begin
                    entry_state[fe_launch_rob_id2] <= ST_FREE;
                    if (fe_launch_replay2) replay_valid <= 1'b0;
                end else begin
                    if (fallback_from_d3 && (fallback_d3_fe_id == 2'd2)) begin
                        entry_state[fe_launch_rob_id2] <= fallback_ready ?
                                                                ST_REPLAY : ST_WAIT_DEP;
                    end else begin
                        entry_state[fe_launch_rob_id2] <= ST_FALLBACK;
                    end
                    return_valid[{2'd2, fe_launch_return_slot2}] <= 1'b0;
                end
            end
            if (fe_launch_valid3) begin
                if (fe_in_valid3) begin
                    entry_state[fe_launch_rob_id3] <= ST_FREE;
                    if (fe_launch_replay3) replay_valid <= 1'b0;
                end else begin
                    if (fallback_from_d3 && (fallback_d3_fe_id == 2'd3)) begin
                        entry_state[fe_launch_rob_id3] <= fallback_ready ?
                                                                ST_REPLAY : ST_WAIT_DEP;
                    end else begin
                        entry_state[fe_launch_rob_id3] <= ST_FALLBACK;
                    end
                    return_valid[{2'd3, fe_launch_return_slot3}] <= 1'b0;
                end
            end

            // D2 writes the next launch and reserves its future return slot.
            // These assignments follow D3 so consume-and-refill works in one edge.
            if (d2_select_valid0) begin
                fe_launch_valid0 <= 1'b1;
                fe_launch_rob_id0 <= d2_select_rob_id0;
                fe_launch_return_slot0 <= d2_select_return_slot0;
                fe_launch_replay0 <= d2_select_replay0;
                entry_state[d2_select_rob_id0] <=
                    (d2_select_replay0 ||
                     (entry_state[d2_select_rob_id0] == ST_READY_DEP)) ?
                    ST_SELECTED_DEP : ST_SELECTED_NODEP;
                return_valid[{2'd0, d2_select_return_slot0}] <= 1'b1;
                return_rob_id[{2'd0, d2_select_return_slot0}] <= d2_select_rob_id0;
                return_seq_tag[{2'd0, d2_select_return_slot0}] <=
                    entry_seq_tag[d2_select_rob_id0];
                if (!d2_select_replay0)
                    entry_queued[d2_select_rob_id0] <= 1'b0;
            end
            if (d2_select_valid1) begin
                fe_launch_valid1 <= 1'b1;
                fe_launch_rob_id1 <= d2_select_rob_id1;
                fe_launch_return_slot1 <= d2_select_return_slot1;
                fe_launch_replay1 <= d2_select_replay1;
                entry_state[d2_select_rob_id1] <=
                    (d2_select_replay1 ||
                     (entry_state[d2_select_rob_id1] == ST_READY_DEP)) ?
                    ST_SELECTED_DEP : ST_SELECTED_NODEP;
                return_valid[{2'd1, d2_select_return_slot1}] <= 1'b1;
                return_rob_id[{2'd1, d2_select_return_slot1}] <= d2_select_rob_id1;
                return_seq_tag[{2'd1, d2_select_return_slot1}] <=
                    entry_seq_tag[d2_select_rob_id1];
                if (!d2_select_replay1)
                    entry_queued[d2_select_rob_id1] <= 1'b0;
            end
            if (d2_select_valid2) begin
                fe_launch_valid2 <= 1'b1;
                fe_launch_rob_id2 <= d2_select_rob_id2;
                fe_launch_return_slot2 <= d2_select_return_slot2;
                fe_launch_replay2 <= d2_select_replay2;
                entry_state[d2_select_rob_id2] <=
                    (d2_select_replay2 ||
                     (entry_state[d2_select_rob_id2] == ST_READY_DEP)) ?
                    ST_SELECTED_DEP : ST_SELECTED_NODEP;
                return_valid[{2'd2, d2_select_return_slot2}] <= 1'b1;
                return_rob_id[{2'd2, d2_select_return_slot2}] <= d2_select_rob_id2;
                return_seq_tag[{2'd2, d2_select_return_slot2}] <=
                    entry_seq_tag[d2_select_rob_id2];
                if (!d2_select_replay2)
                    entry_queued[d2_select_rob_id2] <= 1'b0;
            end
            if (d2_select_valid3) begin
                fe_launch_valid3 <= 1'b1;
                fe_launch_rob_id3 <= d2_select_rob_id3;
                fe_launch_return_slot3 <= d2_select_return_slot3;
                fe_launch_replay3 <= d2_select_replay3;
                entry_state[d2_select_rob_id3] <=
                    (d2_select_replay3 ||
                     (entry_state[d2_select_rob_id3] == ST_READY_DEP)) ?
                    ST_SELECTED_DEP : ST_SELECTED_NODEP;
                return_valid[{2'd3, d2_select_return_slot3}] <= 1'b1;
                return_rob_id[{2'd3, d2_select_return_slot3}] <= d2_select_rob_id3;
                return_seq_tag[{2'd3, d2_select_return_slot3}] <=
                    entry_seq_tag[d2_select_rob_id3];
                if (!d2_select_replay3)
                    entry_queued[d2_select_rob_id3] <= 1'b0;
            end
            if (d2_normal_count != 0)
                class_rr_ptr <= d2_last_class + 2'd1;
            if (d2_select_count != 0)
                fe_rr_ptr <= d2_last_fe_id + 2'd1;

            // D0 creates new entries.  Dependency identity is stored once as a
            // full target tag; target ROB ID and cache bank are its low bits.
            if (alloc_valid0) begin
                entry_packet[alloc_rob_id0] <= in_packet0;
                entry_seq_tag[alloc_rob_id0] <= alloc_seq_tag0;
                entry_desc_delay[alloc_rob_id0] <= in_desc0[1:0];
                entry_target_seq_tag[alloc_rob_id0] <= alloc_target_seq_tag0;
                entry_state[alloc_rob_id0] <= (dep_offset0 == 3'd0) ?
                    ST_READY_NODEP :
                    (alloc_dep_resolved0 ? ST_READY_DEP : ST_FALLBACK);
                entry_queued[alloc_rob_id0] <= alloc_enqueued0;
            end
            if (alloc_valid1) begin
                entry_packet[alloc_rob_id1] <= in_packet1;
                entry_seq_tag[alloc_rob_id1] <= alloc_seq_tag1;
                entry_desc_delay[alloc_rob_id1] <= in_desc1[1:0];
                entry_target_seq_tag[alloc_rob_id1] <= alloc_target_seq_tag1;
                entry_state[alloc_rob_id1] <= (dep_offset1 == 3'd0) ?
                    ST_READY_NODEP :
                    (alloc_dep_resolved1 ? ST_READY_DEP : ST_FALLBACK);
                entry_queued[alloc_rob_id1] <= alloc_enqueued1;
            end
            if (alloc_valid2) begin
                entry_packet[alloc_rob_id2] <= in_packet2;
                entry_seq_tag[alloc_rob_id2] <= alloc_seq_tag2;
                entry_desc_delay[alloc_rob_id2] <= in_desc2[1:0];
                entry_target_seq_tag[alloc_rob_id2] <= alloc_target_seq_tag2;
                entry_state[alloc_rob_id2] <= (dep_offset2 == 3'd0) ?
                    ST_READY_NODEP :
                    (alloc_dep_resolved2 ? ST_READY_DEP : ST_FALLBACK);
                entry_queued[alloc_rob_id2] <= alloc_enqueued2;
            end
            if (alloc_valid3) begin
                entry_packet[alloc_rob_id3] <= in_packet3;
                entry_seq_tag[alloc_rob_id3] <= alloc_seq_tag3;
                entry_desc_delay[alloc_rob_id3] <= in_desc3[1:0];
                entry_target_seq_tag[alloc_rob_id3] <= alloc_target_seq_tag3;
                entry_state[alloc_rob_id3] <= (dep_offset3 == 3'd0) ?
                    ST_READY_NODEP :
                    (alloc_dep_resolved3 ? ST_READY_DEP : ST_FALLBACK);
                entry_queued[alloc_rob_id3] <= alloc_enqueued3;
            end

            if (!bkps && (accept_count != 3'd0)) begin
                next_seq_tag <= next_seq_tag + {2'b00, accept_count};
            end
        end
    end

endmodule
