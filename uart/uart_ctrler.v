/*串口发送接收模块*/
// 如何使用这个驱动？
// 发送字节操作，在tx_byte上放上要发送的字节，然后在tx_trigger上输入一个高电平脉冲，
// 发送完成后，会在tx_done上输出一个高电平脉冲。
// 接收字节操作，当接收到一个字节后，会在rx_done上输出一个高电平脉冲，然后在rx_byte上读取接收字节就行了。
module uart_ctrler #(
    parameter sys_clk_freq = 50_000_000,
    parameter baudrate = 115200
)
(
    input wire sclk,
    input wire nrst,

    input wire[7:0] tx_byte,    //把发送字节传入，这个模块通过tx信号线输出去
    input wire tx_trigger,      //传入一个发送触发信号，触发一次串口发送
    output reg tx_done,         //发送完成后，输出一个高电平脉冲

    output reg rx_done,         //接收完成后，输出一个高电平脉冲
    output reg[7:0] rx_byte,    //这个模块通过rx信号线接收到一个字节后，把这个接收到的字节传出

    output reg tx,              //发送信号线
    input wire rx               //接收信号线
);

reg[31:0] cnt_tx;
parameter cnt_tx_MAX = (sys_clk_freq / baudrate) - 1;
parameter cnt_tx_MAX_minus_1 = cnt_tx_MAX - 1;
reg signal_tx;
reg is_traning;
reg[31:0] uart_tx_time_cnt;
parameter uart_tx_time_cnt_MAX = 9;//计数最大值

// cnt_tx
/*cnt_tx在[0,cnt_tx_MAX]范围之间循环计数*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                       cnt_tx <= 0;
    else if(cnt_tx == cnt_tx_MAX)       cnt_tx <= 0;
    else                                cnt_tx <= cnt_tx + 1;
end

// signal_tx
/*在cnt_tx计数到次大值时，拉高signal_tx并保持一个时钟周期，由此产生一个高电平脉冲。这个高电平脉冲推动uart发送时序进行*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                           signal_tx <= 0;
    else if(cnt_tx == cnt_tx_MAX_minus_1)   signal_tx <= 1;
    else                                    signal_tx <= 0;
end

// is_traning
/*在检测到tx_trigger后，会拉高is_traning信号，直到该字节发送结束（uart_tx_time_cnt计数到最大值）*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        is_traning <= 0;
    else if(!is_traning && tx_trigger)//检测到tx_trigger
        is_traning <= 1;//拉高is_traning（这个高电平会持续到这个字节发送完成）
    else if(signal_tx && is_traning && uart_tx_time_cnt == uart_tx_time_cnt_MAX)//在signal_tx下，正在发送且uart_tx_time_cnt计数到最大值
        is_traning <= 0;//拉低is_traning
    else
        is_traning <= is_traning;
end

// uart_tx_time_cnt
/*在is_traning信号有效时，uart_tx_time_cnt依托于signal_tx信号不断自增，加到最大值后归零并停止，也就代表此次发送结束*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        uart_tx_time_cnt <= 0;
    else if(signal_tx && is_traning && uart_tx_time_cnt == uart_tx_time_cnt_MAX)//在signal_tx下，正在发送且uart_tx_time_cnt计数到最大值
        uart_tx_time_cnt <= 0;//归零
    else if(signal_tx && is_traning)//在signal_tx下，正在发送但未到最大值
        uart_tx_time_cnt <= uart_tx_time_cnt + 1;//自加1
    else
        uart_tx_time_cnt <= uart_tx_time_cnt;
end

reg[7:0] reg_tran_byte;
// tx, reg_tran_byte
/*在is_traning有效时，依托于signal_tx检测uart_tx_time_cnt的值，相应地控制tx信号线输出数据*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        tx <= 1;
        reg_tran_byte <= 8'b1111_1111;
    end
    else if(!is_traning && tx_trigger) begin//发现触发信号
        reg_tran_byte <= tx_byte;//填充发送字节
    end
    else if(is_traning && signal_tx) begin
        case(uart_tx_time_cnt)
            0: begin tx <= 0;                   end//起始信号，并把发送数据转入reg_tran_byte
            1: begin tx <= reg_tran_byte[0];    end//低位先行
            2: begin tx <= reg_tran_byte[1];    end
            3: begin tx <= reg_tran_byte[2];    end
            4: begin tx <= reg_tran_byte[3];    end
            5: begin tx <= reg_tran_byte[4];    end
            6: begin tx <= reg_tran_byte[5];    end
            7: begin tx <= reg_tran_byte[6];    end
            8: begin tx <= reg_tran_byte[7];    end
            9: begin tx <= 1;                   end//停止信号
            default: begin tx <= tx;            end
        endcase
    end
    else begin
        tx <= tx;
        reg_tran_byte <= reg_tran_byte;
    end
end

// tx_done
/*在一个字节发送结束（uart_tx_time_cnt计数到最大值）后，把tx_done拉高一个时钟周期*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        tx_done <= 0;
    else if(is_traning && signal_tx && uart_tx_time_cnt == uart_tx_time_cnt_MAX)//在signal_tx下，正在发送且uart_tx_time_cnt计数到最大值
        tx_done <= 1;//拉高tx_done
    else
        tx_done <= 0;
end










reg[31:0] cnt_rx;
parameter cnt_rx_MAX = (sys_clk_freq / baudrate / 2) - 1;//用波特率2倍的频率
parameter cnt_rx_MAX_minus_1 = cnt_rx_MAX - 1;
reg[31:0] signal_rx;
reg is_recving;
reg[31:0] uart_rx_time_cnt;
parameter uart_rx_time_cnt_MAX = 17;
// cnt_rx
/*在is_recving有效时，cnt_rx在[0,cnt_rx_MAX]范围之间循环计数；is_recving无效时，cnt_rx一直为0*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        cnt_rx <= 0;
    else if(!is_recving)
        cnt_rx <= 0;
    else if(is_recving && cnt_rx == cnt_rx_MAX)
        cnt_rx <= 0;
    else if(is_recving)
        cnt_rx <= cnt_rx + 1;
    else
        cnt_rx <= cnt_rx;
end

// signal_rx
/*在is_recving有效且cnt_rx计数到(cnt_rx_MAX-1)时，拉高signal_rx，其余时间signal_rx为0*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        signal_rx <= 0;
    else if(is_recving && cnt_rx == cnt_rx_MAX_minus_1)
        signal_rx <= 1;
    else
        signal_rx <= 0;
end

// is_recving
/*在空闲状态时，检测到rx信号线为低电平，开始拉高is_recving，即将接收一个字节。当接收结束（uart_rx_time_cnt计数到最大值）后，拉低is_recving*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        is_recving <= 0;
    else if(!is_recving && !rx)
        is_recving <= 1;
    else if(signal_rx && is_recving && uart_rx_time_cnt == uart_rx_time_cnt_MAX)
        is_recving <= 0;
    else
        is_recving <= is_recving;
end

// uart_rx_time_cnt
/*在is_recving有效时，uart_rx_time_cnt依托于signal_rx信号不断自增，加到最大值后归零并停止，也就代表此次接收结束*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        uart_rx_time_cnt <= 0;
    else if(!is_recving)
        uart_rx_time_cnt <= 0;
    else if(is_recving && signal_rx && uart_rx_time_cnt == uart_rx_time_cnt_MAX)
        uart_rx_time_cnt <= 0;
    else if(is_recving && signal_rx)
        uart_rx_time_cnt <= uart_rx_time_cnt + 1;
    else
        uart_rx_time_cnt <= uart_rx_time_cnt;
end

reg[7:0] reg_recv_byte;
// reg_recv_byte
/*在is_recving有效时，依托于signal_rx检测uart_rx_time_cnt，在指定数值时接收rx信号线上的电平，*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        reg_recv_byte <= 0;
    else if(is_recving && signal_rx) begin
        case(uart_rx_time_cnt)
             2: begin reg_recv_byte[0] <= rx; end
             4: begin reg_recv_byte[1] <= rx; end
             6: begin reg_recv_byte[2] <= rx; end
             8: begin reg_recv_byte[3] <= rx; end
            10: begin reg_recv_byte[4] <= rx; end
            12: begin reg_recv_byte[5] <= rx; end
            14: begin reg_recv_byte[6] <= rx; end
            16: begin reg_recv_byte[7] <= rx; end
            default: begin reg_recv_byte <= reg_recv_byte; end
        endcase
    end
    else
        reg_recv_byte <= reg_recv_byte;
end

// rx_byte
/*在接收字节结束（uart_rx_time_cnt计数到最大值）后，把接收到的字节放到输出端口*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        rx_byte <= 8'b1111_1111;
    else if(is_recving && signal_rx && uart_rx_time_cnt == uart_rx_time_cnt_MAX)
        rx_byte <= reg_recv_byte;
    else
        rx_byte <= rx_byte;
end

// rx_done
/*在接收字节结束（uart_rx_time_cnt计数到最大值）后，把rx_done拉高一个时钟周期*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        rx_done <= 0;
    else if(is_recving && signal_rx && uart_rx_time_cnt == uart_rx_time_cnt_MAX)
        rx_done <= 1;
    else
        rx_done <= 0;
end

endmodule