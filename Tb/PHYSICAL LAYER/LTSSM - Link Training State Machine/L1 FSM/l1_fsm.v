
`timescale 1ns/1ps

module l1_fsm (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        l1_req,
    input  wire        l1_ack,
    input  wire        l1_timer_exp,
    input  wire        pm_dllp_rx,
    input  wire        l1_exit_req,

    output reg         send_eios,
    output reg         l1_active,
    output reg         l1_exit,
    output reg  [1:0]  pipe_power_down,
    output reg         l1_timeout_err
);

    localparam [3:0]
        ST_L0          = 4'd0,
        ST_L1_ENTRY    = 4'd1,
        ST_L1_WAIT_ACK = 4'd2,
        ST_L1_SEND_EI  = 4'd3,
        ST_L1          = 4'd4,
        ST_L1_1        = 4'd5,
        ST_L1_2        = 4'd6,
        ST_L1_EXIT     = 4'd7,
        ST_L1_EXIT_EI  = 4'd8,
        ST_ERROR       = 4'd9;

    reg [3:0] state, next_state;

    reg [11:0] timeout_cnt;
    localparam TIMEOUT_LIMIT = 12'd4095;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_L0;
        else
            state <= next_state;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 12'd0;
        end else begin
            case (state)
                ST_L1_WAIT_ACK: begin
                    if (pm_dllp_rx || l1_ack)
                        timeout_cnt <= 12'd0;
                    else if (timeout_cnt < TIMEOUT_LIMIT)
                        timeout_cnt <= timeout_cnt + 12'd1;
                end
                default: timeout_cnt <= 12'd0;
            endcase
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            ST_L0: begin
                if (l1_req)
                    next_state = ST_L1_ENTRY;
            end

            ST_L1_ENTRY: begin

                next_state = ST_L1_WAIT_ACK;
            end

            ST_L1_WAIT_ACK: begin
                if (timeout_cnt >= TIMEOUT_LIMIT)
                    next_state = ST_ERROR;
                else if (pm_dllp_rx || l1_ack)
                    next_state = ST_L1_SEND_EI;
            end

            ST_L1_SEND_EI: begin

                if (l1_timer_exp)
                    next_state = ST_L1;
            end

            ST_L1: begin

                if (l1_exit_req)
                    next_state = ST_L1_EXIT_EI;
                else if (l1_timer_exp)
                    next_state = ST_L1_1;
            end

            ST_L1_1: begin
                if (l1_exit_req)
                    next_state = ST_L1_EXIT_EI;
                else if (l1_timer_exp)
                    next_state = ST_L1_2;
            end

            ST_L1_2: begin
                if (l1_exit_req)
                    next_state = ST_L1_EXIT_EI;
            end

            ST_L1_EXIT_EI: begin
                if (l1_timer_exp)
                    next_state = ST_L1_EXIT;
            end

            ST_L1_EXIT: begin

                next_state = ST_L0;
            end

            ST_ERROR: begin

                next_state = ST_ERROR;
            end

            default: next_state = ST_L0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            send_eios         <= 1'b0;
            l1_active         <= 1'b0;
            l1_exit           <= 1'b0;
            pipe_power_down   <= 2'b00;
            l1_timeout_err    <= 1'b0;
        end else begin

            send_eios      <= 1'b0;
            l1_exit        <= 1'b0;
            l1_timeout_err <= 1'b0;

            case (state)
                ST_L0: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end

                ST_L1_ENTRY: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end

                ST_L1_WAIT_ACK: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end

                ST_L1_SEND_EI: begin
                    send_eios       <= 1'b1;
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b01;
                end

                ST_L1: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b10;
                end

                ST_L1_1: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b10;
                end

                ST_L1_2: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b11;
                end

                ST_L1_EXIT_EI: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b01;
                end

                ST_L1_EXIT: begin
                    l1_active       <= 1'b0;
                    l1_exit         <= 1'b1;
                    pipe_power_down <= 2'b00;
                end

                ST_ERROR: begin
                    l1_timeout_err  <= 1'b1;
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end

                default: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end
            endcase
        end
    end

endmodule
