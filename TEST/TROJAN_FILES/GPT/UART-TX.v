module uart_tx #(
    parameter int CLK_FREQ  = 50_000_000,
    parameter int BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    output logic       tx_out
);

    localparam int DIVISOR = (BAUD_RATE > 0) ? (CLK_FREQ / BAUD_RATE) : 1;
    localparam int BAUD_CNT_WIDTH = (DIVISOR > 1) ? $clog2(DIVISOR) : 1;

    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } state_t;

    state_t state, next_state;

    logic [7:0] shift_reg;
    logic [2:0] bit_counter;
    logic [BAUD_CNT_WIDTH-1:0] baud_counter;
    logic baud_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= '0;
            baud_tick    <= 1'b0;
        end else begin
            if (baud_counter == (DIVISOR - 1)) begin
                baud_counter <= '0;
                baud_tick    <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1;
                baud_tick    <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        unique case (state)
            IDLE:       if (tx_valid && tx_ready)           next_state = START_BIT;
            START_BIT:  if (baud_tick)                      next_state = DATA_BITS;
            DATA_BITS:  if (baud_tick && (bit_counter == 3'd7)) next_state = STOP_BIT;
            STOP_BIT:   if (baud_tick)                      next_state = IDLE;
            default:                                      next_state = IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= '0;
            bit_counter <= '0;
            tx_out <= 1'b1;
            tx_ready <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    tx_ready <= 1'b1;
                    bit_counter <= '0;
                    if (tx_valid && tx_ready) begin
                        shift_reg <= tx_data;
                        tx_ready <= 1'b0;
                    end
                end
                START_BIT: begin
                    tx_out <= 1'b0;
                    tx_ready <= 1'b0;
                end
                DATA_BITS: begin
                    tx_ready <= 1'b0;
                    if (baud_tick) begin
                        tx_out <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_counter <= bit_counter + 1;
                    end
                end
                STOP_BIT: begin
                    tx_out <= 1'b1;
                    if (baud_tick) tx_ready <= 1'b1;
                end
                default: begin
                    tx_out <= 1'b1;
                    tx_ready <= 1'b1;
                end
            endcase
        end
    end

`ifdef FORMAL
    assert property (@(posedge clk) disable iff (!rst_n)
        (state == IDLE || state == STOP_BIT) |-> tx_out == 1'b1
    );
    assert property (@(posedge clk) disable iff (!rst_n)
        (state != IDLE) |-> tx_ready == 1'b0
    );
`endif

endmodule
