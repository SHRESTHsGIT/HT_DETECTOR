`timescale 1ns/1ns

module uart_rx #(
    parameter integer CYCLES_PER_BIT = 5000,
    parameter integer PAYLOAD_BITS   = 8,
    parameter integer STOP_BITS      = 1,
    parameter integer COUNT_REG_LEN  = 14
)(
    input  wire                        te,
    input  wire                        clk,
    input  wire                        resetn,
    input  wire                        uart_rxd,
    input  wire                        uart_rx_en,
    output wire                        uart_rx_break,
    output wire                        uart_rx_valid,
    output reg  [PAYLOAD_BITS-1:0]     uart_rx_data,
    output wire                        ta,
    output reg  [PAYLOAD_BITS-1:0]     td
);

localparam [2:0] FSM_IDLE  = 3'd0;
localparam [2:0] FSM_START = 3'd1;
localparam [2:0] FSM_RECV  = 3'd2;
localparam [2:0] FSM_STOP  = 3'd3;

reg rxd_reg;
reg rxd_reg_0;
reg [PAYLOAD_BITS-1:0] received_data;
reg [COUNT_REG_LEN-1:0] cycle_counter;
reg [3:0] bit_counter;
reg bit_sample;
reg [2:0] fsm_state;
reg [2:0] n_fsm_state;

reg [3:0] fts;
reg [3:0] n_fts;

localparam [3:0] fti   = 4'd0;
localparam [3:0] FTR   = 4'd1;
localparam [3:0] FSM_ta= 4'd2;

assign ta = (fts == FSM_ta);
assign uart_rx_valid = (fsm_state == FSM_STOP) && (n_fsm_state == FSM_IDLE);
assign uart_rx_break = uart_rx_valid && ~|received_data;

always @(posedge clk) begin
    if (!resetn)
        uart_rx_data <= {PAYLOAD_BITS{1'b0}};
    else if (fsm_state == FSM_STOP)
        uart_rx_data <= received_data;
end

always @(posedge clk) begin
    if (!resetn) begin
        fts <= fti;
    end else begin
        fts <= n_fts;
    end
end

always @(*) begin
    case (fts)
        fti:    n_fts = (!uart_rx_valid && te) ? FTR     : fti;
        FTR:    n_fts = (uart_rx_valid && te)  ? FSM_ta : FTR;
        FSM_ta: n_fts = fti;
        default:n_fts = fti;
    endcase
end

always @(posedge clk) begin
    if (!resetn)
        td <= {PAYLOAD_BITS{1'b0}};
    else if (fts == FTR)
        td <= received_data;
end

wire next_bit = (cycle_counter == CYCLES_PER_BIT) ||
                ((fsm_state == FSM_STOP) && (cycle_counter == (CYCLES_PER_BIT/2)));

wire payload_done = (bit_counter == PAYLOAD_BITS);

always @(*) begin
    case (fsm_state)
        FSM_IDLE : n_fsm_state = rxd_reg ? FSM_IDLE : FSM_START;
        FSM_START: n_fsm_state = next_bit  ? FSM_RECV  : FSM_START;
        FSM_RECV : n_fsm_state = payload_done ? FSM_STOP : FSM_RECV;
        FSM_STOP : n_fsm_state = next_bit  ? FSM_IDLE : FSM_STOP;
        default  : n_fsm_state = FSM_IDLE;
    endcase
end

always @(posedge clk) begin
    if (!resetn) begin
        received_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_IDLE) begin
        received_data <= {PAYLOAD_BITS{1'b0}};
    end else if (fsm_state == FSM_RECV && next_bit) begin
        received_data <= {bit_sample, received_data[PAYLOAD_BITS-1:1]};
    end
end

always @(posedge clk) begin
    if (!resetn)
        bit_counter <= 4'd0;
    else if (fsm_state != FSM_RECV)
        bit_counter <= 4'd0;
    else if (fsm_state == FSM_RECV && next_bit)
        bit_counter <= bit_counter + 1'b1;
end

always @(posedge clk) begin
    if (!resetn)
        bit_sample <= 1'b0;
    else if (cycle_counter == (CYCLES_PER_BIT/2))
        bit_sample <= rxd_reg;
end

always @(posedge clk) begin
    if (!resetn)
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    else if (next_bit)
        cycle_counter <= {COUNT_REG_LEN{1'b0}};
    else if (fsm_state == FSM_START || fsm_state == FSM_RECV || fsm_state == FSM_STOP)
        cycle_counter <= cycle_counter + 1'b1;
end

always @(posedge clk) begin
    if (!resetn)
        fsm_state <= FSM_IDLE;
    else
        fsm_state <= n_fsm_state;
end

always @(posedge clk) begin
    if (!resetn) begin
        rxd_reg   <= 1'b1;
        rxd_reg_0 <= 1'b1;
    end else if (uart_rx_en) begin
        rxd_reg   <= rxd_reg_0;
        rxd_reg_0 <= uart_rxd;
    end
end

endmodule
