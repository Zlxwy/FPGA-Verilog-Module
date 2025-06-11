/*将时间的数值数据，转为数码管每个位上显示的数字数据*/
//用的是8位共阳数码管，显示格式：hh-mm-ss
//特殊显示：空格‘ ’用10表示，横杠‘-’用11表示
module num_to_bit(
    input   wire        sclk,
    input   wire        nrst,
    input   wire[5:0]   num_02,
    input   wire[5:0]   num_01,
    input   wire[5:0]   num_00,
    
    /*从右到左依次为bit_0~7*/
    output  reg[3:0]    bit_7,
    output  reg[3:0]    bit_6,
    output  reg[3:0]    bit_5,
    output  reg[3:0]    bit_4,
    output  reg[3:0]    bit_3,
    output  reg[3:0]    bit_2,
    output  reg[3:0]    bit_1,
    output  reg[3:0]    bit_0
);

reg         shift_signal;   //移位信号，在此信号低电平时对数据进行大于4判断，高电平时对数据进行移位
reg[2:0]    cnt_shift;      //依托于shift_signal进行计数，在这个计数周期内数据进行移位计算，得出最终结果
parameter   cnt_shift_MAX = 3'd7;//6位的原数据，需要8个时钟
reg[13:0]   num_02_shift;   //需要存储：结果的8位数据、原数的6位数据，一共14位
reg[13:0]   num_01_shift;   //需要存储：结果的8位数据、原数的6位数据，一共14位
reg[13:0]   num_00_shift;   //需要存储：结果的8位数据、原数的6位数据，一共14位



/*对时钟进行二分频*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)       shift_signal <= 0;
    else                shift_signal <= ~shift_signal;
end



/*cnt_shift在shift_signal的脉冲信号下，在0~7之间进行循环计数*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                                               cnt_shift <= 0;
    else if(cnt_shift == cnt_shift_MAX && shift_signal == 1)    cnt_shift <= 0;
    else if(shift_signal == 1)                                  cnt_shift <= cnt_shift + 1;
    else                                                        cnt_shift <= cnt_shift;
end



/*示例：将一个二位十进制数上的每个十进制位数字转换为8421码*/
// ---------------------------------
// | 0000 | 0000 | 111000 | 56(10)
// ---------------------------------
// | 0000 | 0001 | 11000 | 第1次
// | 0000 | 0011 | 1000  | 第2次
// | 0000 | 0111 | 000   | 第3次
// | 0000 | 1010 | 000   | (+3操作)
// | 0001 | 0100 | 00    | 第4次
// | 0010 | 1000 | 0     | 第5次
// | 0010 | 1011 |       | (+3操作)
// | 0101 | 0110 |       | 第6次
// |  5   |  6   |       | (结果)
// ---------------------------------
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        num_02_shift <= 0;
    else if(cnt_shift == 0)
        num_02_shift <= {8'b0, num_02};
    else if(cnt_shift <= cnt_shift_MAX-1 && shift_signal == 0) begin
        num_02_shift[9:6]   <= (num_02_shift[9:6]   > 4)?(num_02_shift[9:6]   + 3):(num_02_shift[9:6]  );
        num_02_shift[13:10] <= (num_02_shift[13:10] > 4)?(num_02_shift[13:10] + 3):(num_02_shift[13:10]);
    end
    else if(cnt_shift <= cnt_shift_MAX-1 && shift_signal == 1)
        num_02_shift <= num_02_shift << 1;
    else//cnt_shift计数到cnt_shift_MAX时
        num_02_shift <= num_02_shift;//数值保持
end

always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        num_01_shift <= 0;
    else if(cnt_shift == 0)
        num_01_shift <= {8'b0, num_01};
    else if(cnt_shift <= cnt_shift_MAX-1 && shift_signal == 0) begin
        num_01_shift[9:6]   <= (num_01_shift[9:6]   > 4)?(num_01_shift[9:6]   + 3):(num_01_shift[9:6]  );
        num_01_shift[13:10] <= (num_01_shift[13:10] > 4)?(num_01_shift[13:10] + 3):(num_01_shift[13:10]);
    end
    else if(cnt_shift <= cnt_shift_MAX-1 && shift_signal == 1)
        num_01_shift <= num_01_shift << 1;
    else//cnt_shift计数到cnt_shift_MAX时
        num_01_shift <= num_01_shift;//数值保持
end

always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)
        num_00_shift <= 0;
    else if(cnt_shift == 0)
        num_00_shift <= {8'b0, num_00};
    else if(cnt_shift <= cnt_shift_MAX-1 && shift_signal == 0) begin
        num_00_shift[9:6]   <= (num_00_shift[9:6]   > 4)?(num_00_shift[9:6]   + 3):(num_00_shift[9:6]  );
        num_00_shift[13:10] <= (num_00_shift[13:10] > 4)?(num_00_shift[13:10] + 3):(num_00_shift[13:10]);
    end
    else if(cnt_shift <= cnt_shift_MAX-1 && shift_signal == 1)
        num_00_shift <= num_00_shift << 1;
    else//cnt_shift计数到cnt_shift_MAX时
        num_00_shift <= num_00_shift;//数值保持
end



/*cnt_shift计数到cnt_shift_MAX时，更新所有的bit*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        bit_7 <= 4'd10; bit_6 <= 4'd10; bit_5 <= 4'd10; bit_4 <= 4'd10;
        bit_3 <= 4'd10; bit_2 <= 4'd10; bit_1 <= 4'd10; bit_0 <= 4'd10;//全部显示空格
    end
    else if(cnt_shift == cnt_shift_MAX) begin
        bit_7 <= num_02_shift[13:10]; bit_6 <= num_02_shift[9:6];
        bit_5 <= 4'd11;
        bit_4 <= num_01_shift[13:10]; bit_3 <= num_01_shift[9:6];
        bit_2 <= 4'd11;
        bit_1 <= num_00_shift[13:10]; bit_0 <= num_00_shift[9:6];
    end
    else begin
        bit_7 <= bit_7; bit_6 <= bit_6; bit_5 <= bit_5; bit_4 <= bit_4;
        bit_3 <= bit_3; bit_2 <= bit_2; bit_1 <= bit_1; bit_0 <= bit_0;
    end
end

endmodule
