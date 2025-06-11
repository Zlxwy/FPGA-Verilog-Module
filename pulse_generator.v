/*用来产生指定间隔的一系列脉冲*/
module pulse_generator #(
    parameter sys_clk_freq = 50_000_000,
    parameter interval     = 100_000 //单位为ns，取值范围[40,85899345920]
)
(
    input wire sclk,
    input wire nrst,
    input wire enable,
    output reg trigger
);

reg[31:0] cnt_interval;
parameter cnt_interval_MAX = interval / 20 - 1;
parameter cnt_interval_MAX_minus_1 = cnt_interval_MAX - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_interval <= 0;
    else if(enable == 0) cnt_interval <= 0;
    else if(cnt_interval == cnt_interval_MAX) cnt_interval <= 0;
    else cnt_interval <= cnt_interval + 1;
end

always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) trigger <= 0;
    else if(cnt_interval == cnt_interval_MAX_minus_1) trigger <= 1;
    else trigger <= 0;
end

endmodule