//如果读出的数字一直不变，芯片可能处于写保护状态，在0x8E地址写入0x00即可解除写保护状态。
/* 这是一个DS1302时钟芯片的单字节读写模块，该怎么去使用？
 * 写操作：首先在addr输入操作的寄存器地址（只传入写地址即可，若是要读则会自动或上0x01），然后在write_byte输入要写入的字节，
 * 接着在write_trriger给一个触发脉冲信号，写操作完成后，就会在write_done上输出一个脉冲信号。
 * 读操作：还是在addr输入操作的寄存器地址（输入的仍是写地址，会自动或上0x01变为读地址），
 * 然后在read_trigger给一个触发脉冲信号，读操作完成后，就会在read_done上输出一个脉冲信号，在read_byte上读取获取的字节。 */
module ds1302_single_byte_rw #(
    parameter sys_clk_freq = 50_000_000, //系统时钟50MHz
    parameter ds1302_clk_speed = 200_000 //这个指定的是ds1302_sclk的周期频率，默认为0.2MHz
    //如何计算一次读/写操作的时间？：(16.25 / ds1302_clk_speed) second （默认值为81.25us.12308Hz）
    //= (1/sys_clk_freq) * (sys_clk_freq/ds1302_clk_speed/4) * rw_step_cnt_MAX
)
(
    input wire sclk, //系统时钟，50MHz
    input wire nrst, //复位信号，低有效

    input wire[7:0] addr, //读写地址，只传入写地址即可，如果是读地址，会自动或上0x01
    input wire[7:0] write_byte, //写入字节
    output reg[7:0] read_byte, //读取字节

    input wire write_trigger, //写触发信号
    input wire read_trigger, //读触发信号
    output reg write_done, //写操作完成后，产生一个高电平脉冲
    output reg read_done, //读操作完成后，产生一个高电平脉冲
    
    output reg ds1302_ce, //ds1302片选信号
    output reg ds1302_sclk, //ds1302时钟信号
    inout wire ds1302_io //ds1302数据信号，双向IO口
);

/* 若要控制ds1302_io的输出，先要将io_ctrl置1，然后将io_out_reg相应地置1或置0
 * 若要读取ds1302_io的输入，先要将io_ctrl置0，然后在io_in_reg上读取出逻辑值即可 */
reg io_ctrl; //io_ctrl为1时，ds1302_io作为输出；io_ctrl为0时，ds1302_io作为输入
reg io_out_reg; //io_ctrl为1时，通过io_out_reg来间接控制ds1302_io的输出电平
wire io_in_reg; //io_ctrl为0时，通过io_in_reg来间接读取ds1302_io的输入电平
assign ds1302_io = (io_ctrl == 1'b1) ? (io_out_reg) : 1'bz;
assign io_in_reg = ds1302_io; //三态门控制，用以实现双向IO口功能

reg[31:0] cnt_prescaler;
// cnt_prescaler
/*对系统50MHz时钟进行分频，得到一个 (能使得ds1302_sclk的频率等于ds1302_clk_speed) 的分频计数值*/
parameter cnt_prescaler_MAX = (sys_clk_freq / ds1302_clk_speed / 4) - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX) cnt_prescaler <= 0;
    else cnt_prescaler <= cnt_prescaler + 1;
end

reg signal_prescaler;
parameter cnt_prescaler_MAX_minus_1 = cnt_prescaler_MAX - 1;
// signal_prescaler
/*在cnt_prescaler计数到次大值，拉高signal_prescaler保持一个时钟周期，产生一个高电平脉冲，用以推动时序进行*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) signal_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX_minus_1) signal_prescaler <= 1;
    else signal_prescaler <= 0;
end

reg[16:0] rw_step_cnt; //时序计数，基于signal_prescaler信号
parameter write_step_cnt_MAX = 65; //计65个数完成写时序
parameter read_step_cnt_MAX = 65; //计65个数完成读时序
reg is_writing; //是否在进行写入操作，是的话为高电平，否的话低电平
reg is_reading; //是否在进行读取操作，是的话为高电平，否的话低电平
// rw_step_cnt
/* 在is_writing或is_reading为1时，rw_step_cnt依托于信号signal_prescaler进行向上计数
 * 当is_writing时，rw_step_cnt计到65归零
 * 当is_reading时，rw_step_cnt计到65归零 */
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) rw_step_cnt <= 0;

    /*当在写操作时，rw_step_cnt计到65，则写操作结束，rw_step_cnt归零*/
    else if(is_writing && signal_prescaler && rw_step_cnt == write_step_cnt_MAX) rw_step_cnt <= 0;
    else if(is_writing && signal_prescaler) rw_step_cnt <= rw_step_cnt + 1;
    else if(is_writing) rw_step_cnt <= rw_step_cnt;

    /*当在读操作时，rw_step_cnt计到65，则读操作结束，rw_step_cnt归零*/
    else if(is_reading && signal_prescaler && rw_step_cnt == read_step_cnt_MAX) rw_step_cnt <= 0;
    else if(is_reading && signal_prescaler) rw_step_cnt <= rw_step_cnt + 1;
    else if(is_reading) rw_step_cnt <= rw_step_cnt;

    /*如果is_writing和is_reading都为0，则rw_step_cnt一直为0*/
    else rw_step_cnt <= 0;
end

// is_writing, is_reading
/*在这个always块中，检测rw_step_cnt和读写触发信号xxxx_trigger，控制is_writing和is_reading*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        is_writing <= 0; //is_writing默认为0
        is_reading <= 0; //is_reading默认为0
    end

    /*当在读写操作时，rw_step_cnt计数到指定数值，则读写时序结束*/
    else if(is_writing && signal_prescaler && rw_step_cnt == write_step_cnt_MAX) is_writing <= 0;
    else if(is_reading && signal_prescaler && rw_step_cnt == read_step_cnt_MAX) is_reading <= 0;

    /*当不在进行读写操作，且同时发现两个触发信号时，则不做反应*/
    else if(!is_writing && !is_reading && write_trigger && read_trigger) begin
        is_writing <= is_writing;
        is_reading <= is_reading;
    end

    /*当不在进行读写操作，且只发现一个触发信号时，则置对应的is_xxxxing为1*/
    else if(!is_writing && !is_reading && write_trigger) is_writing <= 1;
    else if(!is_writing && !is_reading && read_trigger) is_reading <= 1;

    /*其他情况*/
    else begin
        is_writing <= is_writing;
        is_reading <= is_reading;
    end
end

reg[7:0] reg_send_byte;
reg[7:0] reg_recv_byte;
// ds1302_ce, ds1302_sclk, ds1302_io(io_ctrl, io_out_reg)
// reg_send_byte, reg_recv_byte, read_byte
/*执行DS1302读写时序*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        ds1302_ce <= 0; //使能线低电平
        ds1302_sclk <= 0; //时钟线低电平
        io_ctrl <= 1; //启动IO引脚控制
        io_out_reg <= 1'b0; //默认低电平
        reg_send_byte <= 8'b1111_1111;
        reg_recv_byte <= 8'b1111_1101;
        read_byte <= 8'b1111_1111;
    end
    /*在写入状态时，依托于signal_presacaler脉冲信号，检测rw_step_cnt的值，做相应的时序逻辑*/
    else if(is_writing && signal_prescaler) begin
        case(rw_step_cnt)
            0  : begin
                ds1302_ce <= 1;         //使能线高电平
                ds1302_sclk <= 0;       //时钟线初始低电平
                io_ctrl <= 1;           //启动IO引脚控制
                io_out_reg <= 0;        //控制IO引脚输出低电平
                reg_send_byte <= addr;  //放入即将发送的地址字节
                end
            1  : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[0];    end
            2  : begin ds1302_sclk <= 1;                                end
            4  : begin ds1302_sclk <= 0;                                end
            5  : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[1];    end
            6  : begin ds1302_sclk <= 1;                                end
            8  : begin ds1302_sclk <= 0;                                end
            9  : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[2];    end
            10 : begin ds1302_sclk <= 1;                                end
            12 : begin ds1302_sclk <= 0;                                end
            13 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[3];    end
            14 : begin ds1302_sclk <= 1;                                end
            16 : begin ds1302_sclk <= 0;                                end
            17 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[4];    end
            18 : begin ds1302_sclk <= 1;                                end
            20 : begin ds1302_sclk <= 0;                                end
            21 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[5];    end
            22 : begin ds1302_sclk <= 1;                                end
            24 : begin ds1302_sclk <= 0;                                end
            25 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[6];    end
            26 : begin ds1302_sclk <= 1;                                end
            28 : begin ds1302_sclk <= 0;                                end
            29 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[7];    end
            30 : begin ds1302_sclk <= 1;                                end
            32 : begin ds1302_sclk <= 0; reg_send_byte <= write_byte;   end
            33 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[0];    end
            34 : begin ds1302_sclk <= 1;                                end
            36 : begin ds1302_sclk <= 0;                                end
            37 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[1];    end
            38 : begin ds1302_sclk <= 1;                                end
            40 : begin ds1302_sclk <= 0;                                end
            41 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[2];    end
            42 : begin ds1302_sclk <= 1;                                end
            44 : begin ds1302_sclk <= 0;                                end
            45 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[3];    end
            46 : begin ds1302_sclk <= 1;                                end
            48 : begin ds1302_sclk <= 0;                                end
            49 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[4];    end
            50 : begin ds1302_sclk <= 1;                                end
            52 : begin ds1302_sclk <= 0;                                end
            53 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[5];    end
            54 : begin ds1302_sclk <= 1;                                end
            56 : begin ds1302_sclk <= 0;                                end
            57 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[6];    end
            58 : begin ds1302_sclk <= 1;                                end
            60 : begin ds1302_sclk <= 0;                                end
            61 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[7];    end
            62 : begin ds1302_sclk <= 1;                                end
            64 : begin ds1302_sclk <= 0;                                end
            65 : begin
                ds1302_ce <= 0;
                ds1302_sclk <= 0;
                io_ctrl <= 1;
                io_out_reg <= 0;
            end
            default: begin io_out_reg <= io_out_reg; end
        endcase
    end
    /*在读取状态时，依托于signal_prescaler脉冲信号，检测rw_step_cnt的值，做相应的动作*/
    else if(is_reading && signal_prescaler) begin
        case (rw_step_cnt)
            0  : begin
                ds1302_ce <= 1;         //使能线高电平
                ds1302_sclk <= 0;       //时钟线初始低电平
                io_ctrl <= 1;           //启动IO引脚控制
                io_out_reg <= 0;        //控制IO引脚输出低电平
                reg_send_byte <= addr|8'b0000_0001;  //放入即将发送的地址字节
            end
            1  : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[0];    end
            2  : begin ds1302_sclk <= 1;                                end
            4  : begin ds1302_sclk <= 0;                                end
            5  : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[1];    end
            6  : begin ds1302_sclk <= 1;                                end
            8  : begin ds1302_sclk <= 0;                                end
            9  : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[2];    end
            10 : begin ds1302_sclk <= 1;                                end
            12 : begin ds1302_sclk <= 0;                                end
            13 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[3];    end
            14 : begin ds1302_sclk <= 1;                                end
            16 : begin ds1302_sclk <= 0;                                end
            17 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[4];    end
            18 : begin ds1302_sclk <= 1;                                end
            20 : begin ds1302_sclk <= 0;                                end
            21 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[5];    end
            22 : begin ds1302_sclk <= 1;                                end
            24 : begin ds1302_sclk <= 0;                                end
            25 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[6];    end
            26 : begin ds1302_sclk <= 1;                                end
            28 : begin ds1302_sclk <= 0;                                end
            29 : begin io_ctrl <= 1; io_out_reg <= reg_send_byte[7];    end
            30 : begin ds1302_sclk <= 1;                                end
            32 : begin
                ds1302_sclk <= 0;
                io_ctrl <= 0; //交出IO引脚控制权，开始读取数据输入
                reg_recv_byte <= 8'b1111_1111; //清空接收寄存器
                end
            33 : begin io_ctrl <= 0; reg_recv_byte[0] <= io_in_reg;     end
            34 : begin ds1302_sclk <= 1;                                end
            36 : begin ds1302_sclk <= 0;                                end
            37 : begin io_ctrl <= 0; reg_recv_byte[1] <= io_in_reg;     end
            38 : begin ds1302_sclk <= 1;                                end
            40 : begin ds1302_sclk <= 0;                                end
            41 : begin io_ctrl <= 0; reg_recv_byte[2] <= io_in_reg;     end
            42 : begin ds1302_sclk <= 1;                                end
            44 : begin ds1302_sclk <= 0;                                end
            45 : begin io_ctrl <= 0; reg_recv_byte[3] <= io_in_reg;     end
            46 : begin ds1302_sclk <= 1;                                end
            48 : begin ds1302_sclk <= 0;                                end
            49 : begin io_ctrl <= 0; reg_recv_byte[4] <= io_in_reg;     end
            50 : begin ds1302_sclk <= 1;                                end
            52 : begin ds1302_sclk <= 0;                                end
            53 : begin io_ctrl <= 0; reg_recv_byte[5] <= io_in_reg;     end
            54 : begin ds1302_sclk <= 1;                                end
            56 : begin ds1302_sclk <= 0;                                end
            57 : begin io_ctrl <= 0; reg_recv_byte[6] <= io_in_reg;     end
            58 : begin ds1302_sclk <= 1;                                end
            60 : begin ds1302_sclk <= 0;                                end
            61 : begin io_ctrl <= 0; reg_recv_byte[7] <= io_in_reg;     end
            64 : begin read_byte <= reg_recv_byte;/*OutputTheRecvData*/ end
            65 : begin
                ds1302_ce <= 0;
                ds1302_sclk <= 0;
                io_ctrl <= 1;
                io_out_reg <= 0;
                end
            default: begin io_out_reg <= io_out_reg; end
        endcase
    end
    else begin
        ds1302_ce <= ds1302_ce;
        ds1302_sclk <= ds1302_sclk;
        io_ctrl <= io_ctrl;
        io_out_reg <= io_out_reg;
        reg_send_byte <= reg_send_byte;
        reg_recv_byte <= reg_recv_byte;
        read_byte <= read_byte;
    end
end

// write_done, read_done
/*为了让is_xxxxing由1转0后，xxxx_done能产生一个维持一个时钟周期的高电平脉冲*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        write_done <= 0;
        read_done <= 0;
    end

    else if(signal_prescaler && is_writing && rw_step_cnt == write_step_cnt_MAX) write_done <= 1;
    else if(signal_prescaler && is_reading && rw_step_cnt == read_step_cnt_MAX) read_done <= 1;
    
    else begin
        write_done <= 0;
        read_done <= 0;
    end
end

endmodule