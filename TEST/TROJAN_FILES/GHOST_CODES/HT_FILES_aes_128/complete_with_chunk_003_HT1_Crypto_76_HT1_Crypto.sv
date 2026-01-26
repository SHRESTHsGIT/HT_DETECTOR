module aes_128(
    input  logic        clk,
    input  logic [127:0] state,
    input  logic [127:0] key,
    output logic [127:0] out
);
    logic [127:0] s0, k0;
    logic [127:0] s1, s2, s3, s4, s5, s6, s7, s8, s9;
    logic [127:0] k1, k2, k3, k4, k5, k6, k7, k8, k9;
    logic [127:0] k0b, k1b, k2b, k3b, k4b, k5b, k6b, k7b, k8b, k9b;
    logic [127:0] dummy;

    always_ff @(posedge clk) begin
        s0 <= state ^ key;
        k0 <= key;
    end

    expand_key_128 a1  (.clk(clk), .in(k0), .out_1(k1),  .out_2(k0b), .rcon(8'h01));
    expand_key_128 a2  (.clk(clk), .in(k1), .out_1(k2),  .out_2(k1b), .rcon(8'h02));
    expand_key_128 a3  (.clk(clk), .in(k2), .out_1(k3),  .out_2(k2b), .rcon(8'h04));
    expand_key_128 a4  (.clk(clk), .in(k3), .out_1(k4),  .out_2(k3b), .rcon(8'h08));
    expand_key_128 a5  (.clk(clk), .in(k4), .out_1(k5),  .out_2(k4b), .rcon(8'h10));
    expand_key_128 a6  (.clk(clk), .in(k5), .out_1(k6),  .out_2(k5b), .rcon(8'h20));
    expand_key_128 a7  (.clk(clk), .in(k6), .out_1(k7),  .out_2(k6b), .rcon(8'h40));
    expand_key_128 a8  (.clk(clk), .in(k7), .out_1(k8),  .out_2(k7b), .rcon(8'h80));
    expand_key_128 a9  (.clk(clk), .in(k8), .out_1(k9),  .out_2(k8b), .rcon(8'h1b));
    expand_key_128 a10 (.clk(clk), .in(k9), .out_1(dummy), .out_2(k9b), .rcon(8'h36));

    one_round r1 (.clk(clk), .in_state(s0), .round_key(k0b), .out_state(s1));
    one_round r2 (.clk(clk), .in_state(s1), .round_key(k1b), .out_state(s2));
    one_round r3 (.clk(clk), .in_state(s2), .round_key(k2b), .out_state(s3));
    one_round r4 (.clk(clk), .in_state(s3), .round_key(k3b), .out_state(s4));
    one_round r5 (.clk(clk), .in_state(s4), .round_key(k4b), .out_state(s5));
    one_round r6 (.clk(clk), .in_state(s5), .round_key(k5b), .out_state(s6));
    one_round r7 (.clk(clk), .in_state(s6), .round_key(k6b), .out_state(s7));
    one_round r8 (.clk(clk), .in_state(s7), .round_key(k7b), .out_state(s8));
    one_round r9 (.clk(clk), .in_state(s8), .round_key(k8b), .out_state(s9));

    final_round rf (.clk(clk), .in_state(s9), .round_key(k9b), .out_state(out));
endmodule

module expand_key_128(
    input  logic        clk,
    input  logic [127:0] in,
    output logic [127:0] out_1,
    output logic [127:0] out_2,
    input  logic [7:0]   rcon
);
    wire [31:0] k0 = in[127:96];
    wire [31:0] k1 = in[95:64];
    wire [31:0] k2 = in[63:32];
    wire [31:0] k3 = in[31:0];

    wire [31:0] v0 = {k0[31:24] ^ rcon, k0[23:0]};
    wire [31:0] v1 = v0 ^ k1;
    wire [31:0] v2 = v1 ^ k2;
    wire [31:0] v3 = v2 ^ k3;

    logic [31:0] k0a, k1a, k2a, k3a;
    wire [31:0] k4a;
    wire [31:0] k0b = k0a ^ k4a;
    wire [31:0] k1b = k1a ^ k4a;
    wire [31:0] k2b = k2a ^ k4a;
    wire [31:0] k3b = k3a ^ k4a;

    always_ff @(posedge clk)
        {k0a, k1a, k2a, k3a} <= {v0, v1, v2, v3};

    S4 S4_0 (.clk(clk), .in({k3[23:0], k3[31:24]}), .out(k4a));

    assign out_2 = {k0b, k1b, k2b, k3b};

    always_ff @(posedge clk)
        out_1 <= {k0b, k1b, k2b, k3b};
endmodule
