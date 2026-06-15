// =============================================================================
// PCIe Gen6 DLL Support Block: ACK Timer (ACK_TMR)
// Fix: ack_sent clears replay_num with absolute priority (blocks increment)
// Fix2: replay_timer_exp is cleared combinatorially on ack_sent for same-cycle visibility
// =============================================================================
module ack_tmr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tlp_rx_valid,
    input  wire        ack_sent,
    input  wire [15:0] ack_lat_limit,
    input  wire [15:0] replay_limit,
    output wire        ack_timer_exp,
    output wire        replay_timer_exp,
    output wire [1:0]  replay_num
);
    reg [15:0] ack_cnt;
    reg [15:0] replay_cnt;
    reg        ack_pending;
    reg        ack_timer_exp_r;
    reg        replay_timer_exp_r;
    reg [1:0]  replay_num_r;

    // Combinational outputs: ack_sent immediately suppresses both expiry signals
    assign ack_timer_exp    = ack_timer_exp_r    && !ack_sent;
    assign replay_timer_exp = replay_timer_exp_r && !ack_sent;
    // replay_num: combinational 0 when ack_sent asserted
    assign replay_num       = ack_sent ? 2'd0 : replay_num_r;

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

    // Registered timer flags
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_timer_exp_r    <= 1'b0;
            replay_timer_exp_r <= 1'b0;
        end else begin
            ack_timer_exp_r    <= ack_pending && (ack_cnt    >= ack_lat_limit);
            replay_timer_exp_r <= ack_pending && (replay_cnt >= replay_limit);
        end
    end

    // replay_num: ack_sent has UNCONDITIONAL priority over increment
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            replay_num_r <= 2'd0;
        else if (ack_sent)
            replay_num_r <= 2'd0;
        else if (replay_timer_exp_r && replay_num_r < 2'd3)
            replay_num_r <= replay_num_r + 1'b1;
    end
endmodule
