//=============================================================================
// Testbench for Matrix-Vector Multiplication
//
// This testbench:
//   1. Initializes and resets the design
//   2. Starts the computation
//   3. Monitors all interface signals and states
//   4. Verifies results against expected values (calculated from input_mem.mif)
//   5. Prints detailed pass/fail information
//
// Expected data from input_mem.mif:
//   Matrix A (8x8):
//     Row 0: 01 02 03 04 05 06 07 08
//     Row 1: 11 12 13 14 15 16 17 18
//     Row 2: 21 22 23 24 25 26 27 28
//     Row 3: 31 32 33 34 35 36 37 38
//     Row 4: 41 42 43 44 45 46 47 48
//     Row 5: 51 52 53 54 55 56 57 58
//     Row 6: 61 62 63 64 65 66 67 68
//     Row 7: 71 72 73 74 75 76 77 78
//   Vector B:
//     81 82 83 84 85 86 87 88
//
// QuestaSim command:
//   vsim work.matvec_tb -L C:/intelFPGA_lite/21.1/questa_fse/intel/verilog/altera_mf -voptargs="+acc"
//=============================================================================

`timescale 1ns/1ps

module matvec_tb;

    //=========================================================================
    // Parameters
    //=========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz clock (10ns period)
    parameter TIMEOUT_CYCLES = 5000;  // Maximum cycles before timeout
    
    //=========================================================================
    // Test Data (from input_mem.mif)
    //=========================================================================
    // Matrix A - stored as [row][col]
    logic [7:0] A [0:7][0:7];
    // Vector B
    logic [7:0] B [0:7];
    // Expected results (calculated)
    logic [23:0] C_expected [0:7];
    
    //=========================================================================
    // DUT Signals
    //=========================================================================
    logic        clk;
    logic        rst_n;
    logic        start;
    wire  [23:0] c_out [0:7];
    wire         done;
    wire  [2:0]  current_state;
    
    //=========================================================================
    // Test Control
    //=========================================================================
    integer cycle_count;
    integer errors;
    integer i, j;
    logic [31:0] sum;  // For expected value calculation
    
    //=========================================================================
    // State name strings (for readable output)
    //=========================================================================
    function string state_name(input [2:0] state);
        case (state)
            3'd0: return "S_IDLE";
            3'd1: return "S_FETCH";
            3'd2: return "S_COMPUTE";
            3'd3: return "S_DONE";
            default: return "UNKNOWN";
        endcase
    endfunction
    
    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    matvec_top DUT (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .c_out         (c_out),
        .done          (done),
        .current_state (current_state)
    );
    
    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    //=========================================================================
    // Cycle Counter
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    //=========================================================================
    // Initialize Test Data and Calculate Expected Results
    //=========================================================================
    task initialize_test_data();
        begin
            $display("\n");
            $display("============================================================");
            $display("  Initializing Test Data from input_mem.mif");
            $display("============================================================");
            
            // Matrix A initialization (values from input_mem.mif)
            // Row 0: 0x0102030405060708
            A[0][0] = 8'h01; A[0][1] = 8'h02; A[0][2] = 8'h03; A[0][3] = 8'h04;
            A[0][4] = 8'h05; A[0][5] = 8'h06; A[0][6] = 8'h07; A[0][7] = 8'h08;
            
            // Row 1: 0x1112131415161718
            A[1][0] = 8'h11; A[1][1] = 8'h12; A[1][2] = 8'h13; A[1][3] = 8'h14;
            A[1][4] = 8'h15; A[1][5] = 8'h16; A[1][6] = 8'h17; A[1][7] = 8'h18;
            
            // Row 2: 0x2122232425262728
            A[2][0] = 8'h21; A[2][1] = 8'h22; A[2][2] = 8'h23; A[2][3] = 8'h24;
            A[2][4] = 8'h25; A[2][5] = 8'h26; A[2][6] = 8'h27; A[2][7] = 8'h28;
            
            // Row 3: 0x3132333435363738
            A[3][0] = 8'h31; A[3][1] = 8'h32; A[3][2] = 8'h33; A[3][3] = 8'h34;
            A[3][4] = 8'h35; A[3][5] = 8'h36; A[3][6] = 8'h37; A[3][7] = 8'h38;
            
            // Row 4: 0x4142434445464748
            A[4][0] = 8'h41; A[4][1] = 8'h42; A[4][2] = 8'h43; A[4][3] = 8'h44;
            A[4][4] = 8'h45; A[4][5] = 8'h46; A[4][6] = 8'h47; A[4][7] = 8'h48;
            
            // Row 5: 0x5152535455565758
            A[5][0] = 8'h51; A[5][1] = 8'h52; A[5][2] = 8'h53; A[5][3] = 8'h54;
            A[5][4] = 8'h55; A[5][5] = 8'h56; A[5][6] = 8'h57; A[5][7] = 8'h58;
            
            // Row 6: 0x6162636465666768
            A[6][0] = 8'h61; A[6][1] = 8'h62; A[6][2] = 8'h63; A[6][3] = 8'h64;
            A[6][4] = 8'h65; A[6][5] = 8'h66; A[6][6] = 8'h67; A[6][7] = 8'h68;
            
            // Row 7: 0x7172737475767778
            A[7][0] = 8'h71; A[7][1] = 8'h72; A[7][2] = 8'h73; A[7][3] = 8'h74;
            A[7][4] = 8'h75; A[7][5] = 8'h76; A[7][6] = 8'h77; A[7][7] = 8'h78;
            
            // Vector B: 0x8182838485868788
            B[0] = 8'h81; B[1] = 8'h82; B[2] = 8'h83; B[3] = 8'h84;
            B[4] = 8'h85; B[5] = 8'h86; B[6] = 8'h87; B[7] = 8'h88;
            
            // Print Matrix A
            $display("\nMatrix A (8x8):");
            for (i = 0; i < 8; i = i + 1) begin
                $display("  Row %0d: %02h %02h %02h %02h %02h %02h %02h %02h",
                         i, A[i][0], A[i][1], A[i][2], A[i][3],
                         A[i][4], A[i][5], A[i][6], A[i][7]);
            end
            
            // Print Vector B
            $display("\nVector B:");
            $display("  %02h %02h %02h %02h %02h %02h %02h %02h",
                     B[0], B[1], B[2], B[3], B[4], B[5], B[6], B[7]);
            
            // Calculate expected results: C[i] = sum(A[i][j] * B[j])
            $display("\nCalculating Expected Results (C = A × B):");
            for (i = 0; i < 8; i = i + 1) begin
                sum = 0;
                for (j = 0; j < 8; j = j + 1) begin
                    sum = sum + (A[i][j] * B[j]);
                end
                C_expected[i] = sum[23:0];
                $display("  C[%0d] = 0x%06h (decimal: %0d)", i, C_expected[i], C_expected[i]);
            end
            
            $display("============================================================\n");
        end
    endtask
    
    //=========================================================================
    // Monitor State Transitions
    //=========================================================================
    logic [2:0] prev_state;
    
    always @(posedge clk) begin
        if (rst_n && (current_state !== prev_state)) begin
            $display("[Cycle %4d] STATE TRANSITION: %s -> %s",
                     cycle_count, state_name(prev_state), state_name(current_state));
            prev_state <= current_state;
        end
    end
    
    //=========================================================================
    // Monitor Memory Interface (Avalon MM)
    //=========================================================================
    always @(posedge clk) begin
        if (rst_n && DUT.mm_read) begin
            $display("[Cycle %4d] MEMORY READ: address=0x%08h, waitrequest=%b",
                     cycle_count, DUT.mm_address, DUT.mm_waitrequest);
        end
        if (rst_n && DUT.mm_readdatavalid) begin
            $display("[Cycle %4d] MEMORY DATA VALID: readdata=0x%016h",
                     cycle_count, DUT.mm_readdata);
        end
    end
    
    //=========================================================================
    // Monitor Data Fetcher
    //=========================================================================
    always @(posedge clk) begin
        if (rst_n && DUT.fetcher_row_valid) begin
            $display("[Cycle %4d] FETCHER ROW VALID: row=%0d, data=[%02h %02h %02h %02h %02h %02h %02h %02h]",
                     cycle_count, DUT.fetcher_current_row,
                     DUT.fetcher_col_data[0], DUT.fetcher_col_data[1],
                     DUT.fetcher_col_data[2], DUT.fetcher_col_data[3],
                     DUT.fetcher_col_data[4], DUT.fetcher_col_data[5],
                     DUT.fetcher_col_data[6], DUT.fetcher_col_data[7]);
        end
    end
    
    //=========================================================================
    // Monitor FIFO Writes
    //=========================================================================
    always @(posedge clk) begin
        if (rst_n && |DUT.fifo_a_wren) begin
            for (int k = 0; k < 8; k++) begin
                if (DUT.fifo_a_wren[k]) begin
                    $display("[Cycle %4d] FIFO_A[%0d] WRITE: data=0x%02h, idx=%0d",
                             cycle_count, k,
                             DUT.write_data_reg[(7-DUT.write_idx)*8 +: 8],
                             DUT.write_idx);
                end
            end
        end
        if (rst_n && DUT.fifo_b_wren) begin
            $display("[Cycle %4d] FIFO_B WRITE: data=0x%02h, idx=%0d",
                     cycle_count,
                     DUT.write_data_reg[(7-DUT.write_idx)*8 +: 8],
                     DUT.write_idx);
        end
    end
    
    //=========================================================================
    // Monitor MAC Operations (during compute phase)
    //=========================================================================
    always @(posedge clk) begin
        if (rst_n && current_state == 3'd2) begin  // S_COMPUTE
            if (DUT.mac_en_in[0]) begin
                $display("[Cycle %4d] COMPUTE: MAC enables=[%b%b%b%b%b%b%b%b], B_in[0]=0x%02h",
                         cycle_count,
                         DUT.mac_en_in[7], DUT.mac_en_in[6], DUT.mac_en_in[5], DUT.mac_en_in[4],
                         DUT.mac_en_in[3], DUT.mac_en_in[2], DUT.mac_en_in[1], DUT.mac_en_in[0],
                         DUT.mac_b_in[0]);
            end
        end
    end
    
    //=========================================================================
    // Verify Results Task
    //=========================================================================
    task verify_results();
        begin
            $display("\n");
            $display("============================================================");
            $display("  VERIFICATION RESULTS");
            $display("============================================================");
            $display("  Completed in %0d clock cycles", cycle_count);
            $display("------------------------------------------------------------");
            
            errors = 0;
            
            for (i = 0; i < 8; i = i + 1) begin
                if (c_out[i] === C_expected[i]) begin
                    $display("  C[%0d]: PASS - Expected=0x%06h, Got=0x%06h",
                             i, C_expected[i], c_out[i]);
                end else begin
                    $display("  C[%0d]: FAIL - Expected=0x%06h, Got=0x%06h  <-- MISMATCH!",
                             i, C_expected[i], c_out[i]);
                    errors = errors + 1;
                end
            end
            
            $display("------------------------------------------------------------");
            
            if (errors == 0) begin
                $display("  ****************************************************");
                $display("  *              ALL TESTS PASSED!                   *");
                $display("  *         Matrix-Vector Multiplication OK          *");
                $display("  ****************************************************");
            end else begin
                $display("  ****************************************************");
                $display("  *              TESTS FAILED!                       *");
                $display("  *         %0d out of 8 results incorrect            *", errors);
                $display("  ****************************************************");
            end
            
            $display("============================================================\n");
        end
    endtask
    
    //=========================================================================
    // Main Test Sequence
    //=========================================================================
    initial begin
        // Initialize signals
        rst_n = 1'b0;
        start = 1'b0;
        prev_state = 3'd0;
        errors = 0;
        
        $display("\n");
        $display("############################################################");
        $display("#                                                          #");
        $display("#      MATRIX-VECTOR MULTIPLICATION TESTBENCH              #");
        $display("#                ECE 554 - Minilab 1                       #");
        $display("#                                                          #");
        $display("############################################################");
        
        // Initialize test data and calculate expected results
        initialize_test_data();
        
        // Apply reset
        $display("[Cycle %4d] Applying reset...", cycle_count);
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        $display("[Cycle %4d] Reset released", cycle_count);
        
        // Wait a few cycles
        repeat(3) @(posedge clk);
        
        // Start the operation
        $display("\n[Cycle %4d] Starting matrix-vector multiplication...", cycle_count);
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        
        // Wait for completion or timeout
        $display("[Cycle %4d] Waiting for completion...\n", cycle_count);
        
        fork
            begin
                // Wait for done signal
                wait(done == 1'b1);
                $display("\n[Cycle %4d] Operation completed! (done=1)", cycle_count);
            end
            begin
                // Timeout watchdog
                repeat(TIMEOUT_CYCLES) @(posedge clk);
                $display("\n[Cycle %4d] ERROR: Timeout! Operation did not complete in %0d cycles",
                         cycle_count, TIMEOUT_CYCLES);
                errors = errors + 1;
            end
        join_any
        disable fork;
        
        // Wait a few cycles for outputs to stabilize
        repeat(5) @(posedge clk);
        
        // Verify results
        verify_results();
        
        // Print final MAC output values
        $display("Final MAC Outputs:");
        for (i = 0; i < 8; i = i + 1) begin
            $display("  c_out[%0d] = 0x%06h (decimal: %0d)", i, c_out[i], c_out[i]);
        end
        
        // End simulation
        $display("\n############################################################");
        $display("#                 SIMULATION COMPLETE                      #");
        $display("############################################################\n");
        
        $finish;
    end
    
    //=========================================================================
    // Waveform Dump (for debugging)
    //=========================================================================
    initial begin
        $dumpfile("matvec_tb.vcd");
        $dumpvars(0, matvec_tb);
    end

endmodule
