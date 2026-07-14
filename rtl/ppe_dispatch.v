`timescale 1ns/1ps

module ppe_dispatch #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,
    input                       bkps,

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

    output                      dep_status_valid0,
    output     [3:0]            dep_status_rob_id0,
    output     [4:0]            dep_status_seq_tag0,
    output     [2:0]            dep_status_residue0,
    input                       dep_status_ready0,
    output                      dep_status_valid1,
    output     [3:0]            dep_status_rob_id1,
    output     [4:0]            dep_status_seq_tag1,
    output     [2:0]            dep_status_residue1,
    input                       dep_status_ready1,
    output                      dep_status_valid2,
    output     [3:0]            dep_status_rob_id2,
    output     [4:0]            dep_status_seq_tag2,
    output     [2:0]            dep_status_residue2,
    input                       dep_status_ready2,
    output                      dep_status_valid3,
    output     [3:0]            dep_status_rob_id3,
    output     [4:0]            dep_status_seq_tag3,
    output     [2:0]            dep_status_residue3,
    input                       dep_status_ready3,

    output                      dep_data_valid0,
    output     [3:0]            dep_data_rob_id0,
    output     [4:0]            dep_data_seq_tag0,
    output     [2:0]            dep_data_residue0,
    input                       dep_data_ready0,
    input      [PACKET_W-1:0]   dep_data0,
    output                      dep_data_valid1,
    output     [3:0]            dep_data_rob_id1,
    output     [4:0]            dep_data_seq_tag1,
    output     [2:0]            dep_data_residue1,
    input                       dep_data_ready1,
    input      [PACKET_W-1:0]   dep_data1,
    output                      dep_data_valid2,
    output     [3:0]            dep_data_rob_id2,
    output     [4:0]            dep_data_seq_tag2,
    output     [2:0]            dep_data_residue2,
    input                       dep_data_ready2,
    input      [PACKET_W-1:0]   dep_data2,
    output                      dep_data_valid3,
    output     [3:0]            dep_data_rob_id3,
    output     [4:0]            dep_data_seq_tag3,
    output     [2:0]            dep_data_residue3,
    input                       dep_data_ready3,
    input      [PACKET_W-1:0]   dep_data3,

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

    localparam [1:0] ST_DEP_INIT = 2'd0;
    localparam [1:0] ST_WAIT_DEP = 2'd1;
    localparam [1:0] ST_READY    = 2'd2;
    localparam [1:0] ST_SELECTED = 2'd3;

    reg                       entry_valid [0:15];
    reg [PACKET_W-1:0]        entry_packet [0:15];
    reg [4:0]                 entry_seq_tag [0:15];
    reg [2:0]                 entry_seq_residue [0:15];
    reg [1:0]                 entry_desc_delay [0:15];
    reg [2:0]                 entry_dep_offset [0:15];
    reg [3:0]                 entry_target_rob_id [0:15];
    reg [4:0]                 entry_target_seq_tag [0:15];
    reg [2:0]                 entry_target_residue [0:15];
    reg                       entry_dep_ready [0:15];
    reg                       entry_reserved [0:15];
    reg [1:0]                 entry_state [0:15];

    reg [4:0]                 next_seq_tag;
    reg [2:0]                 next_seq_residue;
    reg [2:0]                 history_count;
    reg [3:0]                 packet_rr_ptr;
    reg [1:0]                 fe_rr_ptr;

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
            case (increment)
                3'd0: residue_add = base;
                3'd1: residue_add = (base >= 3'd6) ? base - 3'd6 : base + 3'd1;
                3'd2: residue_add = (base >= 3'd5) ? base - 3'd5 : base + 3'd2;
                3'd3: residue_add = (base >= 3'd4) ? base - 3'd4 : base + 3'd3;
                3'd4: residue_add = (base >= 3'd3) ? base - 3'd3 : base + 3'd4;
                default: residue_add = base;
            endcase
        end
    endfunction

    function [2:0] residue_sub;
        input [2:0] base;
        input [2:0] decrement;
        begin
            case (decrement)
                3'd0: residue_sub = base;
                3'd1: residue_sub = (base < 3'd1) ? base + 3'd6 : base - 3'd1;
                3'd2: residue_sub = (base < 3'd2) ? base + 3'd5 : base - 3'd2;
                3'd3: residue_sub = (base < 3'd3) ? base + 3'd4 : base - 3'd3;
                3'd4: residue_sub = (base < 3'd4) ? base + 3'd3 : base - 3'd4;
                3'd5: residue_sub = (base < 3'd5) ? base + 3'd2 : base - 3'd5;
                3'd6: residue_sub = (base < 3'd6) ? base + 3'd1 : base - 3'd6;
                default: residue_sub = base;
            endcase
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

    assign dep_status_valid0 = d1_init_valid0;
    assign dep_status_rob_id0 = entry_target_rob_id[d1_init_rob_id0];
    assign dep_status_seq_tag0 = entry_target_seq_tag[d1_init_rob_id0];
    assign dep_status_residue0 = entry_target_residue[d1_init_rob_id0];
    assign dep_status_valid1 = d1_init_valid1;
    assign dep_status_rob_id1 = entry_target_rob_id[d1_init_rob_id1];
    assign dep_status_seq_tag1 = entry_target_seq_tag[d1_init_rob_id1];
    assign dep_status_residue1 = entry_target_residue[d1_init_rob_id1];
    assign dep_status_valid2 = d1_init_valid2;
    assign dep_status_rob_id2 = entry_target_rob_id[d1_init_rob_id2];
    assign dep_status_seq_tag2 = entry_target_seq_tag[d1_init_rob_id2];
    assign dep_status_residue2 = entry_target_residue[d1_init_rob_id2];
    assign dep_status_valid3 = d1_init_valid3;
    assign dep_status_rob_id3 = entry_target_rob_id[d1_init_rob_id3];
    assign dep_status_seq_tag3 = entry_target_seq_tag[d1_init_rob_id3];
    assign dep_status_residue3 = entry_target_residue[d1_init_rob_id3];

    assign dep_data_valid0 = fe_reserved0 &&
                             (entry_dep_offset[fe_selected_rob_id0] != 3'd0);
    assign dep_data_rob_id0 = entry_target_rob_id[fe_selected_rob_id0];
    assign dep_data_seq_tag0 = entry_target_seq_tag[fe_selected_rob_id0];
    assign dep_data_residue0 = residue_sub(entry_seq_residue[fe_selected_rob_id0],
                                            entry_dep_offset[fe_selected_rob_id0]);
    assign dep_data_valid1 = fe_reserved1 &&
                             (entry_dep_offset[fe_selected_rob_id1] != 3'd0);
    assign dep_data_rob_id1 = entry_target_rob_id[fe_selected_rob_id1];
    assign dep_data_seq_tag1 = entry_target_seq_tag[fe_selected_rob_id1];
    assign dep_data_residue1 = residue_sub(entry_seq_residue[fe_selected_rob_id1],
                                            entry_dep_offset[fe_selected_rob_id1]);
    assign dep_data_valid2 = fe_reserved2 &&
                             (entry_dep_offset[fe_selected_rob_id2] != 3'd0);
    assign dep_data_rob_id2 = entry_target_rob_id[fe_selected_rob_id2];
    assign dep_data_seq_tag2 = entry_target_seq_tag[fe_selected_rob_id2];
    assign dep_data_residue2 = residue_sub(entry_seq_residue[fe_selected_rob_id2],
                                            entry_dep_offset[fe_selected_rob_id2]);
    assign dep_data_valid3 = fe_reserved3 &&
                             (entry_dep_offset[fe_selected_rob_id3] != 3'd0);
    assign dep_data_rob_id3 = entry_target_rob_id[fe_selected_rob_id3];
    assign dep_data_seq_tag3 = entry_target_seq_tag[fe_selected_rob_id3];
    assign dep_data_residue3 = residue_sub(entry_seq_residue[fe_selected_rob_id3],
                                            entry_dep_offset[fe_selected_rob_id3]);

    assign fe_in_valid0 = rst_n && fe_reserved0 &&
                          ((entry_dep_offset[fe_selected_rob_id0] == 3'd0) ||
                           dep_data_ready0);
    assign fe_in_data0 = fe_reserved0 ? entry_packet[fe_selected_rob_id0] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid0 = fe_in_valid0 &&
                           (entry_dep_offset[fe_selected_rob_id0] != 3'd0);
    assign fe_dep_data0 = fe_dep_valid0 ? dep_data0 : {PACKET_W{1'b0}};
    assign fe_desc_delay0 = fe_reserved0 ? entry_desc_delay[fe_selected_rob_id0] : 2'd0;
    assign fe_in_valid1 = rst_n && fe_reserved1 &&
                          ((entry_dep_offset[fe_selected_rob_id1] == 3'd0) ||
                           dep_data_ready1);
    assign fe_in_data1 = fe_reserved1 ? entry_packet[fe_selected_rob_id1] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid1 = fe_in_valid1 &&
                           (entry_dep_offset[fe_selected_rob_id1] != 3'd0);
    assign fe_dep_data1 = fe_dep_valid1 ? dep_data1 : {PACKET_W{1'b0}};
    assign fe_desc_delay1 = fe_reserved1 ? entry_desc_delay[fe_selected_rob_id1] : 2'd0;
    assign fe_in_valid2 = rst_n && fe_reserved2 &&
                          ((entry_dep_offset[fe_selected_rob_id2] == 3'd0) ||
                           dep_data_ready2);
    assign fe_in_data2 = fe_reserved2 ? entry_packet[fe_selected_rob_id2] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid2 = fe_in_valid2 &&
                           (entry_dep_offset[fe_selected_rob_id2] != 3'd0);
    assign fe_dep_data2 = fe_dep_valid2 ? dep_data2 : {PACKET_W{1'b0}};
    assign fe_desc_delay2 = fe_reserved2 ? entry_desc_delay[fe_selected_rob_id2] : 2'd0;
    assign fe_in_valid3 = rst_n && fe_reserved3 &&
                          ((entry_dep_offset[fe_selected_rob_id3] == 3'd0) ||
                           dep_data_ready3);
    assign fe_in_data3 = fe_reserved3 ? entry_packet[fe_selected_rob_id3] :
                                        {PACKET_W{1'b0}};
    assign fe_dep_valid3 = fe_in_valid3 &&
                           (entry_dep_offset[fe_selected_rob_id3] != 3'd0);
    assign fe_dep_data3 = fe_dep_valid3 ? dep_data3 : {PACKET_W{1'b0}};
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

    assign d1_resolved0 = dep_status_ready0 ||
                          (d1_init_valid0 &&
                           ((wb_valid0 && (dep_status_rob_id0 == wb_rob_id0) &&
                             (dep_status_seq_tag0 == wb_seq_tag0)) ||
                            (wb_valid1 && (dep_status_rob_id0 == wb_rob_id1) &&
                             (dep_status_seq_tag0 == wb_seq_tag1)) ||
                            (wb_valid2 && (dep_status_rob_id0 == wb_rob_id2) &&
                             (dep_status_seq_tag0 == wb_seq_tag2)) ||
                            (wb_valid3 && (dep_status_rob_id0 == wb_rob_id3) &&
                             (dep_status_seq_tag0 == wb_seq_tag3))));
    assign d1_resolved1 = dep_status_ready1 ||
                          (d1_init_valid1 &&
                           ((wb_valid0 && (dep_status_rob_id1 == wb_rob_id0) &&
                             (dep_status_seq_tag1 == wb_seq_tag0)) ||
                            (wb_valid1 && (dep_status_rob_id1 == wb_rob_id1) &&
                             (dep_status_seq_tag1 == wb_seq_tag1)) ||
                            (wb_valid2 && (dep_status_rob_id1 == wb_rob_id2) &&
                             (dep_status_seq_tag1 == wb_seq_tag2)) ||
                            (wb_valid3 && (dep_status_rob_id1 == wb_rob_id3) &&
                             (dep_status_seq_tag1 == wb_seq_tag3))));
    assign d1_resolved2 = dep_status_ready2 ||
                          (d1_init_valid2 &&
                           ((wb_valid0 && (dep_status_rob_id2 == wb_rob_id0) &&
                             (dep_status_seq_tag2 == wb_seq_tag0)) ||
                            (wb_valid1 && (dep_status_rob_id2 == wb_rob_id1) &&
                             (dep_status_seq_tag2 == wb_seq_tag1)) ||
                            (wb_valid2 && (dep_status_rob_id2 == wb_rob_id2) &&
                             (dep_status_seq_tag2 == wb_seq_tag2)) ||
                            (wb_valid3 && (dep_status_rob_id2 == wb_rob_id3) &&
                             (dep_status_seq_tag2 == wb_seq_tag3))));
    assign d1_resolved3 = dep_status_ready3 ||
                          (d1_init_valid3 &&
                           ((wb_valid0 && (dep_status_rob_id3 == wb_rob_id0) &&
                             (dep_status_seq_tag3 == wb_seq_tag0)) ||
                            (wb_valid1 && (dep_status_rob_id3 == wb_rob_id1) &&
                             (dep_status_seq_tag3 == wb_seq_tag1)) ||
                            (wb_valid2 && (dep_status_rob_id3 == wb_rob_id2) &&
                             (dep_status_seq_tag3 == wb_seq_tag2)) ||
                            (wb_valid3 && (dep_status_rob_id3 == wb_rob_id3) &&
                             (dep_status_seq_tag3 == wb_seq_tag3))));

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
        end else begin
            d1_init_valid0 <= 1'b0;
            d1_init_valid1 <= 1'b0;
            d1_init_valid2 <= 1'b0;
            d1_init_valid3 <= 1'b0;

            if (d1_init_valid0) begin
                entry_dep_ready[d1_init_rob_id0] <= d1_resolved0;
                entry_state[d1_init_rob_id0] <= d1_resolved0 ?
                                               ST_READY : ST_WAIT_DEP;
            end
            if (d1_init_valid1) begin
                entry_dep_ready[d1_init_rob_id1] <= d1_resolved1;
                entry_state[d1_init_rob_id1] <= d1_resolved1 ?
                                               ST_READY : ST_WAIT_DEP;
            end
            if (d1_init_valid2) begin
                entry_dep_ready[d1_init_rob_id2] <= d1_resolved2;
                entry_state[d1_init_rob_id2] <= d1_resolved2 ?
                                               ST_READY : ST_WAIT_DEP;
            end
            if (d1_init_valid3) begin
                entry_dep_ready[d1_init_rob_id3] <= d1_resolved3;
                entry_state[d1_init_rob_id3] <= d1_resolved3 ?
                                               ST_READY : ST_WAIT_DEP;
            end

            for (i = 0; i < 16; i = i + 1) begin
                if (entry_valid[i] && (entry_state[i] == ST_WAIT_DEP) &&
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
                entry_seq_residue[alloc_rob_id0] <= alloc_seq_residue0;
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
                entry_seq_residue[alloc_rob_id1] <= alloc_seq_residue1;
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
                entry_seq_residue[alloc_rob_id2] <= alloc_seq_residue2;
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
                entry_seq_residue[alloc_rob_id3] <= alloc_seq_residue3;
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
