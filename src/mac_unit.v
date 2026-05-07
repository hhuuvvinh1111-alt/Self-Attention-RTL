`timescale 1ns / 1ps

// =============================================================
// Module  : mac_unit
// Chức năng: Multiply-Accumulate (MAC) cho phép nhân ma trận
//            Fixed-point Q8.8, tích lũy 64 phần tử dot-product
//
// Timing với attention_top FSM:
//   S_READ_MEM : clr_acc=1, en=0  → acc_40 bị XÓA VỀ 0 ngay cycle này
//   S_WAIT_MEM : clr_acc=0, en=0  → giữ nguyên (data RAM đang ra)
//   S_MAC_CALC : clr_acc=0, en=1  → bắt đầu tích lũy full_product
//   ...×64...
//   S_WRITE_RAM: clr_acc=0, en=0  → acc_40 giữ nguyên, mac_out hợp lệ
//
// Tại sao clr_acc độc lập với en?
//   attention_top bật clr_acc khi k=0 ở S_READ_MEM (en=0).
//   Nếu clr_acc nằm trong if(en), nó không có tác dụng → acc_40
//   không được reset → kết quả dot-product cộng vào giá trị cũ.
//
// Tại sao dùng 40-bit accumulator?
//   |full_product| ≤ 32767² ≈ 2^30  (Q16.16, 32-bit signed)
//   Cộng dồn 64 lần: tối đa 64 × 2^30 ≈ 2^36
//   → acc_32 tràn số; cần ít nhất 37-bit, dùng 40-bit an toàn.
//
// Ngõ ra mac_out:
//   acc_40 tích lũy Q16.16 → bit[23:8] là kết quả Q8.8.
//   Round-to-nearest: cộng 0x80 (bit[7] = 0.5 LSB) trước khi cắt.
//   mac_out là combinational (wire) → luôn phản ánh acc_40 hiện tại.
// =============================================================

module mac_unit (
    input  wire                  clk,
    input  wire                  rst_n,    // Reset tích cực mức thấp
    input  wire                  en,       // Cho phép tích lũy MAC
    input  wire                  clr_acc,  // Xóa accumulator (độc lập với en)
    input  wire signed [15:0]    a_in,     // Toán hạng A (Q8.8)
    input  wire signed [15:0]    b_in,     // Toán hạng B (Q8.8)
    output wire signed [15:0]    mac_out   // Kết quả (Q8.8), combinational
);

    // ----------------------------------------------------------
    // BƯỚC 1: PHÉP NHÂN TỔ HỢP
    //   a_in × b_in → full_product (Q16.16, 32-bit signed)
    // ----------------------------------------------------------
    wire signed [31:0] full_product;
    assign full_product = a_in * b_in;

    // ----------------------------------------------------------
    // BƯỚC 2: BỘ CỘNG DỒN 40-BIT
    //
    //   clr_acc=1, en=X : xóa acc_40 về 0  (ưu tiên cao nhất)
    //   clr_acc=0, en=1 : cộng dồn full_product
    //   clr_acc=0, en=0 : giữ nguyên
    //
    //   clr_acc KHÔNG phụ thuộc en — khớp đúng timing FSM:
    //   S_READ_MEM bật clr_acc khi en=0 để chuẩn bị cho k=0.
    // ----------------------------------------------------------
    reg signed [39:0] acc_40;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_40 <= 40'sd0;
        end
        else if (clr_acc) begin
            // Xóa accumulator, sẵn sàng cho dot-product mới
            // (en không ảnh hưởng đến bước này)
            acc_40 <= 40'sd0;
        end
        else if (en) begin
            // Cộng dồn: sign-extend full_product 32-bit → 40-bit
            acc_40 <= acc_40 + {{8{full_product[31]}}, full_product};
        end
        // clr_acc=0, en=0: giữ nguyên acc_40
    end

    // ----------------------------------------------------------
    // BƯỚC 3: CẮT BIT NGÕ RA VỚI ROUND-TO-NEAREST
    //   Lấy bit[23:8] của acc_40 (Q8.8 từ tổng Q16.16)
    //   Cộng 0x80 trước để làm tròn về số gần nhất.
    // ----------------------------------------------------------
    wire signed [39:0] acc_rounded;
    assign acc_rounded = acc_40 + 40'sh0000000080;

    assign mac_out = acc_rounded[23:8];

endmodule