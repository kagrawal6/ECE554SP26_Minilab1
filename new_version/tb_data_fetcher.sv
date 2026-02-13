`timescale 1ns/1ps

module tb_data_fetcher;

    parameter CLK_PERIOD = 20;

    logic        clk, rst_n;
    logic        start;

    // Avalon-MM signals between data_fetcher and memory
    logic [31:0] mem_address;
    logic        mem_read;
    logic [63:0] mem_readdata;
    logic        mem_readdatavalid;
    logic        mem_waitrequest;

    // FIFO write outputs
    logic [7:0]  fifo_data;
    logic [3:0]  fifo_sel;
    logic        fifo_wren;
    logic        done;

    // -------------------------------------------------------
    //  DUT: data_fetcher
    // -------------------------------------------------------
    data_fetcher dut (
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
        .done(done)
    );

    // -------------------------------------------------------
    //  Memory module (Avalon-MM slave)
    // -------------------------------------------------------
    mem_wrapper mem (
        .clk(clk),
        .reset_n(rst_n),
        .address(mem_address),
        .read(mem_read),
        .readdata(mem_readdata),
        .readdatavalid(mem_readdatavalid),
        .waitrequest(mem_waitrequest)
    );

    // -------------------------------------------------------
    //  Clock generation
    // -------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------
    //  Monitor: print signals every cycle
    // -------------------------------------------------------
    always @(posedge clk) begin
        $display("[%0t] state=%0s | row=%0d byte=%0d | addr=%h read=%b | wait=%b valid=%b rdata=%h | fifo_sel=%0d wren=%b data=%h done=%b",
            $time,
            (dut.state == dut.IDLE)       ? "IDLE" :
            (dut.state == dut.READ_REQ)   ? "READ_REQ" :
            (dut.state == dut.WAIT_DATA)  ? "WAIT_DATA" :
            (dut.state == dut.WRITE_FIFO) ? "WRITE_FIFO" :
            (dut.state == dut.FETCH_DONE) ? "FETCH_DONE" : "???",
            dut.row_cnt, dut.byte_cnt,
            mem_address, mem_read,
            mem_waitrequest, mem_readdatavalid, mem_readdata,
            fifo_sel, fifo_wren, fifo_data,
            done
        );
    end

    // -------------------------------------------------------
    //  Track FIFO writes for verification
    // -------------------------------------------------------
    logic [7:0] captured_data [0:8][0:7]; // [row][byte]

    always @(posedge clk) begin
        if (fifo_wren && fifo_sel <= 4'd8) begin
            captured_data[fifo_sel][dut.byte_cnt] <= fifo_data;
        end
    end

    // -------------------------------------------------------
    //  Test stimulus
    // -------------------------------------------------------
    integer row, col;

    initial begin
        $display("======================================");
        $display("  Data Fetcher Testbench");
        $display("======================================");

        // Initialize
        rst_n = 1'b0;
        start = 1'b0;

        // Reset
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        @(posedge clk);

        // Start fetching
        $display("\n[%0t] Starting data fetch...", $time);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Wait for done
        wait(done);
        @(posedge clk);
        @(posedge clk);

        // Print all captured data
        $display("\n======================================");
        $display("  Fetched Data Summary");
        $display("======================================");
        for (row = 0; row < 9; row++) begin
            if (row < 8)
                $write("  Row A[%0d]: ", row);
            else
                $write("  Vector B:  ");
            for (col = 0; col < 8; col++) begin
                $write("%h ", captured_data[row][col]);
            end
            $write("\n");
        end

        $display("\n======================================");
        $display("  Data Fetcher Test Complete");
        $display("======================================");

        $stop;
    end

endmodule
