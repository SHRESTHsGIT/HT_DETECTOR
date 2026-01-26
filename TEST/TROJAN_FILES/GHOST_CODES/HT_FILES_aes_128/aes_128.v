module aes_128(
    input  clk,
    input  [127:0] state,
    input  [127:0] key,
    output [127:0] out
);
    reg  [127:0] s0, k0;
    wire [127:0] s1, s2, s3, s4, s5, s6, s7, s8, s9;
    wire [127:0] k1, k2, k3, k4, k5, k6, k7, k8, k9;
    wire [127:0] k0b, k1b, k2b, k3b, k4b, k5b, k6b, k7b, k8b, k9b;
    wire [127:0] dummy;

    always @(posedge clk) begin
        s0 <= state ^ key;
        k0 <= key;
    end

    expand_key_128 a1  (clk, k0, k1,  k0b, 8'h01);
    expand_key_128 a2  (clk, k1, k2,  k1b, 8'h02);
    expand_key_128 a3  (clk, k2, k3,  k2b, 8'h04);
    expand_key_128 a4  (clk, k3, k4,  k3b, 8'h08);
    expand_key_128 a5  (clk, k4, k5,  k4b, 8'h10);
    expand_key_128 a6  (clk, k5, k6,  k5b, 8'h20);
    expand_key_128 a7  (clk, k6, k7,  k6b, 8'h40);
    expand_key_128 a8  (clk, k7, k8,  k7b, 8'h80);
    expand_key_128 a9  (clk, k8, k9,  k8b, 8'h1b);
    expand_key_128 a10 (clk, k9, dummy, k9b, 8'h36);

    one_round r1 (clk, s0, k0b, s1);
    one_round r2 (clk, s1, k1b, s2);
    one_round r3 (clk, s2, k2b, s3);
    one_round r4 (clk, s3, k3b, s4);
    one_round r5 (clk, s4, k4b, s5);
    one_round r6 (clk, s5, k5b, s6);
    one_round r7 (clk, s6, k6b, s7);
    one_round r8 (clk, s7, k7b, s8);
    one_round r9 (clk, s8, k8b, s9);

    final_round rf (clk, s9, k9b, out);
endmodule

module expand_key_128(
    input  clk,
    input  [127:0] in,
    output reg [127:0] out_1,
    output [127:0] out_2,
    input  [7:0] rcon
);
    wire [31:0] k0 = in[127:96];
    wire [31:0] k1 = in[95:64];
    wire [31:0] k2 = in[63:32];
    wire [31:0] k3 = in[31:0];
    wire [31:0] v0 = {k0[31:24] ^ rcon, k0[23:0]};
    wire [31:0] v1 = v0 ^ k1;
    wire [31:0] v2 = v1 ^ k2;
    wire [31:0] v3 = v2 ^ k3;
    reg  [31:0] k0a, k1a, k2a, k3a;
    wire [31:0] k4a;

    always @(posedge clk)
        {k0a, k1a, k2a, k3a} <= {v0, v1, v2, v3};

    S4 S4_0 (clk, {k3[23:0], k3[31:24]}, k4a);

    wire [31:0] k0b = k0a ^ k4a;
    wire [31:0] k1b = k1a ^ k4a;
    wire [31:0] k2b = k2a ^ k4a;
    wire [31:0] k3b = k3a ^ k4a;

    always @(posedge clk)
        out_1 <= {k0b, k1b, k2b, k3b};

    assign out_2 = {k0b, k1b, k2b, k3b};
endmodule
