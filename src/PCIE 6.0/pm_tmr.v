// =============================================================================
// PCIe Gen6 DLL Support Block: Link State Power Timer (PM_TMR) 🔴 MUST
// From HTML: grp="support", tag="PM_TMR"
// Inputs : l0s_entry_req, l1_entry_req, l0s_exit_req, l1_exit_req,
//          l0s_limit[15:0], l1_limit[15:0], clk, rst_n
// Outputs: l0s_timer_exp, l1_timer_exp, pm_timeout_err
// Behavior: Generates L0s and L1 entry/exit timing signals.
// =============================================================================
module pm_tmr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        l0s_entry_req,
    input  wire        l1_entry_req,
    input  wire        l0s_exit_req,
    input  wire        l1_exit_req,
    input  wire [15:0] l0s_limit,
    input  wire [15:0] l1_limit,
    output reg         l0s_timer_exp,
    output reg         l1_timer_exp,
    output reg         pm_timeout_err
);

    reg [15:0] l0s_cnt;
    reg [15:0] l1_cnt;
    reg        l0s_active;
    reg        l1_active;

    // L0s timer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l0s_cnt    <= 16'd0;
            l0s_active <= 1'b0;
        end else if (l0s_exit_req) begin
            l0s_cnt    <= 16'd0;
            l0s_active <= 1'b0;
        end else if (l0s_entry_req) begin
            l0s_active <= 1'b1;
            l0s_cnt    <= l0s_cnt + 1'b1;
        end else if (l0s_active) begin
            l0s_cnt <= l0s_cnt + 1'b1;
        end
    end

    // L1 timer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l1_cnt    <= 16'd0;
            l1_active <= 1'b0;
        end else if (l1_exit_req) begin
            l1_cnt    <= 16'd0;
            l1_active <= 1'b0;
        end else if (l1_entry_req) begin
            l1_active <= 1'b1;
            l1_cnt    <= l1_cnt + 1'b1;
        end else if (l1_active) begin
            l1_cnt <= l1_cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            l0s_timer_exp  <= 1'b0;
            l1_timer_exp   <= 1'b0;
            pm_timeout_err <= 1'b0;
        end else begin
            l0s_timer_exp  <= l0s_active && (l0s_cnt >= l0s_limit);
            l1_timer_exp   <= l1_active  && (l1_cnt  >= l1_limit);
            // Timeout error: both timers fire simultaneously (illegal state)
            pm_timeout_err <= (l0s_active && (l0s_cnt >= l0s_limit)) &&
                              (l1_active  && (l1_cnt  >= l1_limit));
        end
    end

endmodule
