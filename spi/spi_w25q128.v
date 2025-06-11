/* 在spi_ctrl模块的基础上，这个模块能独立完成以下两个功能：
 * 写入一次数据（至少需要1秒钟，如果要连续写入的话，推荐每2秒写入一次）
        发送写使能命令、发送扇区清除命令、发送24位地址、
        发送读状态命令-不断检测接收字节最后一位是否为1(忙)、
        发送写使能命令、发送页编程命令、发送24位地址、连续写入字节（不能超页）、
        发送读状态命令-不断检测接收字节最后一位是否为1(忙)。完成。
 * 读出一次数据（很快）
        发送读数据命令、发送24位地址、连续读取字节（没有页的限制）。完成。 */
module spi_w25q128 #(
    parameter sclk_freq = 50_000_000, //系统时钟频率
    parameter sck_speed = 500_000 //spi_sck的频率
)    
(
    input wire sclk,
    input wire nrst,
    input wire[23:0] flash_addr,
    input wire[7:0] write_byte,
    output reg[7:0] read_byte,

    input wire write_trigger,
    input wire read_trigger,
    output reg write_done,
    output reg read_done,

    output reg cs,
    output wire sck,
    output wire mosi,
    input wire miso
);

reg[16:0] step_cnt;
parameter write_step_cnt_MAX = 14;
parameter read_step_cnt_MAX = 5;
reg is_writing, is_reading;
wire swap_done;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) step_cnt <= 0;
    
    else if(is_writing && (swap_done || first_operation_signal || signal_for_cs) && step_cnt == write_step_cnt_MAX) step_cnt <= 0;
    else if(is_writing && (swap_done || first_operation_signal || signal_for_cs)) step_cnt <= step_cnt + 1;
    else if(is_writing) step_cnt <= step_cnt;

    /*读取不需要延时，一直拉低cs即可，不需要signal_for_cs参与*/
    else if(is_reading && (swap_done || first_operation_signal) && step_cnt == read_step_cnt_MAX) step_cnt <= 0;
    else if(is_reading && (swap_done || first_operation_signal)) step_cnt <= step_cnt + 1;
    else if(is_reading) step_cnt <= step_cnt;

    else step_cnt <= 0;
end

always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        is_writing <= 0;
        is_reading <= 0;
    end

    else if(is_writing && swap_done && step_cnt == write_step_cnt_MAX) is_writing <= 0;
    else if(is_reading && swap_done && step_cnt == read_step_cnt_MAX) is_reading <= 0;

    else if(!is_writing && !is_reading && write_trigger && read_trigger) begin
        is_writing <= is_writing;
        is_reading <= is_reading;
    end

    else if(!is_writing && !is_reading && write_trigger) is_writing <= 1;
    else if(!is_writing && !is_reading && read_trigger) is_reading <= 1;

    else begin
        is_writing <= is_writing;
        is_reading <= is_reading;
    end
end

reg first_operation_signal; //驱动第一次操作的一个脉冲信号
//因为在is_xxxxing置起后，都需要靠swap_done来驱动步骤进行，而第一个步骤还没有任何驱动，需要自行添加一个脉冲来驱动
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) first_operation_signal <= 0;
    else if(!is_writing && !is_reading && write_trigger && read_trigger) first_operation_signal <= 0;
    else if(!is_writing && !is_reading && (write_trigger || read_trigger)) first_operation_signal <= 1;
    else first_operation_signal <= 0;
end

localparam W25Q64_PAGE_PROGRAM          = 8'h02;
localparam W25Q64_READ_DATA             = 8'h03;
localparam W25Q64_WRITE_DISABLE         = 8'h04;
localparam W25Q64_READ_STATUS_REGISTER  = 8'h05;
localparam W25Q64_WRITE_ENABLE          = 8'h06;
localparam W25Q64_SECTOR_ERASE_4KB      = 8'h20;
localparam W25Q64_DUMMY_BYTE            = 8'hFF;

/*是为了能让cs线在完成一次操作被释放后，能隔一段时间再次拉低，就用这个signal_for_cs信号触发*/
/*这个计数周期为250ms，是为了能等待芯片忙状态结束*/
reg[31:0] cnt_for_cs;
reg signal_for_cs;
parameter cnt_for_cs_MAX = (50000000 / 4) - 1;
parameter cnt_for_cs_MAX_minus_1 = cnt_for_cs_MAX - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) cnt_for_cs <= 0;
    else if(is_writing && swap_done && (step_cnt==1 || step_cnt==6 || step_cnt==8))
        cnt_for_cs <= cnt_for_cs + 1; //如果检测到swap_done了，开始一次计数
    else if(cnt_for_cs > 0 && cnt_for_cs < cnt_for_cs_MAX) cnt_for_cs <= cnt_for_cs + 1;
    else cnt_for_cs <= 0;
end
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) signal_for_cs <= 0;
    else if(cnt_for_cs == cnt_for_cs_MAX_minus_1) signal_for_cs <= 1;
    else signal_for_cs <= 0;
end

wire[7:0] wire_recv_byte; //这个用来接上spi_ctrl模块的recv_byte输出
reg[7:0] reg_send_byte;
reg[23:0] reg_flash_addr;
reg swap_trigger;
// read_byte, reg_send_byte
// swap_trigger
/*开始执行写入/读取步骤*/
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        cs <= 1;
        read_byte <= 8'b1111_1111;
        reg_send_byte <= 8'b1111_1101;
        swap_trigger <= 0;
    end

    else if(is_writing && (first_operation_signal || swap_done || signal_for_cs)) begin
        case(step_cnt)
            0:  begin cs <= 0; reg_send_byte <= W25Q64_WRITE_ENABLE; swap_trigger <= 1; end //拉低cs，触发一次传输
            1:  begin cs <= 1; end //cs回高，是为了能重新拉低一次cs
            2:  begin cs <= 0; reg_send_byte <= W25Q64_SECTOR_ERASE_4KB; swap_trigger <= 1; end //拉低cs，触发一次传输
            3:  begin cs <= 0; reg_send_byte <= flash_addr[23:16]; swap_trigger <= 1; end
            4:  begin cs <= 0; reg_send_byte <= flash_addr[15:8]; swap_trigger <= 1; end
            5:  begin cs <= 0; reg_send_byte <= flash_addr[7:0]; swap_trigger <= 1; end
            6:  begin cs <= 1; end
            7:  begin cs <= 0; reg_send_byte <= W25Q64_WRITE_ENABLE; swap_trigger <= 1; end
            8:  begin cs <= 1; end
            9:  begin cs <= 0; reg_send_byte <= W25Q64_PAGE_PROGRAM; swap_trigger <= 1; end
            10: begin cs <= 0; reg_send_byte <= flash_addr[23:16]; swap_trigger <= 1; end
            11: begin cs <= 0; reg_send_byte <= flash_addr[15:8]; swap_trigger <= 1; end
            12: begin cs <= 0; reg_send_byte <= flash_addr[7:0]; swap_trigger <= 1; end
            13: begin cs <= 0; reg_send_byte <= write_byte; swap_trigger <= 1; end
            14: begin cs <= 1; end
            default: begin cs <= cs; end
        endcase
    end

    else if(is_reading && (first_operation_signal || swap_done)) begin
        case(step_cnt)
            0: begin cs <= 0; reg_send_byte <= W25Q64_READ_DATA; swap_trigger <= 1; end
            1: begin cs <= 0; reg_send_byte <= flash_addr[23:16]; swap_trigger <= 1; end
            2: begin cs <= 0; reg_send_byte <= flash_addr[15:8]; swap_trigger <= 1; end
            3: begin cs <= 0; reg_send_byte <= flash_addr[7:0]; swap_trigger <= 1; end
            4: begin cs <= 0; reg_send_byte <= W25Q64_DUMMY_BYTE; swap_trigger <= 1; end
            5: begin cs <= 1; read_byte <= wire_recv_byte; end
            default: begin cs <= cs; end
        endcase
    end

    else begin
        cs <= cs;
        read_byte <= read_byte;
        reg_send_byte <= reg_send_byte;
        swap_trigger <= 0;
    end
end

always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        write_done <= 0;
        read_done <= 0;
    end

    else if(is_writing && swap_done && step_cnt == write_step_cnt_MAX) write_done <= 1;
    else if(is_reading && swap_done && step_cnt == read_step_cnt_MAX) read_done <= 1;

    else begin
        write_done <= 0;
        read_done <= 0;
    end
end

spi_ctrl #(
    .sclk_freq (sclk_freq), //系统时钟频率
    .sck_speed (sck_speed) //spi_sck的频率
) spi_ctrl_inst (
    .sclk(sclk),
    .nrst(nrst),

    .send_byte(reg_send_byte),
    .recv_byte(wire_recv_byte),

    .swap_trigger(swap_trigger),
    .swap_done(swap_done),

    // output reg cs,
    .sck(sck),
    .mosi(mosi),
    .miso(miso)
);

endmodule