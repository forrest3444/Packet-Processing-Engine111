`timescale 1ns/1ps
`default_nettype none

//------------------------------------------------------------------------------
// File        : ppe_wallace_mul_ref.sv
// Project     : Packet Processing Engine (PPE)
// Block       : STA Reference / Wallace-Style Multiplier
//
// Description :
//   Standalone 16x16 unsigned multiplier timing reference. Six explicit 3:2
//   carry-save compression levels reduce sixteen shifted partial-product rows
//   to two rows, followed by one carry-propagate addition. The RTL deliberately
//   avoids the multiplication operator so the measured logic reflects the
//   documented compressor-tree structure.
//
//   This module is not production PPE RTL and is excluded from all design and
//   verification filelists. Registered inputs and outputs create a clean
//   register-to-register path for synthesis-library comparisons.
//
// Clock/reset :
//   State is clocked by clk_i. rst_ni asynchronously clears only validity
//   state. Operand and product fields are ignored while validity is clear.
//------------------------------------------------------------------------------

module ppe_wallace_mul_ref (
    // Clock and reset
    input  logic         clk_i,
    input  logic         rst_ni,

    // Registered unsigned operands
    input  logic         valid_i,
    input  logic [15:0]  operand_a_i,
    input  logic [15:0]  operand_b_i,

    // Registered product
    output logic         product_valid_o,
    output logic [31:0]  product_o
);

    //--------------------------------------------------------------------------
    // Local types and 3:2 compressor helpers
    //--------------------------------------------------------------------------

    typedef logic [31:0] product_t;

    function automatic product_t csa_sum(
        input product_t operand_a,
        input product_t operand_b,
        input product_t operand_c
    );
        begin
            csa_sum = operand_a ^ operand_b ^ operand_c;
        end
    endfunction

    function automatic product_t csa_carry(
        input product_t operand_a,
        input product_t operand_b,
        input product_t operand_c
    );
        product_t carry_bits;
        begin
            carry_bits = (operand_a & operand_b)
                         | (operand_a & operand_c)
                         | (operand_b & operand_c);
            csa_carry = carry_bits << 1;
        end
    endfunction

    //--------------------------------------------------------------------------
    // Input capture boundary
    //--------------------------------------------------------------------------

    logic        valid_q;
    logic [15:0] operand_a_q;
    logic [15:0] operand_b_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin : input_capture
        if (!rst_ni) begin
            valid_q <= 1'b0;
        end else begin
            valid_q     <= valid_i;
            operand_a_q <= operand_a_i;
            operand_b_q <= operand_b_i;
        end
    end

    //--------------------------------------------------------------------------
    // Partial products and balanced carry-save reduction tree
    //--------------------------------------------------------------------------

    logic [15:0][31:0] partial_product;
    logic [10:0][31:0] reduce_level_1;
    logic [7:0][31:0]  reduce_level_2;
    logic [5:0][31:0]  reduce_level_3;
    logic [3:0][31:0]  reduce_level_4;
    logic [2:0][31:0]  reduce_level_5;
    logic [1:0][31:0]  reduce_level_6;
    product_t           product_d;

    always_comb begin : wallace_reduction
        partial_product = '0;
        reduce_level_1  = '0;
        reduce_level_2  = '0;
        reduce_level_3  = '0;
        reduce_level_4  = '0;
        reduce_level_5  = '0;
        reduce_level_6  = '0;
        product_d       = '0;

        // Sixteen unsigned shifted partial-product rows.
        for (int bit_idx = 0; bit_idx < 16; bit_idx++) begin
            if (operand_b_q[bit_idx]) begin
                partial_product[bit_idx] =
                    product_t'({16'b0, operand_a_q}) << bit_idx;
            end
        end

        // Level 1: 16 rows -> 11 rows.
        reduce_level_1[0] = csa_sum(
            partial_product[0], partial_product[1], partial_product[2]);
        reduce_level_1[1] = csa_carry(
            partial_product[0], partial_product[1], partial_product[2]);
        reduce_level_1[2] = csa_sum(
            partial_product[3], partial_product[4], partial_product[5]);
        reduce_level_1[3] = csa_carry(
            partial_product[3], partial_product[4], partial_product[5]);
        reduce_level_1[4] = csa_sum(
            partial_product[6], partial_product[7], partial_product[8]);
        reduce_level_1[5] = csa_carry(
            partial_product[6], partial_product[7], partial_product[8]);
        reduce_level_1[6] = csa_sum(
            partial_product[9], partial_product[10], partial_product[11]);
        reduce_level_1[7] = csa_carry(
            partial_product[9], partial_product[10], partial_product[11]);
        reduce_level_1[8] = csa_sum(
            partial_product[12], partial_product[13], partial_product[14]);
        reduce_level_1[9] = csa_carry(
            partial_product[12], partial_product[13], partial_product[14]);
        reduce_level_1[10] = partial_product[15];

        // Level 2: 11 rows -> 8 rows.
        reduce_level_2[0] = csa_sum(
            reduce_level_1[0], reduce_level_1[1], reduce_level_1[2]);
        reduce_level_2[1] = csa_carry(
            reduce_level_1[0], reduce_level_1[1], reduce_level_1[2]);
        reduce_level_2[2] = csa_sum(
            reduce_level_1[3], reduce_level_1[4], reduce_level_1[5]);
        reduce_level_2[3] = csa_carry(
            reduce_level_1[3], reduce_level_1[4], reduce_level_1[5]);
        reduce_level_2[4] = csa_sum(
            reduce_level_1[6], reduce_level_1[7], reduce_level_1[8]);
        reduce_level_2[5] = csa_carry(
            reduce_level_1[6], reduce_level_1[7], reduce_level_1[8]);
        reduce_level_2[6] = reduce_level_1[9];
        reduce_level_2[7] = reduce_level_1[10];

        // Level 3: 8 rows -> 6 rows.
        reduce_level_3[0] = csa_sum(
            reduce_level_2[0], reduce_level_2[1], reduce_level_2[2]);
        reduce_level_3[1] = csa_carry(
            reduce_level_2[0], reduce_level_2[1], reduce_level_2[2]);
        reduce_level_3[2] = csa_sum(
            reduce_level_2[3], reduce_level_2[4], reduce_level_2[5]);
        reduce_level_3[3] = csa_carry(
            reduce_level_2[3], reduce_level_2[4], reduce_level_2[5]);
        reduce_level_3[4] = reduce_level_2[6];
        reduce_level_3[5] = reduce_level_2[7];

        // Level 4: 6 rows -> 4 rows.
        reduce_level_4[0] = csa_sum(
            reduce_level_3[0], reduce_level_3[1], reduce_level_3[2]);
        reduce_level_4[1] = csa_carry(
            reduce_level_3[0], reduce_level_3[1], reduce_level_3[2]);
        reduce_level_4[2] = csa_sum(
            reduce_level_3[3], reduce_level_3[4], reduce_level_3[5]);
        reduce_level_4[3] = csa_carry(
            reduce_level_3[3], reduce_level_3[4], reduce_level_3[5]);

        // Level 5: 4 rows -> 3 rows.
        reduce_level_5[0] = csa_sum(
            reduce_level_4[0], reduce_level_4[1], reduce_level_4[2]);
        reduce_level_5[1] = csa_carry(
            reduce_level_4[0], reduce_level_4[1], reduce_level_4[2]);
        reduce_level_5[2] = reduce_level_4[3];

        // Level 6: 3 rows -> 2 rows, followed by the final CPA.
        reduce_level_6[0] = csa_sum(
            reduce_level_5[0], reduce_level_5[1], reduce_level_5[2]);
        reduce_level_6[1] = csa_carry(
            reduce_level_5[0], reduce_level_5[1], reduce_level_5[2]);
        product_d = reduce_level_6[0] + reduce_level_6[1];
    end

    //--------------------------------------------------------------------------
    // Output capture boundary
    //--------------------------------------------------------------------------

    always_ff @(posedge clk_i or negedge rst_ni) begin : output_capture
        if (!rst_ni) begin
            product_valid_o <= 1'b0;
        end else begin
            product_valid_o <= valid_q;

            if (valid_q) begin
                product_o <= product_d;
            end
        end
    end

endmodule : ppe_wallace_mul_ref

`default_nettype wire
