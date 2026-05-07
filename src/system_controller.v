`timescale 1ns / 1ps

module system_controller (
    input  wire        clk,
    input  wire        rst_n,

    // Giao tiếp với bộ UART RX
    input  wire [7:0]  rx_data,
    input  wire        rx_done,

    // Giao tiếp với bộ UART TX
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy,
    input  wire        tx_done,

    // Giao tiếp điều khiển RAM X (Nằm ngoài cùng)
    output reg         we_X,

    // Bus chung điều khiển RAM bên trong Lõi AI
    output reg  [11:0] uart_addr,
    output reg  [15:0] uart_data_in,
    output reg         uart_we_Wq,
    output reg         uart_we_Wk,
    output reg         uart_we_Wv,
    input  wire [15:0] uart_data_Z_out,

    // Điều khiển Lõi AI (attention_top)
    output reg         ai_start,
    input  wire        ai_done,
    output wire        mode_ai_running, // Cờ báo AI đang chạy để gạt MUX
    output reg  [3:0]  led_status,       // Hiển thị trạng thái lên LED
	 input  wire        btn_next,     // Xung từ nút nhấn để đổi ma trận
    output wire [15:0] display_data  // Dữ liệu 16-bit đẩy ra LED 7 đoạn
);

    // ==========================================
    // MÁY TRẠNG THÁI (MASTER FSM)
    // ==========================================
    localparam S_IDLE       = 4'd0,
               S_RX_HIGH    = 4'd1,
               S_RX_LOW     = 4'd2,
               S_WRITE_RAM  = 4'd3,
					S_WRITE_DONE = 4'd13,
               S_START_AI   = 4'd4,
               S_WAIT_AI    = 4'd5,
               S_TX_PREPARE = 4'd6,
               S_TX_FETCH   = 4'd7,
               S_TX_HIGH    = 4'd8,
               S_WAIT_TX_H  = 4'd9,
               S_TX_LOW     = 4'd10,
               S_WAIT_TX_L  = 4'd11,
               S_DONE       = 4'd12;

    reg [3:0]  state;
    reg [11:0] word_cnt;   // Đếm từ 0 đến 4095
    reg [2:0]  matrix_idx; // 0=X, 1=Wq, 2=Wk, 3=Wv
    reg [15:0] temp_word;

    // Khi state ở START_AI hoặc WAIT_AI, gạt đường ray cho AI chạy
    assign mode_ai_running = (state == S_START_AI || state == S_WAIT_AI);
	 
	 // Kéo thẳng dữ liệu đang xuất ra từ RAM Z ra ngoài để hiển thị
    assign display_data = uart_data_Z_out;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            word_cnt     <= 0;
            matrix_idx   <= 0;
            tx_start     <= 0;
            ai_start     <= 0;
            led_status   <= 4'b0000;
            
            we_X         <= 0;
            uart_we_Wq   <= 0;
            uart_we_Wk   <= 0;
            uart_we_Wv   <= 0;
        end else begin
            // Reset các xung kích hoạt mặc định
            tx_start   <= 0;
            ai_start   <= 0;
            we_X       <= 0;
            uart_we_Wq <= 0;
            uart_we_Wk <= 0;
            uart_we_Wv <= 0;

            case (state)
                S_IDLE: begin
                    word_cnt   <= 0;
                    matrix_idx <= 0;
                    led_status <= 4'b0001; // Đèn 1: Chờ PC gửi data
                    
                    if (rx_done) begin
                        temp_word[15:8] <= rx_data;
                        state <= S_RX_LOW;
                    end
                end

                // --- BƯỚC 1: NHẬN VÀ GHI 4 MA TRẬN VÀO RAM ---
                S_RX_HIGH: begin
                    if (rx_done) begin
                        temp_word[15:8] <= rx_data;
                        state <= S_RX_LOW;
                    end
                end

                S_RX_LOW: begin
                    if (rx_done) begin
                        temp_word[7:0] <= rx_data;
                        state <= S_WRITE_RAM;
                    end
                end

                S_WRITE_RAM: begin
                    uart_addr    <= word_cnt;
                    uart_data_in <= temp_word;
                    
                    // Route data đến đúng RAM
                    if      (matrix_idx == 0) we_X       <= 1;
                    else if (matrix_idx == 1) uart_we_Wq <= 1;
                    else if (matrix_idx == 2) uart_we_Wk <= 1;
                    else if (matrix_idx == 3) uart_we_Wv <= 1;

                    // Kiểm tra xem đã nạp đủ phần tử chưa
                    if (word_cnt < 4095) begin  // (Lưu ý: Nếu test thực tế thì đổi lại thành 4095)/7 mo phong
                        word_cnt <= word_cnt + 1;
                        state    <= S_RX_HIGH;
                    end else begin
                        word_cnt <= 0;
                        if (matrix_idx < 3) begin
                            matrix_idx <= matrix_idx + 1; // Sang ma trận tiếp theo
                            state      <= S_RX_HIGH;
                        end else begin
                            state      <= S_WRITE_DONE;   // <--- SỬA Ở ĐÂY: Không nhảy thẳng vào AI nữa
                        end
                    end
                end

                // ---> THÊM KHỐI TRẠNG THÁI NÀY VÀO <---
                S_WRITE_DONE: begin
                    // Trạng thái đệm 1 nhịp clock.
                    // Lúc này state chưa phải là START_AI nên mode_ai_running vẫn = 0.
                    // Cửa MUX vẫn mở, xung Ghi (we) của phần tử cuối cùng sẽ lọt vào RAM an toàn.
                    state <= S_START_AI;
                end

                // ... Khối S_START_AI bên dưới giữ nguyên ...
                // --- BƯỚC 2: CHẠY LÕI AI ---
                S_START_AI: begin
                    led_status <= 4'b0011; // Đèn 1+2: AI Đang tính toán
                    ai_start   <= 1;
                    state      <= S_WAIT_AI;
                end

                S_WAIT_AI: begin
                    if (ai_done) begin
                        word_cnt <= 0;
                        state    <= S_TX_PREPARE;
                    end
                end

                // --- BƯỚC 3: ĐỌC RAM Z VÀ GỬI LÊN LAPTOP ---
                S_TX_PREPARE: begin
                    led_status <= 4'b0111; // Đèn 1+2+3: Đang gửi kết quả
                    uart_addr  <= word_cnt;
                    state      <= S_TX_FETCH;
                end

                S_TX_FETCH: begin
                    // Đợi 1 nhịp clock để RAM xuất data Z ra ngoài
                    state <= S_TX_HIGH;
                end

                S_TX_HIGH: begin
                    if (!tx_busy) begin
                        tx_data  <= uart_data_Z_out[15:8];
                        tx_start <= 1;
                        state    <= S_WAIT_TX_H;
                    end
                end

                S_WAIT_TX_H: begin
                    if (tx_done) state <= S_TX_LOW;
                end

                S_TX_LOW: begin
                    if (!tx_busy) begin
                        tx_data  <= uart_data_Z_out[7:0];
                        tx_start <= 1;
                        state    <= S_WAIT_TX_L;
                    end
                end

                S_WAIT_TX_L: begin
                    if (tx_done) begin
                        if (word_cnt < 4095) begin
                            word_cnt <= word_cnt + 1;
                            state    <= S_TX_PREPARE;
                        end else begin
                            led_status <= 4'b1111;
                            word_cnt   <= 0;       // <--- RESET ĐIỂM ĐẾM ĐỂ ĐỌC LED TỪ 0
                            state      <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    // Ở trạng thái này, liên tục ép địa chỉ RAM bằng bộ đếm
                    uart_addr <= word_cnt; 
                    
                    // Nếu có người bấm nút, tăng bộ đếm lên 1 để xem phần tử tiếp theo
                    if (btn_next) begin
                        if (word_cnt < 4095) word_cnt <= word_cnt + 1;
                        else word_cnt <= 0;
                    end
                    
                    state <= S_DONE; // Kẹt vĩnh viễn ở đây
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule