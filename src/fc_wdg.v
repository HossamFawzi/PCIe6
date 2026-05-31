
module fc_wdg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        credit_grant_p,
    input  wire        credit_grant_np,
    input  wire        credit_grant_cpl,
    input  wire        tlp_pending,
    input  wire [15:0] fc_watchdog_limit,
    input  wire        dll_active,
    output reg         fc_deadlock_det,
    output reg         fc_watchdog_err,
    output reg         fc_recovery_req
);

    reg [15:0] wdg_cnt;
    wire       any_credit = credit_grant_p | credit_grant_np | credit_grant_cpl;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wdg_cnt <= 16'd0;
        end else if (!dll_active || !tlp_pending || any_credit) begin
            wdg_cnt <= 16'd0;
        end else begin
            wdg_cnt <= wdg_cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_deadlock_det  <= 1'b0;
            fc_watchdog_err  <= 1'b0;
            fc_recovery_req  <= 1'b0;
        end else begin
            if (dll_active && tlp_pending && (wdg_cnt >= fc_watchdog_limit)) begin
                fc_deadlock_det <= 1'b1;
                fc_watchdog_err <= 1'b1;
                fc_recovery_req <= 1'b1;
            end else begin
                fc_deadlock_det <= 1'b0;
                fc_watchdog_err <= 1'b0;
                fc_recovery_req <= 1'b0;
            end
        end
    end

endmodule
