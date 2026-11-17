module apb_bram (
    input  logic        clk,
    input  logic [ 2:0] itype,
    input  logic        PSEL,
    input  logic        PENABLE,
    input  logic [31:0] PADDR,
    input  logic [31:0] PWDATA,
    input  logic        PWRITE,
    output logic        PREADY,
    output logic [31:0] PRDATA
);

    logic [31:0] dmem[0:127];

    assign PREADY = (PENABLE & PSEL) ? 1'b1 : 1'b0;

    // store
    always_ff @(posedge clk) begin
        if (PREADY && PWRITE) begin
            case (itype)
                3'b010:  dmem[PADDR[8:2]] <= PWDATA;  // SW (Word aligned)
                default: dmem[PADDR[8:2]] <= PWDATA;
            endcase
        end
    end

    // load
    assign PRDATA = (PREADY && !PWRITE) ? dmem[PADDR[8:2]] : 32'b0;

endmodule

