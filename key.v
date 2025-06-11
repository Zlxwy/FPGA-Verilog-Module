/*按键驱动，可识别长短按，像电脑键盘那样的输入逻辑：按一下输出一次高电平脉冲，长按则输出连续的高电平脉冲*/
module key #(
    parameter sclk_freq       = 50_000_000,   // 系统时钟频率50MHz
    parameter press_vol       = 0,            // 按键按下时为低电平
    parameter long_press      = 500,         // 按键按住500ms后识别为长按，参数范围[2~4294967295]ms
    parameter signal_interval = 100     // 识别为长按后，连续脉冲的输出间隔为100ms，参数范围[2~4294967295]ms
)
(
    input wire sclk,
    input wire nrst,
    input wire key_in, // 原始按键信号
    output reg key_out // 出来的按键信号
);

reg[15:0] cnt_1ms;
parameter cnt_1ms_MAX = (sclk_freq / 1000) - 1;
// cnt_1ms
/*按键按住的时候不断循环计数*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_1ms <= 0;
    else if(key_in != press_vol) cnt_1ms <= 0;
    else if(cnt_1ms == cnt_1ms_MAX) cnt_1ms <= 0;
    else cnt_1ms <= cnt_1ms + 1;
end

reg[15:0] cnt_20ms;
parameter cnt_20ms_MAX = 19;
parameter cnt_20ms_MAX_minus_1 = cnt_20ms_MAX - 1;
// cnt_20ms
/*在按住的情况下，cnt_20ms计到最大值，然后保持最大值不再变化*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_20ms <= 0;
    else if(key_in != press_vol) cnt_20ms <= 0;
    else if(cnt_1ms == cnt_1ms_MAX && cnt_20ms == cnt_20ms_MAX) cnt_20ms <= cnt_20ms;
    else if( cnt_1ms == cnt_1ms_MAX) cnt_20ms <= cnt_20ms + 1;
    else cnt_20ms <= cnt_20ms;
end

reg is_lp_rcgn_enable; // Is Recognizing Long Press Enable, 启动用于识别按键长按的计数器
// is_lp_rcgn_enable
/*如果cnt_20ms计到最大值了，拉高is_lp_rcgn_enable，表示开始识别长按*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) is_lp_rcgn_enable <= 0;
    else if(key_in != press_vol) is_lp_rcgn_enable <= 0;
    else if(cnt_1ms == cnt_1ms_MAX && cnt_20ms == cnt_20ms_MAX) is_lp_rcgn_enable <= 1;
    else is_lp_rcgn_enable <= is_lp_rcgn_enable;
end

reg[31:0] cnt_lp_rcgn;
parameter cnt_lp_rcgn_MAX = long_press - 1;
// cnt_lp_rcgn
/*拉高is_lp_rcgn_enable了之后，cnt_lp_rcgn开始计数识别长按*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_lp_rcgn <= 0;
    else if(key_in != press_vol) cnt_lp_rcgn <= 0;
    else if(is_lp_rcgn_enable && cnt_1ms == cnt_1ms_MAX && cnt_lp_rcgn == cnt_lp_rcgn_MAX) cnt_lp_rcgn <= cnt_lp_rcgn;
    else if(is_lp_rcgn_enable && cnt_1ms == cnt_1ms_MAX) cnt_lp_rcgn <= cnt_lp_rcgn + 1;
    else cnt_lp_rcgn <= cnt_lp_rcgn;
end

reg is_lp_rcgn_scsful; //Is Long Press Recognizing Successful, 是否成功识别长按
// is_lp_rcgn_scsful
/*cnt_lp_rcgn计数到最大值了，拉高is_lp_rcgn_scsful，表示长按识别成功*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) is_lp_rcgn_scsful <= 0;
    else if(key_in != press_vol) is_lp_rcgn_scsful <= 0;
    else if(cnt_1ms == cnt_1ms_MAX && cnt_lp_rcgn == cnt_lp_rcgn_MAX) is_lp_rcgn_scsful <= 1;
    else is_lp_rcgn_scsful <= is_lp_rcgn_scsful;
end

reg[31:0] cnt_signal_interval; //在长按识别成功后，用于产生一定间隔的高电平脉冲
parameter cnt_signal_interval_MAX = signal_interval - 1;
// cnt_signal_interval
/*拉高is_lp_rcgn_scsful了之后，即长按识别成功后，开始循环计数用以输出指定间隔的脉冲信号*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_signal_interval <= 0;
    else if(key_in != press_vol) cnt_signal_interval <= 0;
    else if(is_lp_rcgn_scsful && cnt_1ms == cnt_1ms_MAX && cnt_signal_interval == cnt_signal_interval_MAX) cnt_signal_interval <= 0;
    else if(is_lp_rcgn_scsful && cnt_1ms == cnt_1ms_MAX) cnt_signal_interval <= cnt_signal_interval + 1;
    else cnt_signal_interval <= cnt_signal_interval;
end

// key_out
/*输出这一系列的按键脉冲*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) key_out <= 0;
    else if(key_in != press_vol) key_out <= 0;
    else if(cnt_1ms == cnt_1ms_MAX && cnt_20ms == cnt_20ms_MAX_minus_1) key_out <= 1;
    else if(cnt_1ms == cnt_1ms_MAX && cnt_signal_interval == cnt_signal_interval_MAX) key_out <= 1;
    else key_out <= 0;
end

endmodule