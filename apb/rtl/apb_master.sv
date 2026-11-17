module apb_master (
    input  logic        clk,
    input  logic        rst_n,
    
    // 1. CPU와의 인터페이스
    input  logic [31:0] bus_addr,   // CPU로부터 주소 받음
    input  logic [31:0] bus_wdata,  // 쓸 데이터 받음
    input  logic        bus_we,     // 읽기/쓰기 여부 받음
    input  logic        transfer,   // 버스 시작 요청 받음!
    output logic [31:0] bus_rdata,  // 읽은 데이터 건네줌
    output logic        bus_ready,  // 완료 신호 보냄

    // 2. APB 버스 (슬레이브들과의 인터페이스)
    output logic [31:0] PAddr,      // 슬레이브들로 나가는 공통 주소
    output logic [31:0] PWdata,     // 나가는 공통 쓸 데이터
    output logic        PWrite,     // 나가는 쓰기/읽기 플래그
    output logic        PEnable,    // 나가는 인에이블 스트로브
    output logic [ 4:0] PSel,       // 5개 개별 선택선 (One-hot)
    
    input  logic [ 4:0] PReady,     // 5개의 완료 신호선들
    input  logic [31:0] PRData [0:4]// 5개의 읽기 데이터 버스들
);

    typedef enum logic [1:0]{
        ST_IDLE,
        ST_SETUP,
        ST_ACCESS
    } state_e;
    state_e state, state_n;

    assign PAddr   = bus_addr;
    assign PWdata  = bus_wdata;
    assign PWrite  = bus_we;
    assign PEnable = (state == ST_ACCESS);

    // bus_ready: asserted during ACCESS phase when the addressed slave asserts PReady
    assign bus_ready = (state == ST_ACCESS) && (|(PSel & PReady));

    // bus_rdata: multiplexed read data from the selected slave
    always_comb begin
        case (1'b1)
            PSel[0]: bus_rdata = PRData[0];
            PSel[1]: bus_rdata = PRData[1];
            PSel[2]: bus_rdata = PRData[2];
            PSel[3]: bus_rdata = PRData[3];
            PSel[4]: bus_rdata = PRData[4];
            default: bus_rdata = 32'b0;
        endcase
    end

    // address decoder
    // 0: RAM   0x1000_0000 ~ 0x1000_FFFF
    // 1: GPO   0x2000_0100 ~ 0x2000_01FF (LED)
    // 2: GPI   0x2000_0000 ~ 0x2000_00FF (Switch)
    // 3: GPIO  0x2000_0200 ~ 0x2000_02FF (General IO)
    // 4: FND   0x2000_0300 ~ 0x2000_03FF (7-Segment)
    always_comb begin 
        PSel = 5'b0;
        if (state != ST_IDLE) begin
            case (bus_addr[31:28])
                4'h1: begin // 0x1000_0000 : RAM (Slave 0)
                    PSel[0] = 1'b1;
                end
                4'h2: begin // 0x2000_0000 : Peripherals
                    case (bus_addr[11:8])
                        4'h0: PSel[2] = 1'b1; // 0x2000_0000 : GPI (Slave 2)
                        4'h1: PSel[1] = 1'b1; // 0x2000_0100 : GPO (Slave 1)
                        4'h2: PSel[3] = 1'b1; // 0x2000_0200 : GPIO (Slave 3)
                        4'h3: PSel[4] = 1'b1; // 0x2000_0300 : FND (Slave 4)
                        default: PSel = 5'b0;
                    endcase
                end
                default: PSel = 5'b0;
            endcase
        end
    end

    // state machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
        end else begin
            state <= state_n;
        end
    end
    
    always_comb begin 
        state_n = state;
        case (state)
            ST_IDLE: begin
                if (transfer) state_n = ST_SETUP;
            end
            ST_SETUP: begin
                state_n = ST_ACCESS; // 무조건 1클럭 뒤 ACCESS
            end
            ST_ACCESS: begin
                // 선택된 슬레이브가 완료 신호(1)를 주었을 때만 IDLE로 복귀!
                if (|(PSel & PReady)) state_n = ST_IDLE;
            end
            default: state_n = ST_IDLE;
        endcase
    end

endmodule
