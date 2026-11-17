module tb_rv32i_cpu;
    logic clk = 1'b0, reset = 1'b1;
    logic [15:0] sw = 16'h00A5;
    logic [15:0] led;

    always #5 clk = ~clk;
    rv32i_top dut (
        .clk  (clk),
        .reset(reset),
        .sw   (sw),
        .led  (led)
    );

    always @(posedge clk) begin
        if (!reset) begin
            $display("[Time %0t ns] State: %-8s | PC: 0x%08h | IR: 0x%08h | LED: 0x%04h | BusAddr: 0x%08h | BusRdy: %b | X1: 0x%08h | X3: 0x%08h | X4: 0x%08h | X5: 0x%08h", 
                     $time, 
                     dut.U_RV32I_CPU.U_CONTROL_UNIT.state.name(),
                     dut.U_RV32I_CPU.U_DATAPATH.pc,
                     dut.U_RV32I_CPU.U_DATAPATH.ir_reg,
                     led,
                     dut.bus_addr,
                     dut.bus_ready,
                     dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.ram_file[1],
                     dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.ram_file[3],
                     dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.ram_file[4],
                     dut.U_RV32I_CPU.U_DATAPATH.U_REG_FILE.ram_file[5]);
        end
    end

    initial begin
        reset = 1'b1;
        #20;
        @(negedge clk);
        reset = 1'b0;
        #3000;
        $finish;
    end

endmodule
