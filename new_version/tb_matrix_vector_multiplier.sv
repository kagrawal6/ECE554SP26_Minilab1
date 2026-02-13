`timescale 1ns/1ps

module tb_matrix_vector_multiplier;

    parameter DATA_WIDTH = 8;
    parameter DIM = 8;
    parameter DEPTH = 8;
    parameter CLK_PERIOD = 20;

    logic clk, rst_n;

    // FIFO write interface (driven by testbench, simulating data_fetcher)
    logic [DATA_WIDTH-1:0] fifo_data;
    logic [3:0]            fifo_sel;
    logic                  fifo_wren;
    logic                  fetch_done;

    // Results
    logic [DATA_WIDTH*3-1:0] result [0:DIM-1];
    logic                    done;

    // -------------------------------------------------------
    //  DUT
    // -------------------------------------------------------
    matrix_vector_multiplier #(
        .DATA_WIDTH(DATA_WIDTH),
        .DIM(DIM),
        .DEPTH(DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_data(fifo_data),
        .fifo_sel(fifo_sel),
        .fifo_wren(fifo_wren),
        .fetch_done(fetch_done),
        .result(result),
        .done(done)
    );

    // -------------------------------------------------------
    //  Clock generation
    // -------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    //  Monitor MAC pipeline during EXEC
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (dut.state == dut.EXEC) begin
            $display("[%0t] EXEC cnt=%0d | en_src=%b en_delay=%b | mac_out[0]=%0d [1]=%0d [2]=%0d [7]=%0d",
                $time, dut.exec_cnt, dut.en_src, dut.en_delay,
                dut.mac_out[0], dut.mac_out[1], dut.mac_out[2], dut.mac_out[7]);
        end
    end

    // -------------------------------------------------------
    //  Task: Write one byte to a FIFO
    // -------------------------------------------------------
    task write_fifo(input [3:0] sel, input [7:0] data);
        @(posedge clk);
        fifo_sel  = sel;
        fifo_data = data;
        fifo_wren = 1'b1;
        @(posedge clk);
        fifo_wren = 1'b0;
    endtask

    // -------------------------------------------------------
    //  Test stimulus — use simple known values for easy verification
    //  Matrix A = identity-like (A[i][j] = (i==j) ? 1 : 0... too simple)
    //  Instead use: A[i][j] = i+j+1, B[j] = j+1
    //  C[i] = sum_j (i+j+1)*(j+1) for j=0..7
    // -------------------------------------------------------
    integer i, j;
    integer expected [0:DIM-1];
    integer errors = 0;

    initial begin
        $display("======================================");
        $display("  Matrix-Vector Multiplier Testbench");
        $display("======================================");

        // Initialize
        rst_n      = 1'b0;
        fifo_data  = 8'd0;
        fifo_sel   = 4'd0;
        fifo_wren  = 1'b0;
        fetch_done = 1'b0;

        // Reset
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ------- Fill A-FIFOs: A[i][j] = i + j + 1 -------
        $display("\n[%0t] Filling A-FIFOs...", $time);
        for (i = 0; i < DIM; i++) begin
            for (j = 0; j < DIM; j++) begin
                write_fifo(i[3:0], (i + j + 1));
            end
            $display("  A-FIFO[%0d] filled", i);
        end

        // ------- Fill B-FIFO: B[j] = j + 1 -------
        $display("\n[%0t] Filling B-FIFO...", $time);
        for (j = 0; j < DIM; j++) begin
            write_fifo(4'd8, (j + 1));
        end
        $display("  B-FIFO filled");

        // ------- Compute expected results -------
        for (i = 0; i < DIM; i++) begin
            expected[i] = 0;
            for (j = 0; j < DIM; j++) begin
                expected[i] = expected[i] + (i + j + 1) * (j + 1);
            end
        end

        // ------- Trigger execution -------
        @(posedge clk);
        fetch_done = 1'b1;
        @(posedge clk);

        $display("\n[%0t] Execution started, waiting for done...", $time);

        // Wait for done
        wait(done);
        @(posedge clk);
        @(posedge clk);

        // ------- Check results -------
        $display("\n======================================");
        $display("  Results");
        $display("======================================");
        for (i = 0; i < DIM; i++) begin
            $display("  C[%0d] = %0d (0x%06h) | expected = %0d %s",
                i, result[i], result[i], expected[i],
                (result[i] == expected[i]) ? "PASS" : "FAIL");
            if (result[i] != expected[i])
                errors++;
        end

        $display("\n======================================");
        if (errors == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  %0d ERRORS", errors);
        $display("======================================");

        $stop;
    end

endmodule
