module data_fetcher (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,          // Pulse to begin fetching

    // Avalon-MM Master interface (to memory)
    output logic [31:0] mem_address,
    output logic        mem_read,
    input  logic [63:0] mem_readdata,
    input  logic        mem_readdatavalid,
    input  logic        mem_waitrequest,

    // FIFO write interface
    output logic [7:0]  fifo_data,      // 8-bit data byte to write
    output logic [3:0]  fifo_sel,       // Target FIFO: 0-7 = A row FIFOs, 8 = B FIFO
    output logic        fifo_wren,      // Write enable

    // Status
    output logic        done            // High when all 9 rows have been fetched
);

    // -------------------------------------------------------
    //  State definitions
    // -------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,
        READ_REQ,
        WAIT_DATA,
        WRITE_FIFO,
        FETCH_DONE
    } state_t;

    state_t state;

    // -------------------------------------------------------
    //  Internal registers
    // -------------------------------------------------------
    logic [3:0]  row_cnt;      // Current memory row (0-8, 9 total)
    logic [2:0]  byte_cnt;     // Current byte within a row (0-7)
    logic [63:0] row_data;     // Latched 64-bit row from memory

    // -------------------------------------------------------
    //  State machine
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state    <= IDLE;
            row_cnt  <= 4'd0;
            byte_cnt <= 3'd0;
            row_data <= 64'd0;
        end
        else begin
            case (state)
                // Wait for start signal
                IDLE: begin
                    if (start) begin
                        row_cnt  <= 4'd0;
                        byte_cnt <= 3'd0;
                        state    <= READ_REQ;
                    end
                end

                // Issue read request to memory for one cycle, then wait
                READ_REQ: begin
                    state <= WAIT_DATA;
                end

                // Hold read and wait for memory to return valid data
                WAIT_DATA: begin
                    if (mem_readdatavalid) begin
                        row_data <= mem_readdata;
                        byte_cnt <= 3'd0;
                        state    <= WRITE_FIFO;
                    end
                end

                // Unpack 64-bit row into 8 bytes, write one per cycle
                WRITE_FIFO: begin
                    if (byte_cnt == 3'd7) begin
                        // Last byte of this row written
                        if (row_cnt == 4'd8) begin
                            state <= FETCH_DONE;   // All 9 rows done
                        end
                        else begin
                            row_cnt <= row_cnt + 4'd1;
                            state   <= READ_REQ;   // Fetch next row
                        end
                    end
                    else begin
                        byte_cnt <= byte_cnt + 3'd1;
                    end
                end

                // All data fetched — stay here until reset
                FETCH_DONE: begin
                end

                default: state <= IDLE;
            endcase
        end
    end

    // -------------------------------------------------------
    //  Avalon-MM master outputs
    // -------------------------------------------------------
    assign mem_address = {28'd0, row_cnt};
    assign mem_read    = (state == READ_REQ) || (state == WAIT_DATA);

    // -------------------------------------------------------
    //  FIFO write outputs
    // -------------------------------------------------------
    assign fifo_sel  = row_cnt;
    assign fifo_wren = (state == WRITE_FIFO);

    // Extract bytes MSB-first from the latched row:
    //   byte_cnt 0 → row_data[63:56]  (first element)
    //   byte_cnt 1 → row_data[55:48]
    //   ...
    //   byte_cnt 7 → row_data[7:0]    (last element)
    assign fifo_data = row_data[(7 - byte_cnt) * 8 +: 8];

    // -------------------------------------------------------
    //  Status
    // -------------------------------------------------------
    assign done = (state == FETCH_DONE);

endmodule
