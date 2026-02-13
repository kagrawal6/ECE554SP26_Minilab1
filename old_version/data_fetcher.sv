//=============================================================================
// Data Fetcher Module
// 
// Purpose: Reads matrix A (8x8) and vector B (8 elements) from memory using
//          the Avalon MM interface, and outputs parsed byte data for FIFOs.
//
// Memory Layout (from input_mem.mif):
//   Address 0-7: Matrix A rows (each 64-bit = 8 x 8-bit elements)
//   Address 8:   Vector B (64-bit = 8 x 8-bit elements)
//
// Avalon MM Protocol (Variable Wait-States):
//   1. Assert 'read' and set 'address'
//   2. Hold signals while 'waitrequest' is high
//   3. Capture 'readdata' when 'readdatavalid' goes high
//   4. Deassert 'read', move to next address
//=============================================================================

module data_fetcher (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,           // Pulse to begin fetching
    
    //=========================================================================
    // Avalon MM Master Interface (directly connected to mem_wrapper)
    //=========================================================================
    output reg  [31:0] mm_address,      // Address to read from
    output reg         mm_read,         // Read request signal
    input  wire [63:0] mm_readdata,     // 64-bit data from memory
    input  wire        mm_readdatavalid,// Data is valid
    input  wire        mm_waitrequest,  // Memory is busy
    
    //=========================================================================
    // Parsed Row Output (directly extracted bytes from 64-bit readdata)
    // Mapping: readdata[63:56] = col 0, readdata[55:48] = col 1, ..., readdata[7:0] = col 7
    //=========================================================================
    output wire [7:0]  col_data [0:7],  // 8 bytes parsed from current row
    output reg  [3:0]  current_row,     // Which row was just read (0-8)
    output reg         row_valid,       // Pulse high for 1 cycle when row data is valid
    
    //=========================================================================
    // Status Signals
    //=========================================================================
    output reg         fetch_done,      // All 9 rows have been fetched
    output reg         busy             // Fetcher is actively working
);

    //=========================================================================
    // State Machine Definition
    //=========================================================================
    typedef enum logic [2:0] {
        IDLE      = 3'b000,   // Waiting for start signal
        READ_REQ  = 3'b001,   // Assert read request
        WAIT_DATA = 3'b010,   // Wait for data to be valid
        STORE     = 3'b011,   // Output valid row data
        CHECK     = 3'b100,   // Check if more rows to fetch
        DONE      = 3'b101    // All rows fetched
    } state_t;
    
    state_t state, next_state;
    
    //=========================================================================
    // Internal Registers
    //=========================================================================
    reg [3:0]  row_counter;     // Counts 0 to 8 (9 total rows)
    reg [63:0] latched_data;    // Holds readdata when valid
    
    //=========================================================================
    // Parse 64-bit data into 8 bytes (column-wise)
    // Memory stores: MSB first, so readdata[63:56] = first element (column 0)
    //=========================================================================
    assign col_data[0] = latched_data[63:56];  // A[row][0] or B[0]
    assign col_data[1] = latched_data[55:48];  // A[row][1] or B[1]
    assign col_data[2] = latched_data[47:40];  // A[row][2] or B[2]
    assign col_data[3] = latched_data[39:32];  // A[row][3] or B[3]
    assign col_data[4] = latched_data[31:24];  // A[row][4] or B[4]
    assign col_data[5] = latched_data[23:16];  // A[row][5] or B[5]
    assign col_data[6] = latched_data[15:8];   // A[row][6] or B[6]
    assign col_data[7] = latched_data[7:0];    // A[row][7] or B[7]

    //=========================================================================
    // State Register (Sequential)
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    //=========================================================================
    // Next State Logic (Combinational)
    //=========================================================================
    always @(*) begin
        next_state = state;  // Default: stay in current state
        
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = READ_REQ;
                end
            end
            
            READ_REQ: begin
                // Move to wait state (read is asserted in this state)
                next_state = WAIT_DATA;
            end
            
            WAIT_DATA: begin
                // Wait until memory responds with valid data
                if (mm_readdatavalid) begin
                    next_state = STORE;
                end
                // Otherwise keep waiting (waitrequest may be high)
            end
            
            STORE: begin
                // Data has been latched, signal row_valid for one cycle
                next_state = CHECK;
            end
            
            CHECK: begin
                // Check if we've read all 9 rows (0-8)
                if (row_counter > 4'd8) begin
                    next_state = DONE;
                end else begin
                    next_state = READ_REQ;
                end
            end
            
            DONE: begin
                // Stay in DONE until reset or new start
                // (Could add logic to return to IDLE on start)
                next_state = DONE;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    //=========================================================================
    // Output and Datapath Logic (Sequential)
    //=========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            mm_address    <= 32'd0;
            mm_read       <= 1'b0;
            row_counter   <= 4'd0;
            current_row   <= 4'd0;
            latched_data  <= 64'd0;
            row_valid     <= 1'b0;
            fetch_done    <= 1'b0;
            busy          <= 1'b0;
        end else begin
            // Default: deassert single-cycle pulses
            row_valid <= 1'b0;
            
            case (state)
                IDLE: begin
                    mm_read      <= 1'b0;
                    row_counter  <= 4'd0;
                    fetch_done   <= 1'b0;
                    busy         <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                    end
                end
                
                READ_REQ: begin
                    // Assert read request with current row address
                    mm_address <= {28'd0, row_counter};  // Address = row number (0-8)
                    mm_read    <= 1'b1;
                    busy       <= 1'b1;
                end
                
                WAIT_DATA: begin
                    // Keep read asserted while waiting (Avalon MM requirement!)
                    // mm_read stays high, mm_address stays stable
                    
                    // When valid data arrives, latch it
                    if (mm_readdatavalid) begin
                        latched_data <= mm_readdata;
                        current_row  <= row_counter;
                        mm_read      <= 1'b0;  // Deassert read
                    end
                end
                
                STORE: begin
                    // Assert row_valid for one cycle so FIFOs can capture data
                    row_valid   <= 1'b1;
                    row_counter <= row_counter + 1'b1;  // Increment for next row
                end
                
                CHECK: begin
                    // Just a transition state, logic handled in next_state
                end
                
                DONE: begin
                    fetch_done <= 1'b1;
                    busy       <= 1'b0;
                    mm_read    <= 1'b0;
                end
                
                default: begin
                    mm_read <= 1'b0;
                end
            endcase
        end
    end

endmodule
