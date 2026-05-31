
module ack_tmr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tlp_rx_valid,
    input  wire        ack_sent,
    input  wire [15:0] ack_lat_limit,
    input  wire [15:0] replay_limit,
    output reg         ack_timer_exp,
    output reg         replay_timer_exp,
    output reg  [1:0]  replay_num
);
    reg [15:0] ack_cnt;
    reg [15:0] replay_cnt;
    reg        ack_pending;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            ack_pending <= 1'b0;
        else if (ack_sent)     ack_pending <= 1'b0;
        else if (tlp_rx_valid) ack_pending <= 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                        ack_cnt <= 16'd0;
        else if (ack_sent || !ack_pending) ack_cnt <= 16'd0;
        else                               ack_cnt <= ack_cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                           replay_cnt <= 16'd0;
        else if (ack_sent || !ack_pending)    replay_cnt <= 16'd0;
        else                                  replay_cnt <= replay_cnt + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_timer_exp    <= 1'b0;
            replay_timer_exp <= 1'b0;
        end else begin
            ack_timer_exp    <= ack_pending && (ack_cnt    >= ack_lat_limit);

            if (ack_sent)
                replay_timer_exp <= 1'b0;
            else
                replay_timer_exp <= ack_pending && (replay_cnt >= replay_limit);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            replay_num <= 2'd0;
        else if (ack_sent)
            replay_num <= 2'd0;
        else if (replay_timer_exp && !ack_sent && replay_num < 2'd3)
            replay_num <= replay_num + 1'b1;
    end
endmodule
