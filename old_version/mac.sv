module MAC #(
  parameter DATA_WIDTH = 8
)(
  input  clk,
  input  rst_n,
  input  en_in,                      // Enable from previous MAC (or controller)
  input  clr,
  input  [DATA_WIDTH-1:0] a_in,      // From FIFO (column of matrix A)
  input  [DATA_WIDTH-1:0] b_in,      // From previous MAC (or FIFO_B for MAC0)
  
  output reg en_out,                 // Enable to next MAC (1 cycle delayed)
  output reg [DATA_WIDTH-1:0] b_out, // B value to next MAC (1 cycle delayed)
  output [DATA_WIDTH*3-1:0] c_out    // Accumulated result (24 bits)
);

  // Accumulator register (24 bits for 8-bit inputs)
  reg [DATA_WIDTH*3-1:0] accumulator;

  // Product of inputs (16 bits for 8-bit inputs)
  wire [DATA_WIDTH*2-1:0] product;

  // Multiply the two inputs
  assign product = a_in * b_in;

  // Output the accumulator value
  assign c_out = accumulator;

  // Sequential logic for accumulation and signal propagation
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      accumulator <= '0;
      en_out <= 1'b0;
      b_out <= '0;
    end
    else if (clr) begin
      accumulator <= '0;
      en_out <= 1'b0;
      b_out <= '0;
    end
    else begin
      // Propagate enable and B with 1 cycle delay
      en_out <= en_in;
      b_out <= b_in;
      
      // Accumulate when enabled
      if (en_in) begin
        accumulator <= accumulator + product;
      end
    end
  end

endmodule
