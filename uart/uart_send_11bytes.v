// 在模块uart_ctrler的基础上，可连续发送11个字节（发送"COUNT:xxx\r\n"）
module uart_send_11bytes #(
    parameter sys_clk_freq = 50_000_000,
    parameter baudrate = 115200
)
(
    input wire sclk,
    input wire nrst,

    input wire[87:0] send_11bytes,
    input wire send_11bytes_trig,
    output reg send_11bytes_done,

    output wire ch340_tx,
    input wire ch340_rx
);

wire[7:0] UNUSED_rx_byte;
wire UNUSED_rx_done;
uart_ctrler #(
    .sys_clk_freq (sys_clk_freq),
    .baudrate (baudrate)
) uart_ctrler (
    .sclk(sclk),
    .nrst(nrst),

    .tx_trigger(tx_trigger), //传入一个发送触发信号，触发一次串口发送
    .tx_done(tx_done), //发送完成后，输出一个高电平脉冲
    .rx_done(UNUSED_rx_done), //接收完成后，输出一个高电平脉冲

    .tx_byte(tx_byte), //把发送字节传入，这个模块通过tx信号线输出去
    .rx_byte(UNUSED_rx_byte), //这个模块通过rx信号线接收到一个字节后，把这个接收到的字节传出

    .tx(ch340_tx), //发送信号线
    .rx(ch340_rx) //接收信号线
);

reg[16:0] send_step_cnt;
parameter send_step_cnt_MAX = 11;
reg is_sending_11bytes;
wire tx_done;
// send_step_cnt
/*在发送11个字节时，以信号tx_done || first_operation_signal推动步骤进行，不断轮转下一步，轮到最后一步后完成发送，归零*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) send_step_cnt <= 0;
    else if(is_sending_11bytes && (tx_done || first_operation_signal) && send_step_cnt == send_step_cnt_MAX) send_step_cnt <= 0;
    else if(is_sending_11bytes && (tx_done || first_operation_signal)) send_step_cnt <= send_step_cnt + 1;
    else if(is_sending_11bytes) send_step_cnt <= send_step_cnt;
    else send_step_cnt <= 0;
end

// is_sending_11bytes
/*在发送11个字节时，is_sending_11bytes会一直保持高电平*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) is_sending_11bytes <= 0;
    else if(is_sending_11bytes && (tx_done || first_operation_signal) && send_step_cnt == send_step_cnt_MAX) is_sending_11bytes <= 0;
    else if(!is_sending_11bytes && send_11bytes_trig) is_sending_11bytes <= 1;
    else is_sending_11bytes <= is_sending_11bytes;
end

reg first_operation_signal;
// first_operation_signal
/*因为在is_xxxxing_3bytes被置起后，都要靠xxxx_done来驱动步骤进行，而第一个步骤还没有任何驱动，需要自行添加一个脉冲来起始*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) first_operation_signal <= 0;
    else if(!is_sending_11bytes && send_11bytes_trig) first_operation_signal <= 1;
    else first_operation_signal <= 0;
end

reg[7:0] tx_byte;
reg tx_trigger;
// tx_byte, tx_trigger
/*将需要发送的字节输入uart_ctrler模块，同时输入一个发送触发信号*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        tx_byte <= 0;
        tx_trigger <= 0;
    end
    else if(is_sending_11bytes && (first_operation_signal || tx_done)) begin
        case(send_step_cnt)
            0 : begin tx_byte <= send_11bytes[87:80]; tx_trigger <= 1; end
            1 : begin tx_byte <= send_11bytes[79:72]; tx_trigger <= 1; end
            2 : begin tx_byte <= send_11bytes[71:64]; tx_trigger <= 1; end
            3 : begin tx_byte <= send_11bytes[63:56]; tx_trigger <= 1; end
            4 : begin tx_byte <= send_11bytes[55:48]; tx_trigger <= 1; end
            5 : begin tx_byte <= send_11bytes[47:40]; tx_trigger <= 1; end
            6 : begin tx_byte <= send_11bytes[39:32]; tx_trigger <= 1; end
            7 : begin tx_byte <= send_11bytes[31:24]; tx_trigger <= 1; end
            8 : begin tx_byte <= send_11bytes[23:16]; tx_trigger <= 1; end
            9 : begin tx_byte <= send_11bytes[15: 8]; tx_trigger <= 1; end
            10: begin tx_byte <= send_11bytes[ 7: 0]; tx_trigger <= 1; end
            // 11: begin  end
            default: begin tx_byte <= tx_byte; tx_trigger <= tx_trigger; end
        endcase
    end
    else begin
        tx_byte <= tx_byte;
        tx_trigger <= 0;
    end
end

// send_11bytes_done
/*在11个字节发送完成后，产生一个持续一个时钟周期的高电平脉冲*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) send_11bytes_done <= 0;
    else if(is_sending_11bytes && (tx_done || first_operation_signal) && send_step_cnt == send_step_cnt_MAX) send_11bytes_done <= 1;
    else send_11bytes_done <= 0;
end

endmodule