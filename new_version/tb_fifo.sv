`timescale 1ns/1ps

module tb_fifo;

    parameter DATA_WIDTH = 8;
    parameter DEPTH = 8;
    parameter CLK_PERIOD = 20;

    logic clk, rst_n;
    logic rden, wren;
    logic [DATA_WIDTH-1:0] i_data, o_data;
    logic full, empty;

    // -------------------------------------------------------
    //  DUT
    // -------------------------------------------------------
    FIFO #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rden(rden),
        .wren(wren),
        .i_data(i_data),
        .o_data(o_data),
        .full(full),
        .empty(empty)
    );

    // -------------------------------------------------------
    //  Clock generation
    // -------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    //  Test stimulus
    // -------------------------------------------------------
    integer i;
    integer errors = 0;

    initial begin
        $display("======================================");
        $display("  FIFO Testbench");
        $display("======================================");

        // Initialize
        rst_n  = 1'b0;
        rden   = 1'b0;
        wren   = 1'b0;
        i_data = 8'd0;

        // Reset
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ------- Test 1: Check empty after reset -------
        $display("[%0t] Test 1: Empty after reset", $time);
        if (empty !== 1'b1) begin
            $display("  FAIL: empty should be 1, got %b", empty);
            errors++;
        end else
            $display("  PASS: empty = 1");

        if (full !== 1'b0) begin
            $display("  FAIL: full should be 0, got %b", full);
            errors++;
        end else
            $display("  PASS: full = 0");

        // ------- Test 2: Write 8 values (fill FIFO) -------
        $display("\n[%0t] Test 2: Write %0d values", $time, DEPTH);
        for (i = 0; i < DEPTH; i++) begin
            wren   = 1'b1;
            i_data = (i + 1) * 10;  // 10, 20, 30, ..., 80
            @(posedge clk);
            $display("  Writing [%0d] = %0d | full=%b empty=%b", i, i_data, full, empty);
        end
        wren = 1'b0;
        @(posedge clk); // Let last write settle

        // ------- Test 3: Check full -------
        $display("\n[%0t] Test 3: Full after writing %0d values", $time, DEPTH);
        if (full !== 1'b1) begin
            $display("  FAIL: full should be 1, got %b", full);
            errors++;
        end else
            $display("  PASS: full = 1");

        // ------- Test 4: Read all values -------
        $display("\n[%0t] Test 4: Read back all values", $time);
        for (i = 0; i < DEPTH; i++) begin
            $display("  Reading [%0d] = %0d | full=%b empty=%b", i, o_data, full, empty);
            rden = 1'b1;
            @(posedge clk);
        end
        rden = 1'b0;
        @(posedge clk); // Let last read settle

        // ------- Test 5: Check empty -------
        $display("\n[%0t] Test 5: Empty after reading all", $time);
        if (empty !== 1'b1) begin
            $display("  FAIL: empty should be 1, got %b", empty);
            errors++;
        end else
            $display("  PASS: empty = 1");

        // ------- Summary -------
        $display("\n======================================");
        if (errors == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  %0d ERRORS", errors);
        $display("======================================");

        $stop;
    end

endmodule
