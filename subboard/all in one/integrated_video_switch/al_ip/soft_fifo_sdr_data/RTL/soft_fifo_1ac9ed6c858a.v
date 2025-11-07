
`timescale 1ns/1ps
module soft_fifo_1ac9ed6c858a #(
    parameter                          COMMON_CLK_EN        = 0,
    parameter                          MEMORY_TYPE          = 0,
    parameter                          RST_TYPE             = 1,
    parameter                          DATA_WIDTH_W         = 8,
    parameter                          ADDR_WIDTH_W         = 10,
    parameter                          DATA_DEPTH_W         = 2**ADDR_WIDTH_W,
    parameter                          DATA_WIDTH_R         = 8,
    parameter                          ADDR_WIDTH_R         = 10,
    parameter                          DATA_DEPTH_R         = 2**ADDR_WIDTH_R,
    parameter                          DOUT_INITVAL         = 16'd0,
    parameter                          OUTREG_EN            = "NOREG",
    parameter                          SHOW_AHEAD_EN        = 1,
    parameter                          AL_FULL_NUM          = 55,
    parameter                          AL_EMPTY_NUM         = 3,
    parameter                          RDUSEDW_WIDTH        = 11,
    parameter                          WRUSEDW_WIDTH        = 11,
    parameter                          ASYNC_RST_SYNC_RELS  = 1,
    parameter                          SYNC_STAGE           = 2
)(
    
    input                              rrst,
    input                              wrst,
    
    input                              clkr,
    input                              clkw,
    
    input [DATA_WIDTH_W-1:0]           di,
    input                              re,
    input                              we,
    output [DATA_WIDTH_R-1:0]          dout,
    output                             empty_flag,
    output                             aempty,
    output                             full_flag,
    output                             afull,
    output                             valid,
    output                             overflow,
    output                             underflow,
    output                             wr_success,
    output [RDUSEDW_WIDTH-1:0]         rdusedw,
    output [WRUSEDW_WIDTH-1:0]         wrusedw,
    output                             wr_rst_done,
    output                             rd_rst_done
);

soft_fifo_core_1ac9ed6c858a #(
    .COMMON_CLK_EN          (COMMON_CLK_EN          ),
    .MEMORY_TYPE            (MEMORY_TYPE            ),
    .RST_TYPE               (RST_TYPE               ),
    .DATA_WIDTH_W           (DATA_WIDTH_W           ),
    .ADDR_WIDTH_W           (ADDR_WIDTH_W           ),
    .DATA_DEPTH_W           (DATA_DEPTH_W           ),
    .DATA_WIDTH_R           (DATA_WIDTH_R           ),
    .ADDR_WIDTH_R           (ADDR_WIDTH_R           ),
    .DATA_DEPTH_R           (DATA_DEPTH_R           ),
    .DOUT_INITVAL           (DOUT_INITVAL           ),
    .OUTREG_EN              (OUTREG_EN              ),
    .SHOW_AHEAD_EN          (SHOW_AHEAD_EN          ),
    .AL_FULL_NUM            (AL_FULL_NUM            ),
    .AL_EMPTY_NUM           (AL_EMPTY_NUM           ),
    .RDUSEDW_WIDTH          (RDUSEDW_WIDTH          ),
    .WRUSEDW_WIDTH          (WRUSEDW_WIDTH          ),
    .ASYNC_RST_SYNC_RELS    (ASYNC_RST_SYNC_RELS    ),
    .SYNC_STAGE             (SYNC_STAGE             )
)soft_fifo_core_inst(
    
    .rst                    (1'b0                    ),
    
    .srst                   (1'b0                   ),
    
    .rrst                   (rrst                   ),
    .wrst                   (wrst                   ),
    
    .clkr                   (clkr                   ),
    .clkw                   (clkw                   ),
    .clk                    (1'b0                   ),
    
    .di                     (di                     ),
    .re                     (re                     ),
    .we                     (we                     ),
    .dout                   (dout                   ),
    .empty_flag             (empty_flag             ),
    .aempty                 (aempty                 ),
    .full_flag              (full_flag              ),
    .afull                  (afull                  ),
    .valid                  (valid                  ),
    .overflow               (overflow               ),
    .underflow              (underflow              ),
    .wr_success             (wr_success             ),
    .rdusedw                (rdusedw                ),
    .wrusedw                (wrusedw                ),
    .wr_rst_done            (wr_rst_done            ),
    .rd_rst_done            (rd_rst_done            )
);

endmodule

