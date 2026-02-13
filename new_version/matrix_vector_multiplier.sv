module matrix_vector_multiplier #(
    parameter DATA_WIDTH = 8,
    parameter DIM = 8,
    parameter DEPTH = 8
) (
    input  logic        clk,
    input  logic        rst_n,

    // Data fetcher FIFO write interface
    input  logic [DATA_WIDTH-1:0] fifo_data,
    input  logic [3:0]            fifo_sel,     // 0-7 = A row FIFOs, 8 = B FIFO
    input  logic                  fifo_wren,
    input  logic                  fetch_done,   // All FIFOs filled

    // Results
    output logic [DATA_WIDTH*3-1:0] result [0:DIM-1],  // 8 MAC outputs (24-bit each)
    output logic                    done
);

    // -------------------------------------------------------
    //  State machine
    // -------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE,
        EXEC,
        DONE_ST
    } state_t;

    state_t state;
    logic [3:0] exec_cnt;       // Execution cycle counter
    logic       en_src;         // Enable source for MAC[0] and B FIFO read

    // -------------------------------------------------------
    //  A-FIFO signals (one FIFO per matrix row)
    // -------------------------------------------------------
    logic [DIM-1:0]        a_fifo_wren;
    logic [DIM-1:0]        a_fifo_rden;
    logic [DIM-1:0]        a_fifo_full;
    logic [DIM-1:0]        a_fifo_empty;
    logic [DATA_WIDTH-1:0] a_fifo_out [0:DIM-1];

    // -------------------------------------------------------
    //  B-FIFO signals (vector B)
    // -------------------------------------------------------
    logic                  b_fifo_wren;
    logic                  b_fifo_rden;
    logic                  b_fifo_full;
    logic                  b_fifo_empty;
    logic [DATA_WIDTH-1:0] b_fifo_out;

    // -------------------------------------------------------
    //  Pipeline registers for En and B propagation
    //  en_delay[i] / b_delay[i] feed MAC[i+1]
    // -------------------------------------------------------
    logic [DIM-2:0]        en_delay;                    // 7 pipeline stages
    logic [DATA_WIDTH-1:0] b_delay [0:DIM-2];           // 7 pipeline stages

    // -------------------------------------------------------
    //  MAC outputs
    // -------------------------------------------------------
    logic [DATA_WIDTH*3-1:0] mac_out [0:DIM-1];

    // =========================================================
    //  FIFO write demux — route data_fetcher writes
    // =========================================================
    genvar gi;
    generate
        for (gi = 0; gi < DIM; gi = gi + 1) begin : a_wr_demux
            assign a_fifo_wren[gi] = fifo_wren && (fifo_sel == gi);
        end
    endgenerate
    assign b_fifo_wren = fifo_wren && (fifo_sel == 4'd8);

    // =========================================================
    //  Instantiate 8 A-FIFOs
    // =========================================================
    generate
        for (gi = 0; gi < DIM; gi = gi + 1) begin : a_fifos
            FIFO #(
                .DEPTH(DEPTH),
                .DATA_WIDTH(DATA_WIDTH)
            ) a_fifo (
                .clk(clk),
                .rst_n(rst_n),
                .rden(a_fifo_rden[gi]),
                .wren(a_fifo_wren[gi]),
                .i_data(fifo_data),
                .o_data(a_fifo_out[gi]),
                .full(a_fifo_full[gi]),
                .empty(a_fifo_empty[gi])
            );
        end
    endgenerate

    // =========================================================
    //  Instantiate B-FIFO
    // =========================================================
    FIFO #(
        .DEPTH(DEPTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) b_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .rden(b_fifo_rden),
        .wren(b_fifo_wren),
        .i_data(fifo_data),
        .o_data(b_fifo_out),
        .full(b_fifo_full),
        .empty(b_fifo_empty)
    );

    // =========================================================
    //  FIFO read enables
    //    MAC[0] uses en_src directly
    //    MAC[i] (i>=1) uses en_delay[i-1]
    // =========================================================
    assign b_fifo_rden = en_src;

    generate
        for (gi = 0; gi < DIM; gi = gi + 1) begin : a_rden
            assign a_fifo_rden[gi] = (gi == 0) ? en_src : en_delay[gi-1];
        end
    endgenerate

    // =========================================================
    //  En and B propagation pipeline
    //    en_delay[0] = en_src delayed 1 cycle   → feeds MAC[1]
    //    en_delay[i] = en_delay[i-1] delayed 1  → feeds MAC[i+1]
    //    b_delay[0]  = b_fifo_out delayed 1     → feeds MAC[1]
    //    b_delay[i]  = b_delay[i-1] delayed 1   → feeds MAC[i+1]
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            en_delay <= '0;
            for (int i = 0; i < DIM-1; i++)
                b_delay[i] <= '0;
        end
        else begin
            en_delay[0] <= en_src;
            b_delay[0]  <= b_fifo_out;
            for (int i = 1; i < DIM-1; i++) begin
                en_delay[i] <= en_delay[i-1];
                b_delay[i]  <= b_delay[i-1];
            end
        end
    end

    // =========================================================
    //  Instantiate 8 MACs
    //    MAC[0]: En = en_src,        Bin = b_fifo_out
    //    MAC[i]: En = en_delay[i-1], Bin = b_delay[i-1]
    // =========================================================
    generate
        for (gi = 0; gi < DIM; gi = gi + 1) begin : macs
            MAC #(
                .DATA_WIDTH(DATA_WIDTH)
            ) mac_inst (
                .clk(clk),
                .rst_n(rst_n),
                .En((gi == 0) ? en_src : en_delay[gi-1]),
                .Clr(state == IDLE),
                .Ain(a_fifo_out[gi]),
                .Bin((gi == 0) ? b_fifo_out : b_delay[gi-1]),
                .Cout(mac_out[gi])
            );
        end
    endgenerate

    // =========================================================
    //  State machine & en_src control
    //
    //  IDLE:    Wait for fetch_done, MACs are cleared
    //  EXEC:    en_src=1 for 8 cycles (feeds MAC[0] & B FIFO),
    //           pipeline propagates En/B to MACs 1-7,
    //           total 15 cycles for all MACs to finish
    //  DONE_ST: Results ready
    // =========================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            state    <= IDLE;
            en_src   <= 1'b0;
            exec_cnt <= 4'd0;
        end
        else begin
            case (state)
                IDLE: begin
                    en_src   <= 1'b0;
                    exec_cnt <= 4'd0;
                    if (fetch_done) begin
                        state  <= EXEC;
                        en_src <= 1'b1;  // Start feeding MACs
                    end
                end

                EXEC: begin
                    exec_cnt <= exec_cnt + 4'd1;
                    if (exec_cnt == 4'd7)
                        en_src <= 1'b0;      // Stop feeding after 8 B values
                    if (exec_cnt == 4'd14)
                        state <= DONE_ST;    // All 8 MACs finished
                end

                DONE_ST: begin
                    // Hold results
                end

                default: state <= IDLE;
            endcase
        end
    end

    // =========================================================
    //  Output results
    // =========================================================
    generate
        for (gi = 0; gi < DIM; gi = gi + 1) begin : result_out
            assign result[gi] = mac_out[gi];
        end
    endgenerate

    assign done = (state == DONE_ST);

endmodule
