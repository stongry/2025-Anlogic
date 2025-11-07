`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: anlgoic
// Author: Codex assistant
// Description:
//  Static selector for SDRAM write path. Synchronises a slow configuration select
//  signal into the participating clock domains, gates write enables, and switches
//  the write clock through a BUFGMUX. Intended for use with mutually exclusive
//  data sources such as camera vs. SD card.
//////////////////////////////////////////////////////////////////////////////////

module sdram_write_static_sel #(
    parameter integer DATA_WIDTH = 24,
    parameter         DEVICE     = "EG4"
)(    
    input  wire                     rst_n,
    input  wire                     clk_cfg,
    input  wire                     clk_a,
    input  wire                     clk_b,
    input  wire                     sel_raw,

    input  wire                     en_a_raw,
    input  wire [DATA_WIDTH-1:0]    data_a_raw,

    input  wire                     en_b_raw,
    input  wire [DATA_WIDTH-1:0]    data_b_raw,

    output wire                     clk_out,
    output wire                     en_out,
    output wire [DATA_WIDTH-1:0]    data_out,
    output wire                     sel_sync
);

reg sel_cfg_d0, sel_cfg_d1;
always @(posedge clk_cfg or negedge rst_n) begin
    if(!rst_n) begin
        sel_cfg_d0 <= 1'b0;
        sel_cfg_d1 <= 1'b0;
    end else begin
        sel_cfg_d0 <= sel_raw;
        sel_cfg_d1 <= sel_cfg_d0;
    end
end
assign sel_sync = sel_cfg_d1;

reg sel_a_d0, sel_a_d1;
always @(posedge clk_a or negedge rst_n) begin
    if(!rst_n) begin
        sel_a_d0 <= 1'b0;
        sel_a_d1 <= 1'b0;
    end else begin
        sel_a_d0 <= sel_sync;
        sel_a_d1 <= sel_a_d0;
    end
end
wire sel_a_sync = sel_a_d1;

reg sel_b_d0, sel_b_d1;
always @(posedge clk_b or negedge rst_n) begin
    if(!rst_n) begin
        sel_b_d0 <= 1'b0;
        sel_b_d1 <= 1'b0;
    end else begin
        sel_b_d0 <= sel_sync;
        sel_b_d1 <= sel_b_d0;
    end
end
wire sel_b_sync = sel_b_d1;

wire en_a_masked = en_a_raw & ~sel_a_sync;
wire en_b_masked = en_b_raw &  sel_b_sync;

assign en_out   = sel_sync ? en_b_masked : en_a_masked;
assign data_out = sel_sync ? data_b_raw  : data_a_raw;

BUFGMUX #(
    .DEVICE(DEVICE)
) u_clk_sel (
    .o (clk_out),
    .i0(clk_a),
    .i1(clk_b),
    .s (sel_sync)
);

endmodule
