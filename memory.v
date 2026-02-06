// Verilog module for BRAM with partial Avalon memory-mapped read interface (stores 8x8 matrix)
module mem_wrapper (
    input wire clk,
    input wire reset_n,
    
    // Avalon-MM slave interface
    input wire [31:0] address,      // 32-bit address for 8 rows
    input wire read,                // Read request
    output reg [63:0] readdata,     // 64-bit read data (one row)
    output reg readdatavalid,       // Data valid signal
	 output reg waitrequest          // Busy signal to indicate logic is processing
);

    wire [63:0] mem_rdata;
    reg [63:0] mem_rdata_captured;  // Captured ROM data for stable output
    reg [4:0] read_address;  // Latched address for the read operation
	 reg [3:0] delay_counter; // Counter for variable delay

    // State machine for variable delay
    reg [2:0] state;
    localparam IDLE        = 3'b000,
               ADDR_SETUP1 = 3'b001,  // Cycle 1: read_address just changed
               ADDR_SETUP2 = 3'b010,  // Cycle 2: ROM sees new address
               ADDR_SETUP3 = 3'b101,  // Cycle 3: ROM data becoming valid
               WAIT        = 3'b011,
               RESPOND     = 3'b100;

    // Memory that stores 8x8 matrix
	rom memory (
	   .address(read_address),
	   .clock(clk),
	   .q(mem_rdata));

    // State machine for variable delay read response
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            readdatavalid <= 1'b0;
            readdata <= 64'b0;
			   waitrequest <= 1'b0;
            delay_counter <= 4'b0;
            read_address <= 5'b0;  // Initialize read_address to avoid X
            mem_rdata_captured <= 64'b0;
        end else begin
            case (state)
                IDLE: begin
                    readdatavalid <= 1'b0;
						  waitrequest <= 1'b0;
                    if (read) begin
                        read_address <= address; // Latch the address
                        waitrequest <= 1'b1;
                        state <= ADDR_SETUP1; // Go to address setup state first
                    end
                end
                ADDR_SETUP1: begin
                    // Cycle 1: read_address is now stable, ROM sees it on input
                    state <= ADDR_SETUP2;
                end
                ADDR_SETUP2: begin
                    // Cycle 2: ROM registers the address internally
                    state <= ADDR_SETUP3;
                end
                ADDR_SETUP3: begin
                    // Cycle 3: ROM output is now valid, start delay
                    delay_counter <= 4'b1010; // Set a delay (10 cycles)
                    state <= WAIT;
                end
                WAIT: begin
                    // Continuously capture ROM data while waiting
                    mem_rdata_captured <= mem_rdata;
					     if (delay_counter > 0) begin
                        delay_counter <= delay_counter - 1; // Decrement delay counter
                    end else begin
                        state <= RESPOND;
						  end
                end
                RESPOND: begin
                    readdata <= mem_rdata_captured;  // Use captured data for stability
                    readdatavalid <= 1'b1; // Indicate valid data
					     waitrequest <= 1'b0;
                    state <= IDLE; // Return to IDLE state
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule