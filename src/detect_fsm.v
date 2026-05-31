
`timescale 1ns/1ps
module detect_fsm (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        detect_req,
    input  wire        pipe_rx_elec_idle,
    input  wire        detect_timer_exp,
    input  wire [2:0]  pipe_status,

    output wire        detect_done,
    output wire        receiver_detected,
    output wire [15:0] lanes_detected,
    output wire        detect_timeout
);

localparam [2:0]
    ST_IDLE      = 3'd0,
    ST_QUIET     = 3'd1,
    ST_ACTIVE    = 3'd2,
    ST_LANE_EVAL = 3'd3,
    ST_DONE      = 3'd4,
    ST_TIMEOUT   = 3'd5;

localparam [2:0]
    PIPE_ST_IDLE    = 3'b000,
    PIPE_ST_RX_DET  = 3'b001,
    PIPE_ST_NO_RX   = 3'b010,
    PIPE_ST_EI_EXIT = 3'b011;

localparam [7:0]  PROBE_WAIT_INIT = 8'd20;

localparam [3:0]  MAX_LANE        = 4'd15;

reg [2:0]  state, next_state;
reg [3:0]  lane_ptr;
reg [15:0] lane_det_reg;
reg [7:0]  probe_wait;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= ST_IDLE;
    else
        state <= next_state;
end

always @(*) begin
    next_state = state;
    case (state)

        ST_IDLE: begin
            if (detect_req)
                next_state = ST_QUIET;
        end

        ST_QUIET: begin
            if (detect_timer_exp) begin
                if (pipe_rx_elec_idle)
                    next_state = ST_ACTIVE;
                else
                    next_state = ST_QUIET;
            end
        end

        ST_ACTIVE: begin
            if (detect_timer_exp) begin
                next_state = ST_TIMEOUT;
            end else if (probe_wait == 8'd0) begin
                if (lane_ptr == MAX_LANE)
                    next_state = ST_LANE_EVAL;

            end
        end

        ST_LANE_EVAL: begin
            if (lane_det_reg != 16'd0)
                next_state = ST_DONE;
            else
                next_state = ST_TIMEOUT;
        end

        ST_DONE: begin
            next_state = ST_IDLE;
        end

        ST_TIMEOUT: begin
            next_state = ST_IDLE;
        end
        default: next_state = ST_IDLE;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lane_ptr     <= 4'd0;
        lane_det_reg <= 16'd0;
        probe_wait   <= PROBE_WAIT_INIT;

    end else begin
        case (state)
            ST_IDLE: begin
                lane_ptr     <= 4'd0;
                lane_det_reg <= 16'd0;
                probe_wait   <= PROBE_WAIT_INIT;
            end
            ST_QUIET: begin

                lane_ptr     <= 4'd0;
                lane_det_reg <= 16'd0;
                probe_wait   <= PROBE_WAIT_INIT;
            end
            ST_ACTIVE: begin
                if (!detect_timer_exp) begin

                    if (pipe_status == PIPE_ST_RX_DET)
                        lane_det_reg[lane_ptr] <= 1'b1;

                    if (probe_wait != 8'd0) begin
                        probe_wait <= probe_wait - 8'd1;
                    end else begin

                        if (lane_ptr != MAX_LANE) begin
                            lane_ptr   <= lane_ptr + 4'd1;
                            probe_wait <= PROBE_WAIT_INIT;
                        end

                    end
                end
            end
            ST_LANE_EVAL: begin

            end
            default: begin end
        endcase
    end
end

reg        recv_det_hold;
reg [15:0] lanes_hold;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        recv_det_hold <= 1'b0;
        lanes_hold    <= 16'd0;
    end else begin
        if (state == ST_DONE) begin
            recv_det_hold <= (lane_det_reg != 16'd0);
            lanes_hold    <= lane_det_reg;
        end else if (state == ST_TIMEOUT) begin
            recv_det_hold <= 1'b0;
            lanes_hold    <= 16'd0;
        end
    end
end

assign detect_done       = (state == ST_DONE);
assign detect_timeout    = (state == ST_TIMEOUT);
assign receiver_detected = (state == ST_DONE)    ? (lane_det_reg != 16'd0) :
                           (state == ST_TIMEOUT)  ? 1'b0 :
                                                    recv_det_hold;
assign lanes_detected    = (state == ST_DONE)    ? lane_det_reg :
                           (state == ST_TIMEOUT)  ? 16'd0 :
                                                    lanes_hold;
endmodule