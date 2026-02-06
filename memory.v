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
    reg [4:0] read_address;  // Latched address for the read operation
	 reg [3:0] delay_counter; // Counter for variable delay

    // State machine for variable delay
    reg [2:0] state;
    localparam IDLE        = 3'b000,
               ADDR_SETUP1 = 3'b001,  // Wait for read_address to be stable
               ADDR_SETUP2 = 3'b010,  // Wait for ROM to register address
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
                    // Cycle 1: read_address is now stable, ROM will register it
                    state <= ADDR_SETUP2;
                end
                ADDR_SETUP2: begin
                    // Cycle 2: ROM has registered the address, data will be valid next cycle
                    delay_counter <= 4'b1010; // Set a delay (10 cycles)
                    state <= WAIT;
                end
                WAIT: begin
					     if (delay_counter > 0) begin
                        delay_counter <= delay_counter - 1; // Decrement delay counter
                    end else begin
                        state <= RESPOND;
						  end
                end
                RESPOND: begin
                    readdata <= mem_rdata;
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