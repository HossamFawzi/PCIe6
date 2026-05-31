
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

            pm_timeout_err <= (l0s_active && (l0s_cnt >= l0s_limit)) &&
                              (l1_active  && (l1_cnt  >= l1_limit));
        end
    end

endmodule
