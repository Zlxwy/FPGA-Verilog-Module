/*将每个位上的数字数据，转换为数码管可直接执行的信号*/
//位选信号sel，从高位到低位依次为DIG_7~DIG_0（从左到右）
//段选信号seg，从高位到低位依次是DP,G,F,E,D,C,B,A
module bit_to_caseg(
    input   wire        sclk,
    input   wire        nrst,
    input   wire[7:0]   dp_en, //哪一位为1，就在哪一位上显示小数点
    input   wire[3:0]   bit_7,
    input   wire[3:0]   bit_6,
    input   wire[3:0]   bit_5,
    input   wire[3:0]   bit_4,
    input   wire[3:0]   bit_3,
    input   wire[3:0]   bit_2,
    input   wire[3:0]   bit_1,
    input   wire[3:0]   bit_0,
    
    output  reg[7:0]    sel,
    output  reg[7:0]    seg
);



/*综合所有显示位上的数字，bit_7~0，构成一个32位的数*/
wire[31:0] disp_reg;
assign disp_reg = {bit_7, bit_6, bit_5, bit_4, bit_3, bit_2, bit_1, bit_0};



/*cnt_1ms计数块，依托于clk，在0~49999之间循环计数*/
reg[15:0]   cnt_1ms;
parameter   cnt_1ms_MAX = 16'd49_999;//50MHz时钟下计50000个数为1ms
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                       cnt_1ms <= 0;
    else if(cnt_1ms == cnt_1ms_MAX)     cnt_1ms <= 0;
    else                                cnt_1ms <= cnt_1ms + 1;
end



/*signal_1ms高电平脉冲信号产生*/
reg signal_1ms;//在cnt_1ms即将更新之时，产生一个维持一个时钟周期的高电平脉冲
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                       signal_1ms <= 0;
    else if(cnt_1ms == cnt_1ms_MAX-1)   signal_1ms <= 1;
    else                                signal_1ms <= 0;
end



/*cnt_bit计数块，依托于signal_1ms高电平脉冲信号，在0~7循环计数*/
reg[2:0]    cnt_bit;//显示到哪一位数据了，依托于signal_1ms在0~7循环计数
parameter   cnt_bit_MAX = 3'd7;//最大计数到7
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                                           cnt_bit <= 0;
    else if(signal_1ms == 1 && cnt_bit == cnt_bit_MAX)      cnt_bit <= 0;
    else if(signal_1ms == 1)                                cnt_bit <= cnt_bit + 1;
    else                                                    cnt_bit <= cnt_bit;
end



/*位选信号缓冲器sel_disp更新块，依托于cnt_bit的数值、signal_1ms脉冲*/
/*之后真真正正输出的sel会比sel_disp延迟一个时钟*/
reg[7:0]  sel_disp;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        sel_disp <= 0;
    else if(signal_1ms == 1) begin
        case(cnt_bit)
            0:  sel_disp <= ~8'b0000_0001;
            1:  sel_disp <= ~8'b0000_0010;
            2:  sel_disp <= ~8'b0000_0100;
            3:  sel_disp <= ~8'b0000_1000;
            4:  sel_disp <= ~8'b0001_0000;
            5:  sel_disp <= ~8'b0010_0000;
            6:  sel_disp <= ~8'b0100_0000;
            7:  sel_disp <= ~8'b1000_0000;
            default: sel_disp <= sel_disp;
        endcase
    end
    else
        sel_disp <= sel_disp;
end

/*段选信号缓冲器seg_disp更新块，依托于cnt_bit的数值、signal_1ms脉冲*/
/*之后真真正正输出的seg会比seg_disp延迟一个时钟*/
reg[3:0]  seg_disp;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        seg_disp <= 0;
    else if(signal_1ms == 1) begin
        case(cnt_bit)
        0:  seg_disp <= disp_reg[3:0];
        1:  seg_disp <= disp_reg[7:4];
        2:  seg_disp <= disp_reg[11:8];
        3:  seg_disp <= disp_reg[15:12];
        4:  seg_disp <= disp_reg[19:16];
        5:  seg_disp <= disp_reg[23:20];
        6:  seg_disp <= disp_reg[27:24];
        7:  seg_disp <= disp_reg[31:28];
        default: seg_disp <= seg_disp;
        endcase
    end
    else
        seg_disp <= seg_disp;
end



/*输出真正的位选信号sel*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)   sel <= 0;
    else            sel <= sel_disp;
end

/*输出真正的段选信号seg*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        seg <= 0;
    else begin
        case(seg_disp)//共阳极数码管，是阴码字形
            0:  seg <= 8'b1100_0000 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字0   8'hc0
            1:  seg <= 8'b1111_1001 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字1   8'hf9
            2:  seg <= 8'b1010_0100 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字2   8'ha4
            3:  seg <= 8'b1011_0000 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字3   8'hb0
            4:  seg <= 8'b1001_1001 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字4   8'h99
            5:  seg <= 8'b1001_0010 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字5   8'h92
            6:  seg <= 8'b1000_0010 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字6   8'h82
            7:  seg <= 8'b1111_1000 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字7   8'hf8
            8:  seg <= 8'b1000_0000 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字8   8'h80
            9:  seg <= 8'b1001_0000 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//数字9   8'h90
            10: seg <= 8'b1111_1111 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//空格    8'hff
            11: seg <= 8'b1011_1111 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//横杠    8'hbf
            12: seg <= 8'b1000_1000 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//字母A
            13: seg <= 8'b1000_1100 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//字母P
            //  seg <= 8'b1100_0110 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//字母C
            //  seg <= 8'b1000_1001 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//字母H
            //  seg <= 8'b1100_0111 & ((dp_en[cnt_bit-1])?8'b0111_1111:8'b1111_1111);//字母L
            default: seg <= seg;
        endcase
    end
end

endmodule
