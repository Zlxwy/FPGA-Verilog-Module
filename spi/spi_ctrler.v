/*适合W25Qxx系列芯片读写的SPI通信（SPI模式0）*/
// 目前只有sck线、mosi线、miso线引出，时序正确准备在spi_w25q64模块中实现更多功能
module spi_ctrl #(
    parameter sclk_freq = 50_000_000, //系统时钟频率
    parameter sck_speed = 500_000 //spi_sck的频率
)
(
    input wire sclk,
    input wire nrst,

    input wire[7:0] send_byte,
    output reg[7:0] recv_byte,

    input wire swap_trigger,
    output reg swap_done,

    // output reg cs,
    output reg sck,
    output reg mosi,
    input wire miso
);

reg[31:0] cnt_prescaler;
reg signal_prescaler;
parameter cnt_prescaler_MAX = (sclk_freq / sck_speed / 2) - 1;
parameter cnt_prescaler_MAX_minus_1 = cnt_prescaler_MAX - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX) cnt_prescaler <= 0;
    else cnt_prescaler <= cnt_prescaler + 1;
end
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) signal_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX_minus_1) signal_prescaler <= 1;
    else signal_prescaler <= 0;
end

reg[31:0] step_cnt;
parameter step_cnt_MAX = 17;
reg is_swapping;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) step_cnt <= 0;
    else if(is_swapping && signal_prescaler && step_cnt == step_cnt_MAX) step_cnt <= 0;
    else if(is_swapping && signal_prescaler) step_cnt <= step_cnt + 1;
    else if(is_swapping) step_cnt <= step_cnt;
    else step_cnt <= 0;
end
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) is_swapping <= 0;
    else if(is_swapping && signal_prescaler && step_cnt == step_cnt_MAX) is_swapping <= 0;
    else if(!is_swapping && swap_trigger) is_swapping <= 1;
    else is_swapping <= is_swapping;
end

reg[7:0] reg_send_byte;
reg[7:0] reg_recv_byte;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        sck <= 0;
        mosi <= 0;
        reg_send_byte <= 8'b1111_1111;
        reg_recv_byte <= 8'b1111_1101;
    end
    else if(is_swapping && signal_prescaler) begin
        case(step_cnt)
            0 : begin sck <= 0; reg_send_byte <= send_byte; end
            1 : begin sck <= 0; mosi <= reg_send_byte[7]; end
            2 : begin sck <= 1; reg_recv_byte[7] <= miso; end
            3 : begin sck <= 0; mosi <= reg_send_byte[6]; end
            4 : begin sck <= 1; reg_recv_byte[6] <= miso; end
            5 : begin sck <= 0; mosi <= reg_send_byte[5]; end
            6 : begin sck <= 1; reg_recv_byte[5] <= miso; end
            7 : begin sck <= 0; mosi <= reg_send_byte[4]; end
            8 : begin sck <= 1; reg_recv_byte[4] <= miso; end
            9 : begin sck <= 0; mosi <= reg_send_byte[3]; end
            10: begin sck <= 1; reg_recv_byte[3] <= miso; end
            11: begin sck <= 0; mosi <= reg_send_byte[2]; end
            12: begin sck <= 1; reg_recv_byte[2] <= miso; end
            13: begin sck <= 0; mosi <= reg_send_byte[1]; end
            14: begin sck <= 1; reg_recv_byte[1] <= miso; end
            15: begin sck <= 0; mosi <= reg_send_byte[0]; end
            16: begin sck <= 1; reg_recv_byte[0] <= miso; end
            17: begin sck <= 0; recv_byte <= reg_recv_byte; end
            default: begin sck <= sck; mosi <= mosi; end
        endcase
    end
    else begin
        sck <= sck;
        mosi <= mosi;
        reg_send_byte <= reg_send_byte;
        reg_recv_byte <= reg_recv_byte;
    end
end

always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) swap_done <= 0;
    else if(signal_prescaler && is_swapping && step_cnt == step_cnt_MAX) swap_done <= 1;
    else swap_done <= 0;
end

endmodule