`timescale 1ns / 1ps

module tb_system_top();

    // ==========================================
    // 1. KHAI BÁO TÍN HIỆU
    // ==========================================
    reg  clk;
    reg  rst_n;
    reg  uart_rx_pin;
    
    wire uart_tx_pin;
    wire [3:0] led;

    // ==========================================
    // 2. GỌI MODULE SYSTEM TOP (UUT)
    // ==========================================
    system_top uut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .led(led)
    );

    // ==========================================
    // 3. TẠO XUNG CLOCK (50MHz -> Chu kỳ 20ns)
    // ==========================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk; 
    end

    // ==========================================
    // 4. CẤU HÌNH GIAO THỨC UART (LAPTOP MOCK)
    // ==========================================
    localparam BAUD_RATE  = 115200; 
    localparam BIT_PERIOD = 1_000_000_000 / BAUD_RATE; 

    // Hàm giả lập Laptop truyền 1 Byte
    task send_byte;
        input [7:0] data;
        integer i;
        begin
            uart_rx_pin = 1'b0; // Start Bit
            #(BIT_PERIOD);
            
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx_pin = data[i]; // Data Bits
                #(BIT_PERIOD);
            end
            
            uart_rx_pin = 1'b1; // Stop Bit
            #(BIT_PERIOD);
        end
    endtask

    // ==========================================
    // 5. MÁY TRẠNG THÁI NHẬN DỮ LIỆU TỪ FPGA (MONITOR)
    // ==========================================
    reg [7:0] recv_byte;
    integer   recv_count = 0;
    integer   bit_idx = 0;

    always @(negedge uart_tx_pin) begin
        if (rst_n) begin
            #(BIT_PERIOD / 2); // Chờ đến giữa Start Bit
            if (uart_tx_pin == 1'b0) begin 
                #(BIT_PERIOD); // Nhảy đến Data Bit 0
                for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                    recv_byte[bit_idx] = uart_tx_pin;
                    #(BIT_PERIOD);
                end
                
                if (recv_count % 2 == 0)
                    $display("[%0t ns] [FPGA -> PC] Nhận Byte CAO: 8'h%h", $time, recv_byte);
                else
                    $display("[%0t ns] [FPGA -> PC] Nhận Byte THẤP: 8'h%h", $time, recv_byte);
                
                recv_count = recv_count + 1;
            end
        end
    end

    // ==========================================
    // 6. KỊCH BẢN TEST MINI (CHỈ 8 WORDS / MA TRẬN)
    // ==========================================
    integer w;
    initial begin
        rst_n = 0;
        uart_rx_pin = 1;
        
        #100; rst_n = 1; #100;

        $display("=================================================");
        $display("🚀 BẮT ĐẦU TEST MINI HỆ THỐNG FULL SOC");
        $display("=================================================");
        
        // --- Truyền 8 words cho X ---
        $display(">>> Đang truyền 8 words cho X ...");
        for (w = 0; w < 8; w = w + 1) begin
            send_byte(8'h11); send_byte(w[7:0]); 
        end
        
        // --- Truyền 8 words cho Wq ---
        $display(">>> Đang truyền 8 words cho Wq ...");
        for (w = 0; w < 8; w = w + 1) begin
            send_byte(8'h22); send_byte(w[7:0]);
        end

        // --- Truyền 8 words cho Wk ---
        $display(">>> Đang truyền 8 words cho Wk ...");
        for (w = 0; w < 8; w = w + 1) begin
            send_byte(8'h33); send_byte(w[7:0]);
        end

        // --- Truyền 8 words cho Wv ---
        $display(">>> Đang truyền 8 words cho Wv ...");
        for (w = 0; w < 8; w = w + 1) begin
            send_byte(8'h44); send_byte(w[7:0]);
        end

        $display("=================================================");
        $display("✅ PC GỬI XONG. ĐỢI LÕI AI CHẠY VÀ TRẢ VỀ...");
        $display("=================================================");
        
        // Chỉ đợi nhận đúng 16 bytes (8 words) từ FPGA trả về
        wait (recv_count == 16);
        
        $display("=================================================");
        $display("🎉 TEST MINI HOÀN TẤT THÀNH CÔNG!");
        $display("=================================================");
        $stop;
    end

endmodule