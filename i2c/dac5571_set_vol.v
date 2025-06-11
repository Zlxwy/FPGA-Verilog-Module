/*在i2c_ctrl模块的基础上，用来设置电压数值*/
// 如何使用这个驱动？
// 在vol上输入一个8位电压值，然后在set_trig上给一个高电平脉冲，
// 电压设置完成后，会在set_done上输出一个高电平脉冲。
module dac5571_set_vol #(
    parameter sys_clk_freq = 50_000_000,
    parameter i2c_clk_speed = 400_000,
    parameter i2c_equi_addr = 7'b1001_100 //因为dac有个更改器件地址的引脚
)
(
    input wire sclk,
    input wire nrst,
    input wire[7:0] voltage,
    input wire set_trig,
    output wire set_done,
    output wire dac_scl,
    inout wire dac_sda
);

wire[7:0] UNUSED_read_byte;
wire UNUSED_read_trigger;
wire UNUSED_read_done;
i2c_ctrler #(
    .sys_clk_freq (sys_clk_freq),    //系统时钟频率，默认是50MHz
    .i2c_clk_speed (i2c_clk_speed)       //SCL时钟速度，默认400kHz
)
(
    .sclk(sclk),
    .nrst(nrst),

    .equi_addr(i2c_equi_addr),      //从机未左移的原7位地址
    .reg_addr({4'b0000, voltage[7:4]}),       //要读/写寄存器的地址
    .write_byte({voltage[3:0], 4'b0000}),     //要写入的数据
    .read_byte(UNUSED_read_byte),      //进行读操作后读取到的一个字节

    .write_trigger(set_trig),  //输入一个高电平脉冲，开始一次写操作
    .read_trigger(UNUSED_read_trigger),   //输入一个高电平脉冲，开始一次读操作
    //（如果同时输入这两个触发信号，则系统不会响应）
    .write_done(set_done),     //此信号默认为低电平，当写操作完成后，产生一个维持一个时钟周期的高电平脉冲
    .read_done(UNUSED_read_done),      //此信号默认为低电平，当读操作完成后，产生一个维持一个时钟周期的高电平脉冲
    // output  reg         i2c_error,      //若传输异常，这个信号会以100ms间隔翻转电平

    .scl(dac_scl),    //若为数据1时，输出高阻态z；若为数据0时，输出低电平（开漏输出）
    .sda(dac_sda)     //若为数据1时，输出高阻态z；若为数据0时，输出低电平（开漏输出）
);

endmodule