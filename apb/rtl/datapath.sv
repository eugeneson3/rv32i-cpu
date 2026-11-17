//`define SIMULATION

import rv32_pkg::*;

module datapath (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rf_we,
    input  logic        alusrc_sel,
    input  logic [ 2:0] rf_srcsel,
    input  logic [ 3:0] alu_control,
    input  logic [31:0] instr_code,
    input  logic [31:0] bus_rdata,
    input  logic        branch,
    input  logic        ir_write,
    input  logic        pc_en,
    input  logic        bus_ready,
    input  logic        reg_en,
    input  logic        alu_out_en,
    input  logic        jump,
    output logic [ 8:0] instr_addr,
    output logic [31:0] instr_ir,
    output logic [31:0] bus_addr,
    output logic [31:0] bus_wdata
);
    // Internal Datapath Registers (Multi-Cycle pipeline stages)
    logic [31:0] ir_reg;      // Instruction Register (latched at FETCH)
    logic [31:0] pc_reg;      // Original instruction PC (latched at FETCH)
    logic [31:0] rd1_reg;     // Operand A register (latched at DECODE)
    logic [31:0] rd2_reg;     // Operand B register (latched at DECODE)
    logic [31:0] alu_out_reg; // ALU output register (latched at EXEC)
    logic [31:0] mdr_reg;     // Memory Data Register (latched at MEM)

    logic [31:0] alu_result, rf_rd1, rf_rd2;
    logic [31:0] imm_ext, alusrc_muxout, rf_wd;
    logic [31:0] pc;
    logic [31:0] pc_target; // Target address for Branch, JAL, JALR, AUIPC

    opcode_e opcode;
    assign opcode = opcode_e'(ir_reg[6:0]);

    assign instr_addr = pc[8:0];
    assign instr_ir   = ir_reg;      // Latched instruction for control_unit
    assign bus_addr   = alu_out_reg; // Stable memory address from ALUOut register
    assign bus_wdata  = rd2_reg;     // Stable store data from rd2 register

    logic b_cond;
    logic pc_sel;

    // 1. Instruction register & Old PC register (saved on fetch)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin         
            ir_reg <= 32'd0; 
            pc_reg <= 32'd0;
        end else if (ir_write) begin 
            ir_reg <= instr_code;
            pc_reg <= pc;
        end
    end

    // Target PC base selection: JALR uses rd1_reg, others use original instruction PC ()
    logic [31:0] jump_base;
    assign jump_base = (opcode == OP_JALR) ? rd1_reg : pc_reg;
    assign pc_target = jump_base + imm_ext;

    // 2. rd1, rd2 register (latched at DECODE)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd1_reg <= 32'd0;
            rd2_reg <= 32'd0;
        end else if (reg_en) begin
            rd1_reg <= rf_rd1;
            rd2_reg <= rf_rd2;
        end
    end

    // 3. ALUOut register (latched at EXEC)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)          alu_out_reg <= 32'd0;
        else if (alu_out_en) alu_out_reg <= alu_result;
    end

    // Memory data register - latched only at bus_ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mdr_reg <= 32'd0;
        else if (bus_ready) mdr_reg <= bus_rdata;
    end


    // Branch condition evaluation
    always_comb begin
        case (ir_reg[14:12]) // funct3
            3'b000:  b_cond = (rd1_reg == rd2_reg);                   // BEQ
            3'b001:  b_cond = (rd1_reg != rd2_reg);                   // BNE
            3'b100:  b_cond = ($signed(rd1_reg) < $signed(rd2_reg));  // BLT
            3'b101:  b_cond = ($signed(rd1_reg) >= $signed(rd2_reg)); // BGE
            3'b110:  b_cond = (rd1_reg < rd2_reg);                    // BLTU
            3'b111:  b_cond = (rd1_reg >= rd2_reg);                   // BGEU
            default: b_cond = 1'b0;
        endcase
    end

    // Jump / Branch target selection: take target PC if condition met or unconditional jump
    assign pc_sel = (branch & b_cond) | jump;

    // 1. Register File (uses instruction fields latched in ir_reg)
    reg_file U_REG_FILE (
        .clk  (clk),
        .rst_n(rst_n),
        .ra1  (ir_reg[19:15]),
        .ra2  (ir_reg[24:20]),
        .wa   (ir_reg[11:7]),
        .wd   (rf_wd),
        .we   (rf_we),
        .rd1  (rf_rd1),
        .rd2  (rf_rd2)
    );

    // 2. Immediate Extender (decodes immediate from ir_reg)
    imm_ext U_IMM_EXT (
        .instr_code(ir_reg),
        .imm_ext   (imm_ext)
    );

    // 3. ALU Input B selection (0: rd2_reg, 1: imm_ext)
    assign alusrc_muxout = alusrc_sel ? imm_ext : rd2_reg;

    // 4. Arithmetic Logic Unit (ALU)
    alu U_ALU (
        .a          (rd1_reg),
        .b          (alusrc_muxout),
        .alu_control(alu_control),
        .alu_result (alu_result)
    );

    // 5. Register File Write Data MUX (rf_srcsel)
    always_comb begin
        case (rf_srcsel)
            3'b000:  rf_wd = alu_out_reg;       // 0: ALU result (latched in alu_out_reg)
            3'b001:  rf_wd = mdr_reg;           // 1: Memory read data (latched in mdr_reg)
            3'b010:  rf_wd = imm_ext;           // 2: LUI (Immediate)
            3'b011:  rf_wd = pc_target;         // 3: AUIPC (pc_reg + imm)
            3'b100:  rf_wd = pc_reg + 32'd4;    // 4: JAL / JALR return address ( + 4)
            default: rf_wd = alu_out_reg;
        endcase
    end

    // final_pc_en: PC updates when:
    // 1) pc_en == 1 : FETCH stage (PC <= PC + 4) or JAL/JALR jump
    // 2) branch & b_cond : Branch condition is satisfied -> overwrite PC with target address
    logic final_pc_en;
    assign final_pc_en = pc_en | (branch & b_cond);

    // 6. Program Counter (PC)
    program_counter U_PC (
        .clk      (clk),
        .rst_n    (rst_n),
        .pc_en    (final_pc_en),
        .pc_sel   (pc_sel),
        .pc_target(pc_target),
        .pc       (pc)
    );

endmodule

// ================================================================
// Submodules
// ================================================================

// Immediate Extender for I, S, B, U, J types
module imm_ext (
    input  logic [31:0] instr_code,
    output logic [31:0] imm_ext
);
    opcode_e opcode;
    assign opcode = opcode_e'(instr_code[6:0]);

    always_comb begin
        case (opcode)
            OP_STYPE:
                imm_ext = {{20{instr_code[31]}}, instr_code[31:25], instr_code[11:7]};
            OP_ITYPE, OP_ILTYPE, OP_JALR:
                imm_ext = {{20{instr_code[31]}}, instr_code[31:20]};
            OP_BTYPE:
                imm_ext = {{20{instr_code[31]}}, instr_code[7], instr_code[30:25], instr_code[11:8], 1'b0};
            OP_LUI, OP_AUIPC:
                imm_ext = {instr_code[31:12], 12'd0};
            OP_JAL:
                imm_ext = {{12{instr_code[31]}}, instr_code[19:12], instr_code[20], instr_code[30:21], 1'b0};
            default:
                imm_ext = 32'd0;
        endcase
    end
endmodule

// Register File (32 x 32-bit registers, x0 is hardwired to 0)
module reg_file (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [ 4:0] ra1,
    input  logic [ 4:0] ra2,
    input  logic [ 4:0] wa,
    input  logic [31:0] wd,
    input  logic        we,
    output logic [31:0] rd1,
    output logic [31:0] rd2
);
    logic [31:0] ram_file[1:31];
    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
`ifdef SIMULATION
            for (i = 1; i < 32; i = i + 1) ram_file[i] <= i;
`else
            for (i = 1; i < 32; i = i + 1) ram_file[i] <= 32'd0;
`endif
        end else if (we && (wa != 0)) begin
            ram_file[wa] <= wd;
        end
    end

    assign rd1 = (ra1 != 0) ? ram_file[ra1] : 32'd0;
    assign rd2 = (ra2 != 0) ? ram_file[ra2] : 32'd0;
endmodule

// Arithmetic Logic Unit (ALU)
module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [ 3:0] alu_control,
    output logic [31:0] alu_result
);
    always_comb begin
        case (alu_control) // {funct7[5], funct3}
            4'b0_000: alu_result = a + b;                                // ADD
            4'b1_000: alu_result = a - b;                                // SUB
            4'b0_100: alu_result = a ^ b;                                // XOR
            4'b0_110: alu_result = a | b;                                // OR
            4'b0_111: alu_result = a & b;                                // AND
            4'b0_001: alu_result = a << b[4:0];                         // SLL
            4'b0_101: alu_result = a >> b[4:0];                         // SRL
            4'b1_101: alu_result = $signed(a) >>> b[4:0];               // SRA
            4'b0_010: alu_result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0; // SLT
            4'b0_011: alu_result = (a < b) ? 32'd1 : 32'd0;             // SLTU
            default:  alu_result = 32'd0;
        endcase
    end
endmodule

module program_counter (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        pc_en,
    input  logic        pc_sel,
    input  logic [31:0] pc_target,
    output logic [31:0] pc
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)            pc <= 32'd0;
        else if (pc_en) begin
            if (pc_sel)        pc <= pc_target;
            else               pc <= pc + 32'd4;
        end
    end
endmodule
