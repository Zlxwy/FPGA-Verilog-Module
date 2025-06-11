//按键消抖模块，当按键被按下（保持低电平）超过20ms后，输出一个时钟的脉冲信号
module key_debounce(
    input   wire        sclk,
    input   wire        nrst,
    input   wire        key_in,

    output  reg         key_out
);

/*依托于50MHz的时钟信号，在按键按下（低电平）时进行周期为20ms的计数循环*/
reg[19:0]   cnt_20ms;//20ms计数周期的计数器
parameter   cnt_20ms_MAX = 20'd999_999;
parameter   cnt_20ms_MAX_minus_1 = 20'd999_998;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                       cnt_20ms <= 0;
    else if(key_in == 1)                cnt_20ms <= 0;              //如果是高电平（按键没按下），不计数，一直保持为0
    else if(cnt_20ms == cnt_20ms_MAX)   cnt_20ms <= cnt_20ms;       //如果是低电平（按键按下），且计数到最大值，则一直保持这个最大值，不自增也不清零。
    else                                cnt_20ms <= cnt_20ms + 1;   //如果按键按下，且计数还没到最大值，则不断自增。
end

/*在cnt_20ms计数到999998时，拉高输出电平，使输出高电平保持一个时钟周期*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                               key_out <= 0;
    else if(cnt_20ms == cnt_20ms_MAX_minus_1)   key_out <= 1;
    else                                        key_out <= 0;
end

endmodule