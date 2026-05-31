// =============================================================================
// PCIe Gen6 DLL Support Block: FC Update Timer (FC_TMR)
// Inputs : fc_update_sent, fc_timer_limit[15:0], dll_active, clk, rst_n
// Outputs: fc_update_req, fc_timer_exp
// Behavior: Periodic UpdateFC trigger even if credits unchanged.
//
// BUG FIX: Original logic allowed fc_timer_exp to fire on the SAME cycle as
// fc_update_sent because the output register sampled cnt BEFORE the reset.
// Fix: gate the output with !fc_update_sent so sending immediately clears it.
// =============================================================================
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
            // BUG FIX: suppress output immediately on fc_update_sent
            // Without this, the timer fires on same cycle the update is sent
            // because cnt hasn't reset yet (registered reset is one cycle late).
            fc_timer_exp  <= dll_active && !fc_update_sent && (cnt >= fc_timer_limit);
            fc_update_req <= dll_active && !fc_update_sent && (cnt >= fc_timer_limit);
        end
    end

endmodule
