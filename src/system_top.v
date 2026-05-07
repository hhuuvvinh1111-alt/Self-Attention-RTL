`timescale 1ns / 1ps

module system_top (
    input  wire        clk,          
    input  wire [1:0]  KEY,          // KEY[0] làm rst_n, KEY[1] làm nút Next
    input  wire        uart_rx_pin,  
    output wire        uart_tx_pin,  
    output wire [3:0]  led,          
    output wire [6:0]  HEX0,         // LED 7 Đoạn (Byte thấp nhất)
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3          // LED 7 Đoạn (Byte cao nhất)
);

    wire rst_n = KEY[0];
    wire btn_next_pulse;
    wire [15:0] z_display;

    // ==========================================
    // 1. TÍN HIỆU KẾT NỐI NỘI BỘ (INTERNAL WIRES)
    // ==========================================
    
    // UART <-> System Controller
    wire [7:0] rx_data;
    wire       rx_done;
    wire [7:0] tx_data;
    wire       tx_start;
    wire       tx_busy;
    wire       tx_done;

    // System Controller <-> AI Core (Tín hiệu Điều khiển)
    wire       ai_start;
    wire       ai_done;
    wire       mode_ai_running;

    // System Controller <-> Các khối RAM (Bus Dữ liệu & Địa chỉ)
    wire [11:0] uart_addr;
    wire [15:0] uart_data_in;
    wire        we_X, uart_we_Wq, uart_we_Wk, uart_we_Wv;
    wire [15:0] uart_data_Z_out;

    // AI Core <-> RAM X
    wire [11:0] ai_addr_X;
    wire [15:0] data_X_to_ai;

    // ==========================================
    // 2. MODULE KHỐI GIAO TIẾP UART
    // ==========================================
    uart_rx u_uart_rx (
        .clk(clk),
        .rst_n(rst_n),
        .rx_pin(uart_rx_pin),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );

    uart_tx u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_pin(uart_tx_pin),
        .tx_busy(tx_busy),
        .tx_done(tx_done)
    );

    // ==========================================
    // 3. MÁY TRẠNG THÁI ĐIỀU PHỐI TRUNG TÂM
    // ==========================================
    system_controller u_controller (
        .clk(clk),
        .rst_n(rst_n),
        
        // Giao tiếp UART
        .rx_data(rx_data),
        .rx_done(rx_done),
        .tx_data(tx_data),
        .tx_start(tx_start),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        
        // Giao tiếp Bus RAM
        .we_X(we_X),
        .uart_addr(uart_addr),
        .uart_data_in(uart_data_in),
        .uart_we_Wq(uart_we_Wq),
        .uart_we_Wk(uart_we_Wk),
        .uart_we_Wv(uart_we_Wv),
        .uart_data_Z_out(uart_data_Z_out),
        
        // Giao tiếp Lõi AI
        .ai_start(ai_start),
        .ai_done(ai_done),
        .mode_ai_running(mode_ai_running),
        .led_status(led),

        // Thêm 2 chân hiển thị UI mới:
        .btn_next(btn_next_pulse),
        .display_data(z_display)
    );

    // ==========================================
    // 4. BỘ NHỚ RAM X (Simple Dual-Port RAM)
    // ==========================================
    // Chú ý: Cấu hình trong IP Catalog là loại 1 cổng Read, 1 cổng Write
    ram_X u_ram_X (
        .clock(clk),
        
        // Cổng Write: Do Controller nắm quyền để nạp data từ Laptop
        .data(uart_data_in),    
        .wraddress(uart_addr),  
        .wren(we_X),            
        
        // Cổng Read: Do AI Core nắm quyền để đọc ra tính toán
        .rdaddress(ai_addr_X),  
        .q(data_X_to_ai)        
    );

    // ==========================================
    // 5. TRÁI TIM HỆ THỐNG: LÕI AI ATTENTION
    // ==========================================
    attention_top u_ai_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(ai_start),
        .done(ai_done),
        
        // Kết nối với RAM X bên ngoài
        .addr_X(ai_addr_X),
        .data_X(data_X_to_ai),
        
        // Giao tiếp Bus UART từ Controller để nạp Trọng số & Rút Kết quả
        .mode_ai_running(mode_ai_running),
        .uart_addr(uart_addr),
        .uart_data_in(uart_data_in),
        .uart_we_Wq(uart_we_Wq),
        .uart_we_Wk(uart_we_Wk),
        .uart_we_Wv(uart_we_Wv),
        .uart_data_Z_out(uart_data_Z_out)
    );
	 
	 // ==========================================
    // 6. TÍCH HỢP GIAO DIỆN NÚT NHẤN & 7-SEGMENT
    // ==========================================
    
    // Mạch chống dội cho KEY[1]
    button_debouncer u_btn (
        .clk(clk),
        .btn_in(KEY[1]),
        .btn_edge(btn_next_pulse)
    );

    // Giải mã 16-bit dữ liệu Z thành 4 LED 7 đoạn
    hex_decoder h0 (.hex_in(z_display[3:0]),   .segments(HEX0));
    hex_decoder h1 (.hex_in(z_display[7:4]),   .segments(HEX1));
    hex_decoder h2 (.hex_in(z_display[11:8]),  .segments(HEX2));
    hex_decoder h3 (.hex_in(z_display[15:12]), .segments(HEX3));

endmodule