`timescale 1ns/1ps

module ppe_dispatch #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,
    input                       bkps,

    input      [3:0]            in_valid,
    input      [4*PACKET_W-1:0] in_packet,
    input      [19:0]           in_desc,

    output     [3:0]            alloc_valid,
    output     [19:0]           alloc_seq_tag,
    output     [11:0]           alloc_seq_residue,
    input      [15:0]           alloc_rob_id,

    output                      fallback_valid,
    output     [3:0]            fallback_rob_id,
    output     [4:0]            fallback_seq_tag,
    output     [2:0]            fallback_residue,
    input                       fallback_ready,
    input      [PACKET_W-1:0]   fallback_data,

    output     [3:0]            fe_in_valid,
    output     [4*PACKET_W-1:0] fe_in_data,
    output     [3:0]            fe_dep_valid,
    output     [4*PACKET_W-1:0] fe_dep_data,
    output     [7:0]            fe_desc_delay,
    input      [3:0]            fe_out_valid,
    input      [4*PACKET_W-1:0] fe_out_data,

    output     [3:0]            wb_valid,
    output     [15:0]           wb_rob_id,
    output     [19:0]           wb_seq_tag,
    output     [4*PACKET_W-1:0] wb_data
);

    localparam [2:0] ST_DEP_INIT = 3'd0;
    localparam [2:0] ST_FALLBACK = 3'd1;
    localparam [2:0] ST_WAIT_DEP = 3'd2;
    localparam [2:0] ST_READY    = 3'd3;
    localparam [2:0] ST_SELECTED = 3'd4;

    wire                      in_valid0 = in_valid[0];
    wire [PACKET_W-1:0]       in_packet0 = in_packet[0*PACKET_W +: PACKET_W];
    wire [4:0]                in_desc0 = in_desc[0*5 +: 5];
    wire                      in_valid1 = in_valid[1];
    wire [PACKET_W-1:0]       in_packet1 = in_packet[1*PACKET_W +: PACKET_W];
    wire [4:0]                in_desc1 = in_desc[1*5 +: 5];
    wire                      in_valid2 = in_valid[2];
    wire [PACKET_W-1:0]       in_packet2 = in_packet[2*PACKET_W +: PACKET_W];
    wire [4:0]                in_desc2 = in_desc[2*5 +: 5];
    wire                      in_valid3 = in_valid[3];
    wire [PACKET_W-1:0]       in_packet3 = in_packet[3*PACKET_W +: PACKET_W];
    wire [4:0]                in_desc3 = in_desc[3*5 +: 5];

    wire                      alloc_valid0;
    wire [4:0]                alloc_seq_tag0;
    wire [2:0]                alloc_seq_residue0;
    wire [3:0]                alloc_rob_id0 = alloc_rob_id[0*4 +: 4];
    wire                      alloc_valid1;
    wire [4:0]                alloc_seq_tag1;
    wire [2:0]                alloc_seq_residue1;
    wire [3:0]                alloc_rob_id1 = alloc_rob_id[1*4 +: 4];
    wire                      alloc_valid2;
    wire [4:0]                alloc_seq_tag2;
    wire [2:0]                alloc_seq_residue2;
    wire [3:0]                alloc_rob_id2 = alloc_rob_id[2*4 +: 4];
    wire                      alloc_valid3;
    wire [4:0]                alloc_seq_tag3;
    wire [2:0]                alloc_seq_residue3;
    wire [3:0]                alloc_rob_id3 = alloc_rob_id[3*4 +: 4];

    wire                      fe_in_valid0;
    wire [PACKET_W-1:0]       fe_in_data0;
    wire                      fe_dep_valid0;
    wire [PACKET_W-1:0]       fe_dep_data0;
    wire [1:0]                fe_desc_delay0;
    wire                      fe_out_valid0 = fe_out_valid[0];
    wire [PACKET_W-1:0]       fe_out_data0 = fe_out_data[0*PACKET_W +: PACKET_W];
    wire                      fe_in_valid1;
    wire [PACKET_W-1:0]       fe_in_data1;
    wire                      fe_dep_valid1;
    wire [PACKET_W-1:0]       fe_dep_data1;
    wire [1:0]                fe_desc_delay1;
    wire                      fe_out_valid1 = fe_out_valid[1];
    wire [PACKET_W-1:0]       fe_out_data1 = fe_out_data[1*PACKET_W +: PACKET_W];
    wire                      fe_in_valid2;
    wire [PACKET_W-1:0]       fe_in_data2;
    wire                      fe_dep_valid2;
    wire [PACKET_W-1:0]       fe_dep_data2;
    wire [1:0]                fe_desc_delay2;
    wire                      fe_out_valid2 = fe_out_valid[2];
    wire [PACKET_W-1:0]       fe_out_data2 = fe_out_data[2*PACKET_W +: PACKET_W];
    wire                      fe_in_valid3;
    wire [PACKET_W-1:0]       fe_in_data3;
    wire                      fe_dep_valid3;
    wire [PACKET_W-1:0]       fe_dep_data3;
    wire [1:0]                fe_desc_delay3;
    wire                      fe_out_valid3 = fe_out_valid[3];
    wire [PACKET_W-1:0]       fe_out_data3 = fe_out_data[3*PACKET_W +: PACKET_W];

    wire                      wb_valid0;
    wire [3:0]                wb_rob_id0;
    wire [4:0]                wb_seq_tag0;
    wire [PACKET_W-1:0]       wb_data0;
    wire                      wb_valid1;
    wire [3:0]                wb_rob_id1;
    wire [4:0]                wb_seq_tag1;
    wire [PACKET_W-1:0]       wb_data1;
    wire                      wb_valid2;
    wire [3:0]                wb_rob_id2;
    wire [4:0]                wb_seq_tag2;
    wire [PACKET_W-1:0]       wb_data2;
    wire                      wb_valid3;
    wire [3:0]                wb_rob_id3;
    wire [4:0]                wb_seq_tag3;
    wire [PACKET_W-1:0]       wb_data3;

    reg                       entry_valid [0:15];
    reg [PACKET_W-1:0]        entry_packet [0:15];
    reg [4:0]                 entry_seq_tag [0:15];
    reg [1:0]                 entry_desc_delay [0:15];
    reg [2:0]                 entry_dep_offset [0:15];
    reg [3:0]                 entry_target_rob_id [0:15];
    reg [4:0]                 entry_target_seq_tag [0:15];
    reg [2:0]                 entry_target_residue [0:15];
    reg                       entry_dep_ready [0:15];
    reg                       entry_reserved [0:15];
    reg [2:0]                 entry_state [0:15];

    reg                       dep_cache_valid [0:7];
    reg [4:0]                 dep_cache_seq_tag [0:7];
    reg [PACKET_W-1:0]        dep_cache_data [0:7];

    reg [4:0]                 next_seq_tag;
    reg [2:0]                 next_seq_residue;
    reg [2:0]                 history_count;
    reg [3:0]                 packet_rr_ptr;
    reg [1:0]                 fe_rr_ptr;
    reg                       fallback_class_rr;
    reg [1:0]                 fallback_fe_rr_ptr;
    reg [3:0]                 fallback_entry_rr_ptr;

    reg                       d1_init_valid0;
    reg [3:0]                 d1_init_rob_id0;
    reg                       d1_init_valid1;
    reg [3:0]                 d1_init_rob_id1;
    reg                       d1_init_valid2;
    reg [3:0]                 d1_init_rob_id2;
    reg                       d1_init_valid3;
    reg [3:0]                 d1_init_rob_id3;

    reg                       fe_busy0;
    reg                       fe_reserved0;
    reg [3:0]                 fe_selected_rob_id0;
    reg [3:0]                 fe_rob_id0;
    reg [4:0]                 fe_seq_tag0;
    reg                       fe_busy1;
    reg                       fe_reserved1;
    reg [3:0]                 fe_selected_rob_id1;
    reg [3:0]                 fe_rob_id1;
    reg [4:0]                 fe_seq_tag1;
    reg                       fe_busy2;
    reg                       fe_reserved2;
    reg [3:0]                 fe_selected_rob_id2;
    reg [3:0]                 fe_rob_id2;
    reg [4:0]                 fe_seq_tag2;
    reg                       fe_busy3;
    reg                       fe_reserved3;
    reg [3:0]                 fe_selected_rob_id3;
    reg [3:0]                 fe_rob_id3;
    reg [4:0]                 fe_seq_tag3;

    wire [2:0] lane_rank0;
    wire [2:0] lane_rank1;
    wire [2:0] lane_rank2;
    wire [2:0] lane_rank3;
    wire [2:0] accept_count;
    wire [2:0] effective_dep0;
    wire [2:0] effective_dep1;
    wire [2:0] effective_dep2;
    wire [2:0] effective_dep3;
    wire       d1_resolved0;
    wire       d1_resolved1;
    wire       d1_resolved2;
    wire       d1_resolved3;
    wire       d1_cache_hit0;
    wire       d1_cache_hit1;
    wire       d1_cache_hit2;
    wire       d1_cache_hit3;
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

    reg [15:0] eligible_mask;
    reg [15:0] rotated_eligible;
    reg [2:0] group_count0;
    reg [2:0] group_count1;
    reg [2:0] group_count2;
    reg [2:0] group_count3;
    reg [4:0] rotated_rank [0:15];
    reg [3:0] packet_list [0:3];
    reg [1:0] fe_list [0:3];
    integer packet_count;
    integer available_fe_count;
    integer scan_pos;
    integer scan_index;
    integer pair_index;
    reg d2_select_valid0;
    reg [3:0] d2_select_rob_id0;
    reg d2_select_valid1;
    reg [3:0] d2_select_rob_id1;
    reg d2_select_valid2;
    reg [3:0] d2_select_rob_id2;
    reg d2_select_valid3;
    reg [3:0] d2_select_rob_id3;
    reg [3:0] d2_last_rob_id;
    reg [1:0] d2_last_fe_id;

    integer i;

    function [2:0] residue_add;
        input [2:0] base;
        input [2:0] increment;
        begin
            residue_add = base + increment;
        end
    endfunction

    function [2:0] residue_sub;
        input [2:0] base;
        input [2:0] decrement;
        begin
            residue_sub = base - decrement;
        end
    endfunction

    function [2:0] checked_dep;
        input [2:0] dep_offset;
        input [2:0] hist_count;
        input [2:0] lane_rank;
        reg [3:0] preceding;
        begin
            preceding = {1'b0, hist_count} + {1'b0, lane_rank};
            if (preceding > 4'd7) begin
                preceding = 4'd7;
            end
            if ({1'b0, dep_offset} > preceding) begin
                checked_dep = 3'd0;
            end else begin
                checked_dep = dep_offset;
            end
        end
    endfunction

    assign lane_rank0 = 3'd0;
    assign lane_rank1 = {2'b00, in_valid0};
    assign lane_rank2 = {2'b00, in_valid0} + {2'b00, in_valid1};
    assign lane_rank3 = {2'b00, in_valid0} + {2'b00, in_valid1} +
                        {2'b00, in_valid2};
    assign accept_count = {2'b00, in_valid0} + {2'b00, in_valid1} +
                          {2'b00, in_valid2} + {2'b00, in_valid3};

    assign alloc_valid0 = rst_n && !bkps && in_valid0;
    assign alloc_valid1 = rst_n && !bkps && in_valid1;
    assign alloc_valid2 = rst_n && !bkps && in_valid2;
    assign alloc_valid3 = rst_n && !bkps && in_valid3;
    assign alloc_seq_tag0 = next_seq_tag + {2'b00, lane_rank0};
    assign alloc_seq_tag1 = next_seq_tag + {2'b00, lane_rank1};
    assign alloc_seq_tag2 = next_seq_tag + {2'b00, lane_rank2};
    assign alloc_seq_tag3 = next_seq_tag + {2'b00, lane_rank3};
    assign alloc_seq_residue0 = residue_add(next_seq_residue, lane_rank0);
    assign alloc_seq_residue1 = residue_add(next_seq_residue, lane_rank1);
    assign alloc_seq_residue2 = residue_add(next_seq_residue, lane_rank2);
    assign alloc_seq_residue3 = residue_add(next_seq_residue, lane_rank3);

    assign effective_dep0 = checked_dep(in_desc0[4:2], history_count, lane_rank0);
    assign effective_dep1 = checked_dep(in_desc1[4:2], history_count, lane_rank1);
    assign effective_dep2 = checked_dep(in_desc2[4:2], history_count, lane_rank2);
    assign effective_dep3 = checked_dep(in_desc3[4:2], history_count, lane_rank3);

    assign d1_cache_hit0 = d1_init_valid0 &&
        dep_cache_valid[entry_target_residue[d1_init_rob_id0]] &&
        (dep_cache_seq_tag[entry_target_residue[d1_init_rob_id0]] ==
         entry_target_seq_tag[d1_init_rob_id0]);
    assign d1_cache_hit1 = d1_init_valid1 &&
        dep_cache_valid[entry_target_residue[d1_init_rob_id1]] &&
        (dep_cache_seq_tag[entry_target_residue[d1_init_rob_id1]] ==
         entry_target_seq_tag[d1_init_rob_id1]);
    assign d1_cache_hit2 = d1_init_valid2 &&
        dep_cache_valid[entry_target_residue[d1_init_rob_id2]] &&
        (dep_cache_seq_tag[entry_target_residue[d1_init_rob_id2]] ==
         entry_target_seq_tag[d1_init_rob_id2]);
    assign d1_cache_hit3 = d1_init_valid3 &&
        dep_cache_valid[entry_target_residue[d1_init_rob_id3]] &&
        (dep_cache_seq_tag[entry_target_residue[d1_init_rob_id3]] ==
         entry_target_seq_tag[d1_init_rob_id3]);

    assign d3_cache_hit0 = fe_reserved0 &&
        (entry_dep_offset[fe_selected_rob_id0] != 3'd0) &&
        dep_cache_valid[entry_target_residue[fe_selected_rob_id0]] &&
        (dep_cache_seq_tag[entry_target_residue[fe_selected_rob_id0]] ==
         entry_target_seq_tag[fe_selected_rob_id0]);
    assign d3_cache_hit1 = fe_reserved1 &&
        (entry_dep_offset[fe_selected_rob_id1] != 3'd0) &&
        dep_cache_valid[entry_target_residue[fe_selected_rob_id1]] &&
        (dep_cache_seq_tag[entry_target_residue[fe_selected_rob_id1]] ==
         entry_target_seq_tag[fe_selected_rob_id1]);
    assign d3_cache_hit2 = fe_reserved2 &&
        (entry_dep_offset[fe_selected_rob_id2] != 3'd0) &&
        dep_cache_valid[entry_target_residue[fe_selected_rob_id2]] &&
        (dep_cache_seq_tag[entry_target_residue[fe_selected_rob_id2]] ==
         entry_target_seq_tag[fe_selected_rob_id2]);
    assign d3_cache_hit3 = fe_reserved3 &&
        (entry_dep_offset[fe_selected_rob_id3] != 3'd0) &&
        dep_cache_valid[entry_target_residue[fe_selected_rob_id3]] &&
        (dep_cache_seq_tag[entry_target_residue[fe_selected_rob_id3]] ==
         entry_target_seq_tag[fe_selected_rob_id3]);

    assign d3_cache_data0 = dep_cache_data[entry_target_residue[fe_selected_rob_id0]];
    assign d3_cache_data1 = dep_cache_data[entry_target_residue[fe_selected_rob_id1]];
    assign d3_cache_data2 = dep_cache_data[entry_target_residue[fe_selected_rob_id2]];
    assign d3_cache_data3 = dep_cache_data[entry_target_residue[fe_selected_rob_id3]];

    assign fe_in_valid0 = rst_n && fe_reserved0 &&
                          ((entry_dep_offset[fe_selected_rob_id0] == 3'd0) ||
                           d3_cache_hit0 ||
                           (fallback_from_d3 && (fallback_d3_fe_id == 2'd0) &&
                            fallback_ready));
    assign fe_in_data0 = fe_reserved0 ? entry_packet[fe_selected_rob_id0] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid0 = fe_in_valid0 &&
                           (entry_dep_offset[fe_selected_rob_id0] != 3'd0);
    assign fe_dep_data0 = fe_dep_valid0 ?
        (d3_cache_hit0 ? d3_cache_data0 : fallback_data) : {PACKET_W{1'b0}};
    assign fe_desc_delay0 = fe_reserved0 ? entry_desc_delay[fe_selected_rob_id0] : 2'd0;
    assign fe_in_valid1 = rst_n && fe_reserved1 &&
                          ((entry_dep_offset[fe_selected_rob_id1] == 3'd0) ||
                           d3_cache_hit1 ||
                           (fallback_from_d3 && (fallback_d3_fe_id == 2'd1) &&
                            fallback_ready));
    assign fe_in_data1 = fe_reserved1 ? entry_packet[fe_selected_rob_id1] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid1 = fe_in_valid1 &&
                           (entry_dep_offset[fe_selected_rob_id1] != 3'd0);
    assign fe_dep_data1 = fe_dep_valid1 ?
        (d3_cache_hit1 ? d3_cache_data1 : fallback_data) : {PACKET_W{1'b0}};
    assign fe_desc_delay1 = fe_reserved1 ? entry_desc_delay[fe_selected_rob_id1] : 2'd0;
    assign fe_in_valid2 = rst_n && fe_reserved2 &&
                          ((entry_dep_offset[fe_selected_rob_id2] == 3'd0) ||
                           d3_cache_hit2 ||
                           (fallback_from_d3 && (fallback_d3_fe_id == 2'd2) &&
                            fallback_ready));
    assign fe_in_data2 = fe_reserved2 ? entry_packet[fe_selected_rob_id2] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid2 = fe_in_valid2 &&
                           (entry_dep_offset[fe_selected_rob_id2] != 3'd0);
    assign fe_dep_data2 = fe_dep_valid2 ?
        (d3_cache_hit2 ? d3_cache_data2 : fallback_data) : {PACKET_W{1'b0}};
    assign fe_desc_delay2 = fe_reserved2 ? entry_desc_delay[fe_selected_rob_id2] : 2'd0;
    assign fe_in_valid3 = rst_n && fe_reserved3 &&
                          ((entry_dep_offset[fe_selected_rob_id3] == 3'd0) ||
                           d3_cache_hit3 ||
                           (fallback_from_d3 && (fallback_d3_fe_id == 2'd3) &&
                            fallback_ready));
    assign fe_in_data3 = fe_reserved3 ? entry_packet[fe_selected_rob_id3] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid3 = fe_in_valid3 &&
                           (entry_dep_offset[fe_selected_rob_id3] != 3'd0);
    assign fe_dep_data3 = fe_dep_valid3 ?
        (d3_cache_hit3 ? d3_cache_data3 : fallback_data) : {PACKET_W{1'b0}};
    assign fe_desc_delay3 = fe_reserved3 ? entry_desc_delay[fe_selected_rob_id3] : 2'd0;

    assign wb_valid0 = fe_out_valid0 && fe_busy0;
    assign wb_rob_id0 = fe_rob_id0;
    assign wb_seq_tag0 = fe_seq_tag0;
    assign wb_data0 = fe_out_data0;
    assign wb_valid1 = fe_out_valid1 && fe_busy1;
    assign wb_rob_id1 = fe_rob_id1;
    assign wb_seq_tag1 = fe_seq_tag1;
    assign wb_data1 = fe_out_data1;
    assign wb_valid2 = fe_out_valid2 && fe_busy2;
    assign wb_rob_id2 = fe_rob_id2;
    assign wb_seq_tag2 = fe_seq_tag2;
    assign wb_data2 = fe_out_data2;
    assign wb_valid3 = fe_out_valid3 && fe_busy3;
    assign wb_rob_id3 = fe_rob_id3;
    assign wb_seq_tag3 = fe_seq_tag3;
    assign wb_data3 = fe_out_data3;

    assign alloc_valid = {alloc_valid3, alloc_valid2, alloc_valid1, alloc_valid0};
    assign alloc_seq_tag = {alloc_seq_tag3, alloc_seq_tag2,
                            alloc_seq_tag1, alloc_seq_tag0};
    assign alloc_seq_residue = {alloc_seq_residue3, alloc_seq_residue2,
                                alloc_seq_residue1, alloc_seq_residue0};
    assign fe_in_valid = {fe_in_valid3, fe_in_valid2, fe_in_valid1, fe_in_valid0};
    assign fe_in_data = {fe_in_data3, fe_in_data2, fe_in_data1, fe_in_data0};
    assign fe_dep_valid = {fe_dep_valid3, fe_dep_valid2,
                           fe_dep_valid1, fe_dep_valid0};
    assign fe_dep_data = {fe_dep_data3, fe_dep_data2,
                          fe_dep_data1, fe_dep_data0};
    assign fe_desc_delay = {fe_desc_delay3, fe_desc_delay2,
                            fe_desc_delay1, fe_desc_delay0};
    assign wb_valid = {wb_valid3, wb_valid2, wb_valid1, wb_valid0};
    assign wb_rob_id = {wb_rob_id3, wb_rob_id2, wb_rob_id1, wb_rob_id0};
    assign wb_seq_tag = {wb_seq_tag3, wb_seq_tag2, wb_seq_tag1, wb_seq_tag0};
    assign wb_data = {wb_data3, wb_data2, wb_data1, wb_data0};

    assign d1_resolved0 = d1_cache_hit0 ||
                          (d1_init_valid0 &&
                           ((wb_valid0 && (entry_target_rob_id[d1_init_rob_id0] == wb_rob_id0) &&
                             (entry_target_seq_tag[d1_init_rob_id0] == wb_seq_tag0)) ||
                            (wb_valid1 && (entry_target_rob_id[d1_init_rob_id0] == wb_rob_id1) &&
                             (entry_target_seq_tag[d1_init_rob_id0] == wb_seq_tag1)) ||
                            (wb_valid2 && (entry_target_rob_id[d1_init_rob_id0] == wb_rob_id2) &&
                             (entry_target_seq_tag[d1_init_rob_id0] == wb_seq_tag2)) ||
                            (wb_valid3 && (entry_target_rob_id[d1_init_rob_id0] == wb_rob_id3) &&
                             (entry_target_seq_tag[d1_init_rob_id0] == wb_seq_tag3))));
    assign d1_resolved1 = d1_cache_hit1 ||
                          (d1_init_valid1 &&
                           ((wb_valid0 && (entry_target_rob_id[d1_init_rob_id1] == wb_rob_id0) &&
                             (entry_target_seq_tag[d1_init_rob_id1] == wb_seq_tag0)) ||
                            (wb_valid1 && (entry_target_rob_id[d1_init_rob_id1] == wb_rob_id1) &&
                             (entry_target_seq_tag[d1_init_rob_id1] == wb_seq_tag1)) ||
                            (wb_valid2 && (entry_target_rob_id[d1_init_rob_id1] == wb_rob_id2) &&
                             (entry_target_seq_tag[d1_init_rob_id1] == wb_seq_tag2)) ||
                            (wb_valid3 && (entry_target_rob_id[d1_init_rob_id1] == wb_rob_id3) &&
                             (entry_target_seq_tag[d1_init_rob_id1] == wb_seq_tag3))));
    assign d1_resolved2 = d1_cache_hit2 ||
                          (d1_init_valid2 &&
                           ((wb_valid0 && (entry_target_rob_id[d1_init_rob_id2] == wb_rob_id0) &&
                             (entry_target_seq_tag[d1_init_rob_id2] == wb_seq_tag0)) ||
                            (wb_valid1 && (entry_target_rob_id[d1_init_rob_id2] == wb_rob_id1) &&
                             (entry_target_seq_tag[d1_init_rob_id2] == wb_seq_tag1)) ||
                            (wb_valid2 && (entry_target_rob_id[d1_init_rob_id2] == wb_rob_id2) &&
                             (entry_target_seq_tag[d1_init_rob_id2] == wb_seq_tag2)) ||
                            (wb_valid3 && (entry_target_rob_id[d1_init_rob_id2] == wb_rob_id3) &&
                             (entry_target_seq_tag[d1_init_rob_id2] == wb_seq_tag3))));
    assign d1_resolved3 = d1_cache_hit3 ||
                          (d1_init_valid3 &&
                           ((wb_valid0 && (entry_target_rob_id[d1_init_rob_id3] == wb_rob_id0) &&
                             (entry_target_seq_tag[d1_init_rob_id3] == wb_seq_tag0)) ||
                            (wb_valid1 && (entry_target_rob_id[d1_init_rob_id3] == wb_rob_id1) &&
                             (entry_target_seq_tag[d1_init_rob_id3] == wb_seq_tag1)) ||
                            (wb_valid2 && (entry_target_rob_id[d1_init_rob_id3] == wb_rob_id2) &&
                             (entry_target_seq_tag[d1_init_rob_id3] == wb_seq_tag2)) ||
                            (wb_valid3 && (entry_target_rob_id[d1_init_rob_id3] == wb_rob_id3) &&
                             (entry_target_seq_tag[d1_init_rob_id3] == wb_seq_tag3))));

    assign fallback_valid = fallback_valid_r;
    assign fallback_rob_id = fallback_rob_id_r;
    assign fallback_seq_tag = fallback_seq_tag_r;
    assign fallback_residue = fallback_residue_r;

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
                (((fallback_index == 0) && fe_reserved0 &&
                  (entry_dep_offset[fe_selected_rob_id0] != 3'd0) && !d3_cache_hit0) ||
                 ((fallback_index == 1) && fe_reserved1 &&
                  (entry_dep_offset[fe_selected_rob_id1] != 3'd0) && !d3_cache_hit1) ||
                 ((fallback_index == 2) && fe_reserved2 &&
                  (entry_dep_offset[fe_selected_rob_id2] != 3'd0) && !d3_cache_hit2) ||
                 ((fallback_index == 3) && fe_reserved3 &&
                  (entry_dep_offset[fe_selected_rob_id3] != 3'd0) && !d3_cache_hit3))) begin
                fallback_d3_found = 1'b1;
                fallback_d3_any = 1'b1;
                fallback_d3_selected = fallback_index[1:0];
            end
        end

        for (fallback_scan = 0; fallback_scan < 16;
             fallback_scan = fallback_scan + 1) begin
            fallback_index = ({28'd0, fallback_entry_rr_ptr} + fallback_scan) & 32'd15;
            if (!fallback_entry_found && entry_valid[fallback_index] &&
                (entry_state[fallback_index] == ST_FALLBACK) &&
                !(dep_cache_valid[entry_target_residue[fallback_index]] &&
                  (dep_cache_seq_tag[entry_target_residue[fallback_index]] ==
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

        if (fallback_d3_any &&
            (!fallback_entry_any || !fallback_class_rr)) begin
            fallback_valid_r = 1'b1;
            fallback_from_d3 = 1'b1;
            fallback_d3_fe_id = fallback_d3_selected;
            case (fallback_d3_selected)
                2'd0: fallback_entry_id = fe_selected_rob_id0;
                2'd1: fallback_entry_id = fe_selected_rob_id1;
                2'd2: fallback_entry_id = fe_selected_rob_id2;
                default: fallback_entry_id = fe_selected_rob_id3;
            endcase
        end else if (fallback_entry_any) begin
            fallback_valid_r = 1'b1;
            fallback_entry_id = fallback_entry_selected;
        end

        if (fallback_valid_r) begin
            fallback_rob_id_r = entry_target_rob_id[fallback_entry_id];
            fallback_seq_tag_r = entry_target_seq_tag[fallback_entry_id];
            fallback_residue_r = entry_target_residue[fallback_entry_id];
        end
    end

    always @(*) begin
        for (scan_pos = 0; scan_pos < 16; scan_pos = scan_pos + 1) begin
            eligible_mask[scan_pos] = entry_valid[scan_pos] &&
                                      (entry_state[scan_pos] == ST_READY) &&
                                      entry_dep_ready[scan_pos] &&
                                      !entry_reserved[scan_pos];
        end
        for (scan_pos = 0; scan_pos < 4; scan_pos = scan_pos + 1) begin
            packet_list[scan_pos] = 4'd0;
            fe_list[scan_pos] = 2'd0;
        end

        available_fe_count = 0;
        for (scan_pos = 0; scan_pos < 4; scan_pos = scan_pos + 1) begin
            scan_index = ({30'd0, fe_rr_ptr} + scan_pos) & 32'd3;
            if (((scan_index == 0) && !fe_busy0 && !fe_reserved0) ||
                ((scan_index == 1) && !fe_busy1 && !fe_reserved1) ||
                ((scan_index == 2) && !fe_busy2 && !fe_reserved2) ||
                ((scan_index == 3) && !fe_busy3 && !fe_reserved3)) begin
                fe_list[available_fe_count] = scan_index[1:0];
                available_fe_count = available_fe_count + 1;
            end
        end

        for (scan_pos = 0; scan_pos < 16; scan_pos = scan_pos + 1) begin
            scan_index = ({28'd0, packet_rr_ptr} + scan_pos) & 32'd15;
            rotated_eligible[scan_pos] = eligible_mask[scan_index];
        end

        group_count0 = {2'b00, rotated_eligible[0]} +
                       {2'b00, rotated_eligible[1]} +
                       {2'b00, rotated_eligible[2]} +
                       {2'b00, rotated_eligible[3]};
        group_count1 = {2'b00, rotated_eligible[4]} +
                       {2'b00, rotated_eligible[5]} +
                       {2'b00, rotated_eligible[6]} +
                       {2'b00, rotated_eligible[7]};
        group_count2 = {2'b00, rotated_eligible[8]} +
                       {2'b00, rotated_eligible[9]} +
                       {2'b00, rotated_eligible[10]} +
                       {2'b00, rotated_eligible[11]};
        group_count3 = {2'b00, rotated_eligible[12]} +
                       {2'b00, rotated_eligible[13]} +
                       {2'b00, rotated_eligible[14]} +
                       {2'b00, rotated_eligible[15]};

        rotated_rank[0] = 5'd0;
        rotated_rank[1] = {4'b0000, rotated_eligible[0]};
        rotated_rank[2] = {4'b0000, rotated_eligible[0]} +
                          {4'b0000, rotated_eligible[1]};
        rotated_rank[3] = {4'b0000, rotated_eligible[0]} +
                          {4'b0000, rotated_eligible[1]} +
                          {4'b0000, rotated_eligible[2]};
        rotated_rank[4] = {2'b00, group_count0};
        rotated_rank[5] = {2'b00, group_count0} +
                          {4'b0000, rotated_eligible[4]};
        rotated_rank[6] = {2'b00, group_count0} +
                          {4'b0000, rotated_eligible[4]} +
                          {4'b0000, rotated_eligible[5]};
        rotated_rank[7] = {2'b00, group_count0} +
                          {4'b0000, rotated_eligible[4]} +
                          {4'b0000, rotated_eligible[5]} +
                          {4'b0000, rotated_eligible[6]};
        rotated_rank[8] = {2'b00, group_count0} + {2'b00, group_count1};
        rotated_rank[9] = {2'b00, group_count0} + {2'b00, group_count1} +
                          {4'b0000, rotated_eligible[8]};
        rotated_rank[10] = {2'b00, group_count0} + {2'b00, group_count1} +
                           {4'b0000, rotated_eligible[8]} +
                           {4'b0000, rotated_eligible[9]};
        rotated_rank[11] = {2'b00, group_count0} + {2'b00, group_count1} +
                           {4'b0000, rotated_eligible[8]} +
                           {4'b0000, rotated_eligible[9]} +
                           {4'b0000, rotated_eligible[10]};
        rotated_rank[12] = {2'b00, group_count0} + {2'b00, group_count1} +
                           {2'b00, group_count2};
        rotated_rank[13] = {2'b00, group_count0} + {2'b00, group_count1} +
                           {2'b00, group_count2} +
                           {4'b0000, rotated_eligible[12]};
        rotated_rank[14] = {2'b00, group_count0} + {2'b00, group_count1} +
                           {2'b00, group_count2} +
                           {4'b0000, rotated_eligible[12]} +
                           {4'b0000, rotated_eligible[13]};
        rotated_rank[15] = {2'b00, group_count0} + {2'b00, group_count1} +
                           {2'b00, group_count2} +
                           {4'b0000, rotated_eligible[12]} +
                           {4'b0000, rotated_eligible[13]} +
                           {4'b0000, rotated_eligible[14]};

        packet_count = {29'd0, group_count0} + {29'd0, group_count1} +
                       {29'd0, group_count2} + {29'd0, group_count3};
        if (packet_count > available_fe_count) begin
            packet_count = available_fe_count;
        end
        if (packet_count > 4) begin
            packet_count = 4;
        end
        for (scan_pos = 0; scan_pos < 16; scan_pos = scan_pos + 1) begin
            if (rotated_eligible[scan_pos] &&
                ({27'd0, rotated_rank[scan_pos]} < packet_count)) begin
                scan_index = ({28'd0, packet_rr_ptr} + scan_pos) & 32'd15;
                packet_list[rotated_rank[scan_pos][1:0]] = scan_index[3:0];
            end
        end

        d2_select_valid0 = 1'b0;
        d2_select_rob_id0 = 4'd0;
        d2_select_valid1 = 1'b0;
        d2_select_rob_id1 = 4'd0;
        d2_select_valid2 = 1'b0;
        d2_select_rob_id2 = 4'd0;
        d2_select_valid3 = 1'b0;
        d2_select_rob_id3 = 4'd0;
        d2_last_rob_id = packet_rr_ptr;
        d2_last_fe_id = fe_rr_ptr;
        for (pair_index = 0; pair_index < 4; pair_index = pair_index + 1) begin
            if (pair_index < packet_count) begin
                d2_last_rob_id = packet_list[pair_index];
                d2_last_fe_id = fe_list[pair_index];
                case (fe_list[pair_index])
                    2'd0: begin
                        d2_select_valid0 = 1'b1;
                        d2_select_rob_id0 = packet_list[pair_index];
                    end
                    2'd1: begin
                        d2_select_valid1 = 1'b1;
                        d2_select_rob_id1 = packet_list[pair_index];
                    end
                    2'd2: begin
                        d2_select_valid2 = 1'b1;
                        d2_select_rob_id2 = packet_list[pair_index];
                    end
                    default: begin
                        d2_select_valid3 = 1'b1;
                        d2_select_rob_id3 = packet_list[pair_index];
                    end
                endcase
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_seq_tag <= 5'd0;
            next_seq_residue <= 3'd0;
            history_count <= 3'd0;
            packet_rr_ptr <= 4'd0;
            fe_rr_ptr <= 2'd0;
            fallback_class_rr <= 1'b0;
            fallback_fe_rr_ptr <= 2'd0;
            fallback_entry_rr_ptr <= 4'd0;
            d1_init_valid0 <= 1'b0;
            d1_init_valid1 <= 1'b0;
            d1_init_valid2 <= 1'b0;
            d1_init_valid3 <= 1'b0;
            fe_busy0 <= 1'b0;
            fe_reserved0 <= 1'b0;
            fe_busy1 <= 1'b0;
            fe_reserved1 <= 1'b0;
            fe_busy2 <= 1'b0;
            fe_reserved2 <= 1'b0;
            fe_busy3 <= 1'b0;
            fe_reserved3 <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                entry_valid[i] <= 1'b0;
                entry_dep_ready[i] <= 1'b0;
                entry_reserved[i] <= 1'b0;
                entry_state[i] <= ST_DEP_INIT;
            end
            for (i = 0; i < 8; i = i + 1) begin
                dep_cache_valid[i] <= 1'b0;
            end
        end else begin
            d1_init_valid0 <= 1'b0;
            d1_init_valid1 <= 1'b0;
            d1_init_valid2 <= 1'b0;
            d1_init_valid3 <= 1'b0;

            if (d1_init_valid0) begin
                entry_dep_ready[d1_init_rob_id0] <= d1_resolved0;
                entry_state[d1_init_rob_id0] <= d1_resolved0 ?
                                               ST_READY : ST_FALLBACK;
            end
            if (d1_init_valid1) begin
                entry_dep_ready[d1_init_rob_id1] <= d1_resolved1;
                entry_state[d1_init_rob_id1] <= d1_resolved1 ?
                                               ST_READY : ST_FALLBACK;
            end
            if (d1_init_valid2) begin
                entry_dep_ready[d1_init_rob_id2] <= d1_resolved2;
                entry_state[d1_init_rob_id2] <= d1_resolved2 ?
                                               ST_READY : ST_FALLBACK;
            end
            if (d1_init_valid3) begin
                entry_dep_ready[d1_init_rob_id3] <= d1_resolved3;
                entry_state[d1_init_rob_id3] <= d1_resolved3 ?
                                               ST_READY : ST_FALLBACK;
            end

            if (fallback_valid_r) begin
                if (fallback_from_d3) begin
                    fallback_fe_rr_ptr <= fallback_d3_fe_id + 2'd1;
                end else begin
                    fallback_entry_rr_ptr <= fallback_entry_id + 4'd1;
                    entry_dep_ready[fallback_entry_id] <= fallback_ready;
                    entry_state[fallback_entry_id] <= fallback_ready ?
                                                        ST_READY : ST_WAIT_DEP;
                    if (fallback_ready) begin
                        dep_cache_valid[fallback_residue_r] <= 1'b1;
                        dep_cache_seq_tag[fallback_residue_r] <= fallback_seq_tag_r;
                        dep_cache_data[fallback_residue_r] <= fallback_data;
                    end
                end
                if (fallback_d3_any && fallback_entry_any) begin
                    fallback_class_rr <= !fallback_class_rr;
                end
            end

            for (i = 0; i < 16; i = i + 1) begin
                if (entry_valid[i] && (entry_state[i] == ST_FALLBACK) &&
                    dep_cache_valid[entry_target_residue[i]] &&
                    (dep_cache_seq_tag[entry_target_residue[i]] ==
                     entry_target_seq_tag[i])) begin
                    entry_dep_ready[i] <= 1'b1;
                    entry_state[i] <= ST_READY;
                end
                if (entry_valid[i] &&
                    ((entry_state[i] == ST_WAIT_DEP) ||
                     (entry_state[i] == ST_FALLBACK)) &&
                    ((wb_valid0 &&
                      (entry_target_rob_id[i] == wb_rob_id0) &&
                      (entry_target_seq_tag[i] == wb_seq_tag0)) ||
                     (wb_valid1 &&
                      (entry_target_rob_id[i] == wb_rob_id1) &&
                      (entry_target_seq_tag[i] == wb_seq_tag1)) ||
                     (wb_valid2 &&
                      (entry_target_rob_id[i] == wb_rob_id2) &&
                      (entry_target_seq_tag[i] == wb_seq_tag2)) ||
                     (wb_valid3 &&
                      (entry_target_rob_id[i] == wb_rob_id3) &&
                      (entry_target_seq_tag[i] == wb_seq_tag3)))) begin
                    entry_dep_ready[i] <= 1'b1;
                    entry_state[i] <= ST_READY;
                end
            end

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

            if (fe_out_valid0 && fe_busy0) fe_busy0 <= 1'b0;
            if (fe_out_valid1 && fe_busy1) fe_busy1 <= 1'b0;
            if (fe_out_valid2 && fe_busy2) fe_busy2 <= 1'b0;
            if (fe_out_valid3 && fe_busy3) fe_busy3 <= 1'b0;

            if (fe_in_valid0) begin
                entry_valid[fe_selected_rob_id0] <= 1'b0;
                entry_reserved[fe_selected_rob_id0] <= 1'b0;
                fe_reserved0 <= 1'b0;
                fe_busy0 <= 1'b1;
                fe_rob_id0 <= fe_selected_rob_id0;
                fe_seq_tag0 <= entry_seq_tag[fe_selected_rob_id0];
            end
            if (fe_in_valid1) begin
                entry_valid[fe_selected_rob_id1] <= 1'b0;
                entry_reserved[fe_selected_rob_id1] <= 1'b0;
                fe_reserved1 <= 1'b0;
                fe_busy1 <= 1'b1;
                fe_rob_id1 <= fe_selected_rob_id1;
                fe_seq_tag1 <= entry_seq_tag[fe_selected_rob_id1];
            end
            if (fe_in_valid2) begin
                entry_valid[fe_selected_rob_id2] <= 1'b0;
                entry_reserved[fe_selected_rob_id2] <= 1'b0;
                fe_reserved2 <= 1'b0;
                fe_busy2 <= 1'b1;
                fe_rob_id2 <= fe_selected_rob_id2;
                fe_seq_tag2 <= entry_seq_tag[fe_selected_rob_id2];
            end
            if (fe_in_valid3) begin
                entry_valid[fe_selected_rob_id3] <= 1'b0;
                entry_reserved[fe_selected_rob_id3] <= 1'b0;
                fe_reserved3 <= 1'b0;
                fe_busy3 <= 1'b1;
                fe_rob_id3 <= fe_selected_rob_id3;
                fe_seq_tag3 <= entry_seq_tag[fe_selected_rob_id3];
            end

            if (d2_select_valid0) begin
                fe_reserved0 <= 1'b1;
                fe_selected_rob_id0 <= d2_select_rob_id0;
                entry_reserved[d2_select_rob_id0] <= 1'b1;
                entry_state[d2_select_rob_id0] <= ST_SELECTED;
            end
            if (d2_select_valid1) begin
                fe_reserved1 <= 1'b1;
                fe_selected_rob_id1 <= d2_select_rob_id1;
                entry_reserved[d2_select_rob_id1] <= 1'b1;
                entry_state[d2_select_rob_id1] <= ST_SELECTED;
            end
            if (d2_select_valid2) begin
                fe_reserved2 <= 1'b1;
                fe_selected_rob_id2 <= d2_select_rob_id2;
                entry_reserved[d2_select_rob_id2] <= 1'b1;
                entry_state[d2_select_rob_id2] <= ST_SELECTED;
            end
            if (d2_select_valid3) begin
                fe_reserved3 <= 1'b1;
                fe_selected_rob_id3 <= d2_select_rob_id3;
                entry_reserved[d2_select_rob_id3] <= 1'b1;
                entry_state[d2_select_rob_id3] <= ST_SELECTED;
            end
            if (packet_count != 0) begin
                packet_rr_ptr <= d2_last_rob_id + 4'd1;
                fe_rr_ptr <= d2_last_fe_id + 2'd1;
            end

            if (alloc_valid0) begin
                entry_valid[alloc_rob_id0] <= 1'b1;
                entry_packet[alloc_rob_id0] <= in_packet0;
                entry_seq_tag[alloc_rob_id0] <= alloc_seq_tag0;
                entry_desc_delay[alloc_rob_id0] <= in_desc0[1:0];
                entry_dep_offset[alloc_rob_id0] <= effective_dep0;
                entry_target_rob_id[alloc_rob_id0] <= alloc_rob_id0 - effective_dep0;
                entry_target_seq_tag[alloc_rob_id0] <=
                    alloc_seq_tag0 - {2'b00, effective_dep0};
                entry_target_residue[alloc_rob_id0] <=
                    residue_sub(alloc_seq_residue0, effective_dep0);
                entry_reserved[alloc_rob_id0] <= 1'b0;
                entry_dep_ready[alloc_rob_id0] <= (effective_dep0 == 3'd0);
                entry_state[alloc_rob_id0] <= (effective_dep0 == 3'd0) ?
                                             ST_READY : ST_DEP_INIT;
                d1_init_valid0 <= (effective_dep0 != 3'd0);
                d1_init_rob_id0 <= alloc_rob_id0;
            end
            if (alloc_valid1) begin
                entry_valid[alloc_rob_id1] <= 1'b1;
                entry_packet[alloc_rob_id1] <= in_packet1;
                entry_seq_tag[alloc_rob_id1] <= alloc_seq_tag1;
                entry_desc_delay[alloc_rob_id1] <= in_desc1[1:0];
                entry_dep_offset[alloc_rob_id1] <= effective_dep1;
                entry_target_rob_id[alloc_rob_id1] <= alloc_rob_id1 - effective_dep1;
                entry_target_seq_tag[alloc_rob_id1] <=
                    alloc_seq_tag1 - {2'b00, effective_dep1};
                entry_target_residue[alloc_rob_id1] <=
                    residue_sub(alloc_seq_residue1, effective_dep1);
                entry_reserved[alloc_rob_id1] <= 1'b0;
                entry_dep_ready[alloc_rob_id1] <= (effective_dep1 == 3'd0);
                entry_state[alloc_rob_id1] <= (effective_dep1 == 3'd0) ?
                                             ST_READY : ST_DEP_INIT;
                d1_init_valid1 <= (effective_dep1 != 3'd0);
                d1_init_rob_id1 <= alloc_rob_id1;
            end
            if (alloc_valid2) begin
                entry_valid[alloc_rob_id2] <= 1'b1;
                entry_packet[alloc_rob_id2] <= in_packet2;
                entry_seq_tag[alloc_rob_id2] <= alloc_seq_tag2;
                entry_desc_delay[alloc_rob_id2] <= in_desc2[1:0];
                entry_dep_offset[alloc_rob_id2] <= effective_dep2;
                entry_target_rob_id[alloc_rob_id2] <= alloc_rob_id2 - effective_dep2;
                entry_target_seq_tag[alloc_rob_id2] <=
                    alloc_seq_tag2 - {2'b00, effective_dep2};
                entry_target_residue[alloc_rob_id2] <=
                    residue_sub(alloc_seq_residue2, effective_dep2);
                entry_reserved[alloc_rob_id2] <= 1'b0;
                entry_dep_ready[alloc_rob_id2] <= (effective_dep2 == 3'd0);
                entry_state[alloc_rob_id2] <= (effective_dep2 == 3'd0) ?
                                             ST_READY : ST_DEP_INIT;
                d1_init_valid2 <= (effective_dep2 != 3'd0);
                d1_init_rob_id2 <= alloc_rob_id2;
            end
            if (alloc_valid3) begin
                entry_valid[alloc_rob_id3] <= 1'b1;
                entry_packet[alloc_rob_id3] <= in_packet3;
                entry_seq_tag[alloc_rob_id3] <= alloc_seq_tag3;
                entry_desc_delay[alloc_rob_id3] <= in_desc3[1:0];
                entry_dep_offset[alloc_rob_id3] <= effective_dep3;
                entry_target_rob_id[alloc_rob_id3] <= alloc_rob_id3 - effective_dep3;
                entry_target_seq_tag[alloc_rob_id3] <=
                    alloc_seq_tag3 - {2'b00, effective_dep3};
                entry_target_residue[alloc_rob_id3] <=
                    residue_sub(alloc_seq_residue3, effective_dep3);
                entry_reserved[alloc_rob_id3] <= 1'b0;
                entry_dep_ready[alloc_rob_id3] <= (effective_dep3 == 3'd0);
                entry_state[alloc_rob_id3] <= (effective_dep3 == 3'd0) ?
                                             ST_READY : ST_DEP_INIT;
                d1_init_valid3 <= (effective_dep3 != 3'd0);
                d1_init_rob_id3 <= alloc_rob_id3;
            end

            if (!bkps && (accept_count != 3'd0)) begin
                next_seq_tag <= next_seq_tag + {2'b00, accept_count};
                next_seq_residue <= residue_add(next_seq_residue, accept_count);
                if (({1'b0, history_count} + {1'b0, accept_count}) >= 4'd7) begin
                    history_count <= 3'd7;
                end else begin
                    history_count <= history_count + accept_count;
                end
            end
        end
    end

endmodule
