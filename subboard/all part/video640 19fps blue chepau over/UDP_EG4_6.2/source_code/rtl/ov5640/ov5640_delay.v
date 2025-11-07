module ov5640_delay( 
	input 					clk,
    input					rst_n,
	
	input 					cmos_frame_vsync,
	input 					cmos_frame_href,
	input 					cmos_frame_valid,
	input 		[15:0] 		cmos_wr_data,
    
	output             		cam_write_en,
	output 		[31:0]      cam_write_data,
	output  reg             cam_write_req,
	input               	cam_write_req_ack
);
reg cmos_frame_href_d0;
reg cmos_frame_vsync_d0;
reg cmos_frame_valid_d0;
reg [15:0] cmos_wr_data_d0;
reg cmos_frame_href_d1;
reg cmos_frame_vsync_d1;
reg cmos_frame_valid_d1;
reg [15:0] cmos_wr_data_d1;

wire [4:0] r5 = cmos_wr_data_d1[15:11];
wire [5:0] g6 = cmos_wr_data_d1[10:5];
wire [4:0] b5 = cmos_wr_data_d1[4:0];
wire [7:0] cam_R,cam_G,cam_B;
assign cam_R = {r5, r5[4:2]};
assign cam_G = {g6, g6[5:4]};
assign cam_B = {b5, b5[4:2]};
assign cam_write_data = {cam_R,cam_G,cam_B,8'd0};//cmos_wr_data_d1 to 888
assign cam_write_en = cmos_frame_valid_d1;

always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)
	begin
		cmos_frame_href_d0 <= 1'b0;
		cmos_frame_vsync_d0 <= 1'b0;
		cmos_frame_valid_d0 <= 1'b0;
        cmos_wr_data_d0 <= 16'd0;
	end
	else
	begin
		cmos_frame_href_d0 <= cmos_frame_href;
		cmos_frame_vsync_d0 <= cmos_frame_vsync;
		cmos_frame_valid_d0 <= cmos_frame_valid;
        cmos_wr_data_d0 <= cmos_wr_data;
        
		cmos_frame_href_d1 <= cmos_frame_href_d0;
		cmos_frame_vsync_d1 <= cmos_frame_vsync_d0;
		cmos_frame_valid_d1 <= cmos_frame_valid_d0;	
		cmos_wr_data_d1 <= cmos_wr_data_d0;
        
    end
end

always@(posedge clk or negedge rst_n)
begin
	if(~rst_n)
	begin
		cam_write_req <= 1'b0;
    end
	else if(cmos_frame_vsync_d0 & ~cmos_frame_vsync) //vertical synchronization edge (the rising or falling edges are OK)
    begin
		cam_write_req <= 1'b1;
    end
    else if(cam_write_req_ack)begin
		cam_write_req <= 1'b0;
    end
end

endmodule
