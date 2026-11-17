module rv32i_top (
    input  logic        clk,
    input  logic        reset,
    input  logic [15:0] sw,
    output logic [15:0] led
);
    // Active-low reset for internal CPU logic
    logic rst_n;
    assign rst_n = ~reset;

    // GPIO internal signals (unused on board headers)
    logic [15:0] gpio_in;
    logic [15:0] gpio_out;
    logic [15:0] gpio_oe;
    assign gpio_in = 16'h0000;

    // Rom signals
    logic [31:0] instr_code;
    logic [ 8:0] instr_addr;
    
    // CPU <-> APB Master signals
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic [31:0] bus_rdata;
    logic        bus_we;
    logic        bus_ready;
    logic        transfer;
    logic [ 2:0] itype;

    // APB bus signals (Master -> Slaves)
    logic [31:0] PAddr;
    logic [31:0] PWdata;
    logic        PWrite;
    logic        PEnable;
    logic [ 4:0] PSel;
    logic [ 4:0] PReady;
    logic [31:0] PRData [0:4];

    // FND value output (internal)
    logic [31:0] fnd_val;

    // 1. 명령어 메모리 (ROM)
    instruction_rom U_INSTR_ROM (
        .instr_addr(instr_addr),
        .instr_code(instr_code)
    );

    // 2. CPU 코어
    rv32i_cpu U_RV32I_CPU (
        .clk        (clk),
        .rst_n      (rst_n),
        .instr_code (instr_code),
        .instr_addr (instr_addr),
        .bus_rdata  (bus_rdata),
        .bus_ready  (bus_ready),
        .bus_addr   (bus_addr),
        .bus_wdata  (bus_wdata),
        .bus_we     (bus_we),
        .transfer   (transfer),
        .itype      (itype)
    );

    // 3. APB Master (버스 중재 및 주소 디코더)
    apb_master U_APB_MASTER (
        .clk        (clk),
        .rst_n      (rst_n),
        .bus_addr   (bus_addr),
        .bus_wdata  (bus_wdata),
        .bus_we     (bus_we),
        .transfer   (transfer),
        .bus_rdata  (bus_rdata),
        .bus_ready  (bus_ready),
        .PAddr      (PAddr),
        .PWdata     (PWdata),
        .PWrite     (PWrite),
        .PEnable    (PEnable),
        .PSel       (PSel),
        .PReady     (PReady),
        .PRData     (PRData)
    );

    // 4. APB Slave 0: 데이터 메모리 (RAM: 0x0000_0000 ~ 0x0FFF_FFFF)
    apb_bram U_APB_RAM (
        .clk        (clk),
        .itype      (itype),
        .PSEL       (PSel[0]),
        .PENABLE    (PEnable),
        .PADDR      (PAddr),
        .PWDATA     (PWdata),
        .PWRITE     (PWrite),
        .PREADY     (PReady[0]),
        .PRDATA     (PRData[0])
    );

    // 5. APB Slave 1: GPO - LED (0x1000_0000 ~ 0x1000_0FFF)
    apb_gpo U_APB_GPO (
        .clk        (clk),
        .rst_n      (rst_n),
        .PSEL       (PSel[1]),
        .PENABLE    (PEnable),
        .PADDR      (PAddr),
        .PWDATA     (PWdata),
        .PWRITE     (PWrite),
        .PREADY     (PReady[1]),
        .PRDATA     (PRData[1]),
        .out_port   (led)
    );

    // 6. APB Slave 2: GPI - 스위치 (0x1000_1000 ~ 0x1000_1FFF)
    apb_gpi U_APB_GPI (
        .clk        (clk),
        .rst_n      (rst_n),
        .PSEL       (PSel[2]),
        .PENABLE    (PEnable),
        .PADDR      (PAddr),
        .PWDATA     (PWdata),
        .PWRITE     (PWrite),
        .PREADY     (PReady[2]),
        .PRDATA     (PRData[2]),
        .in_port    (sw)
    );

    // 7. APB Slave 3: GPIO - 범용 입출력 (0x1000_2000 ~ 0x1000_2FFF)
    apb_gpio U_APB_GPIO (
        .clk        (clk),
        .rst_n      (rst_n),
        .PSEL       (PSel[3]),
        .PENABLE    (PEnable),
        .PADDR      (PAddr),
        .PWDATA     (PWdata),
        .PWRITE     (PWrite),
        .PREADY     (PReady[3]),
        .PRDATA     (PRData[3]),
        .gpio_in    (gpio_in),
        .gpio_out   (gpio_out),
        .gpio_oe    (gpio_oe)
    );

    // 8. APB Slave 4: FND - 7-Segment (0x1000_3000 ~ 0x1000_3FFF)
    apb_fnd U_APB_FND (
        .clk        (clk),
        .rst_n      (rst_n),
        .PSEL       (PSel[4]),
        .PENABLE    (PEnable),
        .PADDR      (PAddr),
        .PWDATA     (PWdata),
        .PWRITE     (PWrite),
        .PREADY     (PReady[4]),
        .PRDATA     (PRData[4]),
        .fnd_val    (fnd_val)
    );

endmodule

module rv32i_cpu (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_code,
    output logic [ 8:0] instr_addr,

    // APB bus Interface
    input  logic [31:0] bus_rdata,
    input  logic        bus_ready,
    output logic [31:0] bus_addr,
    output logic [31:0] bus_wdata,
    output logic        bus_we,
    output logic        transfer,
    output logic [ 2:0] itype
);
    logic        rf_we;
    logic        alusrc_sel;
    logic [ 2:0] rf_srcsel;
    logic [ 3:0] alu_control;
    logic        branch;
    logic        ir_write;
    logic        pc_en;
    logic [31:0] instr_ir;

    logic        reg_en;
    logic        alu_out_en;
    logic        jump;

    control_unit U_CONTROL_UNIT (
        .clk        (clk),
        .rst_n      (rst_n),
        .instr_code (instr_ir), // Decodes the latched instruction!
        .bus_ready  (bus_ready),
        .ir_write   (ir_write),
        .pc_en      (pc_en),
        .rf_we      (rf_we),
        .alusrc_sel (alusrc_sel),
        .rf_srcsel  (rf_srcsel),
        .alu_control(alu_control),
        .bus_we     (bus_we),
        .transfer   (transfer),
        .branch     (branch),
        .itype      (itype),
        .reg_en     (reg_en),
        .alu_out_en (alu_out_en),
        .jump       (jump)
    );

    datapath U_DATAPATH (
        .clk        (clk),
        .rst_n      (rst_n),
        .rf_we      (rf_we),
        .alusrc_sel (alusrc_sel),
        .rf_srcsel  (rf_srcsel),
        .alu_control(alu_control),
        .instr_code (instr_code), // Raw instruction from ROM to IR
        .bus_rdata  (bus_rdata),
        .branch     (branch),
        .ir_write   (ir_write),
        .pc_en      (pc_en),
        .bus_ready  (bus_ready),
        .reg_en     (reg_en),
        .alu_out_en (alu_out_en),
        .jump       (jump),
        .instr_addr (instr_addr),
        .instr_ir   (instr_ir),
        .bus_addr   (bus_addr),
        .bus_wdata  (bus_wdata)
    );

endmodule
