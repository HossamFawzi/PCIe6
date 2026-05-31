
module pwr_tmr (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        l0s_entry_req,
    input  wire        l1_entry_req,
    input  wire        l0s_exit_req,
    input  wire        l1_exit_req,

    input  wire [11:0] l0s_entry_limit,
    input  wire [15:0] l1_entry_limit,

    output reg         l0s_entry_timer_exp,
    output reg         l1_entry_timer_exp,
    output reg         l0s_exit_timer_exp,
    output reg         l1_exit_timer_exp
);

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

        if (l0s_exit_req) begin
            l0s_entry_run <= 1'b0;
            l0s_entry_cnt <= 12'd0;
        end
    end
end

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
