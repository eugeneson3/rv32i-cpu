// APB Peripheral Slaves: GPO, GPI, GPIO, FND
// Match address mapping in apb_master:
// Slave 1: GPO  (0x1000_0000 ~ 0x1000_0FFF) - LED output
// Slave 2: GPI  (0x1000_1000 ~ 0x1000_1FFF) - Switch input
// Slave 3: GPIO (0x1000_2000 ~ 0x1000_2FFF) - General Purpose IO (MODER, IDR, ODR)
// Slave 4: FND  (0x1000_3000 ~ 0x1000_3FFF) - 7-Segment Display

// 1. APB GPO (General Purpose Output - LED)
module apb_gpo (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic        PREADY,
    output logic [31:0] PRDATA,
    output logic [15:0] out_port
);
    logic [15:0] gpo_reg;

    assign PREADY   = PSEL & PENABLE;
    assign out_port = gpo_reg;
    assign PRDATA   = (PREADY && !PWRITE) ? {16'h0, gpo_reg} : 32'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpo_reg <= 16'h0000;
        end else if (PREADY && PWRITE) begin
            gpo_reg <= PWDATA[15:0];
        end
    end
endmodule

// 2. APB GPI (General Purpose Input - Switch)
module apb_gpi (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic        PREADY,
    output logic [31:0] PRDATA,
    input  logic [15:0] in_port
);
    logic [7:0] reg0;
    logic [7:0] out_port;

    gpi_ctr U_GPI_CTR (
        .clk        (clk),
        .rst_n      (rst_n),
        .Paddr      (PADDR),
        .Pwdata     (PWDATA),
        .Pwrite     (PWRITE),
        .Penable    (PENABLE),
        .Psel       (PSEL),
        .in_port    (out_port),
        .Pready     (PREADY),
        .Prdata     (PRDATA),
        .control_reg(reg0)
    );

    gpi_ip U_GPI_IP (
        .clk     (clk),
        .rst_n   (rst_n),
        .reg0    (reg0),
        .in_port (in_port[7:0]),
        .out_port(out_port)
    );

endmodule

module gpi_ctr (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] Paddr,
    input  logic [31:0] Pwdata,
    input  logic        Pwrite,
    input  logic        Penable,
    input  logic        Psel,
    input  logic [7:0]  in_port,
    output logic        Pready,
    output logic [31:0] Prdata,
    output logic [7:0]  control_reg
);
    logic [31:0] reg0;
    logic [31:0] reg1;

    assign control_reg = reg0[7:0];
    assign reg1        = {24'b0, in_port};
    assign Pready      = Psel & Penable;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg0 <= 32'b0;
        end else if (Psel && Penable && Pwrite) begin
            if (Paddr[3:2] == 2'b00) begin
                reg0 <= Pwdata;
            end
        end
    end

    always_comb begin
        if (Psel && Penable && !Pwrite) begin
            case (Paddr[3:2])
                2'b00:   Prdata = reg0;
                2'b01:   Prdata = reg1;
                default: Prdata = 32'b0;
            endcase
        end else begin
            Prdata = 32'b0;
        end
    end

endmodule

module gpi_ip (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] reg0,
    input  logic [7:0] in_port,
    output logic [7:0] out_port
);
    logic [7:0] in_sync1, in_sync2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_sync1 <= 8'h0;
            in_sync2 <= 8'h0;
        end else begin
            in_sync1 <= in_port;
            in_sync2 <= in_sync1;
        end
    end

    assign out_port = in_sync2 & reg0;
endmodule
// 3. APB GPIO (Bi-directional General Purpose IO)
// Register offsets:
// 0x00: MODER (0 = Input, 1 = Output)
// 0x04: IDR   (Input Data Register, Read-only)
// 0x08: ODR   (Output Data Register, Read/Write)
module apb_gpio (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic        PREADY,
    output logic [31:0] PRDATA,

    // External GPIO signals
    input  logic [15:0] gpio_in,
    output logic [15:0] gpio_out,
    output logic [15:0] gpio_oe
);
    logic [15:0] moder_reg;
    logic [15:0] odr_reg;
    logic [15:0] in_sync1, in_sync2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_sync1 <= 16'h0;
            in_sync2 <= 16'h0;
        end else begin
            in_sync1 <= gpio_in;
            in_sync2 <= in_sync1;
        end
    end

    assign PREADY   = PSEL & PENABLE;
    assign gpio_out = odr_reg;
    assign gpio_oe  = moder_reg;

    // Register Write
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            moder_reg <= 16'h0000;
            odr_reg   <= 16'h0000;
        end else if (PREADY && PWRITE) begin
            case (PADDR[3:2])
                2'b00:   moder_reg <= PWDATA[15:0];  // MODER (0x00)
                2'b10:   odr_reg <= PWDATA[15:0];  // ODR   (0x08)
                default: ;
            endcase
        end
    end

    // Register Read
    always_comb begin
        if (PREADY && !PWRITE) begin
            case (PADDR[3:2])
                2'b00:   PRDATA = {16'h0, moder_reg};  // MODER (0x00)
                2'b01:   PRDATA = {16'h0, in_sync2};  // IDR   (0x04)
                2'b10:   PRDATA = {16'h0, odr_reg};  // ODR   (0x08)
                default: PRDATA = 32'b0;
            endcase
        end else begin
            PRDATA = 32'b0;
        end
    end
endmodule

// 4. APB FND (7-Segment Display Output)
module apb_fnd (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic        PREADY,
    output logic [31:0] PRDATA,
    output logic [31:0] fnd_val
);
    logic [31:0] fnd_reg;

    assign PREADY  = PSEL & PENABLE;
    assign fnd_val = fnd_reg;
    assign PRDATA  = (PREADY && !PWRITE) ? fnd_reg : 32'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fnd_reg <= 32'h0;
        end else if (PREADY && PWRITE) begin
            fnd_reg <= PWDATA;
        end
    end
endmodule
