module video_delay
#(
	parameter DATA_WIDTH = 24,                       // Video data one clock data width
	parameter H_SIZE = 1024                          // Horizontal resolution (from top.v)
)
(
	input                       video_clk,          // Video pixel clock
	input                       rst,
	output                      read_en,            // Read data enable
	input[DATA_WIDTH - 1:0]     read_data,          // Read data
	input                       hs,                 // horizontal synchronization
	input                       vs,                 // vertical synchronization
	input                       de,                 // video valid

	output                      hs_r,               // horizontal synchronization
	output                      vs_r,               // vertical synchronization
	output                      de_r,               // video valid
	output[DATA_WIDTH - 1:0]    vout_data           // video data
);

// RGB to Gray conversion weights
localparam R_WEIGHT = 8'd76;   // 0.299 * 256
localparam G_WEIGHT = 8'd150;  // 0.587 * 256
localparam B_WEIGHT = 8'd29;   // 0.114 * 256

// Line buffer for Sobel processing (2 lines)
reg [7:0] line_buffer_0 [0:H_SIZE-1];
reg [7:0] line_buffer_1 [0:H_SIZE-1];

// Control signals
reg [10:0] pixel_counter;
reg line_buffer_valid;
reg line_buffer_select;  // 0: buffer0 active, 1: buffer1 active
reg vs_d0, vs_d1;

// Sobel pipeline registers
reg [7:0] gray_pixel;
reg [7:0] window [0:8]; // 3x3 window
reg [10:0] gx, gy;
reg [10:0] gradient;
reg [7:0] edge_result;

// Delay chains for synchronization signals
reg [20:0] hs_d;
reg [20:0] vs_d;
reg [20:0] de_d;
reg [DATA_WIDTH - 1:0] vout_data_r;

// Loop counter
integer i;

// RGB to Gray conversion
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		gray_pixel <= 8'b0;
	end else if (de) begin
		// Simplified gray conversion for better timing
		gray_pixel <= (read_data[23:16] + read_data[15:8] + read_data[7:0]) / 3;
	end
end

// Line buffer management
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		pixel_counter <= 0;
		line_buffer_select <= 0;
		line_buffer_valid <= 0;
		vs_d0 <= 0;
		vs_d1 <= 0;
	end else begin
		// VS edge detection for frame reset
		vs_d0 <= vs;
		vs_d1 <= vs_d0;
		
		if (vs_d0 & ~vs_d1) begin // VS falling edge
			pixel_counter <= 0;
			line_buffer_select <= 0;
			line_buffer_valid <= 0;
		end else if (de) begin
			// Write to current line buffer
			if (line_buffer_select == 0) begin
				line_buffer_0[pixel_counter] <= gray_pixel;
			end else begin
				line_buffer_1[pixel_counter] <= gray_pixel;
			end
			
			pixel_counter <= pixel_counter + 1;
			
			// Switch line buffer at end of line
			if (pixel_counter == H_SIZE-1) begin
				pixel_counter <= 0;
				line_buffer_select <= ~line_buffer_select;
				line_buffer_valid <= 1;
			end
		end
	end
end

// 3x3 window formation for Sobel operator
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		for (i = 0; i < 9; i = i + 1) begin
			window[i] <= 8'b0;
		end
	end else if (de && line_buffer_valid && pixel_counter >= 1 && pixel_counter < H_SIZE-1) begin
		// Form 3x3 window for Sobel convolution
		// Previous line
		window[0] <= (line_buffer_select == 0) ? line_buffer_1[pixel_counter-1] : line_buffer_0[pixel_counter-1];
		window[1] <= (line_buffer_select == 0) ? line_buffer_1[pixel_counter]   : line_buffer_0[pixel_counter];
		window[2] <= (line_buffer_select == 0) ? line_buffer_1[pixel_counter+1] : line_buffer_0[pixel_counter+1];
		
		// Current line
		window[3] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter-1] : line_buffer_1[pixel_counter-1];
		window[4] <= gray_pixel; // Center pixel
		window[5] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter+1] : line_buffer_1[pixel_counter+1];
		
		// Next line (from current line buffer)
		window[6] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter-1] : line_buffer_1[pixel_counter-1];
		window[7] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter]   : line_buffer_1[pixel_counter];
		window[8] <= (line_buffer_select == 0) ? line_buffer_0[pixel_counter+1] : line_buffer_1[pixel_counter+1];
	end else if (de) begin
		// For edge pixels, use simple window
		for (i = 0; i < 9; i = i + 1) begin
			window[i] <= gray_pixel;
		end
	end
end

// Sobel convolution calculation
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		gx <= 0;
		gy <= 0;
		gradient <= 0;
		edge_result <= 0;
	end else if (de) begin
		// Simplified Sobel calculation to avoid timing issues
		// Use absolute differences instead of full convolution
		gx <= (window[2] + window[5] + window[8]) - (window[0] + window[3] + window[6]);
		gy <= (window[0] + window[1] + window[2]) - (window[6] + window[7] + window[8]);
		
		// Absolute value and clamp
		if (gx[10]) gx <= -gx;
		if (gy[10]) gy <= -gy;
		
		// Simple gradient magnitude
		gradient <= gx + gy;
		
		// Clamp to 8-bit range with threshold for better edge visibility
		if (gradient > 128) begin
			edge_result <= 8'hFF;
		end else if (gradient > 64) begin
			edge_result <= gradient[7:0] << 1;
		end else begin
			edge_result <= 8'h00;
		end
	end
end

// Output data assignment with edge enhancement
always @(posedge video_clk or posedge rst) begin
	if (rst == 1'b1) begin
		vout_data_r <= {DATA_WIDTH{1'b0}};
	end else if (de_d[19]) begin // Match original delay timing
		// Convert edge result to RGB with proper timing
		vout_data_r <= {edge_result, edge_result, edge_result};
	end
end

// Synchronization signal delay chain
always @(posedge video_clk or posedge rst) begin
	if (rst) begin
		hs_d <= 21'b0;
		vs_d <= 21'b0;
		de_d <= 21'b0;
	end else begin
		// Maintain original 20-stage delay
		hs_d <= {hs_d[19:0], hs};
		vs_d <= {vs_d[19:0], vs};
		de_d <= {de_d[19:0], de};
	end
end

// Output assignments
assign read_en = de_d[18];  // Original timing
assign hs_r = hs_d[20];
assign vs_r = vs_d[20];
assign de_r = de_d[20];
assign vout_data = vout_data_r;

endmodule
