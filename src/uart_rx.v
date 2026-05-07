`timescale 1ns / 1ps

module uart_rx #(
    parameter CLK_FREQ  = 50_000_000, // Tần số thạch anh (50MHz)
    parameter BAUD_RATE = 115200      // Tốc độ truyền (Bits per second)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_pin,         // Chân vật lý nối với dây TX của Laptop
    
    output reg  [7:0] rx_data,        // 1 Byte (8-bit) nhận được
    output reg        rx_done         // Xung chớp 1 nhịp báo hiệu đã nhận xong 1 Byte
);

    // Tính toán số nhịp Clock cho 1 chu kỳ Bit
    localparam BIT_PERIOD  = CLK_FREQ / BAUD_RATE;
    localparam HALF_PERIOD = BIT_PERIOD / 2;

    // Các trạng thái của FSM
    localparam S_IDLE  = 3'd0,
               S_START = 3'd1,
               S_DATA  = 3'd2,
               S_STOP  = 3'd3,
               S_CLEAN = 3'd4;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;

    // =======================================================
    // 1. MẠCH ĐỒNG BỘ HÓA CHỐNG NHIỄU (2-STAGE SYNCHRONIZER)
    // =======================================================
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1; // Đường truyền UART mặc định khi rảnh là mức 1 (High)
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx_pin;
            rx_sync2 <= rx_sync1;
        end
    end

    // =======================================================
    // 2. MÁY TRẠNG THÁI NHẬN DỮ LIỆU
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            clk_cnt <= 0;
            bit_idx <= 0;
            rx_data <= 8'd0;
            rx_done <= 0;
        end else begin
            // Mặc định xung done chỉ nảy lên 1 clock rồi tự tắt
            rx_done <= 0;

            case (state)
                S_IDLE: begin
                    clk_cnt <= 0;
                    bit_idx <= 0;
                    // Đường dây bị kéo xuống 0 -> Có thể là Bit Start
                    if (rx_sync2 == 1'b0) begin 
                        state <= S_START;
                    end
                end

                S_START: begin
                    // Đợi đến đúng GIỮA chu kỳ của Bit Start
                    if (clk_cnt == HALF_PERIOD) begin
                        if (rx_sync2 == 1'b0) begin 
                            // Nếu vẫn là 0, đây là Start thật, bắt đầu nhận Data
                            clk_cnt <= 0;
                            state   <= S_DATA;
                        end else begin
                            // Nếu nó nảy lên 1, đây chỉ là nhiễu điện (Glitch), quay về ngủ tiếp
                            state   <= S_IDLE; 
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    // Đợi đủ 1 chu kỳ Bit (Lấy mẫu ở giữa các bit tiếp theo)
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        rx_data[bit_idx] <= rx_sync2; // Chốt dữ liệu
                        
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            bit_idx <= 0;
                            state   <= S_STOP;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    // Đợi đến giữa Bit Stop
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        state   <= S_CLEAN;
                        rx_done <= 1'b1; // Bắn cờ báo hiệu cho Controller biết đã nhận xong!
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_CLEAN: begin
                    // Trạng thái đệm 1 clock để đảm bảo dọn dẹp an toàn
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule