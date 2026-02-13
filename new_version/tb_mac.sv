`timescale 1ns/1ps

module tb_mac;

    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 20;

    logic clk, rst_n;
    logic En, Clr;
    logic [DATA_WIDTH-1:0] Ain, Bin;
    logic [DATA_WIDTH*3-1:0] Cout;

    // -------------------------------------------------------
    //  DUT
    // -------------------------------------------------------
    MAC #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .En(En),
        .Clr(Clr),
        .Ain(Ain),
        .Bin(Bin),
        .Cout(Cout)
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
    integer expected;
    integer errors = 0;

    initial begin
        $display("======================================");
        $display("  MAC Testbench");
        $display("======================================");

        // Initialize
        rst_n = 1'b0;
        En    = 1'b0;
        Clr   = 1'b0;
        Ain   = 8'd0;
        Bin   = 8'd0;

        // Reset
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ------- Test 1: Check zero after reset -------
        $display("[%0t] Test 1: Zero after reset", $time);
        if (Cout !== 24'd0) begin
            $display("  FAIL: Cout should be 0, got %0d", Cout);
            errors++;
        end else
            $display("  PASS: Cout = 0");

        // ------- Test 2: Accumulate 4 products -------
        //   2*3 + 4*5 + 6*7 + 8*9 = 6 + 20 + 42 + 72 = 140
        $display("\n[%0t] Test 2: Accumulate 4 products", $time);
        expected = 0;

        @(posedge clk);
        En = 1'b1; Ain = 8'd2; Bin = 8'd3;
        $display("  Cycle 1: %0d * %0d", Ain, Bin);

        @(posedge clk);
        Ain = 8'd4; Bin = 8'd5;
        $display("  Cycle 2: %0d * %0d | Cout = %0d", Ain, Bin, Cout);

        @(posedge clk);
        Ain = 8'd6; Bin = 8'd7;
        $display("  Cycle 3: %0d * %0d | Cout = %0d", Ain, Bin, Cout);

        @(posedge clk);
        Ain = 8'd8; Bin = 8'd9;
        $display("  Cycle 4: %0d * %0d | Cout = %0d", Ain, Bin, Cout);

        @(posedge clk);
        En = 1'b0;
        $display("  After 4 cycles: Cout = %0d", Cout);

        expected = 2*3 + 4*5 + 6*7 + 8*9;
        @(posedge clk); // One more cycle for last accumulation
        $display("  Final: Cout = %0d (expected %0d)", Cout, expected);
        if (Cout !== expected) begin
            $display("  FAIL");
            errors++;
        end else
            $display("  PASS");

        // ------- Test 3: Clear -------
        $display("\n[%0t] Test 3: Clear", $time);
        Clr = 1'b1;
        @(posedge clk);
        @(posedge clk);
        Clr = 1'b0;
        if (Cout !== 24'd0) begin
            $display("  FAIL: Cout should be 0 after Clr, got %0d", Cout);
            errors++;
        end else
            $display("  PASS: Cout = 0 after Clr");

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
