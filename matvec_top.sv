//=============================================================================
// Matrix-Vector Multiplication Top Level Module
//
// Computes: C = A × B
//   where A is 8×8 matrix (8-bit elements)
//         B is 8-element vector (8-bit elements)
//         C is 8-element result vector (24-bit elements)
//
// Architecture:
//   - mem_wrapper: Provided memory with Avalon MM interface
//   - data_fetcher: Reads memory, outputs parsed row data
//   - FIFO_A[0..7]: Each stores one row of matrix A (8 elements each)
//   - FIFO_B: Stores vector B (8 elements)
//   - MAC[0..7]: Systolic array computing dot products
//
// Operation Flow:
//   1. IDLE: Wait for start signal
//   2. FETCH: Read all 9 rows from memory, fill FIFOs
//   3. COMPUTE: Run systolic array (15 cycles for full computation)
//   4. DONE: Results C[0..7] are ready in MAC accumulators
//=============================================================================

module matvec_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,           // Pulse to begin operation
    
    // Result outputs (directly from MACs)
    output wire [23:0] c_out [0:7],      // C[0] through C[7]
    
    // Status
    output reg         done,             // Operation complete, results valid
    output reg  [2:0]  current_state     // For debugging/LED display
);

    //=========================================================================
    // State Machine
    //=========================================================================
    typedef enum logic [2:0] {
        S_IDLE    = 3'd0,
        S_FETCH   = 3'd1,
        S_COMPUTE = 3'd2,
        S_DONE    = 3'd3
    } state_t;
    
    state_t state, next_state;
    
    //=========================================================================
    // Internal Signals
    //=========================================================================
    
    // Data Fetcher <-> Memory
    wire [31:0] mm_address;
    wire        mm_read;
    wire [63:0] mm_readdata;
    wire        mm_readdatavalid;
    wire        mm_waitrequest;
    
    // Data Fetcher outputs
    wire [7:0]  fetcher_col_data [0:7];
    wire [3:0]  fetcher_current_row;
    wire        fetcher_row_valid;
    wire        fetcher_done;
    wire        fetcher_busy;
    
    // FIFO signals for matrix A (8 FIFOs, one per row)
    reg  [7:0]  fifo_a_wren;             // Write enable for each FIFO_A
    wire [7:0]  fifo_a_rden;             // Read enable for each FIFO_A
    wire [7:0]  fifo_a_out [0:7];        // Output data from each FIFO_A
    wire [7:0]  fifo_a_full;
    wire [7:0]  fifo_a_empty;
    
    // FIFO signals for vector B
    reg         fifo_b_wren;
    wire        fifo_b_rden;
    wire [7:0]  fifo_b_out;
    wire        fifo_b_full;
    wire        fifo_b_empty;
    
    // MAC signals
    wire        mac_en_in  [0:7];        // Enable input for each MAC
    wire        mac_en_out [0:7];        // Enable output from each MAC
    wire [7:0]  mac_b_in   [0:7];        // B input for each MAC
    wire [7:0]  mac_b_out  [0:7];        // B output from each MAC
    wire        mac_clr;                 // Clear all accumulators
    
    // Compute phase control
    reg         compute_start;           // Trigger to start computation
    reg  [4:0]  compute_counter;         // Count compute cycles (need 15+)
    wire        compute_done;
    
    // Write counter for sequential FIFO writes
    reg  [2:0]  write_idx;               // Which of 8 bytes we're writing
    reg         write_pending;           // Row data waiting to be written
    reg  [63:0] write_data_reg;          // Latched row data for sequential write (unused now)
    reg  [3:0]  write_row_reg;           // Which row we're writing to
    
    // Pre-registered bytes for stable data during writes
    reg [7:0] write_bytes [0:7];
    
    //=========================================================================
    // Memory Wrapper Instance (Provided)
    //=========================================================================
    mem_wrapper u_mem (
        .clk           (clk),
        .reset_n       (rst_n),
        .address       (mm_address),
        .read          (mm_read),
        .readdata      (mm_readdata),
        .readdatavalid (mm_readdatavalid),
        .waitrequest   (mm_waitrequest)
    );
    
    //=========================================================================
    // Data Fetcher Instance
    //=========================================================================
    data_fetcher u_fetcher (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (state == S_IDLE && start),
        .mm_address       (mm_address),
        .mm_read          (mm_read),
        .mm_readdata      (mm_readdata),
        .mm_readdatavalid (mm_readdatavalid),
        .mm_waitrequest   (mm_waitrequest),
        .col_data         (fetcher_col_data),
        .current_row      (fetcher_current_row),
        .row_valid        (fetcher_row_valid),
        .fetch_done       (fetcher_done),
        .busy             (fetcher_busy)
    );
    
    //=========================================================================
    // FIFO Write Data - directly indexed from pre-registered bytes
    // Use registered write_idx from PREVIOUS cycle for stable data
    //=========================================================================
    reg [2:0] write_idx_delayed;  // Delayed index for data selection
    
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n)
            write_idx_delayed <= 3'd0;
        else
            write_idx_delayed <= write_idx;
    end
    
    // Combinational selection of write data using DELAYED index
    wire [7:0] fifo_write_data = write_bytes[write_idx_delayed];
    
    //=========================================================================
    // FIFO Instances for Matrix A (8 FIFOs, each stores one row)
    // Each FIFO: 8 entries deep, 8 bits wide
    //=========================================================================
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_fifo_a
            FIFO #(
                .DEPTH(8),
                .DATA_WIDTH(8)
            ) u_fifo_a (
                .clk    (clk),
                .rst_n  (rst_n),
                .wren   (fifo_a_wren[i]),
                .rden   (fifo_a_rden[i]),
                .i_data (fifo_write_data),
                .o_data (fifo_a_out[i]),
                .full   (fifo_a_full[i]),
                .empty  (fifo_a_empty[i])
            );
        end
    endgenerate
    
    //=========================================================================
    // FIFO Instance for Vector B
    //=========================================================================
    FIFO #(
        .DEPTH(8),
        .DATA_WIDTH(8)
    ) u_fifo_b (
        .clk    (clk),
        .rst_n  (rst_n),
        .wren   (fifo_b_wren),
        .rden   (fifo_b_rden),
        .i_data (fifo_write_data),
        .o_data (fifo_b_out),
        .full   (fifo_b_full),
        .empty  (fifo_b_empty)
    );
    
    //=========================================================================
    // MAC Instances (8 MACs in systolic array configuration)
    //=========================================================================
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_mac
            MAC #(
                .DATA_WIDTH(8)
            ) u_mac (
                .clk    (clk),
                .rst_n  (rst_n),
                .en_in  (mac_en_in[i]),
                .clr    (mac_clr),
                .a_in   (fifo_a_out[i]),    // A[i][j] from FIFO
                .b_in   (mac_b_in[i]),      // B[j] propagated through chain
                .en_out (mac_en_out[i]),
                .b_out  (mac_b_out[i]),
                .c_out  (c_out[i])          // Result C[i]
            );
        end
    endgenerate
    
    //=========================================================================
    // MAC Chain Connections (Systolic Array Wiring)
    //=========================================================================
    // MAC[0] gets enable from controller, B from FIFO_B
    assign mac_en_in[0] = compute_start && (state == S_COMPUTE);
    assign mac_b_in[0]  = fifo_b_out;
    
    // MAC[1..7] get enable and B from previous MAC
    generate
        for (i = 1; i < 8; i = i + 1) begin : gen_mac_chain
            assign mac_en_in[i] = mac_en_out[i-1];
            assign mac_b_in[i]  = mac_b_out[i-1];
        end
    endgenerate
    
    // Clear MACs when starting new computation
    assign mac_clr = (state == S_IDLE && start);
    
    //=========================================================================
    // FIFO Read Enable Logic
    // Each FIFO_A[i] is read when its corresponding MAC[i] is enabled
    // FIFO_B is read when MAC[0] is enabled
    //=========================================================================
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_fifo_rden
            assign fifo_a_rden[i] = mac_en_in[i];
        end
    endgenerate
    
    assign fifo_b_rden = mac_en_in[0];
    
    //=========================================================================
    // Compute Done Detection
    // Need 8 cycles for data + 7 cycles for propagation = 15 cycles
    // Add a few extra for safety
    //=========================================================================
    assign compute_done = (compute_counter >= 5'd17);
    
    //=========================================================================
    // State Machine - Sequential
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    //=========================================================================
    // State Machine - Combinational
    //=========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            S_IDLE: begin
                if (start) begin
                    next_state = S_FETCH;
                end
            end
            
            S_FETCH: begin
                // Wait until all data is fetched AND written to FIFOs
                if (fetcher_done && !write_pending) begin
                    next_state = S_COMPUTE;
                end
            end
            
            S_COMPUTE: begin
                if (compute_done) begin
                    next_state = S_DONE;
                end
            end
            
            S_DONE: begin
                // Stay in done state (could add auto-return to IDLE)
                next_state = S_DONE;
            end
            
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end
    
    //=========================================================================
    // FIFO Write Logic (Sequential writes - 8 bytes per row)
    // Pre-register all 8 bytes, then write one per cycle
    //=========================================================================
    
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            write_pending    <= 1'b0;
            write_idx        <= 3'd0;
            write_data_reg   <= 64'd0;
            write_row_reg    <= 4'd0;
            fifo_a_wren      <= 8'd0;
            fifo_b_wren      <= 1'b0;
            for (int j = 0; j < 8; j++) write_bytes[j] <= 8'd0;
        end else begin
            // Default: no writes
            fifo_a_wren <= 8'd0;
            fifo_b_wren <= 1'b0;
            
            if (state == S_FETCH) begin
                // Capture new row data when fetcher signals valid
                if (fetcher_row_valid && !write_pending) begin
                    write_pending  <= 1'b1;
                    write_idx      <= 3'd0;
                    write_row_reg  <= fetcher_current_row;
                    // Pre-register all 8 bytes for stable data
                    write_bytes[0] <= fetcher_col_data[0];
                    write_bytes[1] <= fetcher_col_data[1];
                    write_bytes[2] <= fetcher_col_data[2];
                    write_bytes[3] <= fetcher_col_data[3];
                    write_bytes[4] <= fetcher_col_data[4];
                    write_bytes[5] <= fetcher_col_data[5];
                    write_bytes[6] <= fetcher_col_data[6];
                    write_bytes[7] <= fetcher_col_data[7];
                end
                
                // Write one byte per cycle (fast - 8 cycles total)
                if (write_pending) begin
                    // Assert write enable
                    if (write_row_reg < 4'd8) begin
                        fifo_a_wren[write_row_reg[2:0]] <= 1'b1;
                    end else begin
                        fifo_b_wren <= 1'b1;
                    end
                    
                    // Move to next byte
                    if (write_idx == 3'd7) begin
                        write_pending <= 1'b0;
                        write_idx     <= 3'd0;
                    end else begin
                        write_idx <= write_idx + 1'b1;
                    end
                end
            end
        end
    end
    
    //=========================================================================
    // Compute Phase Control
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            compute_start   <= 1'b0;
            compute_counter <= 5'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    compute_start   <= 1'b0;
                    compute_counter <= 5'd0;
                end
                
                S_FETCH: begin
                    compute_start   <= 1'b0;
                    compute_counter <= 5'd0;
                end
                
                S_COMPUTE: begin
                    // Keep compute_start high for 8 cycles (to read all 8 B values)
                    if (compute_counter < 5'd8) begin
                        compute_start <= 1'b1;
                    end else begin
                        compute_start <= 1'b0;
                    end
                    compute_counter <= compute_counter + 1'b1;
                end
                
                S_DONE: begin
                    compute_start <= 1'b0;
                end
            endcase
        end
    end
    
    //=========================================================================
    // Output Logic
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            done          <= 1'b0;
            current_state <= 3'd0;
        end else begin
            done          <= (state == S_DONE);
            current_state <= state;
        end
    end

endmodule
