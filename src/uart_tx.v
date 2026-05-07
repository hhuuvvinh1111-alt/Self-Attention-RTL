`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000, // Tần số thạch anh (50MHz)
    parameter BAUD_RATE = 115200      // Tốc độ truyền (Bits per second)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,       // Xung kích hoạt (1 clock) để bắt đầu gửi
    input  wire [7:0] tx_data,        // 1 Byte (8-bit) cần gửi đi
    
    output reg        tx_pin,         // Chân vật lý nối với dây RX của Laptop
    output reg        tx_busy,        // Cờ báo bận (1 = Đang gửi, không được nhồi thêm data)
    output reg        tx_done         // Xung chớp 1 nhịp báo hiệu đã gửi xong 1 Byte
);

    // Tính toán số nhịp Clock cho 1 chu kỳ Bit
    localparam BIT_PERIOD = CLK_FREQ / BAUD_RATE;

    // Các trạng thái của FSM
    localparam S_IDLE  = 3'd0,
               S_START = 3'd1,
               S_DATA  = 3'd2,
               S_STOP  = 3'd3,
               S_CLEAN = 3'd4;

    reg [2:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    
    // Thanh ghi đệm nội bộ (Giữ an toàn dữ liệu trong lúc gửi)
    reg [7:0]  data_reg; 

    // =======================================================
    // MÁY TRẠNG THÁI PHÁT DỮ LIỆU
    // =======================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            tx_pin   <= 1'b1;  // Mặc định đường truyền rảnh là mức Cao (1)
            tx_busy  <= 1'b0;
            tx_done  <= 1'b0;
            data_reg <= 8'd0;
        end else begin
            // Mặc định xung done chỉ nảy lên 1 clock rồi tự tắt
            tx_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    tx_pin  <= 1'b1;
                    tx_busy <= 1'b0;
                    
                    if (tx_start) begin
                        data_reg <= tx_data; // Chốt ngay dữ liệu vào bụng để bảo toàn
                        tx_busy  <= 1'b1;    // Kéo cờ bận lên để chặn Controller nhồi thêm
                        state    <= S_START;
                        clk_cnt  <= 0;
                    end
                end

                S_START: begin
                    tx_pin <= 1'b0; // Kéo xuống mức 0 để tạo Bit Start báo hiệu cho Laptop
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        state   <= S_DATA;
                        bit_idx <= 0;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_DATA: begin
                    tx_pin <= data_reg[bit_idx]; // Đẩy từng bit ra đường dây (Truyền LSB trước)
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            state <= S_STOP;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_STOP: begin
                    tx_pin <= 1'b1; // Kéo lên mức 1 để tạo Bit Stop kết thúc gói tin
                    if (clk_cnt == BIT_PERIOD - 1) begin
                        clk_cnt <= 0;
                        tx_done <= 1'b1; // Bắn cờ báo cáo hoàn thành
                        state   <= S_CLEAN;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                S_CLEAN: begin
                    // Trạng thái đệm 1 clock để đảm bảo nhịp điệu chuyển mạch an toàn
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule