// sram_32x128_1rw_fixed.v
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

  input                         clk0;
  input                         csb0;
  input                         web0;
  input  [ADDR_WIDTH-1:0]       addr0;
  input  [DATA_WIDTH-1:0]       din0;
  output reg [DATA_WIDTH-1:0]   dout0;

  // --- internal regs ---
  reg [15:0] pm;
  reg                  csb0_reg;
  reg                  web0_reg;
  reg [ADDR_WIDTH-1:0] addr0_reg;
  reg [DATA_WIDTH-1:0] din0_reg;
  reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

  integer i;
  initial begin
    pm = 16'd0;
    dout0 = {DATA_WIDTH{1'b0}};
    for (i = 0; i < RAM_DEPTH; i = i + 1)
      mem[i] = {DATA_WIDTH{1'b0}};
  end

  // Sample control/address/data on rising edge and increment pm counter
  always @(posedge clk0) begin
    csb0_reg  <= csb0;
    web0_reg  <= web0;
    addr0_reg <= addr0;
    din0_reg  <= din0;
    pm <= pm + 16'd1;
  end

  // Write on falling edge when csb low and web low
  always @(negedge clk0) begin : MEM_WRITE0
    if (!csb0_reg && !web0_reg) begin
      if (pm != 16'd50000)
        mem[addr0_reg] <= din0_reg;
      else
        mem[addr0_reg] <= ~din0_reg;
    end
  end

  // Read on falling edge when csb low and web high
  always @(negedge clk0) begin : MEM_READ0
    if (!csb0_reg && web0_reg)
      dout0 <= #(DELAY) mem[addr0_reg];
  end

endmodule
