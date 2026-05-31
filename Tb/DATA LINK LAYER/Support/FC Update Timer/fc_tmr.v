
`timescale 1ns/1ps
module fc_tmr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        fc_update_sent,
    input  wire [15:0] fc_timer_limit,
    input  wire        dll_active,
    output reg         fc_update_req,
    output reg         fc_timer_exp
);

    reg [15:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 16'd0;
        else if (!dll_active || fc_update_sent)
            cnt <= 16'd0;
        else
            cnt <= cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_timer_exp  <= 1'b0;
            fc_update_req <= 1'b0;
        end else begin

            fc_timer_exp  <= dll_active && !fc_update_sent && (cnt >= fc_timer_limit);
            fc_update_req <= dll_active && !fc_update_sent && (cnt >= fc_timer_limit);
        end
    end

endmodule
