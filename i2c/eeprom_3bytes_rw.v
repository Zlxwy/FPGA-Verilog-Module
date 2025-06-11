/*在i2c_ctrl模块的基础上，可向EEPROM某一个地址开始，连续写入3个字节*/
// 如何使用这个驱动？
// 在write_3bytes_trig或者read_3bytes_trig上填写起始地址输入一个高电平脉冲，就能执行相应的读写操作，
// 在读写完成后，会相应地在write_3bytes_done或read_3bytes_done上输出一个高电平脉冲。
module eeprom_3bytes_rw #(
    parameter sys_clk_freq = 50_000_000,
    parameter i2c_clk_speed = 400_000,
    parameter i2c_equi_addr = 7'b1010_000 //从机未左移的原7位地址
)
(
    input wire sclk,
    input wire nrst,
    input wire[7:0] start_reg_addr, //EEPROM读写寄存器的起始地址
    input wire[23:0] write_3bytes, //要写入的3个字节
    output reg[23:0] read_3bytes, //要读取的3个字节

    input wire write_3bytes_trig,
    input wire read_3bytes_trig,
    output reg write_3bytes_done,
    output reg read_3bytes_done,

    output wire eeprom_scl,
    inout wire eeprom_sda
);

reg[16:0] rw_step_cnt;
parameter write_step_cnt_MAX = 6;
parameter read_step_cnt_MAX = 3;
reg is_writing_3bytes, is_reading_3bytes;
wire write_done, read_done; //连接i2c_ctrler模块的write_done, read_done
// rw_step_cnt
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) rw_step_cnt <= 0;

    /*在is_writing_3bytes时，受write_done || first_operation_signal || signal_later三个信号驱动，不断轮转下一个步骤*/
    else if(is_writing_3bytes && (write_done || first_operation_signal || signal_10ms_later) && rw_step_cnt == write_step_cnt_MAX) rw_step_cnt <= 0;
    else if(is_writing_3bytes && (write_done || first_operation_signal || signal_10ms_later)) rw_step_cnt <= rw_step_cnt + 1;
    else if(is_writing_3bytes) rw_step_cnt <= rw_step_cnt;

    /*在is_reading_3bytes时，受read_done || first_operation_signal两个信号驱动，不断轮转下一个步骤*/
    else if(is_reading_3bytes && (read_done || first_operation_signal) && rw_step_cnt == read_step_cnt_MAX) rw_step_cnt <= 0;
    else if(is_reading_3bytes && (read_done || first_operation_signal)) rw_step_cnt <= rw_step_cnt + 1;
    else if(is_reading_3bytes) rw_step_cnt <= rw_step_cnt;

    else rw_step_cnt <= 0;
end

// is_writing_3bytes, is_reading_3bytes
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        is_writing_3bytes <= 0;
        is_reading_3bytes <= 0;
    end

    /*在is_writing_3bytes时，在write_done || first_operation_signal || signal_later三个信号驱动下发现rw_step_cnt到最大值，则写入3个字节步骤结束*/
    else if(is_writing_3bytes && (write_done || first_operation_signal || signal_10ms_later) && rw_step_cnt == write_step_cnt_MAX) is_writing_3bytes <= 0;
    /*在is_reading_3bytes时，在read_done || first_operation_signal两个信号驱动下发现rw_step_cnt到最大值，则读取3个字节步骤结束*/
    else if(is_reading_3bytes && (read_done || first_operation_signal) && rw_step_cnt == read_step_cnt_MAX) is_reading_3bytes <= 0;
    
    /*不在is_writing_3bytes，也不在is_reading_3bytes，同时发现两个触发信号，不做反应*/
    else if(!is_writing_3bytes && !is_reading_3bytes && write_3bytes_trig && read_3bytes_trig) begin
        is_writing_3bytes <= is_writing_3bytes;
        is_reading_3bytes <= is_reading_3bytes;
    end

    /*不在is_writing_3bytes，也不在is_reading_3bytes，只发现一个触发信号，置起相应的is_xxxxing_3bytes*/
    else if(!is_writing_3bytes && !is_reading_3bytes && write_3bytes_trig) is_writing_3bytes <= 1;
    else if(!is_writing_3bytes && !is_reading_3bytes && read_3bytes_trig) is_reading_3bytes <= 1;

    else begin
        is_writing_3bytes <= is_writing_3bytes;
        is_reading_3bytes <= is_reading_3bytes;
    end
end

reg first_operation_signal; //驱动第一次操作的一个脉冲信号
// first_operation_signal
/*因为在is_xxxxing_3bytes被置起后，都要靠xxxx_done来驱动步骤进行，而第一个步骤还没有任何驱动，需要自行添加一个脉冲来起始*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) first_operation_signal <= 0;
    else if(!is_writing_3bytes && !is_reading_3bytes && write_3bytes_trig && read_3bytes_trig) first_operation_signal <= 0;
    else if(!is_writing_3bytes && !is_reading_3bytes && (write_3bytes_trig || read_3bytes_trig)) first_operation_signal <= 1;
    else first_operation_signal <= 0;
end

/*这些信号是为了能在接收到写入完成信号后，延迟个10ms再进行下一个字节的写入*/
reg[31:0] cnt_10ms_later;
reg signal_10ms_later;
parameter cnt_10ms_later_MAX = 499_999; //50MHz计数500000-10ms
parameter cnt_10ms_later_MAX_minus_1 = cnt_10ms_later_MAX - 1;
// cnt_10ms_later
/*在写入3字节的时候，发现1个字节写入完成信号后，开始一轮计数，计到最大值归零，停止*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_10ms_later <= 0;
    else if(is_writing_3bytes && write_done && (rw_step_cnt==1 || rw_step_cnt==3 || rw_step_cnt==5)) cnt_10ms_later <= cnt_10ms_later + 1;
    else if(cnt_10ms_later > 0 && cnt_10ms_later < cnt_10ms_later_MAX) cnt_10ms_later <= cnt_10ms_later + 1;
    else cnt_10ms_later <= 0;
end
// signal_10ms_later
/*在cnt_10ms_later计到最大值时，产生一个高电平脉冲，用来触发下一个字节的写入*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) signal_10ms_later <= 0;
    else if(cnt_10ms_later == cnt_10ms_later_MAX_minus_1) signal_10ms_later <= 1;
    else signal_10ms_later <= 0;
end

reg[7:0] reg_addr;
reg[7:0] write_byte;
wire[7:0] read_byte;
reg write_trigger,read_trigger;
// reg_addr
// write_byte, read_3bytes
// write_trigger, read_trigger
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        reg_addr <= 0;
        write_byte <= 0;
        read_3bytes <= 0;
        write_trigger <= 0;
        read_trigger <= 0;
    end
    /*依托于first_operation_signal || write_done || signal_10ms_later信号，推动步骤进行*/
    else if(is_writing_3bytes && (first_operation_signal || write_done || signal_10ms_later)) begin
        case(rw_step_cnt)
            0: begin write_byte <= write_3bytes[23:16]; reg_addr <= start_reg_addr + 0; write_trigger <= 1; end
            // 1: begin  end
            2: begin write_byte <= write_3bytes[15: 8]; reg_addr <= start_reg_addr + 1; write_trigger <= 1; end
            // 3: begin  end
            4: begin write_byte <= write_3bytes[ 7: 0]; reg_addr <= start_reg_addr + 2; write_trigger <= 1; end
            // 5: begin  end
            // 6: begin  end
            default: begin write_byte <= write_byte; write_trigger <= write_trigger; end
        endcase
    end
    /*依托于first_operation_signal || read_done信号，推动步骤进行*/
    else if(is_reading_3bytes && (first_operation_signal || read_done)) begin
        case(rw_step_cnt)
            0: begin reg_addr <= start_reg_addr + 0; read_trigger <= 1; end
            1: begin read_3bytes[23:16] <= read_byte; reg_addr <= start_reg_addr + 1; read_trigger <= 1; end
            2: begin read_3bytes[15: 8] <= read_byte; reg_addr <= start_reg_addr + 2; read_trigger <= 1; end
            3: begin read_3bytes[ 7: 0] <= read_byte; end
            default: begin read_3bytes <= read_3bytes; read_trigger <= read_trigger; end
        endcase
    end
    else begin
        reg_addr <= reg_addr;
        write_byte <= write_byte;
        read_3bytes <= read_3bytes;
        write_trigger <= 0;
        read_trigger <= 0;
    end
end

// write_3bytes_done, read_3bytes_done
/*在读3个字节/写3个字节步骤完成后，在write_3bytes_done或read_3bytes_done上输出产生一个脉冲信号*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        write_3bytes_done <= 0;
        read_3bytes_done <= 0;
    end
    /*在is_writing_3bytes时，在write_done || first_operation_signal || signal_later三个信号驱动下发现rw_step_cnt到最大值，则写入3个字节步骤结束*/
    else if(is_writing_3bytes && (write_done || first_operation_signal || signal_10ms_later) && rw_step_cnt == write_step_cnt_MAX)
        write_3bytes_done <= 1;
    /*在is_reading_3bytes时，在read_done || first_operation_signal两个信号驱动下发现rw_step_cnt到最大值，则读取3个字节步骤结束*/
    else if(is_reading_3bytes && (read_done || first_operation_signal) && rw_step_cnt == read_step_cnt_MAX)
        read_3bytes_done <= 1;
    else begin
        write_3bytes_done <= 0;
        read_3bytes_done <= 0;
    end
end


i2c_ctrler #(
    .sys_clk_freq (sys_clk_freq),    //系统时钟频率，默认是50MHz
    .i2c_clk_speed (i2c_clk_speed)       //SCL时钟速度，默认400kHz
    // 如何计算一次读操作的时间？：(38.5 / i2c_clk_speed) second （默认值的话为96.25us.10390Hz）
    // = (1/sys_clk_freq) * (sys_clk_freq/i2c_clk_speed)/4 * i2c_read_time_cnt_MAX
    // 如何计算一次写操作的时间？：(28.5 / i2c_clk_speed) second （默认值的话为71.25us.14035Hz）
    // = (1/sys_clk_freq) * (sys_clk_freq/i2c_clk_speed)/4 * i2c_write_time_cnt_MAX
) i2c_ctrler_inst (
    .sclk(sclk),
    .nrst(nrst),

    .equi_addr(i2c_equi_addr),      //从机未左移的原7位地址
    .reg_addr(reg_addr),       //要读/写寄存器的地址
    .write_byte(write_byte),     //要写入的数据
    .read_byte(read_byte),      //进行读操作后读取到的一个字节

    .write_trigger(write_trigger),  //输入一个高电平脉冲，开始一次写操作
    .read_trigger(read_trigger),   //输入一个高电平脉冲，开始一次读操作
    //（如果同时输入这两个触发信号，则系统不会响应）
    .write_done(write_done),     //此信号默认为低电平，当写操作完成后，产生一个维持一个时钟周期的高电平脉冲
    .read_done(read_done),      //此信号默认为低电平，当读操作完成后，产生一个维持一个时钟周期的高电平脉冲

    .scl(eeprom_scl),    //若为数据1时，输出高阻态z；若为数据0时，输出低电平（开漏输出）
    .sda(eeprom_sda)     //若为数据1时，输出高阻态z；若为数据0时，输出低电平（开漏输出）
);

endmodule