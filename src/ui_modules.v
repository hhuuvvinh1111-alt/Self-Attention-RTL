`timescale 1ns / 1ps

// ==========================================
// 1. MẠCH CHỐNG DỘI PHÍM & BẮT XUNG CẠNH
// ==========================================
module button_debouncer (
    input  wire clk,
    input  wire btn_in,    // Tín hiệu thô từ nút nhấn
    output reg  btn_edge   // Xung sạch 1 nhịp clock khi nút ĐƯỢC NHẤN XUỐNG
);
    reg [19:0] count;
    reg btn_sync_0, btn_sync_1, btn_state;

    always @(posedge clk) begin
        // Đồng bộ hóa chống nhiễu lây chéo (Metastability)
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
        btn_edge   <= 1'b0; // Mặc định tắt cờ báo

        if (btn_state != btn_sync_1) begin
            count <= count + 1;
            if (count == 20'hFFFFF) begin // Đợi khoảng 20ms
                btn_state <= btn_sync_1;
                if (btn_sync_1 == 1'b0)   // Nút bị nhấn xuống (Mức 0)
                    btn_edge <= 1'b1;     // Bắn 1 xung ra ngoài
                count <= 0;
            end
        end else begin
            count <= 0;
        end
    end
endmodule

// ==========================================
// 2. MẠCH GIẢI MÃ LED 7 ĐOẠN (HEX TO 7-SEG)
// ==========================================
module hex_decoder(
    input  wire [3:0] hex_in,
    output reg  [6:0] segments
);
    // 0 = Sáng, 1 = Tắt (Chân Active-Low)
    always @(*) begin
        case(hex_in)
            4'h0: segments = 7'b1000000;
            4'h1: segments = 7'b1111001;
            4'h2: segments = 7'b0100100;
            4'h3: segments = 7'b0110000;
            4'h4: segments = 7'b0011001;
            4'h5: segments = 7'b0010010;
            4'h6: segments = 7'b0000010;
            4'h7: segments = 7'b1111000;
            4'h8: segments = 7'b0000000;
            4'h9: segments = 7'b0010000;
            4'hA: segments = 7'b0001000;
            4'hB: segments = 7'b0000011;
            4'hC: segments = 7'b1000110;
            4'hD: segments = 7'b0100001;
            4'hE: segments = 7'b0000110;
            4'hF: segments = 7'b0001110;
            default: segments = 7'b1111111;
        endcase
    end
endmodule