// -----------------------------------------------------------------------------
// File       : fe_mock.v
// Author     : Codex
// Description: Mock Forward Engine for PPE bring-up and debug.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module fe_mock #(
    parameter integer PACKET_W = 128,
    parameter integer RESULT_W = 128,
    parameter integer FE_ID    = 0
) (
    input                       clk,
    input                       rst_n,

    input                       fe_in_valid,
    output                      fe_in_ready,
    input      [PACKET_W-1:0]   fe_in_packet,

    output reg                  fe_out_valid,
    input                       fe_out_ready,
    output reg [PACKET_W-1:0]   fe_out_packet,
    output reg [RESULT_W-1:0]   fe_out_result
);

    reg                  busy;
    reg [2:0]            delay_cnt;
    reg [PACKET_W-1:0]   pkt_q;

    wire [2:0] next_delay;

    assign fe_in_ready = (!busy) && (!fe_out_valid);
    assign next_delay  = {1'b0, fe_in_packet[33:32]} + 3'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            delay_cnt    <= 3'd0;
            pkt_q        <= {PACKET_W{1'b0}};
            fe_out_valid <= 1'b0;
            fe_out_packet <= {PACKET_W{1'b0}};
            fe_out_result <= {RESULT_W{1'b0}};
        end else begin
            if (fe_out_valid && fe_out_ready) begin
                fe_out_valid <= 1'b0;
            end

            if (fe_in_valid && fe_in_ready) begin
                busy      <= 1'b1;
                delay_cnt <= next_delay;
                pkt_q     <= fe_in_packet;
            end else if (busy) begin
                if (delay_cnt != 3'd0) begin
                    delay_cnt <= delay_cnt - 3'd1;
                end else if (!fe_out_valid) begin
                    busy <= 1'b0;

                    /* Keep packet[31:0] seq unchanged for ordering debug. */
                    fe_out_packet[31:0]   <= pkt_q[31:0];
                    fe_out_packet[127:32] <=
                        {pkt_q[126:32], pkt_q[127]} ^ 96'h1357_9bdf_2468_ace0_55aa_0000;

                    fe_out_result <= pkt_q ^ 128'h0f0f_f0f0_55aa_aa55_1234_5678_9abc_def0;
                end
            end
        end
    end

endmodule
