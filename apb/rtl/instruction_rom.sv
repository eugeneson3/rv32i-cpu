//`define SIMULATION_TEST

module instruction_rom (
    input  logic [8:0]  instr_addr,
    output logic [31:0] instr_code
);
    logic [31:0] instr_rom [0:127];
    integer i;

    initial begin 
        for (i = 0; i < 128; i = i + 1) instr_rom[i] = 32'h0000_0013; // NOP (addi x0, x0, 0)
        $readmemh("rom_code_2.mem", instr_rom);
    end

    // least 2 bits are always 0 for RV32I; like 0,4,8,...
    assign instr_code = instr_rom[instr_addr[8:2]]; 
    
endmodule
