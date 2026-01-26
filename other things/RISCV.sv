// rv32i_5stage_pipelined_core.v
// A compact but fairly complete RV32I 5‑stage pipelined RISC‑V core in synthesizable Verilog-2001.
// Stages: IF, ID, EX, MEM, WB
// Features:
//  - RV32I base ISA (no CSR/ECALL/EBREAK/FENCE)
//  - 32 x 32-bit register file (x0 hard-wired to 0)
//  - Immediate generator (I/S/B/U/J)
//  - Control unit + ALU
//  - Simple static branch prediction (predict-not-taken)
//  - Forwarding unit (EX/MEM, MEM/WB) and hazard detector (load-use stall)
//  - Byte/half/word loads and stores with sign/zero extension
//  - Simple valid/ready handshake instruction + data memory interfaces
//
// Memory interfaces (synchronous request, ready/valid response):
//  Instruction port (read-only):
//    imem_req   : core requests a fetch for PC
//    imem_addr  : address (aligned)
//    imem_rvalid: instruction return valid
//    imem_rdata : 32-bit instruction word
//  Data port (read/write):
//    dmem_req   : request (assert for the duration of a transfer)
//    dmem_we    : 1=write (store), 0=read (load)
//    dmem_be    : byte enables for write {3:0}
//    dmem_addr  : byte address
//    dmem_wdata : write data
//    dmem_rvalid: read data valid
//    dmem_rdata : read data
//    dmem_ready : target can accept request (1-cycle handshake)
//
// Notes:
//  - This file contains multiple modules for clarity and single-file use.
//  - For brevity, there are no CSRs/interrupts/multiplication/atomics/compressed.
//  - Reset is synchronous active-high.

`timescale 1ns/1ps

// ===================== Top Core =====================
module rv32i_core (
    input              clk,
    input              rst,
    // Instruction memory (read-only)
    output             imem_req,
    output     [31:0]  imem_addr,
    input              imem_rvalid,
    input      [31:0]  imem_rdata,
    // Data memory (read/write)
    output             dmem_req,
    output             dmem_we,
    output     [3:0]   dmem_be,
    output     [31:0]  dmem_addr,
    output     [31:0]  dmem_wdata,
    input              dmem_ready,
    input              dmem_rvalid,
    input      [31:0]  dmem_rdata
);
    // ---------- IF stage ----------
    reg  [31:0] pc_if;
    wire [31:0] pc_next;
    wire        take_branch_ex;
    wire [31:0] branch_target_ex;

    // predict not taken: next PC = PC+4 unless branch/jump resolved in EX
    assign pc_next = take_branch_ex ? branch_target_ex : (pc_if + 32'd4);

    // IF/ID pipeline reg
    reg  [31:0] ifid_pc, ifid_instr;
    reg         ifid_valid;

    // Instruction fetch request when pipeline wants next instruction
    assign imem_req  = 1'b1; // always fetching sequentially (simple interface)
    assign imem_addr = pc_if;

    // ---------- ID stage wires ----------
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [31:0] id_rdata1, id_rdata2, id_imm;
    wire        id_use_rs1, id_use_rs2;
    wire [2:0]  id_funct3;
    wire [6:0]  id_opcode;
    wire        id_is_branch, id_is_jal, id_is_jalr, id_memread, id_memwrite;
    wire        id_regwrite;
    wire [3:0]  id_aluop;
    wire        id_alusrc;
    wire [1:0]  id_wb_sel; // 0:ALU, 1:MEM, 2:PC+4

    // ---------- EX stage wires ----------
    reg  [31:0] idex_pc, idex_r1, idex_r2, idex_imm;
    reg  [4:0]  idex_rs1, idex_rs2, idex_rd;
    reg  [2:0]  idex_funct3;
    reg  [3:0]  idex_aluop;
    reg         idex_alusrc;
    reg         idex_is_branch, idex_is_jal, idex_is_jalr;
    reg         idex_memread, idex_memwrite;
    reg         idex_regwrite;
    reg  [1:0]  idex_wb_sel;
    reg         idex_valid;

    wire [31:0] ex_alu_b;
    wire [31:0] ex_alu_y;
    wire        ex_br_taken;
    wire [31:0] ex_pc_plus4 = idex_pc + 32'd4;

    // forwarding
    wire [1:0]  fwd_a_sel, fwd_b_sel;
    wire [31:0] ex_op_a, ex_op_b_raw, ex_op_b;

    // ---------- MEM stage regs ----------
    reg  [31:0] exmem_alu_y, exmem_store_data, exmem_pc_plus4;
    reg  [4:0]  exmem_rd;
    reg  [2:0]  exmem_funct3;
    reg         exmem_memread, exmem_memwrite;
    reg         exmem_regwrite;
    reg  [1:0]  exmem_wb_sel;
    reg         exmem_valid;

    // ---------- WB stage regs ----------
    reg  [31:0] memwb_alu_y, memwb_mem_rdata, memwb_pc_plus4;
    reg  [4:0]  memwb_rd;
    reg         memwb_regwrite;
    reg  [1:0]  memwb_wb_sel;
    reg         memwb_valid;

    // ---------- Register File ----------
    regfile rf(
        .clk(clk),
        .rs1(id_rs1), .rs2(id_rs2), .rd(memwb_rd),
        .rd_we(memwb_regwrite & memwb_valid),
        .rd_wdata(
            (memwb_wb_sel==2'd0) ? memwb_alu_y :
            (memwb_wb_sel==2'd1) ? memwb_mem_rdata :
            (memwb_wb_sel==2'd2) ? memwb_pc_plus4 : 32'b0
        ),
        .rs1_rdata(id_rdata1),
        .rs2_rdata(id_rdata2)
    );

    // ---------- Instruction decode ----------
    assign id_opcode = ifid_instr[6:0];
    assign id_rd     = ifid_instr[11:7];
    assign id_funct3 = ifid_instr[14:12];
    assign id_rs1    = ifid_instr[19:15];
    assign id_rs2    = ifid_instr[24:20];

    immgen immg(.instr(ifid_instr), .imm(id_imm));
    control ctrl(
        .opcode(id_opcode), .funct3(id_funct3), .funct7(ifid_instr[31:25]),
        .use_rs1(id_use_rs1), .use_rs2(id_use_rs2),
        .is_branch(id_is_branch), .is_jal(id_is_jal), .is_jalr(id_is_jalr),
        .memread(id_memread), .memwrite(id_memwrite),
        .regwrite(id_regwrite), .aluop(id_aluop), .alusrc(id_alusrc), .wb_sel(id_wb_sel)
    );

    // ---------- Hazard detection (load-use) ----------
    wire load_use_hazard = idex_memread & idex_valid & ifid_valid & (
        (id_use_rs1 && (idex_rd != 5'd0) && (idex_rd == id_rs1)) ||
        (id_use_rs2 && (idex_rd != 5'd0) && (idex_rd == id_rs2))
    );

    // ---------- Forwarding ----------
    forwarding_unit fwd(
        .idex_rs1(idex_rs1), .idex_rs2(idex_rs2),
        .exmem_rd(exmem_rd), .exmem_regwrite(exmem_regwrite & exmem_valid),
        .memwb_rd(memwb_rd), .memwb_regwrite(memwb_regwrite & memwb_valid),
        .fwd_a(fwd_a_sel), .fwd_b(fwd_b_sel)
    );

    // select forwarded operands
    assign ex_op_a = (fwd_a_sel==2'd0) ? idex_r1 :
                     (fwd_a_sel==2'd1) ? exmem_alu_y :
                     (fwd_a_sel==2'd2) ? ((memwb_wb_sel==2'd0)?memwb_alu_y:(memwb_wb_sel==2'd1?memwb_mem_rdata:memwb_pc_plus4)) :
                     idex_r1;

    assign ex_op_b_raw = (fwd_b_sel==2'd0) ? idex_r2 :
                         (fwd_b_sel==2'd1) ? exmem_alu_y :
                         (fwd_b_sel==2'd2) ? ((memwb_wb_sel==2'd0)?memwb_alu_y:(memwb_wb_sel==2'd1?memwb_mem_rdata:memwb_pc_plus4)) :
                         idex_r2;

    assign ex_alu_b = idex_alusrc ? idex_imm : ex_op_b_raw;

    alu alu0(
        .op(idex_aluop), .a(ex_op_a), .b(ex_alu_b), .y(ex_alu_y)
    );

    // Branch unit
    branch_unit bru(
        .funct3(idex_funct3), .rs1(ex_op_a), .rs2(ex_op_b_raw),
        .taken(ex_br_taken)
    );

    assign take_branch_ex   = (idex_is_branch & ex_br_taken) | idex_is_jal | idex_is_jalr;
    assign branch_target_ex = idex_is_jalr ? (ex_op_a + idex_imm) & ~32'd1 : // JALR target (clear LSB)
                              idex_is_jal  ? (idex_pc + idex_imm) :
                              idex_is_branch ? (idex_pc + idex_imm) : 32'b0;

    // ---------- Data memory interface ----------
    // Form write strobes and data according to size in funct3
    wire [3:0] store_be;
    wire [31:0] store_wdata;
    store_align salign(
        .addr(exmem_alu_y[1:0]), .funct3(exmem_funct3), .rs2(exmem_store_data),
        .be(store_be), .wdata(store_wdata)
    );

    assign dmem_req   = exmem_valid & (exmem_memread | exmem_memwrite);
    assign dmem_we    = exmem_memwrite;
    assign dmem_be    = store_be;
    assign dmem_addr  = exmem_alu_y;
    assign dmem_wdata = store_wdata;

    // Load data alignment / sign extend
    wire [31:0] load_data_aligned;
    load_align lalign(
        .addr(exmem_alu_y[1:0]), .funct3(exmem_funct3), .rdata(dmem_rdata),
        .y(load_data_aligned)
    );

    // ---------- Pipeline control (stalls/flushes) ----------
    wire if_stall  = load_use_hazard; // hold IF when hazard
    wire id_stall  = load_use_hazard; // hold ID when hazard
    wire id_flush  = take_branch_ex;  // flush ID on taken branch/jump
    wire ex_flush  = take_branch_ex;  // flush EX control when redirecting

    // ---------- Sequential logic ----------
    always @(posedge clk) begin
        if (rst) begin
            pc_if      <= 32'h0000_0000;
            ifid_pc    <= 32'b0;
            ifid_instr <= 32'b0;
            ifid_valid <= 1'b0;

            // Clear pipeline regs
            idex_pc        <= 32'b0; idex_r1 <= 32'b0; idex_r2 <= 32'b0; idex_imm <= 32'b0;
            idex_rs1       <= 5'b0;  idex_rs2<= 5'b0;  idex_rd  <= 5'b0; idex_funct3 <= 3'b0;
            idex_aluop     <= 4'b0;  idex_alusrc <= 1'b0;
            idex_is_branch <= 1'b0;  idex_is_jal <= 1'b0; idex_is_jalr <= 1'b0;
            idex_memread   <= 1'b0;  idex_memwrite <= 1'b0; idex_regwrite <= 1'b0; idex_wb_sel <= 2'b0;
            idex_valid     <= 1'b0;

            exmem_alu_y    <= 32'b0; exmem_store_data <= 32'b0; exmem_pc_plus4 <= 32'b0;
            exmem_rd       <= 5'b0; exmem_funct3 <= 3'b0;
            exmem_memread  <= 1'b0; exmem_memwrite <= 1'b0; exmem_regwrite <= 1'b0; exmem_wb_sel <= 2'b0;
            exmem_valid    <= 1'b0;

            memwb_alu_y    <= 32'b0; memwb_mem_rdata <= 32'b0; memwb_pc_plus4 <= 32'b0;
            memwb_rd       <= 5'b0; memwb_regwrite <= 1'b0; memwb_wb_sel <= 2'b0; memwb_valid <= 1'b0;
        end else begin
            // PC update
            if (!if_stall) begin
                pc_if <= pc_next;
            end

            // IF/ID register update
            if (id_flush) begin
                ifid_valid <= 1'b0; // bubble
                ifid_pc    <= 32'b0;
                ifid_instr <= 32'b0;
            end else if (!id_stall) begin
                ifid_valid <= imem_rvalid;
                ifid_pc    <= pc_if;     // PC of fetched instruction
                ifid_instr <= imem_rdata;
            end

            // ID/EX register update
            if (ex_flush) begin
                idex_valid     <= 1'b0;
                idex_pc        <= 32'b0;
                idex_r1        <= 32'b0;
                idex_r2        <= 32'b0;
                idex_imm       <= 32'b0;
                idex_rs1       <= 5'b0; idex_rs2 <= 5'b0; idex_rd <= 5'b0;
                idex_funct3    <= 3'b0; idex_aluop <= 4'b0; idex_alusrc <= 1'b0;
                idex_is_branch <= 1'b0; idex_is_jal <= 1'b0; idex_is_jalr <= 1'b0;
                idex_memread   <= 1'b0; idex_memwrite <= 1'b0; idex_regwrite <= 1'b0; idex_wb_sel <= 2'b0;
            end else begin
                if (load_use_hazard) begin
                    // insert bubble by zeroing control while holding IF/ID (done above)
                    idex_valid     <= 1'b0;
                    idex_pc        <= 32'b0;
                    idex_r1        <= 32'b0;
                    idex_r2        <= 32'b0;
                    idex_imm       <= 32'b0;
                    idex_rs1       <= 5'b0; idex_rs2 <= 5'b0; idex_rd <= 5'b0;
                    idex_funct3    <= 3'b0; idex_aluop <= 4'b0; idex_alusrc <= 1'b0;
                    idex_is_branch <= 1'b0; idex_is_jal <= 1'b0; idex_is_jalr <= 1'b0;
                    idex_memread   <= 1'b0; idex_memwrite <= 1'b0; idex_regwrite <= 1'b0; idex_wb_sel <= 2'b0;
                end else begin
                    idex_valid     <= ifid_valid;
                    idex_pc        <= ifid_pc;
                    idex_r1        <= id_rdata1;
                    idex_r2        <= id_rdata2;
                    idex_imm       <= id_imm;
                    idex_rs1       <= id_rs1; idex_rs2 <= id_rs2; idex_rd <= id_rd;
                    idex_funct3    <= id_funct3;
                    idex_aluop     <= id_aluop;
                    idex_alusrc    <= id_alusrc;
                    idex_is_branch <= id_is_branch; idex_is_jal <= id_is_jal; idex_is_jalr <= id_is_jalr;
                    idex_memread   <= id_memread; idex_memwrite <= id_memwrite;
                    idex_regwrite  <= id_regwrite; idex_wb_sel <= id_wb_sel;
                end
            end

            // EX/MEM register update
            exmem_valid     <= idex_valid;
            exmem_alu_y     <= ex_alu_y;
            exmem_store_data<= ex_op_b_raw;
            exmem_pc_plus4  <= ex_pc_plus4;
            exmem_rd        <= idex_rd;
            exmem_funct3    <= idex_funct3;
            exmem_memread   <= idex_memread;
            exmem_memwrite  <= idex_memwrite;
            exmem_regwrite  <= idex_regwrite;
            exmem_wb_sel    <= idex_wb_sel;

            // MEM/WB register update
            memwb_valid     <= exmem_valid;
            memwb_alu_y     <= exmem_alu_y;
            memwb_pc_plus4  <= exmem_pc_plus4;
            memwb_rd        <= exmem_rd;
            memwb_regwrite  <= exmem_regwrite;
            memwb_wb_sel    <= exmem_wb_sel;

            // capture memory read data when valid
            if (dmem_rvalid) begin
                memwb_mem_rdata <= load_data_aligned;
            end
        end
    end

endmodule

// ===================== Register File =====================
module regfile (
    input              clk,
    input      [4:0]   rs1,
    input      [4:0]   rs2,
    input      [4:0]   rd,
    input              rd_we,
    input      [31:0]  rd_wdata,
    output     [31:0]  rs1_rdata,
    output     [31:0]  rs2_rdata
);
    reg [31:0] regs[31:0];

    // read (combinational)
    assign rs1_rdata = (rs1 == 5'd0) ? 32'b0 : regs[rs1];
    assign rs2_rdata = (rs2 == 5'd0) ? 32'b0 : regs[rs2];

    // write (x0 is hardwired to 0)
    always @(posedge clk) begin
        if (rd_we && (rd != 5'd0)) regs[rd] <= rd_wdata;
        regs[0] <= 32'b0;
    end
endmodule

// ===================== Immediate Generator =====================
module immgen(
    input  [31:0] instr,
    output [31:0] imm
);
    wire [6:0] opcode = instr[6:0];
    wire [31:0] I = {{21{instr[31]}}, instr[30:20]};
    wire [31:0] S = {{21{instr[31]}}, instr[30:25], instr[11:7]};
    wire [31:0] B = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] U = {instr[31:12], 12'b0};
    wire [31:0] J = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

    assign imm = (opcode==7'b0010011 /*I-type ALU*/ || opcode==7'b0000011 /*LOAD*/ || opcode==7'b1100111 /*JALR*/)
                 ? I :
                 (opcode==7'b0100011 /*STORE*/) ? S :
                 (opcode==7'b1100011 /*BRANCH*/) ? B :
                 (opcode==7'b0110111 /*LUI*/ || opcode==7'b0010111 /*AUIPC*/) ? U :
                 (opcode==7'b1101111 /*JAL*/) ? J : 32'b0;
endmodule

// ===================== Control Unit =====================
module control(
    input  [6:0] opcode,
    input  [2:0] funct3,
    input  [6:0] funct7,
    output       use_rs1,
    output       use_rs2,
    output       is_branch,
    output       is_jal,
    output       is_jalr,
    output       memread,
    output       memwrite,
    output       regwrite,
    output [3:0] aluop,
    output       alusrc,
    output [1:0] wb_sel
);
    // defaults
    reg r_use_rs1, r_use_rs2, r_branch, r_jal, r_jalr, r_memread, r_memwrite, r_regwrite, r_alusrc;
    reg [3:0] r_aluop;
    reg [1:0] r_wbsel;

    always @(*) begin
        r_use_rs1=0; r_use_rs2=0; r_branch=0; r_jal=0; r_jalr=0; r_memread=0; r_memwrite=0; r_regwrite=0; r_alusrc=0; r_aluop=4'h0; r_wbsel=2'd0;
        case (opcode)
            7'b0110011: begin // R-type
                r_use_rs1=1; r_use_rs2=1; r_regwrite=1; r_alusrc=0; r_wbsel=2'd0;
                case ({funct7[5],funct3})
                    4'b0000: r_aluop=4'h0; // ADD
                    4'b1000: r_aluop=4'h1; // SUB
                    4'b0001: r_aluop=4'h2; // SLL
                    4'b0010: r_aluop=4'h3; // SLT
                    4'b0011: r_aluop=4'h4; // SLTU
                    4'b0100: r_aluop=4'h5; // XOR
                    4'b0101: r_aluop=4'h6; // SRL
                    4'b1101: r_aluop=4'h7; // SRA
                    4'b0110: r_aluop=4'h8; // OR
                    4'b0111: r_aluop=4'h9; // AND
                    default: r_aluop=4'h0;
                endcase
            end
            7'b0010011: begin // I-type ALU
                r_use_rs1=1; r_use_rs2=0; r_regwrite=1; r_alusrc=1; r_wbsel=2'd0;
                case (funct3)
                    3'b000: r_aluop=4'h0; // ADDI
                    3'b010: r_aluop=4'h3; // SLTI
                    3'b011: r_aluop=4'h4; // SLTIU
                    3'b100: r_aluop=4'h5; // XORI
                    3'b110: r_aluop=4'h8; // ORI
                    3'b111: r_aluop=4'h9; // ANDI
                    3'b001: r_aluop=4'h2; // SLLI
                    3'b101: r_aluop=(funct7[5]?4'h7:4'h6); // SRAI/SRLI
                    default: r_aluop=4'h0;
                endcase
            end
            7'b0000011: begin // LOAD
                r_use_rs1=1; r_regwrite=1; r_alusrc=1; r_memread=1; r_wbsel=2'd1; r_aluop=4'h0; // address = rs1 + imm
            end
            7'b0100011: begin // STORE
                r_use_rs1=1; r_use_rs2=1; r_alusrc=1; r_memwrite=1; r_aluop=4'h0;
            end
            7'b1100011: begin // BRANCH
                r_use_rs1=1; r_use_rs2=1; r_branch=1; r_aluop=4'h1; // use SUB for comparison baseline
            end
            7'b1101111: begin // JAL
                r_jal=1; r_regwrite=1; r_wbsel=2'd2;
            end
            7'b1100111: begin // JALR
                r_use_rs1=1; r_jalr=1; r_regwrite=1; r_wbsel=2'd2; r_alusrc=1; // target computed in EX
            end
            7'b0110111: begin // LUI
                r_regwrite=1; r_wbsel=2'd0; r_aluop=4'hA; r_alusrc=1; // ALU passes B
            end
            7'b0010111: begin // AUIPC
                r_regwrite=1; r_wbsel=2'd0; r_aluop=4'hB; r_alusrc=1; // ALU A=PC, B=imm
            end
            default: begin end
        endcase
    end

    assign use_rs1   = r_use_rs1;
    assign use_rs2   = r_use_rs2;
    assign is_branch = r_branch;
    assign is_jal    = r_jal;
    assign is_jalr   = r_jalr;
    assign memread   = r_memread;
    assign memwrite  = r_memwrite;
    assign regwrite  = r_regwrite;
    assign aluop     = r_aluop;
    assign alusrc    = r_alusrc;
    assign wb_sel    = r_wbsel;
endmodule

// ===================== ALU =====================
module alu(
    input  [3:0]  op,
    input  [31:0] a,
    input  [31:0] b,
    output [31:0] y
);
    reg [31:0] r;
    always @(*) begin
        case (op)
            4'h0: r = a + b;                       // ADD/ADDI/addr
            4'h1: r = a - b;                       // SUB (used for compare baseline)
            4'h2: r = a << b[4:0];                 // SLL/SLLI
            4'h3: r = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT/SLTI
            4'h4: r = (a < b) ? 32'd1 : 32'd0;     // SLTU/SLTIU
            4'h5: r = a ^ b;                       // XOR/XORI
            4'h6: r = a >> b[4:0];                 // SRL/SRLI
            4'h7: r = $signed(a) >>> b[4:0];       // SRA/SRAI
            4'h8: r = a | b;                       // OR/ORI
            4'h9: r = a & b;                       // AND/ANDI
            4'hA: r = b;                           // LUI pass-through
            4'hB: r = a + b;                       // AUIPC (A=PC)
            default: r = 32'b0;
        endcase
    end
    assign y = r;
endmodule

// ===================== Branch Unit =====================
module branch_unit(
    input  [2:0]  funct3,
    input  [31:0] rs1,
    input  [31:0] rs2,
    output        taken
);
    reg t;
    always @(*) begin
        case (funct3)
            3'b000: t = (rs1 == rs2);                    // BEQ
            3'b001: t = (rs1 != rs2);                    // BNE
            3'b100: t = ($signed(rs1) < $signed(rs2));   // BLT
            3'b101: t = !($signed(rs1) < $signed(rs2));  // BGE
            3'b110: t = (rs1 < rs2);                     // BLTU
            3'b111: t = !(rs1 < rs2);                    // BGEU
            default: t = 1'b0;
        endcase
    end
    assign taken = t;
endmodule

// ===================== Forwarding Unit =====================
module forwarding_unit(
    input  [4:0] idex_rs1,
    input  [4:0] idex_rs2,
    input  [4:0] exmem_rd,
    input        exmem_regwrite,
    input  [4:0] memwb_rd,
    input        memwb_regwrite,
    output [1:0] fwd_a,
    output [1:0] fwd_b
);
    reg [1:0] a,b;
    always @(*) begin
        // defaults (00: use ID/EX)
        a=2'd0; b=2'd0;
        // EX hazard
        if (exmem_regwrite && (exmem_rd!=5'd0) && (exmem_rd==idex_rs1)) a=2'd1;
        if (exmem_regwrite && (exmem_rd!=5'd0) && (exmem_rd==idex_rs2)) b=2'd1;
        // MEM hazard
        if (memwb_regwrite && (memwb_rd!=5'd0) && (memwb_rd==idex_rs1) && !(exmem_regwrite && (exmem_rd!=5'd0) && (exmem_rd==idex_rs1))) a=2'd2;
        if (memwb_regwrite && (memwb_rd!=5'd0) && (memwb_rd==idex_rs2) && !(exmem_regwrite && (exmem_rd!=5'd0) && (exmem_rd==idex_rs2))) b=2'd2;
    end
    assign fwd_a=a; assign fwd_b=b;
endmodule

// ===================== Store data aligner =====================
module store_align(
    input  [1:0]  addr,
    input  [2:0]  funct3,
    input  [31:0] rs2,
    output [3:0]  be,
    output [31:0] wdata
);
    reg [3:0]  r_be;
    reg [31:0] r_wdata;
    always @(*) begin
        case (funct3)
            3'b000: begin // SB
                case (addr)
                    2'b00: begin r_be=4'b0001; r_wdata={24'b0, rs2[7:0]}; end
                    2'b01: begin r_be=4'b0010; r_wdata={16'b0, rs2[7:0], 8'b0}; end
                    2'b10: begin r_be=4'b0100; r_wdata={8'b0, rs2[7:0], 16'b0}; end
                    default:begin r_be=4'b1000; r_wdata={rs2[7:0], 24'b0}; end
                endcase
            end
            3'b001: begin // SH
                if (addr[1]==1'b0) begin
                    r_be = 4'b0011; r_wdata = {16'b0, rs2[15:0]};
                end else begin
                    r_be = 4'b1100; r_wdata = {rs2[15:0], 16'b0};
                end
            end
            default: begin // SW
                r_be   = 4'b1111; r_wdata = rs2;
            end
        endcase
    end
    assign be = r_be; assign wdata = r_wdata;
endmodule

// ===================== Load data aligner =====================
module load_align(
    input  [1:0]  addr,
    input  [2:0]  funct3,
    input  [31:0] rdata,
    output [31:0] y
);
    reg [31:0] r;
    wire [7:0]  byte0 = rdata[7:0];
    wire [7:0]  byte1 = rdata[15:8];
    wire [7:0]  byte2 = rdata[23:16];
    wire [7:0]  byte3 = rdata[31:24];

    wire [15:0] half_lo = rdata[15:0];
    wire [15:0] half_hi = rdata[31:16];

    always @(*) begin
        case (funct3)
            3'b000: begin // LB
                case (addr)
                    2'b00: r = {{24{byte0[7]}}, byte0};
                    2'b01: r = {{24{byte1[7]}}, byte1};
                    2'b10: r = {{24{byte2[7]}}, byte2};
                    default: r = {{24{byte3[7]}}, byte3};
                endcase
            end
            3'b100: begin // LBU
                case (addr)
                    2'b00: r = {24'b0, byte0};
                    2'b01: r = {24'b0, byte1};
                    2'b10: r = {24'b0, byte2};
                    default: r = {24'b0, byte3};
                endcase
            end
            3'b001: begin // LH
                if (addr[1]==1'b0) r = {{16{half_lo[15]}}, half_lo};
                else               r = {{16{half_hi[15]}}, half_hi};
            end
            3'b101: begin // LHU
                if (addr[1]==1'b0) r = {16'b0, half_lo};
                else               r = {16'b0, half_hi};
            end
            default: begin // LW
                r = rdata;
            end
        endcase
    end
    assign y = r;
endmodule

// ===================== Simple test memory (optional) =====================
// This is a simple behavioral memory implementing both instruction and data
// ports. Useful for simulation-only bring up.
module simple_dualport_mem #(
    parameter MEM_BYTES = 4096
)(
    input         clk,
    input         rst,
    // instruction
    input         imem_req,
    input  [31:0] imem_addr,
    output reg    imem_rvalid,
    output [31:0] imem_rdata,
    // data
    input         dmem_req,
    input         dmem_we,
    input  [3:0]  dmem_be,
    input  [31:0] dmem_addr,
    input  [31:0] dmem_wdata,
    output        dmem_ready,
    output reg    dmem_rvalid,
    output [31:0] dmem_rdata
);
    reg [7:0] mem[0:MEM_BYTES-1];

    // Ready is always 1 in this simple model
    assign dmem_ready = 1'b1;

    // Instruction fetch (1-cycle latency)
    wire [31:0] iaddr = imem_addr;
    assign imem_rdata = {mem[iaddr+3], mem[iaddr+2], mem[iaddr+1], mem[iaddr+0]};

    // Data read (1-cycle latency)
    wire [31:0] daddr = dmem_addr;
    assign dmem_rdata = {mem[daddr+3], mem[daddr+2], mem[daddr+1], mem[daddr+0]};

    integer k;
    always @(posedge clk) begin
        if (rst) begin
            imem_rvalid <= 1'b0; dmem_rvalid <= 1'b0;
            // Optional: init memory to 0
            for (k=0; k<MEM_BYTES; k=k+1) mem[k] <= 8'h00;
        end else begin
            // reads are 1-cycle delayed valid
            imem_rvalid <= imem_req;
            dmem_rvalid <= dmem_req & ~dmem_we; // valid for loads

            // writes
            if (dmem_req && dmem_we) begin
                if (dmem_be[0]) mem[daddr+0] <= dmem_wdata[7:0];
                if (dmem_be[1]) mem[daddr+1] <= dmem_wdata[15:8];
                if (dmem_be[2]) mem[daddr+2] <= dmem_wdata[23:16];
                if (dmem_be[3]) mem[daddr+3] <= dmem_wdata[31:24];
            end
        end
    end
endmodule

// ===================== Example SoC wrapper (for quick sim) =====================
module rv32i_soc_example(
    input clk,
    input rst
);
    wire imem_req, imem_rvalid; wire [31:0] imem_addr, imem_rdata;
    wire dmem_req, dmem_we, dmem_ready, dmem_rvalid; wire [3:0] dmem_be; wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;

    rv32i_core core(
        .clk(clk), .rst(rst),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rvalid(imem_rvalid), .imem_rdata(imem_rdata),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_ready(dmem_ready), .dmem_rvalid(dmem_rvalid), .dmem_rdata(dmem_rdata)
    );

    simple_dualport_mem #(.MEM_BYTES(16384)) mem(
        .clk(clk), .rst(rst),
        .imem_req(imem_req), .imem_addr(imem_addr), .imem_rvalid(imem_rvalid), .imem_rdata(imem_rdata),
        .dmem_req(dmem_req), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_ready(dmem_ready), .dmem_rvalid(dmem_rvalid), .dmem_rdata(dmem_rdata)
    );
endmodule


