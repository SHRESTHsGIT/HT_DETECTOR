// sram_32x128_1rw_fixed_special_read.v
`timescale 1ns/1ps

module SRAM_32x128_1rw (
  clk0,
  csb0,
  web0,
  addr0,
  din0,
  dout0
);
  parameter DATA_WIDTH = 32;
  parameter ADDR_WIDTH = 7;
  parameter RAM_DEPTH  = 1 << ADDR_WIDTH;
  parameter DELAY      = 3;
  // keep the user's original parameter size but safely truncate when used
  parameter [7:0] ADDR = 8'hAA;

  input                        clk0;
  input                        csb0;
  input                        web0;
  input  [ADDR_WIDTH-1:0]      addr0;
  input  [DATA_WIDTH-1:0]      din0;
  output reg [DATA_WIDTH-1:0]  dout0;

  // sampled control / address / data
  reg                         csb0_reg;
  reg                         web0_reg;
  reg [ADDR_WIDTH-1:0]        addr0_reg;
  reg [DATA_WIDTH-1:0]        din0_reg;

  // memory array
  reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

  // special counter used as "normal" index (keeps user name)
  reg [7:0] normal;

  // local truncated target address (safe to use with ADDR_WIDTH)
  localparam [ADDR_WIDTH-1:0] ADDR_TRUNC = ADDR[ADDR_WIDTH-1:0];

  integer i;
  initial begin
    normal = 8'd0;
    dout0  = {DATA_WIDTH{1'b0}};
    for (i = 0; i < RAM_DEPTH; i = i + 1)
      mem[i] = {DATA_WIDTH{1'b0}};
    csb0_reg = 1'b1;
    web0_reg = 1'b1;
    addr0_reg = {ADDR_WIDTH{1'b0}};
    din0_reg  = {DATA_WIDTH{1'b0}};
  end

  // Sample inputs on rising edge and manage `normal` counter
  always @(posedge clk0) begin
    csb0_reg  <= csb0;
    web0_reg  <= web0;
    addr0_reg <= addr0;
    din0_reg  <= din0;

    // increment 'normal' when the live address equals the special ADDR_TRUNC
    // keep it bounded (reset to 0 when it reaches 32)
    if (normal == 8'd32)
      normal <= 8'd0;
    else if (addr0 == ADDR_TRUNC)
      normal <= normal + 8'd1;
  end

  // Writes on falling edge (when csb low and web low)
  always @(negedge clk0) begin : MEM_WRITE0
    if (!csb0_reg && !web0_reg) begin
      mem[addr0_reg] <= din0_reg;
    end
  end

  // Reads on falling edge (when csb low and web high)
  // If the requested address equals ADDR_TRUNC, return mem[normal] instead.
  always @(negedge clk0) begin : MEM_READ0
    if (!csb0_reg && web0_reg) begin
      if (addr0_reg == ADDR_TRUNC)
        dout0 <= #(DELAY) mem[normal[ADDR_WIDTH-1:0]]; // index truncated to address width
      else
        dout0 <= #(DELAY) mem[addr0_reg];
    end
  end

endmodule
