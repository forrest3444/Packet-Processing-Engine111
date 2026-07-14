`timescale 1ns/1ps

module ppe_reorder #(
    parameter integer PACKET_W = 128
) (
    input                       clk,
    input                       rst_n,

    input                       in_valid0,
    input                       in_valid1,
    input                       in_valid2,
    input                       in_valid3,
    output                      bkps,

    input                       alloc_valid0,
    input      [4:0]            alloc_seq_tag0,
    input      [2:0]            alloc_seq_residue0,
    output     [3:0]            alloc_rob_id0,
    input                       alloc_valid1,
    input      [4:0]            alloc_seq_tag1,
    input      [2:0]            alloc_seq_residue1,
    output     [3:0]            alloc_rob_id1,
    input                       alloc_valid2,
    input      [4:0]            alloc_seq_tag2,
    input      [2:0]            alloc_seq_residue2,
    output     [3:0]            alloc_rob_id2,
    input                       alloc_valid3,
    input      [4:0]            alloc_seq_tag3,
    input      [2:0]            alloc_seq_residue3,
    output     [3:0]            alloc_rob_id3,

    input                       dep_status_valid0,
    input      [3:0]            dep_status_rob_id0,
    input      [4:0]            dep_status_seq_tag0,
    input      [2:0]            dep_status_residue0,
    output                      dep_status_ready0,
    input                       dep_status_valid1,
    input      [3:0]            dep_status_rob_id1,
    input      [4:0]            dep_status_seq_tag1,
    input      [2:0]            dep_status_residue1,
    output                      dep_status_ready1,
    input                       dep_status_valid2,
    input      [3:0]            dep_status_rob_id2,
    input      [4:0]            dep_status_seq_tag2,
    input      [2:0]            dep_status_residue2,
    output                      dep_status_ready2,
    input                       dep_status_valid3,
    input      [3:0]            dep_status_rob_id3,
    input      [4:0]            dep_status_seq_tag3,
    input      [2:0]            dep_status_residue3,
    output                      dep_status_ready3,

    input                       dep_data_valid0,
    input      [3:0]            dep_data_rob_id0,
    input      [4:0]            dep_data_seq_tag0,
    input      [2:0]            dep_data_residue0,
    output                      dep_data_ready0,
    output     [PACKET_W-1:0]   dep_data0,
    input                       dep_data_valid1,
    input      [3:0]            dep_data_rob_id1,
    input      [4:0]            dep_data_seq_tag1,
    input      [2:0]            dep_data_residue1,
    output                      dep_data_ready1,
    output     [PACKET_W-1:0]   dep_data1,
    input                       dep_data_valid2,
    input      [3:0]            dep_data_rob_id2,
    input      [4:0]            dep_data_seq_tag2,
    input      [2:0]            dep_data_residue2,
    output                      dep_data_ready2,
    output     [PACKET_W-1:0]   dep_data2,
    input                       dep_data_valid3,
    input      [3:0]            dep_data_rob_id3,
    input      [4:0]            dep_data_seq_tag3,
    input      [2:0]            dep_data_residue3,
    output                      dep_data_ready3,
    output     [PACKET_W-1:0]   dep_data3,

    input                       wb_valid0,
    input      [3:0]            wb_rob_id0,
    input      [4:0]            wb_seq_tag0,
    input      [PACKET_W-1:0]   wb_data0,
    input                       wb_valid1,
    input      [3:0]            wb_rob_id1,
    input      [4:0]            wb_seq_tag1,
    input      [PACKET_W-1:0]   wb_data1,
    input                       wb_valid2,
    input      [3:0]            wb_rob_id2,
    input      [4:0]            wb_seq_tag2,
    input      [PACKET_W-1:0]   wb_data2,
    input                       wb_valid3,
    input      [3:0]            wb_rob_id3,
    input      [4:0]            wb_seq_tag3,
    input      [PACKET_W-1:0]   wb_data3,

    output reg                  out_valid0,
    output reg [PACKET_W-1:0]  out_packet0,
    output reg                  out_valid1,
    output reg [PACKET_W-1:0]  out_packet1,
    output reg                  out_valid2,
    output reg [PACKET_W-1:0]  out_packet2,
    output reg                  out_valid3,
    output reg [PACKET_W-1:0]  out_packet3
);

    reg                       rob_valid [0:15];
    reg [4:0]                 rob_seq_tag [0:15];
    reg [2:0]                 rob_seq_residue [0:15];
    reg                       rob_result_valid [0:15];
    reg [PACKET_W-1:0]        rob_data [0:15];

    reg                       result_valid [0:6];
    reg [4:0]                 result_seq_tag [0:6];
    reg [PACKET_W-1:0]        result_data [0:6];

    reg [3:0]                 head_ptr;
    reg [3:0]                 tail_ptr;
    reg [4:0]                 occupancy;
    reg [1:0]                 start_lane;

    wire [2:0] input_count;
    wire [2:0] alloc_count;
    wire [4:0] free_count;
    wire [3:0] head_idx0;
    wire [3:0] head_idx1;
    wire [3:0] head_idx2;
    wire [3:0] head_idx3;
    wire       done0;
    wire       done1;
    wire       done2;
    wire       done3;
    wire [2:0] retire_count;

    wire [PACKET_W:0] status_lookup0;
    wire [PACKET_W:0] status_lookup1;
    wire [PACKET_W:0] status_lookup2;
    wire [PACKET_W:0] status_lookup3;
    wire [PACKET_W:0] data_lookup0;
    wire [PACKET_W:0] data_lookup1;
    wire [PACKET_W:0] data_lookup2;
    wire [PACKET_W:0] data_lookup3;

    integer i;
    function [PACKET_W:0] lookup_result;
        input [3:0] lookup_rob_id;
        input [4:0] lookup_seq_tag;
        input [2:0] lookup_residue;
        begin
            lookup_result = {(PACKET_W+1){1'b0}};
            if (rob_valid[lookup_rob_id] &&
                (rob_seq_tag[lookup_rob_id] == lookup_seq_tag)) begin
                if (rob_result_valid[lookup_rob_id]) begin
                    lookup_result = {1'b1, rob_data[lookup_rob_id]};
                end
            end else if ((lookup_residue < 3'd7) &&
                         result_valid[lookup_residue] &&
                         (result_seq_tag[lookup_residue] == lookup_seq_tag)) begin
                lookup_result = {1'b1, result_data[lookup_residue]};
            end
        end
    endfunction

    assign input_count = {2'b00, in_valid0} + {2'b00, in_valid1} +
                         {2'b00, in_valid2} + {2'b00, in_valid3};
    assign alloc_count = {2'b00, alloc_valid0} + {2'b00, alloc_valid1} +
                         {2'b00, alloc_valid2} + {2'b00, alloc_valid3};
    assign free_count = 5'd16 - occupancy;
    assign bkps = (!rst_n) || (free_count < {2'b00, input_count});

    assign alloc_rob_id0 = tail_ptr;
    assign alloc_rob_id1 = tail_ptr + {3'b000, alloc_valid0};
    assign alloc_rob_id2 = tail_ptr + {3'b000, alloc_valid0} +
                                      {3'b000, alloc_valid1};
    assign alloc_rob_id3 = tail_ptr + {3'b000, alloc_valid0} +
                                      {3'b000, alloc_valid1} +
                                      {3'b000, alloc_valid2};

    assign head_idx0 = head_ptr;
    assign head_idx1 = head_ptr + 4'd1;
    assign head_idx2 = head_ptr + 4'd2;
    assign head_idx3 = head_ptr + 4'd3;
    assign done0 = rob_valid[head_idx0] && rob_result_valid[head_idx0];
    assign done1 = done0 && rob_valid[head_idx1] && rob_result_valid[head_idx1];
    assign done2 = done1 && rob_valid[head_idx2] && rob_result_valid[head_idx2];
    assign done3 = done2 && rob_valid[head_idx3] && rob_result_valid[head_idx3];
    assign retire_count = {2'b00, done0} + {2'b00, done1} +
                          {2'b00, done2} + {2'b00, done3};

    assign status_lookup0 = lookup_result(dep_status_rob_id0,
                                           dep_status_seq_tag0,
                                           dep_status_residue0);
    assign status_lookup1 = lookup_result(dep_status_rob_id1,
                                           dep_status_seq_tag1,
                                           dep_status_residue1);
    assign status_lookup2 = lookup_result(dep_status_rob_id2,
                                           dep_status_seq_tag2,
                                           dep_status_residue2);
    assign status_lookup3 = lookup_result(dep_status_rob_id3,
                                           dep_status_seq_tag3,
                                           dep_status_residue3);
    assign dep_status_ready0 = dep_status_valid0 && status_lookup0[PACKET_W];
    assign dep_status_ready1 = dep_status_valid1 && status_lookup1[PACKET_W];
    assign dep_status_ready2 = dep_status_valid2 && status_lookup2[PACKET_W];
    assign dep_status_ready3 = dep_status_valid3 && status_lookup3[PACKET_W];

    assign data_lookup0 = lookup_result(dep_data_rob_id0,
                                         dep_data_seq_tag0,
                                         dep_data_residue0);
    assign data_lookup1 = lookup_result(dep_data_rob_id1,
                                         dep_data_seq_tag1,
                                         dep_data_residue1);
    assign data_lookup2 = lookup_result(dep_data_rob_id2,
                                         dep_data_seq_tag2,
                                         dep_data_residue2);
    assign data_lookup3 = lookup_result(dep_data_rob_id3,
                                         dep_data_seq_tag3,
                                         dep_data_residue3);
    assign dep_data_ready0 = dep_data_valid0 && data_lookup0[PACKET_W];
    assign dep_data_ready1 = dep_data_valid1 && data_lookup1[PACKET_W];
    assign dep_data_ready2 = dep_data_valid2 && data_lookup2[PACKET_W];
    assign dep_data_ready3 = dep_data_valid3 && data_lookup3[PACKET_W];
    assign dep_data0 = data_lookup0[PACKET_W-1:0];
    assign dep_data1 = data_lookup1[PACKET_W-1:0];
    assign dep_data2 = data_lookup2[PACKET_W-1:0];
    assign dep_data3 = data_lookup3[PACKET_W-1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= 4'd0;
            tail_ptr <= 4'd0;
            occupancy <= 5'd0;
            start_lane <= 2'd0;
            out_valid0 <= 1'b0;
            out_valid1 <= 1'b0;
            out_valid2 <= 1'b0;
            out_valid3 <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                rob_valid[i] <= 1'b0;
                rob_result_valid[i] <= 1'b0;
            end
            for (i = 0; i < 7; i = i + 1) begin
                result_valid[i] <= 1'b0;
            end
        end else begin
            out_valid0 <= 1'b0;
            out_valid1 <= 1'b0;
            out_valid2 <= 1'b0;
            out_valid3 <= 1'b0;

            if (alloc_valid0) begin
                rob_valid[alloc_rob_id0] <= 1'b1;
                rob_seq_tag[alloc_rob_id0] <= alloc_seq_tag0;
                rob_seq_residue[alloc_rob_id0] <= alloc_seq_residue0;
                rob_result_valid[alloc_rob_id0] <= 1'b0;
            end
            if (alloc_valid1) begin
                rob_valid[alloc_rob_id1] <= 1'b1;
                rob_seq_tag[alloc_rob_id1] <= alloc_seq_tag1;
                rob_seq_residue[alloc_rob_id1] <= alloc_seq_residue1;
                rob_result_valid[alloc_rob_id1] <= 1'b0;
            end
            if (alloc_valid2) begin
                rob_valid[alloc_rob_id2] <= 1'b1;
                rob_seq_tag[alloc_rob_id2] <= alloc_seq_tag2;
                rob_seq_residue[alloc_rob_id2] <= alloc_seq_residue2;
                rob_result_valid[alloc_rob_id2] <= 1'b0;
            end
            if (alloc_valid3) begin
                rob_valid[alloc_rob_id3] <= 1'b1;
                rob_seq_tag[alloc_rob_id3] <= alloc_seq_tag3;
                rob_seq_residue[alloc_rob_id3] <= alloc_seq_residue3;
                rob_result_valid[alloc_rob_id3] <= 1'b0;
            end

            if (wb_valid0 && rob_valid[wb_rob_id0] &&
                (rob_seq_tag[wb_rob_id0] == wb_seq_tag0) &&
                !rob_result_valid[wb_rob_id0]) begin
                rob_data[wb_rob_id0] <= wb_data0;
                rob_result_valid[wb_rob_id0] <= 1'b1;
            end
            if (wb_valid1 && rob_valid[wb_rob_id1] &&
                (rob_seq_tag[wb_rob_id1] == wb_seq_tag1) &&
                !rob_result_valid[wb_rob_id1]) begin
                rob_data[wb_rob_id1] <= wb_data1;
                rob_result_valid[wb_rob_id1] <= 1'b1;
            end
            if (wb_valid2 && rob_valid[wb_rob_id2] &&
                (rob_seq_tag[wb_rob_id2] == wb_seq_tag2) &&
                !rob_result_valid[wb_rob_id2]) begin
                rob_data[wb_rob_id2] <= wb_data2;
                rob_result_valid[wb_rob_id2] <= 1'b1;
            end
            if (wb_valid3 && rob_valid[wb_rob_id3] &&
                (rob_seq_tag[wb_rob_id3] == wb_seq_tag3) &&
                !rob_result_valid[wb_rob_id3]) begin
                rob_data[wb_rob_id3] <= wb_data3;
                rob_result_valid[wb_rob_id3] <= 1'b1;
            end

            if (done0) begin
                result_valid[rob_seq_residue[head_idx0]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx0]] <= rob_seq_tag[head_idx0];
                result_data[rob_seq_residue[head_idx0]] <= rob_data[head_idx0];
                rob_valid[head_idx0] <= 1'b0;
                rob_result_valid[head_idx0] <= 1'b0;
                case (start_lane)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx0]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx0]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx0]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx0]; end
                endcase
            end
            if (done1) begin
                result_valid[rob_seq_residue[head_idx1]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx1]] <= rob_seq_tag[head_idx1];
                result_data[rob_seq_residue[head_idx1]] <= rob_data[head_idx1];
                rob_valid[head_idx1] <= 1'b0;
                rob_result_valid[head_idx1] <= 1'b0;
                case (start_lane + 2'd1)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx1]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx1]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx1]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx1]; end
                endcase
            end
            if (done2) begin
                result_valid[rob_seq_residue[head_idx2]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx2]] <= rob_seq_tag[head_idx2];
                result_data[rob_seq_residue[head_idx2]] <= rob_data[head_idx2];
                rob_valid[head_idx2] <= 1'b0;
                rob_result_valid[head_idx2] <= 1'b0;
                case (start_lane + 2'd2)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx2]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx2]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx2]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx2]; end
                endcase
            end
            if (done3) begin
                result_valid[rob_seq_residue[head_idx3]] <= 1'b1;
                result_seq_tag[rob_seq_residue[head_idx3]] <= rob_seq_tag[head_idx3];
                result_data[rob_seq_residue[head_idx3]] <= rob_data[head_idx3];
                rob_valid[head_idx3] <= 1'b0;
                rob_result_valid[head_idx3] <= 1'b0;
                case (start_lane + 2'd3)
                    2'd0: begin out_valid0 <= 1'b1; out_packet0 <= rob_data[head_idx3]; end
                    2'd1: begin out_valid1 <= 1'b1; out_packet1 <= rob_data[head_idx3]; end
                    2'd2: begin out_valid2 <= 1'b1; out_packet2 <= rob_data[head_idx3]; end
                    default: begin out_valid3 <= 1'b1; out_packet3 <= rob_data[head_idx3]; end
                endcase
            end

            head_ptr <= head_ptr + {1'b0, retire_count};
            tail_ptr <= tail_ptr + {1'b0, alloc_count};
            occupancy <= occupancy + {2'b00, alloc_count} -
                         {2'b00, retire_count};
            start_lane <= start_lane + retire_count[1:0];
        end
    end

endmodule
