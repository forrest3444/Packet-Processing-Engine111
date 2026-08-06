`timescale 1ns/1ps
`default_nettype none
`include "rtl/common/ppe_config.vh"

//------------------------------------------------------------------------------
// Maps dense logical retirement slots onto rotating registered output lanes.
//------------------------------------------------------------------------------
module PPE_RETIRE_OUTPUT #(
    parameter integer PACKET_W = `PPE_DEFAULT_PACKET_W
) (
    input  wire                              clk_i,
    input  wire                              rst_ni,
    input  wire [`PPE_N-1:0]                 retire_valid_i,
    input  wire [PACKET_W-1:0]               retire_data_i [0:`PPE_N-1],
    output reg  [`PPE_N-1:0]                 out_valid_o,
    output reg  [PACKET_W-1:0]               out_packet_o [0:`PPE_N-1]
);

    localparam integer N              = `PPE_N;
    localparam integer LANE_ID_W      = 2;

    reg [LANE_ID_W-1:0]               start_lane_q;
    reg [LANE_ID_W-1:0]               start_lane_next;
    reg [LANE_ID_W-1:0]               retire_advance_mod4;
    reg [N-1:0]                       rotate_one_valid;
    reg [PACKET_W-1:0]                rotate_one_data [0:N-1];
    reg [N-1:0]                       mapped_valid;
    reg [PACKET_W-1:0]                mapped_data [0:N-1];

    always @* begin : retirement_lane_mapping
        rotate_one_valid = retire_valid_i;
        rotate_one_data[0] = retire_data_i[0];
        rotate_one_data[1] = retire_data_i[1];
        rotate_one_data[2] = retire_data_i[2];
        rotate_one_data[3] = retire_data_i[3];
        if (start_lane_q[0]) begin
            rotate_one_valid =
                {retire_valid_i[2:0], retire_valid_i[3]};
            rotate_one_data[0] = retire_data_i[3];
            rotate_one_data[1] = retire_data_i[0];
            rotate_one_data[2] = retire_data_i[1];
            rotate_one_data[3] = retire_data_i[2];
        end

        mapped_valid = rotate_one_valid;
        mapped_data[0] = rotate_one_data[0];
        mapped_data[1] = rotate_one_data[1];
        mapped_data[2] = rotate_one_data[2];
        mapped_data[3] = rotate_one_data[3];
        if (start_lane_q[1]) begin
            mapped_valid =
                {rotate_one_valid[1:0], rotate_one_valid[3:2]};
            mapped_data[0] = rotate_one_data[2];
            mapped_data[1] = rotate_one_data[3];
            mapped_data[2] = rotate_one_data[0];
            mapped_data[3] = rotate_one_data[1];
        end

        retire_advance_mod4[0] = ^retire_valid_i;
        retire_advance_mod4[1] =
            retire_valid_i[1] ^ retire_valid_i[3];
        start_lane_next[0] =
            start_lane_q[0] ^ retire_advance_mod4[0];
        start_lane_next[1] =
            start_lane_q[1]
            ^ retire_advance_mod4[1]
            ^ (start_lane_q[0] & retire_advance_mod4[0]);
    end

    always @(posedge clk_i or negedge rst_ni) begin : output_state_update
        integer lane_idx;

        if (!rst_ni) begin
            start_lane_q <= {LANE_ID_W{1'b0}};
            out_valid_o  <= {N{1'b0}};
        end else begin
            out_valid_o <= mapped_valid;
            for (lane_idx = 0; lane_idx < N; lane_idx = lane_idx + 1) begin
                if (mapped_valid[lane_idx]) begin
                    out_packet_o[lane_idx] <= mapped_data[lane_idx];
                end
            end

            start_lane_q <= start_lane_next;
        end
    end

endmodule

`default_nettype wire
