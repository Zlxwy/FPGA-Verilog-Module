/*在ds1302_single_byte_rw模块的基础上，能设置、获取所有时间数据的模块。*/
module ds1302_all_time_rw #(
    parameter sys_clk_freq = 50_000_000, //系统时钟50MHz
    parameter ds1302_clk_speed = 200_000 //这个指定的是ds1302_sclk的周期频率，默认为0.2MHz
    //如何计算一次读取/设置操作的时间？：(130 / ds1302_clk_speed) second （默认值为650us.1538Hz）
    //= (1/sys_clk_freq) * (sys_clk_freq/ds1302_clk_speed/4) * rw_step_cnt_MAX * sg_step_cnt_MAX
)
(
    input wire sclk,
    input wire nrst,

    input wire set_trig,
    input wire get_trig,

    /* {wp, year, day, month, date, hour, minute, second} */
    input wire[63:0] bcd_time_set,
    output reg[63:0] bcd_time_get,

    output wire ds1302_ce, //ds1302片选信号
    output wire ds1302_sclk, //ds1302时钟信号
    inout wire ds1302_io //ds1302数据信号，双向IO口
);

reg[16:0] sg_step_cnt;
parameter set_step_cnt_MAX = 8;
parameter get_step_cnt_MAX = 8;
reg is_setting, is_getting;
wire write_done, read_done;
// sg_step_cnt
// 当开始进行一次设置/读取时间操作后，这个sg_step_cnt用来对步骤进行计数
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) sg_step_cnt <= 0;

    /*在进行设置时间操作时，sg_step_cnt计到最大值，则设置时间操作结束，sg_step_cnt归零*/
    else if(is_setting && write_done && sg_step_cnt == set_step_cnt_MAX) sg_step_cnt <= 0;
    else if(is_setting && write_done) sg_step_cnt <= sg_step_cnt + 1;
    else if(is_setting) sg_step_cnt <= sg_step_cnt;

    /*在进行获取时间操作时，sg_step_cnt计到最大值，则获取时间操作结束，sg_step_cnt归零*/
    else if(is_getting && read_done && sg_step_cnt == get_step_cnt_MAX) sg_step_cnt <= 0;
    else if(is_getting && read_done) sg_step_cnt <= sg_step_cnt + 1;
    else if(is_getting) sg_step_cnt <= sg_step_cnt;

    /*如果is_setting和is_getting都为0，则sg_step_cnt一直为0*/
    else sg_step_cnt <= 0;
end

// is_setting, is_getting
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        is_setting <= 0;
        is_getting <= 0;
    end

    /*当正在进行设置/获取时间操作时，sg_step_cnt计数到指定数值，则操作结束*/
    else if(is_setting && write_done && sg_step_cnt == set_step_cnt_MAX) is_setting <= 0;
    else if(is_getting && read_done && sg_step_cnt == get_step_cnt_MAX) is_getting <= 0;

    /*当不在进行设置/获取时间操作，且同时发现两个触发信号时，则不做反应*/
    else if(!is_setting && !is_getting && set_trig && get_trig) begin
        is_setting <= is_setting;
        is_getting <= is_getting;
    end

    /*当不在进行设置/获取时间操作，且只发现一个触发信号时，则置对应的is_xxxxing为1*/
    else if(!is_setting && !is_getting && set_trig) is_setting <= 1;
    else if(!is_setting && !is_getting && get_trig) is_getting <= 1;

    /*其他情况*/
    else begin
        is_setting <= is_setting;
        is_getting <= is_getting;
    end
end

reg first_operation_signal; //驱动第一次操作的一个信号
// first_operation_signal
//因为在is_xxxxing置起后，都需要靠xxxx_done来驱动步骤进行，而第一个步骤还没有任何驱动，需要自行添加一个脉冲来驱动
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) first_operation_signal <= 0;
    else if(!is_setting && !is_getting && set_trig && get_trig) first_operation_signal <= 0;
    else if(!is_setting && !is_getting && (set_trig || get_trig)) first_operation_signal <= 1;
    else first_operation_signal <= 0;
end

/*时分秒寄存器的写地址*/
localparam DS1302_SECOND_REG = 8'h80;
localparam DS1302_MINUTE_REG = 8'h82;
localparam DS1302_HOUR_REG   = 8'h84;
localparam DS1302_DATE_REG   = 8'h86;
localparam DS1302_MONTH_REG  = 8'h88;
localparam DS1302_DAY_REG    = 8'h8A;
localparam DS1302_YEAR_REG   = 8'h8C;
localparam DS1302_WP_REG     = 8'h8E;

reg[7:0] addr, write_byte;
wire[7:0] read_byte;
reg write_trigger, read_trigger;
// addr, write_byte
// write_trigger, read_trigger
// bcd_time_get
/*开始执行步骤*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        addr <= 0; write_byte <= 0;
        write_trigger <= 0; read_trigger <= 0;
        bcd_time_get <= 0;
    end

    /*开始以first_operation_signal和write_done信号，驱动(设置时间操作步骤)进行*/
    else if(is_setting && (first_operation_signal || write_done)) begin
        case(sg_step_cnt)
            0: begin write_byte <= bcd_time_set[63:56]; addr <= DS1302_WP_REG;     write_trigger <= 1; end
            1: begin write_byte <= bcd_time_set[55:48]; addr <= DS1302_YEAR_REG;   write_trigger <= 1; end
            2: begin write_byte <= bcd_time_set[47:40]; addr <= DS1302_DAY_REG;    write_trigger <= 1; end
            3: begin write_byte <= bcd_time_set[39:32]; addr <= DS1302_MONTH_REG;  write_trigger <= 1; end
            4: begin write_byte <= bcd_time_set[31:24]; addr <= DS1302_DATE_REG;   write_trigger <= 1; end
            5: begin write_byte <= bcd_time_set[23:16]; addr <= DS1302_HOUR_REG;   write_trigger <= 1; end
            6: begin write_byte <= bcd_time_set[15: 8]; addr <= DS1302_MINUTE_REG; write_trigger <= 1; end
            7: begin write_byte <= bcd_time_set[ 7: 0]; addr <= DS1302_SECOND_REG; write_trigger <= 1; end
            8: begin write_byte <= 0; addr <= 0; write_trigger <= 0; end
            default: begin write_byte <= write_byte; addr <= addr; write_trigger <= write_trigger;  end
        endcase
    end

    /*开始以first_operation_signal和read_done信号，驱动(获取时间操作步骤)进行*/
    else if(is_getting && (first_operation_signal || read_done)) begin
        case(sg_step_cnt)
            0: begin addr <= DS1302_WP_REG; read_trigger <= 1; end
            1: begin bcd_time_get[63:56] <= read_byte; addr <= DS1302_YEAR_REG;   read_trigger <= 1; end
            2: begin bcd_time_get[55:48] <= read_byte; addr <= DS1302_DAY_REG;    read_trigger <= 1; end
            3: begin bcd_time_get[47:40] <= read_byte; addr <= DS1302_MONTH_REG;  read_trigger <= 1; end
            4: begin bcd_time_get[39:32] <= read_byte; addr <= DS1302_DATE_REG;   read_trigger <= 1; end
            5: begin bcd_time_get[31:24] <= read_byte; addr <= DS1302_HOUR_REG;   read_trigger <= 1; end
            6: begin bcd_time_get[23:16] <= read_byte; addr <= DS1302_MINUTE_REG; read_trigger <= 1; end
            7: begin bcd_time_get[15: 8] <= read_byte; addr <= DS1302_SECOND_REG; read_trigger <= 1; end
            8: begin bcd_time_get[ 7: 0] <= read_byte; end
            default: begin bcd_time_get <= bcd_time_get; addr <= addr; read_trigger <= read_trigger; end
        endcase
    end

    else begin
        addr <= addr;
        write_byte <= write_byte;
        write_trigger <= 0; read_trigger <= 0;
        bcd_time_get <= bcd_time_get;
    end
end


ds1302_single_byte_rw #(
    .sys_clk_freq (sys_clk_freq), //系统时钟50MHz
    .ds1302_clk_speed (ds1302_clk_speed) //这个指定的是ds1302_sclk的周期频率，默认为0.2MHz
    //如何计算一次读/写操作的时间？：(16.25 / ds1302_clk_speed) second （默认值为81.25us.12308Hz）
    //= (1/sys_clk_freq) * (sys_clk_freq/ds1302_clk_speed/4) * rw_step_cnt_MAX
) ds1302_single_byte_rw_inst (
    .sclk(sclk), //系统时钟，50MHz
    .nrst(nrst), //复位信号，低有效

    .addr(addr), //读写地址，只传入写地址即可，如果是读地址，会自动或上0x01
    .write_byte(write_byte), //写入字节
    .read_byte(read_byte), //读取字节

    .write_trigger(write_trigger), //写触发信号
    .read_trigger(read_trigger), //读触发信号
    .write_done(write_done), //写操作完成后，产生一个高电平脉冲
    .read_done(read_done), //读操作完成后，产生一个高电平脉冲
    
    .ds1302_ce(ds1302_ce), //ds1302片选信号
    .ds1302_sclk(ds1302_sclk), //ds1302时钟信号
    .ds1302_io(ds1302_io) //ds1302数据信号，双向IO口
);

endmodule