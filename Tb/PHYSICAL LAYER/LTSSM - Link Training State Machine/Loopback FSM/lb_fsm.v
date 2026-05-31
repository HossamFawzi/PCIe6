
`timescale 1ns/1ps

module lb_fsm (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        lb_req,
    input  wire        lb_master,
    input  wire        ts1_lb_bit,
    input  wire        lb_timer_exp,

    output reg         lb_active,
    output reg         send_ts1_lb,
    output reg         lb_data_en,
    output reg         lb_exit
);

    localparam [3:0]
        ST_IDLE            = 4'd0,
        ST_LB_ENTRY        = 4'd1,
        ST_LB_WAIT_TS1     = 4'd2,
        ST_LB_SLAVE_DETECT = 4'd3,
        ST_LB_ACTIVE_MSTR  = 4'd4,
        ST_LB_ACTIVE_SLV   = 4'd5,
        ST_LB_EXIT_MSTR    = 4'd6,
        ST_LB_EXIT_SLV     = 4'd7,
        ST_LB_DONE         = 4'd8;

    reg [3:0] state, next_state;

    reg [1:0] ts1_lb_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts1_lb_cnt <= 2'd0;
        end else begin
            if (state == ST_LB_WAIT_TS1) begin
                if (ts1_lb_bit)
                    ts1_lb_cnt <= ts1_lb_cnt + 2'd1;
                else
                    ts1_lb_cnt <= 2'd0;
            end else begin
                ts1_lb_cnt <= 2'd0;
            end
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (lb_req)
                    next_state = lb_master ? ST_LB_ENTRY : ST_LB_SLAVE_DETECT;
            end

            ST_LB_ENTRY: begin

                if (lb_timer_exp)
                    next_state = ST_LB_WAIT_TS1;
            end

            ST_LB_WAIT_TS1: begin

                if (lb_timer_exp)
                    next_state = ST_LB_DONE;
                else if (ts1_lb_cnt >= 2'd2)
                    next_state = ST_LB_ACTIVE_MSTR;
            end

            ST_LB_ACTIVE_MSTR: begin

                if (lb_timer_exp)
                    next_state = ST_LB_EXIT_MSTR;
            end

            ST_LB_EXIT_MSTR: begin

                if (lb_timer_exp)
                    next_state = ST_LB_DONE;
            end

            ST_LB_SLAVE_DETECT: begin

                if (ts1_lb_bit)
                    next_state = ST_LB_ACTIVE_SLV;
            end

            ST_LB_ACTIVE_SLV: begin

                if (!ts1_lb_bit || lb_timer_exp)
                    next_state = ST_LB_EXIT_SLV;
            end

            ST_LB_EXIT_SLV: begin
                if (lb_timer_exp)
                    next_state = ST_LB_DONE;
            end

            ST_LB_DONE: begin

                next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_active    <= 1'b0;
            send_ts1_lb  <= 1'b0;
            lb_data_en   <= 1'b0;
            lb_exit      <= 1'b0;
        end else begin

            send_ts1_lb <= 1'b0;
            lb_exit     <= 1'b0;

            case (state)
                ST_IDLE: begin
                    lb_active  <= 1'b0;
                    lb_data_en <= 1'b0;
                end

                ST_LB_ENTRY: begin
                    lb_active   <= 1'b0;
                    send_ts1_lb <= 1'b1;
                    lb_data_en  <= 1'b0;
                end

                ST_LB_WAIT_TS1: begin
                    lb_active   <= 1'b0;
                    send_ts1_lb <= 1'b1;
                    lb_data_en  <= 1'b0;
                end

                ST_LB_SLAVE_DETECT: begin
                    lb_active   <= 1'b0;
                    send_ts1_lb <= 1'b1;
                    lb_data_en  <= 1'b0;
                end

                ST_LB_ACTIVE_MSTR: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;
                    lb_data_en  <= 1'b0;
                end

                ST_LB_ACTIVE_SLV: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;
                    lb_data_en  <= 1'b1;
                end

                ST_LB_EXIT_MSTR: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;
                    lb_data_en  <= 1'b0;
                end

                ST_LB_EXIT_SLV: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;
                    lb_data_en  <= 1'b0;
                end

                ST_LB_DONE: begin
                    lb_active   <= 1'b0;
                    lb_data_en  <= 1'b0;
                    lb_exit     <= 1'b1;
                end

                default: begin
                    lb_active  <= 1'b0;
                    lb_data_en <= 1'b0;
                end
            endcase
        end
    end

endmodule
