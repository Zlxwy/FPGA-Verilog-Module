/*只做读电压的时序*/
// 如何使用这个驱动？
// 在reaD_trigger端输入一个高电平脉冲，
// 在收到read_done输出的高电平脉冲后，就可以读取voltage的输出了。
module adc_081c021_get_vol # (
    parameter sys_clk_freq = 50_000_000,
    parameter i2c_clk_speed = 400_000
    // 如何计算一次读操作的时间？：(28.5 / i2c_clk_speed) second （默认值的话为71.25us.14035Hz）
    // = (1/sys_clk_freq) * (sys_clk_freq/i2c_clk_speed)/4 * read_step_cnt_MAX
)
(
    input wire sclk,
    input wire nrst,

    input wire read_trigger, //输入一个高电平脉冲信号，触发读取一次数据
    output reg read_done, //读取数据完成后，输出一个高电平脉冲信号
    output reg[7:0] voltage, //读取到的原始8位数值，需要根据参考电压换算出伏特单位的电压值

    output wire scl,
    inout wire sda,
//逻辑分析仪调试---------------------------------------------------------------------|
    output wire DEBUG_scl,
    output wire DEBUG_sda
//逻辑分析仪调试---------------------------------------------------------------------|
);

//逻辑分析仪调试---------------------------------------------------------------------|
assign DEBUG_scl = scl_out_reg;
assign DEBUG_sda = sda_ctrl==1?sda_out_reg:sda_in_reg;
//逻辑分析仪调试---------------------------------------------------------------------|

wire[7:0] equi_addr_read;
assign equi_addr_read = 8'b1010_1001; //8'hAB是读地址（赛方的原理图标记错误了）

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

reg[31:0] read_step_cnt;
reg is_reading;
parameter read_step_cnt_MAX = 113;
// read_step_cnt
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) read_step_cnt <= 0;

    /*在读的时候，read_step_cnt计到最大值，则读操作结束，read_step_cnt归零*/
    else if(is_reading && signal_prescaler && read_step_cnt == read_step_cnt_MAX) read_step_cnt <= 0;
    else if(is_reading && signal_prescaler) read_step_cnt <= read_step_cnt + 1;
    else if(is_reading) read_step_cnt <= read_step_cnt;

    /*没有在读操作，则read_step_cnt一直为0*/
    else read_step_cnt <= 0;
end

// is_reading
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) is_reading <= 0;
    else if(is_reading && signal_prescaler && read_step_cnt == read_step_cnt_MAX) is_reading <= 0;
    else if(!is_reading && read_trigger) is_reading <= 1;
    else is_reading <= is_reading;
end

reg[7:0] reg_send_byte;
reg[15:0] reg_recv_byte;
// scl(scl_out_reg), sda(sda_ctrl, sda_out_reg)
// reg_send_byte, reg_recv_byte, voltage
/*执行读操作时序*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        scl_out_reg <= 1'b1;
        sda_ctrl <= 1;
        sda_out_reg <= 1'b1;
        reg_send_byte <= 8'b1111_1111;
        reg_recv_byte <= 16'b1111_0011_1000_1111;
        voltage <= 0;
    end
    /*在读操作时，依托于signal_prescaler信号，检测read_step_cnt的值，做相应的动作*/
    else if(is_reading && signal_prescaler) begin
        case(read_step_cnt)
        0  : begin sda_ctrl <= 1; sda_out_reg <= 0;                     end
        1  : begin scl_out_reg <= 0; reg_send_byte <= equi_addr_read;   end
        2  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];      end
        3  : begin scl_out_reg <= 1;                                    end
        5  : begin scl_out_reg <= 0;                                    end
        6  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];      end
        7  : begin scl_out_reg <= 1;                                    end
        9  : begin scl_out_reg <= 0;                                    end
        10 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];      end
        11 : begin scl_out_reg <= 1;                                    end
        13 : begin scl_out_reg <= 0;                                    end
        14 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];      end
        15 : begin scl_out_reg <= 1;                                    end
        17 : begin scl_out_reg <= 0;                                    end
        18 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];      end
        19 : begin scl_out_reg <= 1;                                    end
        21 : begin scl_out_reg <= 0;                                    end
        22 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];      end
        23 : begin scl_out_reg <= 1;                                    end
        25 : begin scl_out_reg <= 0;                                    end
        26 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];      end
        27 : begin scl_out_reg <= 1;                                    end
        29 : begin scl_out_reg <= 0;                                    end
        30 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];      end
        31 : begin scl_out_reg <= 1;                                    end
        33 : begin scl_out_reg <= 0;                                    end
        34 : begin sda_ctrl <= 0; sda_out_reg <= 1;                     end
        35 : begin scl_out_reg <= 1;                                    end
        37 : begin scl_out_reg <= 0; reg_recv_byte <= 8'b1111_1111;     end
        39 : begin scl_out_reg <= 1;                                    end
        40 : begin sda_ctrl <= 0; reg_recv_byte[15] <= sda_in_reg;      end
        41 : begin scl_out_reg <= 0;                                    end
        43 : begin scl_out_reg <= 1;                                    end
        44:  begin sda_ctrl <= 0; reg_recv_byte[14] <= sda_in_reg;      end
        45 : begin scl_out_reg <= 0;                                    end
        47 : begin scl_out_reg <= 1;                                    end
        48:  begin sda_ctrl <= 0; reg_recv_byte[13] <= sda_in_reg;      end
        49 : begin scl_out_reg <= 0;                                    end
        51 : begin scl_out_reg <= 1;                                    end
        52:  begin sda_ctrl <= 0; reg_recv_byte[12] <= sda_in_reg;      end
        53 : begin scl_out_reg <= 0;                                    end
        55 : begin scl_out_reg <= 1;                                    end
        56:  begin sda_ctrl <= 0; reg_recv_byte[11] <= sda_in_reg;      end
        57 : begin scl_out_reg <= 0;                                    end
        59 : begin scl_out_reg <= 1;                                    end
        60:  begin sda_ctrl <= 0; reg_recv_byte[10] <= sda_in_reg;      end
        61 : begin scl_out_reg <= 0;                                    end
        63 : begin scl_out_reg <= 1;                                    end
        64:  begin sda_ctrl <= 0; reg_recv_byte[9] <= sda_in_reg;       end
        65 : begin scl_out_reg <= 0;                                    end
        67 : begin scl_out_reg <= 1;                                    end
        68:  begin sda_ctrl <= 0; reg_recv_byte[8] <= sda_in_reg;       end
        69 : begin scl_out_reg <= 0;                                    end
        70 : begin sda_ctrl <= 1; sda_out_reg <= 0;                     end
        71 : begin scl_out_reg <= 1;                                    end
        73 : begin scl_out_reg <= 0;                                    end
        74 : begin sda_ctrl <= 0; sda_out_reg <= 1;                     end
        75 : begin scl_out_reg <= 1;                                    end
        76:  begin sda_ctrl <= 0; reg_recv_byte[7] <= sda_in_reg;       end
        77 : begin scl_out_reg <= 0;                                    end
        79 : begin scl_out_reg <= 1;                                    end
        80:  begin sda_ctrl <= 0; reg_recv_byte[6] <= sda_in_reg;       end
        81 : begin scl_out_reg <= 0;                                    end
        83 : begin scl_out_reg <= 1;                                    end
        84:  begin sda_ctrl <= 0; reg_recv_byte[5] <= sda_in_reg;       end
        85 : begin scl_out_reg <= 0;                                    end
        87 : begin scl_out_reg <= 1;                                    end
        88:  begin sda_ctrl <= 0; reg_recv_byte[4] <= sda_in_reg;       end
        89 : begin scl_out_reg <= 0;                                    end
        91 : begin scl_out_reg <= 1;                                    end
        92:  begin sda_ctrl <= 0; reg_recv_byte[3] <= sda_in_reg;       end
        93 : begin scl_out_reg <= 0;                                    end
        95 : begin scl_out_reg <= 1;                                    end
        96:  begin sda_ctrl <= 0; reg_recv_byte[2] <= sda_in_reg;       end
        97 : begin scl_out_reg <= 0;                                    end
        99 : begin scl_out_reg <= 1;                                    end
        100: begin sda_ctrl <= 0; reg_recv_byte[1] <= sda_in_reg;       end
        101: begin scl_out_reg <= 0;                                    end
        103: begin scl_out_reg <= 1;                                    end
        104: begin sda_ctrl <= 0; reg_recv_byte[0] <= sda_in_reg;       end
        105: begin scl_out_reg <= 0;                                    end
        106: begin sda_ctrl <= 1; sda_out_reg <= 1;                     end
        107: begin scl_out_reg <= 1;                                    end
        109: begin scl_out_reg <= 0;                                    end
        110: begin sda_ctrl <= 1; sda_out_reg <= 0;                     end
        111: begin scl_out_reg <= 1;                                    end
        112: begin sda_ctrl <= 1; sda_out_reg <= 1;                     end
        113: begin voltage <= reg_recv_byte[11:4];                      end
        default: begin
            scl_out_reg <= scl_out_reg;
            sda_ctrl <= sda_ctrl;
            sda_out_reg <= sda_out_reg;
            reg_send_byte <= reg_send_byte;
            reg_recv_byte <= reg_recv_byte;
            voltage <= voltage;
        end
        endcase
    end
    else begin
        scl_out_reg <= scl_out_reg;
        sda_ctrl <= sda_ctrl;
        sda_out_reg <= sda_out_reg;
        reg_send_byte <= reg_send_byte;
        reg_recv_byte <= reg_recv_byte;
        voltage <= voltage;
    end
end

// read_done
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) read_done <= 0;
    else if(signal_prescaler && is_reading && read_step_cnt == read_step_cnt_MAX) read_done <= 1;
    else read_done <= 0;
end

endmodule