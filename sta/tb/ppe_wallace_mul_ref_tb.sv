`timescale 1ns/1ps
`default_nettype none

module ppe_wallace_mul_ref_tb;

    logic        clk;
    logic        rst_n;
    logic        valid;
    logic [15:0] operand_a;
    logic [15:0] operand_b;
    logic        product_valid;
    logic [31:0] product;

    logic        expected_valid;
    logic [31:0] expected_product;

    ppe_wallace_mul_ref dut (
        .clk_i           (clk),
        .rst_ni          (rst_n),
        .valid_i         (valid),
        .operand_a_i     (operand_a),
        .operand_b_i     (operand_b),
        .product_valid_o (product_valid),
        .product_o       (product)
    );

    initial begin : clock_generation
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_and_advance;
        begin
            @(posedge clk);
            #1;

            if (product_valid !== expected_valid) begin
                $fatal(1, "valid mismatch: expected=%0b actual=%0b",
                       expected_valid, product_valid);
            end
            if (expected_valid && (product !== expected_product)) begin
                $fatal(1,
                       "product mismatch: expected=%08h actual=%08h",
                       expected_product, product);
            end

            expected_valid = valid;
            expected_product = operand_a * operand_b;
        end
    endtask

    initial begin : random_regression
        rst_n            = 1'b0;
        valid            = 1'b0;
        operand_a        = '0;
        operand_b        = '0;
        expected_valid   = 1'b0;
        expected_product = '0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        for (int sample_idx = 0; sample_idx < 10000; sample_idx++) begin
            @(negedge clk);
            valid     = 1'b1;
            operand_a = 16'($urandom);
            operand_b = 16'($urandom);
            check_and_advance();
        end

        @(negedge clk);
        valid = 1'b0;
        check_and_advance();
        check_and_advance();

        $display("PASS: 10000 Wallace multiplier samples");
        $finish;
    end

endmodule : ppe_wallace_mul_ref_tb

`default_nettype wire
