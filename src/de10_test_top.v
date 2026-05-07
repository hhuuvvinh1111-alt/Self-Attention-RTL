`timescale 1ns / 1ps

module de10_test_top (
    input  wire        CLOCK_50,  // Clock 50MHz từ Kit
    input  wire [1:0]  KEY,       // Nút nhấn (KEY[0] dùng làm rst_n)
    input  wire [9:0]  SW,        // 10 Công tắc gạt
    output wire [9:0]  LEDR       // 10 Đèn LED đỏ
);

    wire clk   = CLOCK_50;
    wire rst_n = KEY[0];          // Nhấn KEY0 để Reset toàn hệ thống

    // ==========================================
    // 1. TÍN HIỆU KẾT NỐI
    // ==========================================
    wire        ai_start;
    wire        ai_done;
    wire        mode_ai_running;
    
    // Bus điều khiển RAM
    wire [11:0] uart_addr;
    wire [15:0] uart_data_in;
    wire        we_X, uart_we_Wq, uart_we_Wk, uart_we_Wv;
    wire [15:0] uart_data_Z_out;

    // AI Core <-> RAM X
    wire [11:0] ai_addr_X;
    wire [15:0] data_X_to_ai;

    // ==========================================
    // 2. MÁY TRẠNG THÁI TỰ ĐỘNG NẠP DỮ LIỆU BẢN TEST
    // ==========================================
    localparam S_INIT_X  = 3'd0,
               S_INIT_WQ = 3'd1,
               S_INIT_WK = 3'd2,
               S_INIT_WV = 3'd3,
               S_START   = 3'd4,
               S_WAIT    = 3'd5,
               S_READ    = 3'd6;

    reg [2:0]  state;
    reg [6:0]  word_cnt; // Đếm từ 0 đến 63 (Đủ 64 phần tử cho Hàng 0)
    
    // Tín hiệu nội bộ của FSM
    reg [11:0] fsm_addr;
    reg [15:0] fsm_data_in;
    reg        fsm_we_X, fsm_we_Wq, fsm_we_Wk, fsm_we_Wv;
    reg        fsm_ai_start;

    // Phân luồng tín hiệu (MUX giữa FSM nạp data và Switch đọc data)
    assign mode_ai_running = (state == S_START || state == S_WAIT);
    assign ai_start        = fsm_ai_start;
    
    // Khi chạy AI hoặc Nạp data, dùng địa chỉ của FSM. 
    // Khi xong (S_READ), dùng 6 switch đầu tiên để tạo địa chỉ đọc.
    assign uart_addr    = (state == S_READ) ? {6'd0, SW[5:0]} : fsm_addr;
    assign uart_data_in = fsm_data_in;
    assign we_X         = fsm_we_X;
    assign uart_we_Wq   = fsm_we_Wq;
    assign uart_we_Wk   = fsm_we_Wk;
    assign uart_we_Wv   = fsm_we_Wv;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_INIT_X;
            word_cnt     <= 0;
            fsm_ai_start <= 0;
            fsm_we_X     <= 0; fsm_we_Wq <= 0; fsm_we_Wk <= 0; fsm_we_Wv <= 0;
        end else begin
            // Reset các cờ mặc định
            fsm_ai_start <= 0;
            fsm_we_X <= 0; fsm_we_Wq <= 0; fsm_we_Wk <= 0; fsm_we_Wv <= 0;
            fsm_addr <= {5'd0, word_cnt}; // Địa chỉ bằng bộ đếm hiện tại

            case (state)
                S_INIT_X: begin
                    fsm_data_in <= 16'h1100 + word_cnt;
                    fsm_we_X    <= 1;
                    if (word_cnt < 63) word_cnt <= word_cnt + 1;
                    else begin word_cnt <= 0; state <= S_INIT_WQ; end
                end
                
                S_INIT_WQ: begin
                    fsm_data_in <= 16'h2200 + word_cnt;
                    fsm_we_Wq   <= 1;
                    if (word_cnt < 63) word_cnt <= word_cnt + 1;
                    else begin word_cnt <= 0; state <= S_INIT_WK; end
                end

                S_INIT_WK: begin
                    fsm_data_in <= 16'h3300 + word_cnt;
                    fsm_we_Wk   <= 1;
                    if (word_cnt < 63) word_cnt <= word_cnt + 1;
                    else begin word_cnt <= 0; state <= S_INIT_WV; end
                end

                S_INIT_WV: begin
                    fsm_data_in <= 16'h4400 + word_cnt;
                    fsm_we_Wv   <= 1;
                    if (word_cnt < 63) word_cnt <= word_cnt + 1;
                    else begin word_cnt <= 0; state <= S_START; end
                end

                S_START: begin
                    fsm_ai_start <= 1; // Bóp cò kích hoạt AI
                    state        <= S_WAIT;
                end

                S_WAIT: begin
                    if (ai_done) state <= S_READ; // Đợi tính xong
                end

                S_READ: begin
                    state <= S_READ; // Kẹt ở đây vĩnh viễn để bạn dùng Switch đọc LED
                end

                default: state <= S_INIT_X;
            endcase
        end
    end

    // ==========================================
    // 3. HIỂN THỊ LÊN LED THEO THAO TÁC SWITCH
    // ==========================================
    // LED 9: Sáng khi đã tính toán xong toàn bộ (Chế độ đọc)
    assign LEDR[9] = (state == S_READ);
    
    // LED 8: Sáng nhấp nháy/liên tục khi AI đang chạy tính toán
    assign LEDR[8] = (state == S_WAIT);
    
    // LED 7 đến 0: Hiển thị giá trị của ma trận Z
    // Gạt SW[9] LÊN (1) -> Xem 8 bit CAO. Gạt XUỐNG (0) -> Xem 8 bit THẤP
    assign LEDR[7:0] = SW[9] ? uart_data_Z_out[15:8] : uart_data_Z_out[7:0];


    // ==========================================
    // 4. TRIỆU HỒI CÁC MODULE CỐT LÕI
    // ==========================================
    ram_X u_ram_X (
        .clock(clk),
        .data(uart_data_in),    .wraddress(uart_addr),  .wren(we_X),            
        .rdaddress(ai_addr_X),  .q(data_X_to_ai)        
    );

    attention_top u_ai_core (
        .clk(clk),              .rst_n(rst_n),          .start(ai_start),     .done(ai_done),
        .addr_X(ai_addr_X),     .data_X(data_X_to_ai),
        .mode_ai_running(mode_ai_running),
        .uart_addr(uart_addr),  .uart_data_in(uart_data_in),
        .uart_we_Wq(uart_we_Wq), .uart_we_Wk(uart_we_Wk), .uart_we_Wv(uart_we_Wv),
        .uart_data_Z_out(uart_data_Z_out)
    );

endmodule