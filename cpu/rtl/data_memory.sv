module data_memory (
  input   logic         clk,        // System clock
  input   logic [31:0]  daddr,      // Data memory byte address
  input   logic [31:0]  dwdata,     // Data to write into memory
  input   logic         dwe,        // Data write enable (1: write, 0: read)
  input   logic [ 2:0]  itype,      // Memory access type (funct3)
  output  logic [31:0]  drdata      // Data read from memory
);
  logic [31:0]  data_reg [0:127];   // 128 words x 32-bit (512-byte) memory array

  always_ff @(posedge clk) begin    // Synchronous memory write on rising clock edge
    if(dwe) begin                   // Check if write operation is enabled
      case (itype)                  // Decode store instruction type by funct3
        3'b010: data_reg[daddr[31:2]] <= dwdata;  // SW: Store Word (32-bit)
        3'b001: begin                             // SH: Store Halfword (16-bit)
          if(daddr[1]) data_reg[daddr[31:2]] [31:16] <= dwdata[15:0];  // Upper halfword (offset 2)
          else data_reg[daddr[31:2]] [15:0] <= dwdata[15:0];           // Lower halfword (offset 0)
        end
        3'b000: begin                             // SB: Store Byte (8-bit)
          case (daddr[1:0])                       // Decode byte offset within word
            2'b00: data_reg[daddr[31:2]] [7:0] <= dwdata[7:0];    // Write to byte 0
            2'b01: data_reg[daddr[31:2]] [15:8] <= dwdata[7:0];   // Write to byte 1
            2'b10: data_reg[daddr[31:2]] [23:16] <= dwdata[7:0];  // Write to byte 2
            2'b11: data_reg[daddr[31:2]] [31:24] <= dwdata[7:0];  // Write to byte 3
          endcase
        end
        default: data_reg[daddr[31:2]] <= data_reg[daddr[31:2]];  // Retain existing data
      endcase
    end
  end

  always_comb begin                 // Combinational memory read block
    drdata = 32'd0;                 // Default read output value
    case(itype)                     // Decode load instruction type by funct3
      3'b010: drdata = data_reg[daddr[31:2]];  // LW: Load Word (full 32-bit)
      3'b001: begin                           // LH: Load Halfword (16-bit sign-extended)
        if(daddr[1]) drdata = {{16{data_reg[daddr[31:2]] [31]}}, data_reg[daddr[31:2]] [31:16]}; // Upper halfword sign extension
        else drdata = {{16{data_reg[daddr[31:2]] [15]}}, data_reg[daddr[31:2]] [15:0]};          // Lower halfword sign extension
      end
      3'b000: begin                           // LB: Load Byte (8-bit sign-extended)
        case (daddr[1:0])                     // Select byte by lower 2 bits of address
          2'b00: drdata = {{16{data_reg[daddr[31:2]] [7]}}, data_reg[daddr[31:2]] [7:0]};   // Byte 0 sign extension
          2'b01: drdata = {{16{data_reg[daddr[31:2]] [15]}}, data_reg[daddr[31:2]] [15:8]};  // Byte 1 sign extension
          2'b10: drdata = {{16{data_reg[daddr[31:2]] [23]}}, data_reg[daddr[31:2]] [23:16]}; // Byte 2 sign extension
          2'b11: drdata = {{16{data_reg[daddr[31:2]] [31]}}, data_reg[daddr[31:2]] [31:24]}; // Byte 3 sign extension
        endcase
      end
      3'b101: begin                           // LHU: Load Halfword Unsigned (zero-extended)
        if(daddr[1]) drdata = {16'd0, data_reg[daddr[31:2]] [31:16]};  // Upper halfword zero-padding
        else drdata = {16'd0, data_reg[daddr[31:2]] [15:0]};           // Lower halfword zero-padding
      end
      3'b100: begin                           // LBU: Load Byte Unsigned (zero-extended)
        case (daddr[1:0])                     // Select byte by lower 2 bits of address
          2'b00: drdata = {24'd0 ,data_reg[daddr[31:2]] [7:0]};   // Byte 0 zero-padding
          2'b01: drdata = {24'd0 ,data_reg[daddr[31:2]] [15:8]};  // Byte 1 zero-padding
          2'b10: drdata = {24'd0 ,data_reg[daddr[31:2]] [23:16]}; // Byte 2 zero-padding
          2'b11: drdata = {24'd0 ,data_reg[daddr[31:2]] [31:24]}; // Byte 3 zero-padding
        endcase
      end
    endcase
  end
endmodule
