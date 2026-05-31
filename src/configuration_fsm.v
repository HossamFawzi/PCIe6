
module cfg_fsm (

    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  ts1_link_num,
    input  wire [7:0]  ts1_lane_num,
    input  wire        ts2_detected,
    input  wire        cfg_timer_exp,
    input  wire        upcfg_req,

    output reg  [7:0]  cfg_link_num,
    output reg  [7:0]  cfg_lane_num,
    output reg         send_ts2,
    output reg         cfg_done,
    output wire [5:0]  negotiated_width,
    output reg         cfg_timeout_err
);

    localparam [2:0]
        ST_IDLE       = 3'd0,
        ST_LNKNUM     = 3'd1,
        ST_LANENUM    = 3'd2,
        ST_COMPLETE   = 3'd3,
        ST_UPCFG      = 3'd4,
        ST_DONE       = 3'd5,
        ST_TIMEOUT    = 3'd6;

    reg [2:0] state, next_state;

    reg [1:0] ts2_agree_cnt;

    reg [7:0] latch_link_num;
    reg [7:0] latch_lane_num;

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

                if (ts1_link_num != 8'hFF)
                    next_state = ST_LNKNUM;
            end

            ST_LNKNUM: begin

                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_link_num != 8'hFF)
                    next_state = ST_LANENUM;
            end

            ST_LANENUM: begin
                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_lane_num != 8'hFF)
                    next_state = ST_COMPLETE;
            end

            ST_COMPLETE: begin
                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (upcfg_req)
                    next_state = ST_UPCFG;
                else if (ts2_agree_cnt == 2'd2)
                    next_state = ST_DONE;
            end

            ST_UPCFG: begin

                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_lane_num != 8'hFF)
                    next_state = ST_COMPLETE;
            end

            ST_DONE:    next_state = ST_IDLE;
            ST_TIMEOUT: next_state = ST_IDLE;

            default:    next_state = ST_IDLE;
        endcase
    end

    reg [5:0] negotiated_width_r;
    assign negotiated_width = negotiated_width_r;

    always @(*) begin
        case (latch_lane_num)
            8'd0:    negotiated_width_r = 6'd1;
            8'd1:    negotiated_width_r = 6'd2;
            8'd3:    negotiated_width_r = 6'd4;
            8'd7:    negotiated_width_r = 6'd8;
            8'd15:   negotiated_width_r = 6'd16;
            default: negotiated_width_r = 6'd1;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cfg_link_num      <= 8'h00;
            cfg_lane_num      <= 8'h00;
            send_ts2          <= 1'b0;
            cfg_done          <= 1'b0;
            cfg_timeout_err   <= 1'b0;
            ts2_agree_cnt     <= 2'd0;
            latch_link_num    <= 8'hFF;
            latch_lane_num    <= 8'hFF;
        end else begin

            send_ts2        <= 1'b0;
            cfg_done        <= 1'b0;
            cfg_timeout_err <= 1'b0;

            case (state)

                ST_LNKNUM: begin
                    if (ts1_link_num != 8'hFF)
                        latch_link_num <= ts1_link_num;
                end

                ST_LANENUM: begin
                    if (ts1_lane_num != 8'hFF)
                        latch_lane_num <= ts1_lane_num;
                end

                ST_COMPLETE: begin

                    cfg_link_num <= latch_link_num;
                    cfg_lane_num <= latch_lane_num;
                    send_ts2     <= 1'b1;

                    if (ts2_detected && (ts2_agree_cnt < 2'd2))
                        ts2_agree_cnt <= ts2_agree_cnt + 2'd1;
                end

                ST_UPCFG: begin
                    send_ts2     <= 1'b1;
                    cfg_link_num <= latch_link_num;

                    cfg_lane_num <= 8'hFF;
                    ts2_agree_cnt <= 2'd0;

                    if (ts1_lane_num != 8'hFF)
                        latch_lane_num <= ts1_lane_num;
                end

                ST_DONE: begin
                    cfg_done      <= 1'b1;
                    ts2_agree_cnt <= 2'd0;
                end

                ST_TIMEOUT: begin
                    cfg_timeout_err <= 1'b1;
                    ts2_agree_cnt   <= 2'd0;
                    latch_link_num  <= 8'hFF;
                    latch_lane_num  <= 8'hFF;
                end

                default: ;
            endcase
        end
    end

endmodule
