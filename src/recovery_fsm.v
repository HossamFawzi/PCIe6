
module recv_fsm (

    input  wire clk,
    input  wire rst_n,

    input  wire recv_req,
    input  wire ts1_detected,
    input  wire ts2_detected,
    input  wire idle_detected,
    input  wire speed_change_req,
    input  wire eq_done,
    input  wire recv_timer_exp,

    output reg  send_ts1,
    output reg  send_ts2,
    output reg  speed_change_en,
    output reg  eq_start,
    output reg  recv_done,
    output reg  recv_timeout_err,
    output reg  retrain_req
);

    localparam [2:0]
        ST_IDLE         = 3'd0,
        ST_RCVR_LOCK    = 3'd1,
        ST_RCVR_CFG     = 3'd2,
        ST_RCVR_IDLE    = 3'd3,
        ST_SPEED        = 3'd4,
        ST_EQ           = 3'd5,
        ST_DONE         = 3'd6,
        ST_TIMEOUT      = 3'd7;

    reg [2:0] state, next_state;

    reg [1:0] ts2_cnt;

    reg [1:0] retrain_cnt;

    always @(posedge clk) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: begin
                if (recv_req)
                    next_state = ST_RCVR_LOCK;
            end

            ST_RCVR_LOCK: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_detected)
                    next_state = ST_RCVR_CFG;
            end

            ST_RCVR_CFG: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (speed_change_req)
                    next_state = ST_SPEED;
                else if (ts2_cnt == 2'd2)
                    next_state = ST_RCVR_IDLE;
            end

            ST_RCVR_IDLE: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (idle_detected)
                    next_state = ST_DONE;
            end

            ST_SPEED: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else

                    next_state = ST_RCVR_LOCK;
            end

            ST_EQ: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (eq_done)
                    next_state = ST_RCVR_CFG;
            end

            ST_DONE:    next_state = ST_IDLE;
            ST_TIMEOUT: next_state = ST_IDLE;

            default:    next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            send_ts1        <= 1'b0;
            send_ts2        <= 1'b0;
            speed_change_en <= 1'b0;
            eq_start        <= 1'b0;
            recv_done       <= 1'b0;
            recv_timeout_err <= 1'b0;
            retrain_req     <= 1'b0;
            ts2_cnt         <= 2'd0;
            retrain_cnt     <= 2'd0;
        end else begin

            send_ts1         <= 1'b0;
            send_ts2         <= 1'b0;
            speed_change_en  <= 1'b0;
            eq_start         <= 1'b0;
            recv_done        <= 1'b0;
            recv_timeout_err <= 1'b0;
            retrain_req      <= 1'b0;

            case (state)

                ST_RCVR_LOCK: begin
                    send_ts1 <= 1'b1;
                end

                ST_RCVR_CFG: begin
                    send_ts2 <= 1'b1;
                    if (ts2_detected && ts2_cnt < 2'd2)
                        ts2_cnt <= ts2_cnt + 2'd1;
                end

                ST_RCVR_IDLE: begin

                    ts2_cnt <= 2'd0;
                end

                ST_SPEED: begin
                    speed_change_en <= 1'b1;
                    ts2_cnt         <= 2'd0;
                end

                ST_EQ: begin
                    eq_start <= 1'b1;
                end

                ST_DONE: begin
                    recv_done   <= 1'b1;
                    retrain_cnt <= 2'd0;
                end

                ST_TIMEOUT: begin
                    recv_timeout_err <= 1'b1;
                    ts2_cnt          <= 2'd0;

                    if (retrain_cnt == 2'd2) begin
                        retrain_req  <= 1'b1;
                        retrain_cnt  <= 2'd0;
                    end else begin
                        retrain_cnt  <= retrain_cnt + 2'd1;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
