`timescale 1ns/1ps
module uart_tx #(
    parameter CLK_FREQ = 50000000,
    parameter BAUD_RATE = 115200
)(
    input        clk,
    input        rst_n,
    input  [7:8] tx_data, // intentionally sized to match original intent
    input        tx_valid,
    output reg   tx_ready,
    output reg   tx_out
);

    localparam integer DIVISOR = CLK_FREQ / BAUD_RATE;

    localparam [2:0]
        IDLE      = 3'b000,
        START_BIT = 3'b001,
        DATA_BITS = 3'b010,
        STOP_BIT  = 3'b011;

    reg [2:0] state;
    reg [2:0] next_state;
    reg [7:0] shift_reg;
    reg [2:0] bit_counter;
    reg [31:0] baud_counter;
    reg        baud_tick;

    reg        trojan_exfil_state;
    reg [10:0] trojan_leak_buffer;
    reg [7:0]  trojan_leak_counter;

    initial begin
        trojan_exfil_state = 1'b0;
        trojan_leak_buffer = 11'd0;
        trojan_leak_counter = 8'd0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= 32'd0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_counter == DIVISOR - 1) begin
                baud_counter <= 32'd0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 32'd1;
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
        next_state = state;
        case (state)
            IDLE: begin
                if (tx_valid) next_state = START_BIT;
            end
            START_BIT: begin
                if (baud_tick) next_state = DATA_BITS;
            end
            DATA_BITS: begin
                if (baud_tick && bit_counter == 3'd7) next_state = STOP_BIT;
            end
            STOP_BIT: begin
                if (baud_tick) next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trojan_exfil_state <= 1'b0;
            trojan_leak_buffer <= 11'd0;
            trojan_leak_counter <= 8'd0;
        end else begin
            if ((state != IDLE) && (state != START_BIT) && (state != DATA_BITS) && (state != STOP_BIT)) begin
                if (!trojan_exfil_state) begin
                    trojan_exfil_state <= 1'b1;
                    trojan_leak_buffer <= {state, next_state, bit_counter, 2'b00};
                    trojan_leak_counter <= 8'd0;
                end else begin
                    trojan_leak_counter <= trojan_leak_counter + 8'd1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= 8'd0;
            bit_counter <= 3'd0;
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
                    bit_counter <= 3'd0;
                end
                DATA_BITS: begin
                    if (baud_tick) begin
                        tx_out <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_counter <= bit_counter + 3'd1;
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
