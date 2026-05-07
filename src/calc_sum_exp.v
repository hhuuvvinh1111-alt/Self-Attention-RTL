`timescale 1ns / 1ps

module calc_sum_exp (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    
    // Chỉ định hàng đang xử lý
    input  wire [5:0]           row_idx,    
    
    // Giá trị Max (Nhận từ khối find_max_unit)
    input  wire signed [15:0]   max_val,    

    // Tín hiệu ngõ ra
    output reg                  done,
    output reg  [31:0]          sum_val,    // Mẫu số (Cộng dồn 64 giá trị e^x)

    // Giao tiếp với RAM Score (Chỉ đọc)
    output wire [11:0]          addr_Score,
    input  wire signed [15:0]   data_Score,

    // Giao tiếp với ROM e^x (Chỉ đọc)
    output wire [12:0]          addr_Exp,   // ROM có 4097 words -> cần 13 bit
    input  wire [15:0]          data_Exp    // Giá trị e^x (Luôn dương, Q8.8)
);

    // ==========================================
    // 1. TẠO ĐỊA CHỈ CHO RAM SCORE
    // ==========================================
    reg [5:0] col;
    assign addr_Score = {row_idx, col};

    // ==========================================
    // 2. MẠCH TỔ HỢP: TÍNH x_norm VÀ ÁNH XẠ ĐỊA CHỈ ROM
    // ==========================================
    // BÍ KÍP: Mở rộng lên 17-bit có dấu để tránh lỗi tràn số khi trừ 2 số 16-bit
    wire signed [16:0] ext_score = {data_Score[15], data_Score};
    wire signed [16:0] ext_max   = {max_val[15], max_val};
    
    // Tính x_norm = score_val - max_val (Kết quả luôn <= 0)
    wire signed [16:0] x_norm    = ext_score - ext_max;

    // Ánh xạ địa chỉ: Cộng thêm 4096 (Tương đương 16.0 trong Q8.8)
    wire signed [16:0] addr_raw  = x_norm + 17'd4096;

    // KẸP ĐỊA CHỈ (Clamping): Bảo vệ ROM khỏi bị crash
    // Nếu addr_raw bị âm (bit [16] = 1), ép địa chỉ về 0 (tương ứng e^x = 0)
    // Nếu không, lấy 13 bit dưới cùng đưa vào ROM.
    // Kẹp 2 chiều: Bảo vệ ROM tuyệt đối
    assign addr_Exp = (addr_raw[16] == 1'b1)      ? 13'd0 : 
                      (addr_raw[12:0] > 13'd4096) ? 13'd4096 : 
                      addr_raw[12:0];
    // ==========================================
    // 3. MÁY TRẠNG THÁI (FSM)
    // ==========================================
    localparam S_IDLE      = 3'd0,
               S_READ_RAM  = 3'd1,
               S_WAIT_RAM  = 3'd2,
               S_WAIT_ROM  = 3'd3,
               S_ACCUM     = 3'd4,
               S_DONE      = 3'd5;

    reg [2:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            done    <= 0;
            col     <= 0;
            sum_val <= 32'd0;
        end 
        else begin
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        col     <= 0;
                        sum_val <= 32'd0; // Reset lại bộ cộng dồn
                        state   <= S_READ_RAM;
                    end
                end

                S_READ_RAM: begin
                    // Ở nhịp này, addr_Score đã được đẩy vào RAM
                    state <= S_WAIT_RAM;
                end

                S_WAIT_RAM: begin
                    // Ở nhịp này, RAM trả data_Score ra.
                    // Mạch tổ hợp (phần 2) lập tức tính x_norm và đẩy addr_Exp vào ROM!
                    state <= S_WAIT_ROM;
                end

                S_WAIT_ROM: begin
                    // Ở nhịp này, ROM đang dò bảng để lấy dữ liệu.
                    state <= S_ACCUM;
                end

                S_ACCUM: begin
                    // ROM đã trả data_Exp ra. Ta tiến hành cộng dồn.
                    // (Mở rộng data_Exp lên 32-bit không dấu để cộng)
                    sum_val <= sum_val + {16'd0, data_Exp};
                    
                    if (col < 63) begin
                        col   <= col + 1;
                        state <= S_READ_RAM;
                    end else begin
                        state <= S_DONE;
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