/**把8位8段共阳数码管的位选信号和段选信号，转成74hc595芯片可直接执行的信号输出**/
//位选信号sel，从高位到低位依次为DIG_7~DIG_0
//段选信号seg，从高位到低位依次是DP,G,F,E,D,C,B,A
module caseg_to_hc595(
  input   wire        sclk,//系统时钟50MHz
  input   wire        nrst,//复位信号，低电平有效
  input   wire[7:0]   sel,//位选信号，控制哪个位显示
  input   wire[7:0]   seg,//段选信号，控制位上显示的字形

  output  reg         ds,//数据输入端
  output  reg         shcp,//移位时钟，上升沿移位
  output  reg         stcp,//输出时钟，上升沿
  output  wire        oe//使能端，低电平有效
);


wire[15:0]  data;//要移入74hc595的16位数据
reg[1:0]    cnt;//在系统时钟下，0~3循环计数
parameter   cnt_MAX = 2'd3;
reg[3:0]    bit;//data的某一位数据
parameter   bit_MAX = 4'd15;


//移入74hc595的先后顺序依次是DIG7~DIG0,DP,G~A (sel[7]~sel[0],seg[7]~seg[0])
assign data = { seg[0],seg[1],seg[2],seg[3],seg[4],seg[5],seg[6],seg[7],
                sel[0],sel[1],sel[2],sel[3],sel[4],sel[5],sel[6],sel[7] };


/*cnt计数块，0~3循环计数*/
always @(posedge sclk or negedge nrst)
  if(nrst == 0)           cnt <= 0;
  else if(cnt == cnt_MAX) cnt <= 0;
  else                    cnt <= cnt + 1;


/*bit计数块，依托于cnt更新事件，在0~15循环计数*/
always @(posedge sclk or negedge nrst)
  if(nrst == 0)                               bit <= 0;
  else if(cnt == cnt_MAX && bit == bit_MAX)   bit <= 0;        //如果cnt到了最大值并且bit也到了最大值：bit清零
  else if(cnt == cnt_MAX)                     bit <= bit + 1;  //如果只是cnt到了最大值：bit加一
  else                                        bit <= bit;


/*cnt计数在0时，在ds引脚上输出数据位data[bit]*/
always @(posedge sclk or negedge nrst)
  if(nrst == 0)           ds <= 0;
  else if(cnt == 0)       ds <= data[bit];
  else                    ds <= ds;


/*在cnt计数在2时，把shcp引脚电平拉高，产生上升沿使数据位移入到SR中，然后cnt计数在0时拉低*/
always @(posedge sclk or negedge nrst)
  if(nrst == 0)         shcp <= 0;
  else if(cnt == 2)     shcp <= 1;
  else if(cnt == 0)     shcp <= 0;
  else                  shcp <= shcp;


/*把stcp引脚电平拉高，让移位数据从SR更新到输出锁存器上*/
always @(posedge sclk or negedge nrst)
  if(nrst == 0)                     stcp <= 0;
  else if(bit == 0 && cnt == 0)     stcp <= 1;
  else if(bit == 0 && cnt == 2)     stcp <= 0;
  else                              stcp <= stcp;


/*低电平有效引脚，使其一直保持低电平*/
assign oe = 0;

endmodule