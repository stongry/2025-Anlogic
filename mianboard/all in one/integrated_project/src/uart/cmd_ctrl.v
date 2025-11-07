`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Anlogic
// Author : Codex assistant
// Module : cmd_ctrl
// Description:
//   Lightweight UART command parser used to control high level features in the
//   design. The command set is intentionally small:
//     * "S0" / "S1"  : disable / enable SD-card based frame load
//     * "D0" / "D1"  : route camera / SD path into the video pipeline
//     * "R"          : restore both settings to their default inputs
//     * "?"          : report the current state (SD=?, DISP=?)
//     * "H"          : print a short help string
//   Commands are case insensitive. Characters other than the ones listed above
//   trigger an "ERR" response.
//////////////////////////////////////////////////////////////////////////////////

module cmd_ctrl #(
    parameter integer CLK_FRE   = 50,       // MHz
    parameter integer BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire rst_n,
    input  wire uart_rx,
    output wire uart_tx,

    input  wire default_sd_enable,
    input  wire default_display_sel,

    output reg  sd_read_enable,
    output reg  display_use_sd
);

localparam CMD_IDLE     = 2'd0;
localparam CMD_WAIT_VAL = 2'd1;

localparam TARGET_NONE = 2'd0;
localparam TARGET_SD   = 2'd1;
localparam TARGET_DISP = 2'd2;

localparam RESP_NONE   = 3'd0;
localparam RESP_OK     = 3'd1;
localparam RESP_ERR    = 3'd2;
localparam RESP_STATUS = 3'd3;
localparam RESP_HELP   = 3'd4;

wire [7:0] rx_data;
wire       rx_valid;
wire       rx_ready = 1'b1;

reg [7:0] rx_byte;
reg       rx_valid_d;
wire      rx_new = rx_valid & ~rx_valid_d;

wire       tx_ready;
reg  [7:0] tx_data_r;
reg        tx_valid_r;

reg [1:0] cmd_state;
reg [1:0] cmd_target;

reg        resp_request;
reg [2:0]  resp_request_type;
reg        defaults_loaded;
reg        resp_pending;
reg [2:0]  resp_pending_type;
reg        resp_active;
reg [2:0]  resp_type_active;
reg [4:0]  resp_index;

function [7:0] to_upper;
    input [7:0] ch;
begin
    if(ch >= "a" && ch <= "z")
        to_upper = ch - 8'd32;
    else
        to_upper = ch;
end
endfunction

function is_whitespace;
    input [7:0] ch;
begin
    case(ch)
        8'h0D,
        8'h0A,
        8'h20,
        8'h09:
            is_whitespace = 1'b1;
        default:
            is_whitespace = 1'b0;
    endcase
end
endfunction

function [4:0] resp_length;
    input [2:0] type;
begin
    case(type)
        RESP_OK    : resp_length = 5'd3;
        RESP_ERR   : resp_length = 5'd4;
        RESP_STATUS: resp_length = 5'd12;
        RESP_HELP  : resp_length = 5'd31;
        default    : resp_length = 5'd0;
    endcase
end
endfunction

function [7:0] resp_char;
    input [2:0] type;
    input [4:0] index;
    input       sd_en;
    input       disp_sel;
begin
    case(type)
        RESP_OK: begin
            case(index)
                5'd0: resp_char = "O";
                5'd1: resp_char = "K";
                default: resp_char = 8'h0A;
            endcase
        end
        RESP_ERR: begin
            case(index)
                5'd0: resp_char = "E";
                5'd1: resp_char = "R";
                5'd2: resp_char = "R";
                default: resp_char = 8'h0A;
            endcase
        end
        RESP_STATUS: begin
            case(index)
                5'd0 : resp_char = "S";
                5'd1 : resp_char = "D";
                5'd2 : resp_char = "=";
                5'd3 : resp_char = sd_en ? "1" : "0";
                5'd4 : resp_char = " ";
                5'd5 : resp_char = "D";
                5'd6 : resp_char = "I";
                5'd7 : resp_char = "S";
                5'd8 : resp_char = "P";
                5'd9 : resp_char = "=";
                5'd10: resp_char = disp_sel ? "1" : "0";
                default: resp_char = 8'h0A;
            endcase
        end
        RESP_HELP: begin
            case(index)
                5'd0 : resp_char = "S";
                5'd1 : resp_char = "0";
                5'd2 : resp_char = "/";
                5'd3 : resp_char = "S";
                5'd4 : resp_char = "1";
                5'd5 : resp_char = " ";
                5'd6 : resp_char = "S";
                5'd7 : resp_char = "D";
                5'd8 : resp_char = ",";
                5'd9 : resp_char = " ";
                5'd10: resp_char = "D";
                5'd11: resp_char = "0";
                5'd12: resp_char = "/";
                5'd13: resp_char = "D";
                5'd14: resp_char = "1";
                5'd15: resp_char = " ";
                5'd16: resp_char = "D";
                5'd17: resp_char = "I";
                5'd18: resp_char = "S";
                5'd19: resp_char = "P";
                5'd20: resp_char = ",";
                5'd21: resp_char = " ";
                5'd22: resp_char = "?";
                5'd23: resp_char = " ";
                5'd24: resp_char = "S";
                5'd25: resp_char = "T";
                5'd26: resp_char = "A";
                5'd27: resp_char = "T";
                5'd28: resp_char = "U";
                5'd29: resp_char = "S";
                default: resp_char = 8'h0A;
            endcase
        end
        default: resp_char = 8'h00;
    endcase
end
endfunction

uart_rx #(
    .CLK_FRE  (CLK_FRE),
    .BAUD_RATE(BAUD_RATE)
) u_uart_rx (
    .clk          (clk),
    .rst_n        (rst_n),
    .rx_data      (rx_data),
    .rx_data_valid(rx_valid),
    .rx_data_ready(rx_ready),
    .rx_pin       (uart_rx)
);

uart_tx #(
    .CLK_FRE  (CLK_FRE),
    .BAUD_RATE(BAUD_RATE)
) u_uart_tx (
    .clk          (clk),
    .rst_n        (rst_n),
    .tx_data      (tx_data_r),
    .tx_data_valid(tx_valid_r),
    .tx_data_ready(tx_ready),
    .tx_pin       (uart_tx)
);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_byte    <= 8'd0;
        rx_valid_d <= 1'b0;
    end else begin
        rx_valid_d <= rx_valid;
        if(rx_new)
            rx_byte <= rx_data;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cmd_state     <= CMD_IDLE;
        cmd_target    <= TARGET_NONE;
        sd_read_enable<= 1'b0;
        display_use_sd<= 1'b0;
        defaults_loaded <= 1'b0;
        resp_request  <= 1'b0;
        resp_request_type <= RESP_NONE;
    end else begin
        resp_request <= 1'b0;

        if(!defaults_loaded) begin
            defaults_loaded <= 1'b1;
            sd_read_enable  <= default_sd_enable;
            display_use_sd  <= default_display_sel;
        end

        if(rx_new) begin
            case(cmd_state)
                CMD_IDLE: begin
                    if(is_whitespace(rx_byte)) begin
                        cmd_target <= TARGET_NONE;
                    end else begin
                        case(to_upper(rx_byte))
                            "S": begin
                                cmd_state  <= CMD_WAIT_VAL;
                                cmd_target <= TARGET_SD;
                            end
                            "D": begin
                                cmd_state  <= CMD_WAIT_VAL;
                                cmd_target <= TARGET_DISP;
                            end
                            "R": begin
                                sd_read_enable <= default_sd_enable;
                                display_use_sd <= default_display_sel;
                                resp_request      <= 1'b1;
                                resp_request_type <= RESP_OK;
                            end
                            "?": begin
                                resp_request      <= 1'b1;
                                resp_request_type <= RESP_STATUS;
                            end
                            "H": begin
                                resp_request      <= 1'b1;
                                resp_request_type <= RESP_HELP;
                            end
                            default: begin
                                resp_request      <= 1'b1;
                                resp_request_type <= RESP_ERR;
                            end
                        endcase
                    end
                end
                CMD_WAIT_VAL: begin
                    if(is_whitespace(rx_byte)) begin
                        // ignore and stay in wait state
                        cmd_state <= CMD_WAIT_VAL;
                    end else begin
                        if(rx_byte == "0" || rx_byte == "1") begin
                            if(cmd_target == TARGET_SD)
                                sd_read_enable <= (rx_byte == "1");
                            else if(cmd_target == TARGET_DISP)
                                display_use_sd <= (rx_byte == "1");
                            resp_request      <= 1'b1;
                            resp_request_type <= RESP_OK;
                        end else begin
                            resp_request      <= 1'b1;
                            resp_request_type <= RESP_ERR;
                        end
                        cmd_state  <= CMD_IDLE;
                        cmd_target <= TARGET_NONE;
                    end
                end
                default: begin
                    cmd_state  <= CMD_IDLE;
                    cmd_target <= TARGET_NONE;
                end
            endcase
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        resp_pending      <= 1'b0;
        resp_pending_type <= RESP_NONE;
        resp_active       <= 1'b0;
        resp_type_active  <= RESP_NONE;
        resp_index        <= 5'd0;
        tx_valid_r        <= 1'b0;
        tx_data_r         <= 8'd0;
    end else begin
        tx_valid_r <= 1'b0;

        if(resp_request) begin
            if(resp_active) begin
                resp_pending      <= 1'b1;
                resp_pending_type <= resp_request_type;
            end else if(resp_pending) begin
                resp_pending      <= 1'b1;
                resp_pending_type <= resp_request_type;
            end else begin
                resp_active      <= 1'b1;
                resp_type_active <= resp_request_type;
                resp_index       <= 5'd0;
            end
        end else if(!resp_active && resp_pending) begin
            resp_active      <= 1'b1;
            resp_type_active <= resp_pending_type;
            resp_pending     <= 1'b0;
            resp_index       <= 5'd0;
        end

        if(resp_active) begin
            if(tx_ready) begin
                tx_valid_r <= 1'b1;
                tx_data_r  <= resp_char(resp_type_active, resp_index,
                                        sd_read_enable, display_use_sd);
                if(resp_index == resp_length(resp_type_active) - 1) begin
                    resp_active <= 1'b0;
                    resp_index  <= 5'd0;
                end else begin
                    resp_index  <= resp_index + 5'd1;
                end
            end
        end
    end
end

endmodule
