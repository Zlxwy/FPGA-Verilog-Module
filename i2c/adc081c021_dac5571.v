/*读一次ADC，然后立马写一次DAC*/
module adc081c021_dac5571 # (
    parameter sys_clk_freq = 50_000_000,
    parameter i2c_clk_speed = 400_000
)
(
    input wire sclk,
    input wire nrst,
    input wire dac_enable, //如果为低电平，则dac一直设置为0，高电平则按照ADC读取到的电压设置
    input wire gs_trig, //输入一个触发信号，触发一次获取电压并设置电压
    output reg gs_done, //获取电压并设置电压完成后，输出一个高电平脉冲
    output reg[7:0] vol, //获取的电压值
    output wire scl,
    inout wire sda,
//逻辑分析仪调试---------------------------------------------------------------------|
    output wire DEBUG_scl,
    output wire DEBUG_sda
//逻辑分析仪调试---------------------------------------------------------------------|
);
//逻辑分析仪调试---------------------------------------------------------------------|
assign DEBUG_scl = scl_out_reg;
assign DEBUG_sda = sda_ctrl==1?sda_out_reg:sda_in_reg;
//逻辑分析仪调试---------------------------------------------------------------------|

reg sda_ctrl;
reg sda_out_reg;
wire sda_in_reg;
assign sda = (sda_ctrl == 1'b1) ? ((sda_out_reg==1'b1)?1'bz:1'b0) : 1'bz;
assign sda_in_reg = sda;
reg scl_out_reg;
assign scl = (scl_out_reg == 1'b1) ? 1'bz : 1'b0;

reg[31:0] cnt_prescaler;
// cnt_prescaler
/*对系统时钟进行分频，得到一个 (能使得scl的频率等于i2c_clk_speed) 的分频计数值*/
parameter cnt_prescaler_MAX = (sys_clk_freq / i2c_clk_speed / 4) - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                               cnt_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX) cnt_prescaler <= 0;
    else                                        cnt_prescaler <= cnt_prescaler + 1;
end

reg signal_prescaler;
// signal_prescaler
/*在cnt_prescaler计数到次大值时，拉高signal_prescaler保持一个时钟周期，产生一个高电平脉冲。推动i2c时序进行*/
parameter cnt_prescaler_MAX_minus_1 = cnt_prescaler_MAX - 1;
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0)                                       signal_prescaler <= 0;
    else if(cnt_prescaler == cnt_prescaler_MAX_minus_1) signal_prescaler <= 1;
    else                                                signal_prescaler <= 0;
end

reg[31:0] gs_step_cnt;
reg is_gsing;
parameter gs_step_cnt_MAX = 226;
// gs_step_cnt
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) gs_step_cnt <= 0;
    else if(is_gsing && signal_prescaler && gs_step_cnt == gs_step_cnt_MAX) gs_step_cnt <= 0;
    else if(is_gsing && signal_prescaler) gs_step_cnt <= gs_step_cnt + 1;
    else if(is_gsing) gs_step_cnt <= gs_step_cnt;
    else gs_step_cnt <= 0;
end

// is_gsing
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) is_gsing <= 0;
    else if(is_gsing && signal_prescaler && gs_step_cnt == gs_step_cnt_MAX) is_gsing <= 0;
    else if(!is_gsing && gs_trig) is_gsing <= 1;
    else is_gsing <= is_gsing;
end

wire[7:0] adc_equi_addr_read, dac_equi_addr_write;
assign adc_equi_addr_read = 8'b1010_1001; //8'hAB是读地址（赛方的原理图标记错误了）
assign dac_equi_addr_write = 8'b1001_1000;
reg[7:0] reg_send_byte;
reg[15:0] reg_recv_byte;
// scl(scl_out_reg), sda(sda_ctrl, sda_out_reg)
// reg_send_byte, reg_recv_byte, vol
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) begin
        scl_out_reg <= 1'b1;
        sda_ctrl <= 1;
        sda_out_reg <= 1'b1;
        reg_send_byte <= 8'b1111_1111;
        reg_recv_byte <= 16'b1111_1111_1000_1111;
        vol <= 0;
    end
    else if(is_gsing && signal_prescaler) begin
        case(gs_step_cnt)
            0  : begin sda_ctrl <= 1; sda_out_reg <= 0;                     end
            1  : begin scl_out_reg <= 0; reg_send_byte <= adc_equi_addr_read;   end
            2  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];      end
            3  : begin scl_out_reg <= 1;                                    end
            5  : begin scl_out_reg <= 0;                                    end
            6  : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];      end
            7  : begin scl_out_reg <= 1;                                    end
            9  : begin scl_out_reg <= 0;                                    end
            10 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];      end
            11 : begin scl_out_reg <= 1;                                    end
            13 : begin scl_out_reg <= 0;                                    end
            14 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];      end
            15 : begin scl_out_reg <= 1;                                    end
            17 : begin scl_out_reg <= 0;                                    end
            18 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];      end
            19 : begin scl_out_reg <= 1;                                    end
            21 : begin scl_out_reg <= 0;                                    end
            22 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];      end
            23 : begin scl_out_reg <= 1;                                    end
            25 : begin scl_out_reg <= 0;                                    end
            26 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];      end
            27 : begin scl_out_reg <= 1;                                    end
            29 : begin scl_out_reg <= 0;                                    end
            30 : begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];      end
            31 : begin scl_out_reg <= 1;                                    end
            33 : begin scl_out_reg <= 0;                                    end
            34 : begin sda_ctrl <= 0; sda_out_reg <= 1;                     end
            35 : begin scl_out_reg <= 1;                                    end
            37 : begin scl_out_reg <= 0; reg_recv_byte <= 8'b1111_1111;     end
            39 : begin scl_out_reg <= 1;                                    end
            40 : begin sda_ctrl <= 0; reg_recv_byte[15] <= sda_in_reg;      end
            41 : begin scl_out_reg <= 0;                                    end
            43 : begin scl_out_reg <= 1;                                    end
            44:  begin sda_ctrl <= 0; reg_recv_byte[14] <= sda_in_reg;      end
            45 : begin scl_out_reg <= 0;                                    end
            47 : begin scl_out_reg <= 1;                                    end
            48:  begin sda_ctrl <= 0; reg_recv_byte[13] <= sda_in_reg;      end
            49 : begin scl_out_reg <= 0;                                    end
            51 : begin scl_out_reg <= 1;                                    end
            52:  begin sda_ctrl <= 0; reg_recv_byte[12] <= sda_in_reg;      end
            53 : begin scl_out_reg <= 0;                                    end
            55 : begin scl_out_reg <= 1;                                    end
            56:  begin sda_ctrl <= 0; reg_recv_byte[11] <= sda_in_reg;      end
            57 : begin scl_out_reg <= 0;                                    end
            59 : begin scl_out_reg <= 1;                                    end
            60:  begin sda_ctrl <= 0; reg_recv_byte[10] <= sda_in_reg;      end
            61 : begin scl_out_reg <= 0;                                    end
            63 : begin scl_out_reg <= 1;                                    end
            64:  begin sda_ctrl <= 0; reg_recv_byte[9] <= sda_in_reg;       end
            65 : begin scl_out_reg <= 0;                                    end
            67 : begin scl_out_reg <= 1;                                    end
            68:  begin sda_ctrl <= 0; reg_recv_byte[8] <= sda_in_reg;       end
            69 : begin scl_out_reg <= 0;                                    end
            70 : begin sda_ctrl <= 1; sda_out_reg <= 0;                     end
            71 : begin scl_out_reg <= 1;                                    end
            73 : begin scl_out_reg <= 0;                                    end
            74 : begin sda_ctrl <= 0; sda_out_reg <= 1;                     end
            75 : begin scl_out_reg <= 1;                                    end
            76:  begin sda_ctrl <= 0; reg_recv_byte[7] <= sda_in_reg;       end
            77 : begin scl_out_reg <= 0;                                    end
            79 : begin scl_out_reg <= 1;                                    end
            80:  begin sda_ctrl <= 0; reg_recv_byte[6] <= sda_in_reg;       end
            81 : begin scl_out_reg <= 0;                                    end
            83 : begin scl_out_reg <= 1;                                    end
            84:  begin sda_ctrl <= 0; reg_recv_byte[5] <= sda_in_reg;       end
            85 : begin scl_out_reg <= 0;                                    end
            87 : begin scl_out_reg <= 1;                                    end
            88:  begin sda_ctrl <= 0; reg_recv_byte[4] <= sda_in_reg;       end
            89 : begin scl_out_reg <= 0;                                    end
            91 : begin scl_out_reg <= 1;                                    end
            92:  begin sda_ctrl <= 0; reg_recv_byte[3] <= sda_in_reg;       end
            93 : begin scl_out_reg <= 0;                                    end
            95 : begin scl_out_reg <= 1;                                    end
            96:  begin sda_ctrl <= 0; reg_recv_byte[2] <= sda_in_reg;       end
            97 : begin scl_out_reg <= 0;                                    end
            99 : begin scl_out_reg <= 1;                                    end
            100: begin sda_ctrl <= 0; reg_recv_byte[1] <= sda_in_reg;       end
            101: begin scl_out_reg <= 0;                                    end
            103: begin scl_out_reg <= 1;                                    end
            104: begin sda_ctrl <= 0; reg_recv_byte[0] <= sda_in_reg;       end
            105: begin scl_out_reg <= 0;                                    end
            106: begin sda_ctrl <= 1; sda_out_reg <= 1;                     end
            107: begin scl_out_reg <= 1;                                    end
            109: begin scl_out_reg <= 0;                                    end
            110: begin sda_ctrl <= 1; sda_out_reg <= 0;                     end
            111: begin scl_out_reg <= 1;                                    end
            112: begin sda_ctrl <= 1; sda_out_reg <= 1; vol <= reg_recv_byte[11:4];  end
            (113+0  ): begin sda_ctrl <= 1; sda_out_reg <= 0;                 end
            (113+1  ): begin scl_out_reg <= 0; reg_send_byte <= dac_equi_addr_write;   end
            (113+2  ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            (113+3  ): begin scl_out_reg <= 1;                                end
            (113+5  ): begin scl_out_reg <= 0;                                end
            (113+6  ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            (113+7  ): begin scl_out_reg <= 1;                                end
            (113+9  ): begin scl_out_reg <= 0;                                end
            (113+10 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            (113+11 ): begin scl_out_reg <= 1;                                end
            (113+13 ): begin scl_out_reg <= 0;                                end
            (113+14 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            (113+15 ): begin scl_out_reg <= 1;                                end
            (113+17 ): begin scl_out_reg <= 0;                                end
            (113+18 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            (113+19 ): begin scl_out_reg <= 1;                                end
            (113+21 ): begin scl_out_reg <= 0;                                end
            (113+22 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            (113+23 ): begin scl_out_reg <= 1;                                end
            (113+25 ): begin scl_out_reg <= 0;                                end
            (113+26 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            (113+27 ): begin scl_out_reg <= 1;                                end
            (113+29 ): begin scl_out_reg <= 0;                                end
            (113+30 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            (113+31 ): begin scl_out_reg <= 1;                                end
            (113+33 ): begin scl_out_reg <= 0;                                end
            (113+34 ): begin sda_ctrl <= 0;                                   end
            (113+35 ): begin scl_out_reg <= 1;                                end
            (113+37 ): begin scl_out_reg <= 0; reg_send_byte <= {4'b0000, (dac_enable)?vol[7:4]:0};     end
            (113+38 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            (113+39 ): begin scl_out_reg <= 1;                                end
            (113+41 ): begin scl_out_reg <= 0;                                end
            (113+42 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            (113+43 ): begin scl_out_reg <= 1;                                end
            (113+45 ): begin scl_out_reg <= 0;                                end
            (113+46 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            (113+47 ): begin scl_out_reg <= 1;                                end
            (113+49 ): begin scl_out_reg <= 0;                                end
            (113+50 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            (113+51 ): begin scl_out_reg <= 1;                                end
            (113+53 ): begin scl_out_reg <= 0;                                end
            (113+54 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            (113+55 ): begin scl_out_reg <= 1;                                end
            (113+57 ): begin scl_out_reg <= 0;                                end
            (113+58 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            (113+59 ): begin scl_out_reg <= 1;                                end
            (113+61 ): begin scl_out_reg <= 0;                                end
            (113+62 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            (113+63 ): begin scl_out_reg <= 1;                                end
            (113+65 ): begin scl_out_reg <= 0;                                end
            (113+66 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            (113+67 ): begin scl_out_reg <= 1;                                end
            (113+69 ): begin scl_out_reg <= 0;                                end
            (113+70 ): begin sda_ctrl <= 0;                                   end
            (113+71 ): begin scl_out_reg <= 1;                                end
            (113+73 ): begin scl_out_reg <= 0; reg_send_byte <= {(dac_enable)?vol[3:0]:0, 4'b0000};   end
            (113+74 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[7];  end
            (113+75 ): begin scl_out_reg <= 1;                                end
            (113+77 ): begin scl_out_reg <= 0;                                end
            (113+78 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[6];  end
            (113+79 ): begin scl_out_reg <= 1;                                end
            (113+81 ): begin scl_out_reg <= 0;                                end
            (113+82 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[5];  end
            (113+83 ): begin scl_out_reg <= 1;                                end
            (113+85 ): begin scl_out_reg <= 0;                                end
            (113+86 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[4];  end
            (113+87 ): begin scl_out_reg <= 1;                                end
            (113+89 ): begin scl_out_reg <= 0;                                end
            (113+90 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[3];  end
            (113+91 ): begin scl_out_reg <= 1;                                end
            (113+93 ): begin scl_out_reg <= 0;                                end
            (113+94 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[2];  end
            (113+95 ): begin scl_out_reg <= 1;                                end
            (113+97 ): begin scl_out_reg <= 0;                                end
            (113+98 ): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[1];  end
            (113+99 ): begin scl_out_reg <= 1;                                end
            (113+101): begin scl_out_reg <= 0;                                end
            (113+102): begin sda_ctrl <= 1; sda_out_reg <= reg_send_byte[0];  end
            (113+103): begin scl_out_reg <= 1;                                end
            (113+105): begin scl_out_reg <= 0;                                end
            (113+106): begin sda_ctrl <= 0;                                   end
            (113+107): begin scl_out_reg <= 1;                                end
            (113+109): begin scl_out_reg <= 0;                                end
            (113+110): begin sda_ctrl <= 1; sda_out_reg <= 0;                 end
            (113+111): begin scl_out_reg <= 1;                                end
            (113+112): begin sda_ctrl <= 1; sda_out_reg <= 1;                 end
        default: begin
            scl_out_reg <= scl_out_reg;
            sda_ctrl <= sda_ctrl;
            sda_out_reg <= sda_out_reg;
            reg_send_byte <= reg_send_byte;
            reg_recv_byte <= reg_recv_byte;
            vol <= vol;
        end
        endcase
    end
    else begin
        scl_out_reg <= scl_out_reg;
        sda_ctrl <= sda_ctrl;
        sda_out_reg <= sda_out_reg;
        reg_send_byte <= reg_send_byte;
        reg_recv_byte <= reg_recv_byte;
        vol <= vol;
    end
end

// gs_done
always @(posedge sclk or negedge nrst) begin
    if(nrst == 0) gs_done <= 0;
    else if(is_gsing && signal_prescaler && gs_step_cnt == gs_step_cnt_MAX) gs_done <= 1;
    else gs_done <= 0;
end

endmodule