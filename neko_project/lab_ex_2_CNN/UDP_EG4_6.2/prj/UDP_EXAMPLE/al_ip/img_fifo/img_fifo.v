/************************************************************\
**	Copyright (c) 2012-2025 Anlogic Inc.
**	All Right Reserved.
\************************************************************/
/************************************************************\
**	Build time: Oct 16 2025 23:03:19
**	TD version	:	6.2.168116
************************************************************/
`timescale 1ns/1ps
module img_fifo
(
  input   [7:0]                 di,
  input                         clkr,
  input                         rrst,
  input                         re,
  input                         clkw,
  input                         wrst,
  input                         we,
  output  [15:0]                dout,
  output                        empty_flag,
  output                        aempty,
  output                        full_flag,
  output                        afull,
  output                        valid,
  output                        overflow,
  output                        underflow,
  output                        wr_success,
  output  [11:0]                rdusedw,
  output  [12:0]                wrusedw,
  output                        wr_rst_done,
  output                        rd_rst_done
);

  soft_fifo_9c6690866e03
  #(
      .COMMON_CLK_EN(0),
      .MEMORY_TYPE(2),
      .RST_TYPE(1),
      .DATA_WIDTH_W(8),
      .ADDR_WIDTH_W(13),
      .DATA_WIDTH_R(16),
      .ADDR_WIDTH_R(12),
      .DOUT_INITVAL(16'h0),
      .OUTREG_EN("NOREG"),
      .SHOW_AHEAD_EN(0),
      .AL_FULL_NUM(8186),
      .AL_EMPTY_NUM(2),
      .RDUSEDW_WIDTH(12),
      .WRUSEDW_WIDTH(13),
      .ASYNC_RST_SYNC_RELS(0),
      .SYNC_STAGE(2)
  )soft_fifo_9c6690866e03_Inst
  (
      .di(di),
      .clkr(clkr),
      .rrst(rrst),
      .re(re),
      .clkw(clkw),
      .wrst(wrst),
      .we(we),
      .dout(dout),
      .empty_flag(empty_flag),
      .aempty(aempty),
      .full_flag(full_flag),
      .afull(afull),
      .valid(valid),
      .overflow(overflow),
      .underflow(underflow),
      .wr_success(wr_success),
      .rdusedw(rdusedw),
      .wrusedw(wrusedw),
      .wr_rst_done(wr_rst_done),
      .rd_rst_done(rd_rst_done)
  );
endmodule
