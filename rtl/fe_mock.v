`timescale 1ns/1ps

module fe_mock #(
    parameter integer PACKET_W = 128,
    parameter integer FE_ID = 0
) (
    input                       clk,
    input                       rst_n,
    input                       fe_in_valid,
    input      [PACKET_W-1:0]   fe_in_data,
    input                       fe_dep_valid,
    input      [PACKET_W-1:0]   fe_dep_data,
    input      [1:0]            fe_desc_delay,
    output reg                  fe_out_valid,
    output reg [PACKET_W-1:0]  fe_out_data
);

    reg                       busy;
    reg [2:0]                 delay_count;
    reg [PACKET_W-1:0]        packet_q;
    reg                       dep_valid_q;
    reg [PACKET_W-1:0]        dep_data_q;
    reg [1:0]                 delay_q;

    wire [PACKET_W-1:0] fe_id_mask;
    wire [PACKET_W-1:0] delay_mask;

    assign fe_id_mask = {{(PACKET_W-8){1'b0}}, FE_ID[7:0]};
    assign delay_mask = {{(PACKET_W-2){1'b0}}, delay_q};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
            delay_count <= 3'd0;
            dep_valid_q <= 1'b0;
            delay_q <= 2'd0;
            fe_out_valid <= 1'b0;
        end else begin
            fe_out_valid <= 1'b0;

            if (fe_in_valid && !busy) begin
                busy <= 1'b1;
                delay_count <= {1'b0, fe_desc_delay} + 3'd1;
                packet_q <= fe_in_data;
                dep_valid_q <= fe_dep_valid;
                dep_data_q <= fe_dep_data;
                delay_q <= fe_desc_delay;
            end else if (busy) begin
                if (delay_count > 3'd1) begin
                    delay_count <= delay_count - 3'd1;
                end else begin
                    busy <= 1'b0;
                    delay_count <= 3'd0;
                    fe_out_valid <= 1'b1;
                    fe_out_data <= packet_q ^
                                   (dep_valid_q ? dep_data_q : {PACKET_W{1'b0}}) ^
                                   delay_mask ^ fe_id_mask;
                end
            end
        end
    end

endmodule
