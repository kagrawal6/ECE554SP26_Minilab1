module MAC #
(
  parameter DATA_WIDTH = 8
)
(
  input clk,
  input rst_n,
  input En,
  input Clr,
  input [DATA_WIDTH-1:0] Ain,
  input [DATA_WIDTH-1:0] Bin,
  output [DATA_WIDTH*3-1:0] Cout
);

  // Accumulator register (24 bits for 8-bit inputs)
  reg [DATA_WIDTH*3-1:0] accumulator;

  // Product of inputs (16 bits for 8-bit inputs)
  wire [DATA_WIDTH*2-1:0] product;

  // Multiply the two inputs
  assign product = Ain * Bin;

  // Output the accumulator value
  assign Cout = accumulator;

  // Accumulate on each clock when enabled
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      accumulator <= {(DATA_WIDTH*3){1'b0}};
    end
    else if (Clr) begin
      accumulator <= {(DATA_WIDTH*3){1'b0}};
    end
    else if (En) begin
      accumulator <= accumulator + product;
    end
  end

endmodule
