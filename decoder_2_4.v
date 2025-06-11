/*2-4译码器*/
module decoder_2_4
(
  input   wire    in_1,
  input   wire    in_0,
  
  output  wire    out_0,
  output  wire    out_1,
  output  wire    out_2,
  output  wire    out_3
);

assign out_0 = ((!in_1)&(!in_0));//00
assign out_1 = ((!in_1)&( in_0));//01
assign out_2 = (( in_1)&(!in_0));//10
assign out_3 = (( in_1)&( in_0));//11

endmodule
