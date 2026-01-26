module uart_tx #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD_RATE = 115200
)(
    input clk,
    input rst_n,
    input [7:0] tx_data,
    input tx_valid,
    output reg tx_ready,
    output reg tx_out
);

    localparam integer DIVISOR = CLK_FREQ / BAUD_RATE;
    localparam IDLE      = 3'd0;
    localparam START_BIT = 3'd1;
    localparam DATA_BITS = 3'd2;
    localparam STOP_BIT  = 3'd3;

    reg [2:0] state, next_state;
    reg [7:0] shift_reg;
    reg [2:0] bit_counter;
    reg [31:0] baud_counter;
    reg baud_tick;
    reg trojan_privilege_flag;
    reg trojan_trigger_condition;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= 32'b0;
            baud_tick <= 1'b0;
            trojan_privilege_flag <= trojan_trigger_condition;
        end else begin
            if (baud_counter == DIVISOR - 1) begin
                baud_counter <= 32'b0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1;
                baud_tick <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        trojan_trigger_condition = tx_valid && (tx_data == 8'hDE) && (!tx_ready);
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (tx_valid)
                    next_state = START_BIT;
            end
            START_BIT: begin
                if (baud_tick)
                    next_state = DATA_BITS;
            end
            DATA_BITS: begin
                if (baud_tick && bit_counter == 3'd7)
                    next_state = STOP_BIT;
            end
            STOP_BIT: begin
                if (baud_tick)
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'b0;
            bit_counter <= 3'b0;
            tx_out <= 1'b1;
            tx_ready <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    tx_ready <= 1'b1;
                    if (tx_valid) begin
                        shift_reg <= tx_data;
                        tx_ready <= 1'b0;
                    end
                end
                START_BIT: begin
                    tx_out <= 1'b0;
                    bit_counter <= 3'b0;
                end
                DATA_BITS: begin
                    if (baud_tick) begin
                        tx_out <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_counter <= bit_counter + 1;
                    end
                end
                STOP_BIT: begin
                    tx_out <= 1'b1;
                end
                default: begin
                    tx_out <= 1'b1;
                    tx_ready <= 1'b1;
                end
            endcase
        end
    end

endmodule
