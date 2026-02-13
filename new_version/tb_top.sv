`timescale 1ns/1ps

module tb_top;

    parameter DATA_WIDTH = 8;
    parameter DIM = 8;
    parameter DEPTH = 8;
    parameter CLK_PERIOD = 20;  // 50 MHz

    logic clk, rst_n;
    logic start;

    // -------------------------------------------------------
    //  Avalon-MM wires (data_fetcher ↔ memory)
    // -------------------------------------------------------
    logic [31:0] mem_address;
    logic        mem_read;
    logic [63:0] mem_readdata;
    logic        mem_readdatavalid;
    logic        mem_waitrequest;

    // -------------------------------------------------------
    //  data_fetcher → matrix_vector_multiplier wires
    // -------------------------------------------------------
    logic [7:0]  fifo_data;
    logic [3:0]  fifo_sel;
    logic        fifo_wren;
    logic        fetch_done;

    // -------------------------------------------------------
    //  matrix_vector_multiplier outputs
    // -------------------------------------------------------
    logic [DATA_WIDTH*3-1:0] result [0:DIM-1];
    logic                    mul_done;

    // =========================================================
    //  Module instantiations
    // =========================================================

    // Memory (Avalon-MM slave with ROM)
    mem_wrapper mem (
        .clk(clk),
        .reset_n(rst_n),
        .address(mem_address),
        .read(mem_read),
        .readdata(mem_readdata),
        .readdatavalid(mem_readdatavalid),
        .waitrequest(mem_waitrequest)
    );

    // Data fetcher (Avalon-MM master)
    data_fetcher fetcher (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .mem_address(mem_address),
        .mem_read(mem_read),
        .mem_readdata(mem_readdata),
        .mem_readdatavalid(mem_readdatavalid),
        .mem_waitrequest(mem_waitrequest),
        .fifo_data(fifo_data),
        .fifo_sel(fifo_sel),
        .fifo_wren(fifo_wren),
        .done(fetch_done)
    );

    // Matrix-vector multiplier
    matrix_vector_multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .DIM(DIM),
        .DEPTH(DEPTH)
    ) multiplier (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_data(fifo_data),
        .fifo_sel(fifo_sel),
        .fifo_wren(fifo_wren),
        .fetch_done(fetch_done),
        .result(result),
        .done(mul_done)
    );

    // -------------------------------------------------------
    //  Clock generation
    // -------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    //  Monitor: Avalon-MM interface signals
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (mem_read || mem_readdatavalid || mem_waitrequest) begin
            $display("[%0t] AVALON | addr=%h read=%b | waitreq=%b valid=%b rdata=%h",
                $time, mem_address, mem_read,
                mem_waitrequest, mem_readdatavalid, mem_readdata);
        end
    end

    // -------------------------------------------------------
    //  Monitor: FIFO write activity
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (fifo_wren) begin
            $display("[%0t] FIFO_WR | sel=%0d data=%h",
                $time, fifo_sel, fifo_data);
        end
    end

    // -------------------------------------------------------
    //  Monitor: state transitions
    // -------------------------------------------------------
    always @(posedge clk) begin
        // Data fetcher state
        $display("[%0t] FETCHER state=%0s | MUL state=%0s en_src=%b exec_cnt=%0d",
            $time,
            (fetcher.state == fetcher.IDLE)       ? "IDLE" :
            (fetcher.state == fetcher.READ_REQ)   ? "READ_REQ" :
            (fetcher.state == fetcher.WAIT_DATA)  ? "WAIT_DATA" :
            (fetcher.state == fetcher.WRITE_FIFO) ? "WRITE_FIFO" :
            (fetcher.state == fetcher.FETCH_DONE) ? "FETCH_DONE" : "???",
            (multiplier.state == multiplier.IDLE)    ? "IDLE" :
            (multiplier.state == multiplier.EXEC)    ? "EXEC" :
            (multiplier.state == multiplier.DONE_ST) ? "DONE" : "???",
            multiplier.en_src, multiplier.exec_cnt
        );
    end

    // -------------------------------------------------------
    //  Expected results (computed from MIF data)
    //
    //  Matrix A (hex from MIF):
    //    Row 0: 01 02 03 04 05 06 07 08
    //    Row 1: 11 12 13 14 15 16 17 18
    //    ...
    //    Row 7: 71 72 73 74 75 76 77 78
    //  Vector B: 81 82 83 84 85 86 87 88
    //
    //  C[i] = sum_j A[i][j] * B[j]
    // -------------------------------------------------------
    integer exp [0:DIM-1];
    integer errors = 0;
    integer i, j;
    integer a_val, b_val;

    initial begin
        // Compute expected results from MIF values
        for (i = 0; i < DIM; i++) begin
            exp[i] = 0;
            for (j = 0; j < DIM; j++) begin
                // A[i][j] = (i*16 + 16) + (j + 1)  in hex: {i+0, j+1} but actually
                // Row i, byte j: upper nibble = i, lower nibble = j+1
                // e.g. Row 0: 01,02,...,08  Row 1: 11,12,...,18
                a_val = i * 16 + j + 1;    // 0x(i)(j+1)
                b_val = 8 * 16 + j + 1;    // 0x8(j+1) = 81,82,...,88
                exp[i] = exp[i] + a_val * b_val;
            end
        end
    end

    // -------------------------------------------------------
    //  Test stimulus
    // -------------------------------------------------------
    initial begin
        $display("=====================================================");
        $display("  Top-Level System Testbench (Part 1A)");
        $display("  Matrix A (8x8) x Vector B (8x1) = C (8x1)");
        $display("=====================================================");

        // Initialize
        rst_n = 1'b0;
        start = 1'b0;

        // Reset
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        @(posedge clk);

        // Start the data fetch
        $display("\n[%0t] ===== START FETCH =====", $time);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Wait for data fetch to complete
        wait(fetch_done);
        $display("\n[%0t] ===== FETCH DONE =====", $time);
        @(posedge clk);

        // Wait for multiplication to complete
        wait(mul_done);
        $display("\n[%0t] ===== MULTIPLICATION DONE =====", $time);
        @(posedge clk);
        @(posedge clk);

        // Print results
        $display("\n=====================================================");
        $display("  Results: C = A x B");
        $display("=====================================================");
        for (i = 0; i < DIM; i++) begin
            $display("  C[%0d] = %6d (0x%06h) | expected = %6d (0x%06h) %s",
                i, result[i], result[i], exp[i], exp[i],
                (result[i] == exp[i]) ? "PASS" : "*** FAIL ***");
            if (result[i] != exp[i])
                errors++;
        end

        $display("\n=====================================================");
        if (errors == 0)
            $display("  ALL %0d RESULTS CORRECT!", DIM);
        else
            $display("  %0d / %0d ERRORS DETECTED", errors, DIM);
        $display("=====================================================");

        repeat(5) @(posedge clk);
        $stop;
    end

    // -------------------------------------------------------
    //  Timeout watchdog
    // -------------------------------------------------------
    initial begin
        #100000;
        $display("\n*** TIMEOUT: Simulation exceeded 100us ***");
        $stop;
    end

endmodule
