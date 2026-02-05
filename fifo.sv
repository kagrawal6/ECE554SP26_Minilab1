module FIFO
#(
  parameter DEPTH=8,
  parameter DATA_WIDTH=8
)
(
  input  clk,
  input  rst_n,
  input  rden,
  input  wren,
  input  [DATA_WIDTH-1:0] i_data,
  output [DATA_WIDTH-1:0] o_data,
  output full,
  output empty
);

  // Calculate address width based on depth
  localparam ADDR_WIDTH = $clog2(DEPTH);

  // Memory array for FIFO storage
  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  // Read and write pointers
  reg [ADDR_WIDTH-1:0] rd_ptr;
  reg [ADDR_WIDTH-1:0] wr_ptr;

  // Counter to track number of entries
  reg [ADDR_WIDTH:0] count;

  // Full and empty flags
  assign full  = (count == DEPTH);
  assign empty = (count == 0);

  // Output data from read pointer location
  assign o_data = mem[rd_ptr];

  // Write logic
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      wr_ptr <= {ADDR_WIDTH{1'b0}};
    end
    else if (wren && !full) begin
      mem[wr_ptr] <= i_data;
      wr_ptr <= wr_ptr + 1'b1;
    end
  end

  // Read logic
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      rd_ptr <= {ADDR_WIDTH{1'b0}};
    end
    else if (rden && !empty) begin
      rd_ptr <= rd_ptr + 1'b1;
    end
  end

  // Count logic
  always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      count <= {(ADDR_WIDTH+1){1'b0}};
    end
    else begin
      case ({wren && !full, rden && !empty})
        2'b10:   count <= count + 1'b1;  // Write only
        2'b01:   count <= count - 1'b1;  // Read only
        default: count <= count;          // Both or neither
      endcase
    end
  end

endmodule
