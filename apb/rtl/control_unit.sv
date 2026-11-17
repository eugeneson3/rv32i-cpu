import rv32_pkg::*;

module control_unit (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_code,
    input  logic        bus_ready,
    output logic        ir_write, // save instruction to register when enabled(IR)
    output logic        pc_en, // move PC to next when enabled
    output logic        rf_we,
    output logic        alusrc_sel,
    output logic [ 2:0] rf_srcsel,
    output logic [ 3:0] alu_control,
    output logic        bus_we,
    output logic        transfer,
    output logic        branch,
    output logic [ 2:0] itype,
    output logic        reg_en,
    output logic        alu_out_en,
    output logic        jump
);
    logic [2:0] funct3;

    opcode_e opcode;
    assign opcode = opcode_e'(instr_code[6:0]);

    assign funct3 = instr_code[14:12];
    assign itype  = funct3; // Memory access width (sb, sh, sw)

    // 1. FSM state definitions
    typedef enum logic [2:0] {
        S_FETCH,    // IF: Fetch instruction & PC <= PC + 4
        S_DECODE,   // ID: Decode instruction & fetch operands
        S_EXEC,     // EX: ALU operation or address generation
        S_MEM,      // MEM: Data memory access (Load/Store)
        S_WB        // WB: Register writeback
    } state_e;

    state_e state, next_state;

    // 2. State register
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= S_FETCH;
        else        state <= next_state;
    end

    // 3. Next state & output combinational logic
    always_comb begin
        // Default inactive outputs to prevent latches
        ir_write    = 1'b0;
        pc_en       = 1'b0;
        rf_we       = 1'b0;
        alusrc_sel  = 1'b0;
        rf_srcsel   = 3'b000;
        bus_we      = 1'b0;
        transfer    = 1'b0;
        alu_control = 4'b0000;
        branch      = 1'b0;
        reg_en      = 1'b0;
        alu_out_en  = 1'b0;
        jump        = 1'b0;
        next_state  = S_FETCH;

        case (state)
            // [1] FETCH: Latch IR and increment PC
            S_FETCH: begin
                ir_write   = 1'b1;     // latch instructions only in fetch state
                pc_en      = 1'b1;     // move PC to next when enabled
                next_state = S_DECODE;
            end

            // [2] DECODE: Determine next state based on opcode
            S_DECODE: begin
                reg_en = 1'b1;         // Latch rd1_reg and rd2_reg
                case (opcode)
                    OP_RTYPE, OP_ITYPE, OP_ILTYPE, OP_STYPE: next_state = S_EXEC;
                    OP_BTYPE:                                next_state = S_EXEC;
                    OP_JAL, OP_JALR:                         next_state = S_EXEC;
                    OP_LUI, OP_AUIPC:                        next_state = S_WB; // Direct writeback without ALU
                    default:                                 next_state = S_FETCH;
                endcase
            end

            // [3] EXEC: Execute ALU op, address calc, or branch
            S_EXEC: begin
                alu_out_en = 1'b1;     // Latch ALU result into alu_out_reg
                case (opcode)
                    // R-type: A op B
                    OP_RTYPE: begin
                        alusrc_sel  = 1'b0; // Select register B
                        alu_control = {instr_code[30], funct3};
                        next_state  = S_WB; // Proceed to WB
                    end

                    // I-type: A op imm
                    OP_ITYPE: begin
                        alusrc_sel  = 1'b1; // Select immediate
                        if (funct3 == 3'b101)
                            alu_control = {instr_code[30], funct3}; // SRAI, SRLI
                        else
                            alu_control = {1'b0, funct3};           // ADDI, ANDI, ORI, etc.
                        next_state  = S_WB; // Proceed to WB
                    end

                    // Load/Store: Calculate effective address (A + offset)
                    OP_ILTYPE, OP_STYPE: begin
                        alusrc_sel  = 1'b1;    // Select offset
                        alu_control = 4'b0000; // ADD for address
                        next_state  = S_MEM;   // Proceed to MEM
                    end

                    // Branch: Evaluate condition
                    OP_BTYPE: begin
                        branch     = 1'b1;
                        next_state = S_FETCH;  // Branch resolved, fetch next
                    end

                    // JAL/JALR: Jump to target PC
                    OP_JAL, OP_JALR: begin
                        jump       = 1'b1;     // pc_sel = 1 only in EXEC of jump
                        pc_en      = 1'b1;     // Update PC with jump target
                        next_state = S_WB;     // Proceed to WB to link PC+4
                    end

                    default: next_state = S_FETCH;
                endcase
            end

            // [4] MEM: Data memory access (Load/Store)
            S_MEM: begin
                bus_we   = (opcode == OP_STYPE) ? 1'b1 : 1'b0;
                transfer = 1'b1;
                if (bus_ready) begin
                    if (opcode == OP_ILTYPE) begin
                        next_state = S_WB;
                    end else begin
                        next_state = S_FETCH;
                    end
                end else begin
                    next_state = S_MEM; // APB 전송 완료(bus_ready=1)될 때까지 대기
                end
            end

            // [5] WB: Write result back to register file
            S_WB: begin
                rf_we = 1'b1; // Register write enable only in WB
                case (opcode)
                    OP_RTYPE, OP_ITYPE: rf_srcsel = 3'b000; // ALU result
                    OP_ILTYPE:          rf_srcsel = 3'b001; // Memory read data (MDR)
                    OP_LUI:             rf_srcsel = 3'b010; // Imm
                    OP_AUIPC:           rf_srcsel = 3'b011; // PC + Imm
                    OP_JAL, OP_JALR:    rf_srcsel = 3'b100; // Return address (PC+4)
                    default:            rf_srcsel = 3'b000;
                endcase
                next_state = S_FETCH; // Instruction completed, fetch next
            end

            default: next_state = S_FETCH;
        endcase
    end

endmodule
