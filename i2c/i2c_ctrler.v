/*这是个i2c读写驱动，只能完成指定地址单独写、指定地址单独读两个操作。*/
// 如何使用这个驱动？
// 写操作需要输入器件地址、寄存器地址、写入字节数据，然后在write_trigger上给个高电平脉冲，
// 写操作完成后，就会在write_done上输出一个高电平脉冲。
// 读操作需要输入器件地址、寄存器地址，然后在read_trigger上给个高电平脉冲，
// 读操作完成后，就会在read_done上输出一个高电平脉冲，此时就可以读取read_byte上的输出了。
module i2c_ctrler #(
    parameter sys_clk_freq = 50_000_000,    //系统时钟频率，默认是50MHz
    parameter i2c_clk_speed = 400_000       //SCL时钟速度，默认400kHz
    // 如何计算一次读操作的时间？：(38.5 / i2c_clk_speed) second （默认值的话为96.25us.10390Hz）
    // = (1/sys_clk_freq) * (sys_clk_freq/i2c_clk_speed)/4 * i2c_read_time_cnt_MAX
    // 如何计算一次写操作的时间？：(28.5 / i2c_clk_speed) second （默认值的话为71.25us.14035Hz）
    // = (1/sys_clk_freq) * (sys_clk_freq/i2c_clk_speed)/4 * i2c_write_time_cnt_MAX
)
(
    input   wire        sclk,
    input   wire        nrst,

    input   wire[6:0]   equi_addr,      //从机未左移的原7位地址
    input   wire[7:0]   reg_addr,       //要读/写寄存器的地址
    input   wire[7:0]   write_byte,     //要写入的数据
    output  reg[7:0]    read_byte,      //进行读操作后读取到的一个字节

    input   wire        write_trigger,  //输入一个高电平脉冲，开始一次写操作
    input   wire        read_trigger,   //输入一个高电平脉冲，开始一次读操作
    //（如果同时输入这两个触发信号，则系统不会响应）
    output  reg         write_done,     //此信号默认为低电平，当写操作完成后，产生一个维持一个时钟周期的高电平脉冲
    output  reg         read_done,      //此信号默认为低电平，当读操作完成后，产生一个维持一个时钟周期的高电平脉冲
    // output  reg         i2c_error,      //若传输异常，这个信号会以100ms间隔翻转电平

    output  wire        scl,    //若为数据1时，输出高阻态z；若为数据0时，输出低电平（开漏输出）
    inout   wire        sda     //若为数据1时，输出高阻态z；若为数据0时，输出低电平（开漏输出）
);

wire[7:0] addr_write;
wire[7:0] addr_read;
assign addr_write = {equi_addr, 1'b0};  //从机写地址（把最后一位置0）
assign addr_read  = {equi_addr, 1'b1};  //从机读地址（把最后一位置1）

/* 以下这些东西，只需要知道：
 * 若要让SCL输出逻辑1或逻辑0，只需将scl_out_reg置1或置0即可
 * 若要控制SDA的输出，先要将sda_ctrl置1，然后才能将sda_out_reg相应地置1或置0
 * 若要读取SDA的输入，先要将sda_strl置0，然后才能读取sda_in_reg
 * （这样子设置是为了让引脚模拟开漏输出，而不是推挽式地输出） */
reg sda_ctrl;       //当SDA被主机控制时，sda_ctrl为1；若为从机控制，sda_ctrl为0
reg sda_out_reg;    //当sda_ctrl为1时，控制这个sda_out_reg，来间接控制sda的输出
wire sda_in_reg;    //当sda_ctrl为0时，读取这个sda_in_reg，来间接获取sda的输入
/*当sda_ctrl使能时，如果sda_out_reg为1，则sda输出高阻态，如果sda_out_reg为0，则sda输出低电平*/
assign sda = (sda_ctrl == 1'b1) ? ((sda_out_reg==1'b1)?1'bz:1'b0) : 1'bz;   //这里控制sda的输出
assign sda_in_reg = sda;                                                    //这里读取sda的输入
reg scl_out_reg;
/*如果scl_out_reg为1，则scl输出高阻态，如果scl_out_reg为0，则scl输出低电平*/
assign scl = (scl_out_reg == 1'b1) ? 1'bz : 1'b0;

reg[31:0] cnt_prescaler;
// cnt_prescaler
/*对系统时钟进行分频，得到一个 (能使得scl的频率等于i2c_clk_speed) 的分频计数值*/
parameter cnt_prescaler_MAX = (sys_clk_freq / i2c_clk_speed / 4) - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                               cnt_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX) cnt_prescaler <= 0;
    else                                        cnt_prescaler <= cnt_prescaler + 1;
end

reg signal_prescaler;
// signal_prescaler
/*在cnt_prescaler计数到次大值时，拉高signal_prescaler保持一个时钟周期，产生一个高电平脉冲。推动i2c时序进行*/
parameter cnt_prescaler_MAX_minus_1 = cnt_prescaler_MAX - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                                       signal_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX_minus_1) signal_prescaler <= 1;
    else                                                signal_prescaler <= 0;
end

reg[31:0] i2c_time_cnt;
reg is_writing; //是否在进行写入操作，是的话为高电平，否的话低电平
reg is_reading; //是否在进行读取操作，是的话为高电平，否的话低电平
parameter i2c_write_time_cnt_MAX = 113;
parameter i2c_read_time_cnt_MAX = 153;
// i2c_time_cnt
/* 在is_writing或is_reading为1时，i2c_time_cnt依托于信号signal_prescaler进行向上计数
 * 当is_writing时，i2c_time_cnt计到113归零
 * 当is_reading时，i2c_time_cnt计到153归零 */
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                                                   i2c_time_cnt <= 0;
    
    /*当在写操作时，i2c_time_cnt计到113，则写操作结束，i2c_time_cnt归零*/
    else if(is_writing && signal_prescaler && i2c_time_cnt == i2c_write_time_cnt_MAX)  i2c_time_cnt <= 0;
    else if(is_writing && signal_prescaler)                             i2c_time_cnt <= i2c_time_cnt + 1;
    else if(is_writing)                                                 i2c_time_cnt <= i2c_time_cnt;

    /*当在读操作时，i2c_time_cnt计到153，则读操作结束，i2c_time_cnt归零*/
    else if(is_reading && signal_prescaler && i2c_time_cnt == i2c_read_time_cnt_MAX)    i2c_time_cnt <= 0;
    else if(is_reading && signal_prescaler)                             i2c_time_cnt <= i2c_time_cnt + 1;
    else if(is_reading)                                                 i2c_time_cnt <= i2c_time_cnt;

    /*如果is_writing和is_reading都为0，则i2c_time_cnt一直为0*/
    else                                                            i2c_time_cnt <= 0;
end

// is_writing, is_reading
/*在这个always块中，检测i2c_time_cnt和读写触发信号xxxx_trigger，控制is_writing和is_reading*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        is_writing <= 0; // is_writing默认为0
        is_reading <= 0; // is_reading默认为0
    end

    /*当在读写操作时，i2c_time_cnt计到指定数值，则读写结束*/
    else if(is_writing && signal_prescaler && i2c_time_cnt == i2c_write_time_cnt_MAX) is_writing <= 0;//计到113，写操作结束
    else if(is_reading && signal_prescaler && i2c_time_cnt == i2c_read_time_cnt_MAX) is_reading <= 0;//计到153，读操作结束

    /*当不在进行读写操作，且同时发现两个触发信号时，则不做反应*/
    else if(!is_writing && !is_reading && write_trigger && read_trigger) begin
        is_reading <= is_reading;
        is_writing <= is_writing;
    end
    /*当不在进行读写操作，且只发现一个触发信号时，则置对应的is_xxxxing为1*/
    else if(!is_writing && !is_reading && write_trigger) is_writing <= 1;
    else if(!is_writing && !is_reading && read_trigger)  is_reading <= 1;

    /*其他情况*/
    else begin
        is_writing <= is_writing;
        is_reading <= is_reading;
    end
end

reg[7:0] reg_send_byte;     //写入数据寄存器，把准备发送的字节先存入这个reg_send_byte，先是设备地址，再是寄存器地址、最后是写入数据
reg[7:0] reg_recv_byte;     //读取数据寄存器，读取到的数据存入reg_recv_byte，最后读取完成再复制给模块输出read_byte
// scl(scl_out_reg), sda(sda_ctrl, sda_out_reg) 
// reg_send_byte, reg_recv_byte, read_byte
/*执行i2c读写时序*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        scl_out_reg <= 1'b1;                    //SCL输出逻辑1
        sda_ctrl <= 1;                          //启动SDA控制
        sda_out_reg <= 1'b1;                    //SDA输出逻辑1
        reg_send_byte <= 8'b1111_1111;          //给一个默认值
        reg_recv_byte <= 8'b1111_1101;          //给一个默认值
        read_byte <= 8'b1111_1101;              //给一个默认值
    end
    /*在写入状态时，依托于signal_prescaler脉冲信号，检测i2c_time_cnt的值，做相应的动作*/
    else if(is_writing && signal_prescaler) begin
        case(i2c_time_cnt)
            0  : begin sda_ctrl <= 1; sda_out_reg <= 0;                 end
            1  : begin scl_out_reg <= 0; reg_send_byte <= addr_write;   end
            2  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            3  : begin scl_out_reg <= 1;                                end
            5  : begin scl_out_reg <= 0;                                end
            6  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            7  : begin scl_out_reg <= 1;                                end
            9  : begin scl_out_reg <= 0;                                end
            10 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            11 : begin scl_out_reg <= 1;                                end
            13 : begin scl_out_reg <= 0;                                end
            14 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            15 : begin scl_out_reg <= 1;                                end
            17 : begin scl_out_reg <= 0;                                end
            18 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            19 : begin scl_out_reg <= 1;                                end
            21 : begin scl_out_reg <= 0;                                end
            22 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            23 : begin scl_out_reg <= 1;                                end
            25 : begin scl_out_reg <= 0;                                end
            26 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            27 : begin scl_out_reg <= 1;                                end
            29 : begin scl_out_reg <= 0;                                end
            30 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            31 : begin scl_out_reg <= 1;                                end
            33 : begin scl_out_reg <= 0;                                end
            34 : begin sda_ctrl <= 0;                                   end
            35 : begin scl_out_reg <= 1;                                end
            37 : begin scl_out_reg <= 0; reg_send_byte <= reg_addr;     end
            38 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            39 : begin scl_out_reg <= 1;                                end
            41 : begin scl_out_reg <= 0;                                end
            42 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            43 : begin scl_out_reg <= 1;                                end
            45 : begin scl_out_reg <= 0;                                end
            46 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            47 : begin scl_out_reg <= 1;                                end
            49 : begin scl_out_reg <= 0;                                end
            50 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            51 : begin scl_out_reg <= 1;                                end
            53 : begin scl_out_reg <= 0;                                end
            54 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            55 : begin scl_out_reg <= 1;                                end
            57 : begin scl_out_reg <= 0;                                end
            58 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            59 : begin scl_out_reg <= 1;                                end
            61 : begin scl_out_reg <= 0;                                end
            62 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            63 : begin scl_out_reg <= 1;                                end
            65 : begin scl_out_reg <= 0;                                end
            66 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            67 : begin scl_out_reg <= 1;                                end
            69 : begin scl_out_reg <= 0;                                end
            70 : begin sda_ctrl <= 0;                                   end
            71 : begin scl_out_reg <= 1;                                end
            73 : begin scl_out_reg <= 0; reg_send_byte <= write_byte;   end
            74 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            75 : begin scl_out_reg <= 1;                                end
            77 : begin scl_out_reg <= 0;                                end
            78 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            79 : begin scl_out_reg <= 1;                                end
            81 : begin scl_out_reg <= 0;                                end
            82 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            83 : begin scl_out_reg <= 1;                                end
            85 : begin scl_out_reg <= 0;                                end
            86 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            87 : begin scl_out_reg <= 1;                                end
            89 : begin scl_out_reg <= 0;                                end
            90 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            91 : begin scl_out_reg <= 1;                                end
            93 : begin scl_out_reg <= 0;                                end
            94 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            95 : begin scl_out_reg <= 1;                                end
            97 : begin scl_out_reg <= 0;                                end
            98 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            99 : begin scl_out_reg <= 1;                                end
            101: begin scl_out_reg <= 0;                                end
            102: begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            103: begin scl_out_reg <= 1;                                end
            105: begin scl_out_reg <= 0;                                end
            106: begin sda_ctrl <= 0;                                   end
            107: begin scl_out_reg <= 1;                                end
            109: begin scl_out_reg <= 0;                                end
            110: begin sda_ctrl <= 1; sda_out_reg <= 0;                 end
            111: begin scl_out_reg <= 1;                                end
            112: begin sda_ctrl <= 1; sda_out_reg <= 1;                 end
            default: begin scl_out_reg <= scl_out_reg;                  end
        endcase
    end
    
    /*在读取状态时，依托于signal_prescaler脉冲信号，检测i2c_time_cnt的值，做相应的动作*/
    else if(is_reading && signal_prescaler) begin
        case(i2c_time_cnt)
            0  : begin sda_ctrl <= 1; sda_out_reg <= 0;                 end
            1  : begin scl_out_reg <= 0; reg_send_byte <= addr_write;   end
            2  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            3  : begin scl_out_reg <= 1;                                end
            5  : begin scl_out_reg <= 0;                                end
            6  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            7  : begin scl_out_reg <= 1;                                end
            9  : begin scl_out_reg <= 0;                                end
            10 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            11 : begin scl_out_reg <= 1;                                end
            13 : begin scl_out_reg <= 0;                                end
            14 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            15 : begin scl_out_reg <= 1;                                end
            17 : begin scl_out_reg <= 0;                                end
            18 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            19 : begin scl_out_reg <= 1;                                end
            21 : begin scl_out_reg <= 0;                                end
            22 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            23 : begin scl_out_reg <= 1;                                end
            25 : begin scl_out_reg <= 0;                                end
            26 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            27 : begin scl_out_reg <= 1;                                end
            29 : begin scl_out_reg <= 0;                                end
            30 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            31 : begin scl_out_reg <= 1;                                end
            33 : begin scl_out_reg <= 0;                                end
            34 : begin sda_ctrl <= 0;                                   end
            35 : begin scl_out_reg <= 1;                                end
            37 : begin scl_out_reg <= 0; reg_send_byte <= reg_addr;     end
            38 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            39 : begin scl_out_reg <= 1;                                end
            41 : begin scl_out_reg <= 0;                                end
            42 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            43 : begin scl_out_reg <= 1;                                end
            45 : begin scl_out_reg <= 0;                                end
            46 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            47 : begin scl_out_reg <= 1;                                end
            49 : begin scl_out_reg <= 0;                                end
            50 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            51 : begin scl_out_reg <= 1;                                end
            53 : begin scl_out_reg <= 0;                                end
            54 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            55 : begin scl_out_reg <= 1;                                end
            57 : begin scl_out_reg <= 0;                                end
            58 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            59 : begin scl_out_reg <= 1;                                end
            61 : begin scl_out_reg <= 0;                                end
            62 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            63 : begin scl_out_reg <= 1;                                end
            65 : begin scl_out_reg <= 0;                                end
            66 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            67 : begin scl_out_reg <= 1;                                end
            69 : begin scl_out_reg <= 0;                                end
            70 : begin sda_ctrl <= 0;                                   end
            71 : begin scl_out_reg <= 1;                                end
            73 : begin scl_out_reg <= 0;                                end
            74 : begin sda_ctrl <= 1; sda_out_reg <= 1;                 end
            75 : begin scl_out_reg <= 1;                                end
            76 : begin sda_ctrl <= 1; sda_out_reg <= 0;                 end
            77 : begin scl_out_reg <= 0; reg_send_byte <= addr_read;    end
            78 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            79 : begin scl_out_reg <= 1;                                end
            81 : begin scl_out_reg <= 0;                                end
            82 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            83 : begin scl_out_reg <= 1;                                end
            85 : begin scl_out_reg <= 0;                                end
            86 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            87 : begin scl_out_reg <= 1;                                end
            89 : begin scl_out_reg <= 0;                                end
            90 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            91 : begin scl_out_reg <= 1;                                end
            93 : begin scl_out_reg <= 0;                                end
            94 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            95 : begin scl_out_reg <= 1;                                end
            97 : begin scl_out_reg <= 0;                                end
            98 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            99 : begin scl_out_reg <= 1;                                end
            101: begin scl_out_reg <= 0;                                end
            102: begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            103: begin scl_out_reg <= 1;                                end
            105: begin scl_out_reg <= 0;                                end
            106: begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            107: begin scl_out_reg <= 1;                                end
            109: begin scl_out_reg <= 0;                                end
            110: begin sda_ctrl <= 0;                                   end
            111: begin scl_out_reg <= 1;                                end
            113: begin scl_out_reg <= 0;                                end
            115: begin scl_out_reg <= 1; reg_recv_byte <= 8'b1111_1111; end
            116: begin sda_ctrl <= 0; reg_recv_byte[7] = sda_in_reg;    end
            117: begin scl_out_reg <= 0;                                end
            119: begin scl_out_reg <= 1;                                end
            120: begin sda_ctrl <= 0; reg_recv_byte[6] = sda_in_reg;    end
            121: begin scl_out_reg <= 0;                                end
            123: begin scl_out_reg <= 1;                                end
            124: begin sda_ctrl <= 0; reg_recv_byte[5] = sda_in_reg;    end
            125: begin scl_out_reg <= 0;                                end
            127: begin scl_out_reg <= 1;                                end
            128: begin sda_ctrl <= 0; reg_recv_byte[4] = sda_in_reg;    end
            129: begin scl_out_reg <= 0;                                end
            131: begin scl_out_reg <= 1;                                end
            132: begin sda_ctrl <= 0; reg_recv_byte[3] = sda_in_reg;    end
            133: begin scl_out_reg <= 0;                                end
            135: begin scl_out_reg <= 1;                                end
            136: begin sda_ctrl <= 0; reg_recv_byte[2] = sda_in_reg;    end
            137: begin scl_out_reg <= 0;                                end
            139: begin scl_out_reg <= 1;                                end
            140: begin sda_ctrl <= 0; reg_recv_byte[1] = sda_in_reg;    end
            141: begin scl_out_reg <= 0;                                end
            143: begin scl_out_reg <= 1;                                end
            144: begin sda_ctrl <= 0; reg_recv_byte[0] = sda_in_reg;    end
            145: begin scl_out_reg <= 0; read_byte <= reg_recv_byte;    end
            146: begin sda_ctrl <= 1; sda_out_reg <= 1;                 end
            147: begin scl_out_reg <= 1;                                end
            149: begin scl_out_reg <= 0;                                end
            150: begin sda_ctrl <= 1; sda_out_reg <= 0;                 end
            151: begin scl_out_reg <= 1;                                end
            152: begin sda_ctrl <= 1; sda_out_reg <= 1;                 end
            default: begin scl_out_reg <= scl_out_reg;                  end
        endcase
    end
    else begin
        reg_send_byte <= reg_send_byte;
        reg_recv_byte <= reg_recv_byte;
        read_byte <= read_byte;
        scl_out_reg <= scl_out_reg;
        sda_ctrl <= sda_ctrl;
        sda_out_reg <= sda_out_reg;
    end
end

// write_done, read_done
/*为了让is_xxxxing由1转0后，xxxx_done能产生一个维持一个时钟周期的高电平脉冲*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        write_done <= 0;
        read_done <= 0;
    end

    else if(signal_prescaler && is_writing && i2c_time_cnt == i2c_write_time_cnt_MAX)  write_done <= 1;
    else if(signal_prescaler && is_reading && i2c_time_cnt == i2c_read_time_cnt_MAX)  read_done <= 1;

    else begin
        write_done <= 0;
        read_done <= 0;
    end
end

endmodule