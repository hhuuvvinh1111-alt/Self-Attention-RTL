`timescale 1ns / 1ps

module softmax_top (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    
    // Tín hiệu hoàn thành toàn bộ ma trận Softmax 64x64 cho một hàng
    output reg                  done,

    // Giao tiếp với RAM Score (Chỉ đọc)
    output wire [11:0]          addr_Score,
    input  wire signed [15:0]   data_Score,

    // Đầu vào MỚI: Giá trị Max của hàng hiện tại (Tính sẵn từ Pha 1)
    input  wire signed [15:0]   max_val_in,

    // Giao tiếp với ROM e^x (Chỉ đọc)
    output wire [12:0]          addr_Exp,
    input  wire [15:0]          data_Exp,
    
    // Giao tiếp với RAM Softmax (Chỉ ghi - chứa kết quả cuối cùng)
    output reg                  we_Softmax,
    output wire [11:0]          addr_Softmax,
    output wire [15:0]          data_Softmax
);

    // ==========================================
    // 1. KHAI BÁO TÍN HIỆU ĐIỀU KHIỂN NỘI BỘ
    // ==========================================
    reg [5:0] row_idx; // Quản lý vòng lặp Hàng (0->63)
    reg [5:0] col_idx; // Quản lý vòng lặp Cột (Dành riêng cho Pass 3)

    reg  start_sum;
    wire sum_done;
    
    wire [31:0] sum_val_out;
    wire [11:0] addr_Score_sum;
    wire [12:0] addr_Exp_sum;

    // ==========================================
    // 2. KHAI BÁO MÁY TRẠNG THÁI (FSM PARAMETERS)
    // ==========================================
    localparam S_IDLE         = 4'd0,
               S_START_SUM    = 4'd1, // Bỏ qua Pass 1, đi thẳng vào Pass 2
               S_CALC_SUM     = 4'd2,
               S_DIV_READ     = 4'd3, // Bắt đầu Pass 3
               S_DIV_WAIT_RAM = 4'd4,
               S_DIV_WAIT_ROM = 4'd5,
               S_DIV_WRITE    = 4'd6,
               S_NEXT_ROW     = 4'd7,
               S_DONE         = 4'd8;

    reg [3:0] state;

    // ==========================================
    // 3. GỌI CÁC MODULE CON (SUB-MODULES)
    // ==========================================
    // KHÔNG CÒN MODULE find_max_unit

    // 3.1. Khối Tính Tổng Mẫu Số (Pass 2)
    // Lưu ý: Đưa trực tiếp max_val_in vào khối này
    calc_sum_exp u_sum (
        .clk(clk), .rst_n(rst_n), .start(start_sum),
        .row_idx(row_idx), .max_val(max_val_in), 
        .done(sum_done), .sum_val(sum_val_out),
        .addr_Score(addr_Score_sum), .data_Score(data_Score),
        .addr_Exp(addr_Exp_sum), .data_Exp(data_Exp)
    );

    // 3.2. Mạch Tổ Hợp cho Pass 3 (Tính x_norm và kẹp địa chỉ ROM)
    wire signed [16:0] ext_score = {data_Score[15], data_Score};
    wire signed [16:0] ext_max   = {max_val_in[15], max_val_in}; // Dùng max_val_in
    wire signed [16:0] x_norm    = ext_score - ext_max;
    wire signed [16:0] addr_raw  = x_norm + 17'd4096;
    
    // Kẹp 2 chiều an toàn
    wire [12:0] addr_Exp_pass3 = (addr_raw[16] == 1'b1)      ? 13'd0 : 
                                 (addr_raw[12:0] > 13'd4096) ? 13'd4096 : 
                                 addr_raw[12:0];

    // 3.3. Bộ Chia Phần Cứng (Pass 3)
    wire [31:0] div_quotient;
    wire [31:0] div_remain; // THÊM DÂY ĐỂ HỨNG SỐ DƯ TỪ BỘ CHIA
    
    softmax_divide u_div (
        .numer   ( {8'd0, data_Exp, 8'd0} ), // Dịch trái 8 bit (Q8.8)
        .denom   ( sum_val_out ),
        .quotient( div_quotient ),
        .remain  ( div_remain )              // KẾT NỐI SỐ DƯ VÀO ĐÂY
    );

    // ==========================================
    // BÍ KÍP TỐI ƯU SAI SỐ PHÉP CHIA (Round-to-Nearest)
    // ==========================================
    // Dịch trái 1 bit (<< 1) tương đương với nhân 2. 
    // Nếu (Số dư * 2) >= Mẫu số, nghĩa là phần thập phân >= 0.5 -> Cần cộng 1.
    wire round_bit = ( (div_remain << 1) >= sum_val_out ) ? 1'b1 : 1'b0;

    // ==========================================
    // 4. BỘ GHÉP KÊNH (MULTIPLEXER) CHUYỂN ĐƯỜNG RAY
    // ==========================================
    assign addr_Score = (state == S_CALC_SUM) ? addr_Score_sum : {row_idx, col_idx};
    assign addr_Exp   = (state == S_CALC_SUM) ? addr_Exp_sum : addr_Exp_pass3;

    // Địa chỉ ghi và dữ liệu ghi
    assign addr_Softmax = {row_idx, col_idx};
    
    // CỘNG THÊM BIT LÀM TRÒN VÀO KẾT QUẢ CUỐI CÙNG
    assign data_Softmax = div_quotient[15:0] + {15'd0, round_bit};

    // ==========================================
    // 5. MASTER FSM (ĐIỀU KHIỂN LUỒNG)
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            done       <= 0;
            start_sum  <= 0;
            we_Softmax <= 0;
            row_idx    <= 0;
            col_idx    <= 0;
        end 
        else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        row_idx <= 0;
                        state   <= S_START_SUM; // BỎ QUA PASS 1, VÀO THẲNG PASS 2
                    end
                end

                // --- PASS 2: TÍNH TỔNG (Tính sum_val) ---
                S_START_SUM: begin
                    start_sum <= 1;
                    state     <= S_CALC_SUM;
                end
                S_CALC_SUM: begin
                    start_sum <= 0;
                    if (sum_done) begin
                        col_idx <= 0;
                        state   <= S_DIV_READ; 
                    end
                end

                // --- PASS 3: CHIA VÀ GHI KẾT QUẢ ---
                S_DIV_READ: begin
                    state <= S_DIV_WAIT_RAM; 
                end

                S_DIV_WAIT_RAM: begin
                    state <= S_DIV_WAIT_ROM; 
                end

                S_DIV_WAIT_ROM: begin
                    we_Softmax <= 1; // Bật cờ ghi sớm
                    state <= S_DIV_WRITE;
                end

                S_DIV_WRITE: begin
                    we_Softmax <= 0; // Tắt cờ ghi ngay lập tức
                    
                    if (col_idx < 63) begin
                        col_idx <= col_idx + 1;
                        state   <= S_DIV_READ; 
                    end else begin
                        state   <= S_NEXT_ROW; 
                    end
                end

                // --- CHUYỂN HÀNG HOẶC KẾT THÚC ---
                S_NEXT_ROW: begin
                    we_Softmax <= 0;
                    if (row_idx < 63) begin
                        row_idx <= row_idx + 1;
                        state   <= S_START_SUM; // Lặp lại Pass 2 cho hàng mới
                    end else begin
                        state   <= S_DONE;      
                    end
                end

                S_DONE: begin
                    done  <= 1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule