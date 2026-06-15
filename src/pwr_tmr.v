// ============================================================
// Module 52 : Power State Timer — L0s / L1 (PWR_TMR)
// PCIe Gen6 Physical Layer
// PHY-level timers for L0s/L1 entry and exit sequencing.
// Distinct from DLL PM_TMR — PHY needs its own timing for
// PIPE power-down sequencing.
// ============================================================
module pwr_tmr (
    input  wire        clk,
    input  wire        rst_n,

    // Entry/Exit requests
    input  wire        l0s_entry_req,        // Request L0s entry
    input  wire        l1_entry_req,         // Request L1 entry
    input  wire        l0s_exit_req,         // Request L0s exit
    input  wire        l1_exit_req,          // Request L1 exit

    // Timer limits (in clock cycles)
    input  wire [11:0] l0s_entry_limit,      // L0s entry timer limit
    input  wire [15:0] l1_entry_limit,       // L1 entry timer limit

    // Timer expiry outputs (pulses)
    output reg         l0s_entry_timer_exp,  // L0s entry timer expired
    output reg         l1_entry_timer_exp,   // L1 entry timer expired
    output reg         l0s_exit_timer_exp,   // L0s exit timer expired
    output reg         l1_exit_timer_exp     // L1 exit timer expired
);

// ── L0s Entry Timer ──────────────────────────────────────────
reg [11:0] l0s_entry_cnt;
reg        l0s_entry_run;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        l0s_entry_cnt     <= 12'd0;
        l0s_entry_run     <= 1'b0;
        l0s_entry_timer_exp <= 1'b0;
    end else begin
        l0s_entry_timer_exp <= 1'b0;
        if (l0s_entry_req && !l0s_entry_run) begin
            l0s_entry_cnt <= 12'd0;
            l0s_entry_run <= 1'b1;
        end else if (l0s_entry_run) begin
            if (l0s_entry_cnt >= l0s_entry_limit) begin
                l0s_entry_timer_exp <= 1'b1;
                l0s_entry_run       <= 1'b0;
                l0s_entry_cnt       <= 12'd0;
            end else begin
                l0s_entry_cnt <= l0s_entry_cnt + 12'd1;
            end
        end
        // Cancel on exit request
        if (l0s_exit_req) begin
            l0s_entry_run <= 1'b0;
            l0s_entry_cnt <= 12'd0;
        end
    end
end

// ── L1 Entry Timer ───────────────────────────────────────────
reg [15:0] l1_entry_cnt;
reg        l1_entry_run;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        l1_entry_cnt      <= 16'd0;
        l1_entry_run      <= 1'b0;
        l1_entry_timer_exp <= 1'b0;
    end else begin
        l1_entry_timer_exp <= 1'b0;
        if (l1_entry_req && !l1_entry_run) begin
            l1_entry_cnt  <= 16'd0;
            l1_entry_run  <= 1'b1;
        end else if (l1_entry_run) begin
            if (l1_entry_cnt >= l1_entry_limit) begin
                l1_entry_timer_exp <= 1'b1;
                l1_entry_run       <= 1'b0;
                l1_entry_cnt       <= 16'd0;
            end else begin
                l1_entry_cnt <= l1_entry_cnt + 16'd1;
            end
        end
        if (l1_exit_req) begin
            l1_entry_run <= 1'b0;
            l1_entry_cnt <= 16'd0;
        end
    end
end

// ── L0s Exit Timer ───────────────────────────────────────────
// Fixed minimum exit time: 4 clock cycles (simplified)
localparam L0S_EXIT_LIMIT = 12'd4;
reg [11:0] l0s_exit_cnt;
reg        l0s_exit_run;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        l0s_exit_cnt      <= 12'd0;
        l0s_exit_run      <= 1'b0;
        l0s_exit_timer_exp <= 1'b0;
    end else begin
        l0s_exit_timer_exp <= 1'b0;
        if (l0s_exit_req && !l0s_exit_run) begin
            l0s_exit_cnt  <= 12'd0;
            l0s_exit_run  <= 1'b1;
        end else if (l0s_exit_run) begin
            if (l0s_exit_cnt >= L0S_EXIT_LIMIT) begin
                l0s_exit_timer_exp <= 1'b1;
                l0s_exit_run       <= 1'b0;
                l0s_exit_cnt       <= 12'd0;
            end else begin
                l0s_exit_cnt <= l0s_exit_cnt + 12'd1;
            end
        end
    end
end

// ── L1 Exit Timer ────────────────────────────────────────────
// Fixed minimum exit time: 8 clock cycles (simplified)
localparam L1_EXIT_LIMIT = 16'd8;
reg [15:0] l1_exit_cnt;
reg        l1_exit_run;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        l1_exit_cnt      <= 16'd0;
        l1_exit_run      <= 1'b0;
        l1_exit_timer_exp <= 1'b0;
    end else begin
        l1_exit_timer_exp <= 1'b0;
        if (l1_exit_req && !l1_exit_run) begin
            l1_exit_cnt  <= 16'd0;
            l1_exit_run  <= 1'b1;
        end else if (l1_exit_run) begin
            if (l1_exit_cnt >= L1_EXIT_LIMIT) begin
                l1_exit_timer_exp <= 1'b1;
                l1_exit_run       <= 1'b0;
                l1_exit_cnt       <= 16'd0;
            end else begin
                l1_exit_cnt <= l1_exit_cnt + 16'd1;
            end
        end
    end
end

endmodule
