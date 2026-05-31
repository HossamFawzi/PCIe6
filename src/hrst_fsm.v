
`timescale 1ns/1ps

module hrst_fsm (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        hot_reset_req,
    input  wire        disable_req,
    input  wire        ts1_hr_bit,
    input  wire        ts1_dis_bit,
    input  wire        timer_exp,

    output reg         send_ts1_hr,
    output reg         send_ts1_dis,
    output reg         hot_reset_done,
    output reg         disabled_done,
    output reg  [1:0]  pipe_power_down
);

localparam [3:0]
    ST_IDLE          = 4'd0,

    ST_HR_ASSERT     = 4'd1,
    ST_HR_CONFIRM    = 4'd2,
    ST_HR_DONE       = 4'd3,

    ST_DIS_SEND      = 4'd4,
    ST_DIS_CONFIRM   = 4'd5,
    ST_DIS_POWERDN   = 4'd6,
    ST_DIS_DONE      = 4'd7,

    ST_RECOVER       = 4'd15;

localparam [15:0]
    HR_CONFIRM_NEEDED  = 16'd2,
    DIS_CONFIRM_NEEDED = 16'd2,
    HR_DWELL_CY        = 16'd500,
    DIS_RAMP_CY        = 16'd10;

reg [3:0]  cur_state, nxt_state;

reg [15:0] hr_confirm_cnt;
reg [15:0] dis_confirm_cnt;
reg [15:0] dwell_cnt;

wire [3:0]  dbg_cur_state   = cur_state;
wire [3:0]  dbg_nxt_state   = nxt_state;
wire [15:0] dbg_hr_confirm  = hr_confirm_cnt;
wire [15:0] dbg_dis_confirm = dis_confirm_cnt;
wire [15:0] dbg_dwell       = dwell_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cur_state       <= ST_IDLE;
        hr_confirm_cnt  <= 16'd0;
        dis_confirm_cnt <= 16'd0;
        dwell_cnt       <= 16'd0;
    end else begin
        cur_state <= nxt_state;

        case (cur_state)
            ST_HR_ASSERT: begin
                if (ts1_hr_bit)
                    hr_confirm_cnt <= hr_confirm_cnt + 16'd1;
                else
                    hr_confirm_cnt <= 16'd0;
                dwell_cnt <= 16'd0;
            end
            ST_HR_CONFIRM: begin
                dwell_cnt <= dwell_cnt + 16'd1;
            end
            ST_HR_DONE: begin
                dwell_cnt <= 16'd0;
            end

            ST_DIS_SEND: begin
                if (ts1_dis_bit)
                    dis_confirm_cnt <= dis_confirm_cnt + 16'd1;
                else
                    dis_confirm_cnt <= 16'd0;
                dwell_cnt <= 16'd0;
            end
            ST_DIS_CONFIRM: begin
                dwell_cnt <= 16'd0;
            end
            ST_DIS_POWERDN: begin
                dwell_cnt <= dwell_cnt + 16'd1;
            end
            default: begin
                hr_confirm_cnt  <= 16'd0;
                dis_confirm_cnt <= 16'd0;
                dwell_cnt       <= 16'd0;
            end
        endcase
    end
end

always @(*) begin

    nxt_state      = cur_state;
    send_ts1_hr    = 1'b0;
    send_ts1_dis   = 1'b0;
    hot_reset_done = 1'b0;
    disabled_done  = 1'b0;
    pipe_power_down = 2'b00;

    case (cur_state)

        ST_IDLE: begin
            pipe_power_down = 2'b00;
            if (hot_reset_req)
                nxt_state = ST_HR_ASSERT;
            else if (disable_req)
                nxt_state = ST_DIS_SEND;
        end

        ST_HR_ASSERT: begin
            send_ts1_hr    = 1'b1;
            pipe_power_down = 2'b00;
            if (timer_exp && hr_confirm_cnt < HR_CONFIRM_NEEDED) begin

                nxt_state = ST_IDLE;
            end else if (hr_confirm_cnt >= HR_CONFIRM_NEEDED) begin
                nxt_state = ST_HR_CONFIRM;
            end
        end

        ST_HR_CONFIRM: begin
            send_ts1_hr    = 1'b1;
            pipe_power_down = 2'b00;
            if (dwell_cnt >= HR_DWELL_CY || timer_exp)
                nxt_state = ST_HR_DONE;
        end

        ST_HR_DONE: begin
            hot_reset_done  = 1'b1;
            pipe_power_down = 2'b00;
            if (!hot_reset_req)
                nxt_state = ST_IDLE;
        end

        ST_DIS_SEND: begin
            send_ts1_dis   = 1'b1;
            pipe_power_down = 2'b01;
            if (timer_exp && dis_confirm_cnt < DIS_CONFIRM_NEEDED) begin
                nxt_state = ST_IDLE;
            end else if (dis_confirm_cnt >= DIS_CONFIRM_NEEDED) begin
                nxt_state = ST_DIS_CONFIRM;
            end
        end

        ST_DIS_CONFIRM: begin
            send_ts1_dis   = 1'b1;
            pipe_power_down = 2'b01;
            nxt_state = ST_DIS_POWERDN;
        end

        ST_DIS_POWERDN: begin
            pipe_power_down = 2'b10;
            if (dwell_cnt >= DIS_RAMP_CY || timer_exp)
                nxt_state = ST_DIS_DONE;
        end

        ST_DIS_DONE: begin
            disabled_done   = 1'b1;
            pipe_power_down = 2'b10;
            if (!disable_req)
                nxt_state = ST_IDLE;
        end

        ST_RECOVER: begin
            pipe_power_down = 2'b00;
            nxt_state = ST_IDLE;
        end

        default: begin

            nxt_state = ST_RECOVER;
        end
    endcase
end

endmodule
