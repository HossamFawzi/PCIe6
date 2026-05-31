
module eq_ctrl (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        eq_req,
    input  wire [1:0]  eq_phase,
    input  wire        ts1_eq_req_bit,
    input  wire [3:0]  ts2_eq_preset,
    input  wire        pipe_rxeqeval,
    input  wire        eq_timer_exp,

    output reg  [2:0]  pipe_txdeemph,
    output reg  [2:0]  pipe_txmargin,
    output reg         pipe_rxeqeval_out,
    output reg         eq_done,
    output reg  [1:0]  eq_phase_out,
    output reg         eq_err
);

localparam [3:0]
    S_IDLE       = 4'd0,
    S_PHASE0     = 4'd1,
    S_PHASE1_REQ = 4'd2,
    S_PHASE1_ACK = 4'd3,
    S_PHASE2_REQ = 4'd4,
    S_PHASE2_ACK = 4'd5,
    S_PHASE3     = 4'd6,
    S_DONE       = 4'd7,
    S_ERROR      = 4'd8;

reg [3:0] state, next_state;

function [5:0] preset_to_pipe;
    input [3:0] preset;
    case (preset)
        4'd0:  preset_to_pipe = 6'b000_000;
        4'd1:  preset_to_pipe = 6'b001_000;
        4'd2:  preset_to_pipe = 6'b010_000;
        4'd3:  preset_to_pipe = 6'b011_001;
        4'd4:  preset_to_pipe = 6'b100_001;
        4'd5:  preset_to_pipe = 6'b101_010;
        4'd6:  preset_to_pipe = 6'b110_010;
        4'd7:  preset_to_pipe = 6'b111_011;
        default: preset_to_pipe = 6'b000_000;
    endcase
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
end

always @(*) begin
    next_state = state;
    case (state)
        S_IDLE:
            if (eq_req) begin
                case (eq_phase)
                    2'd0: next_state = S_PHASE0;
                    2'd1: next_state = S_PHASE1_REQ;
                    2'd2: next_state = S_PHASE2_REQ;
                    2'd3: next_state = S_PHASE3;
                    default: next_state = S_IDLE;
                endcase
            end

        S_PHASE0:

            next_state = S_PHASE1_REQ;

        S_PHASE1_REQ:

            if (eq_timer_exp) next_state = S_ERROR;
            else if (pipe_rxeqeval) next_state = S_PHASE1_ACK;

        S_PHASE1_ACK:

            next_state = S_PHASE2_REQ;

        S_PHASE2_REQ:

            if (eq_timer_exp) next_state = S_ERROR;
            else if (pipe_rxeqeval) next_state = S_PHASE2_ACK;

        S_PHASE2_ACK:
            next_state = S_PHASE3;

        S_PHASE3:

            if (!ts1_eq_req_bit) next_state = S_DONE;
            else if (eq_timer_exp) next_state = S_ERROR;

        S_DONE:
            next_state = S_IDLE;

        S_ERROR:
            next_state = S_IDLE;

        default:
            next_state = S_IDLE;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_txdeemph    <= 3'b000;
        pipe_txmargin    <= 3'b000;
        pipe_rxeqeval_out <= 1'b0;
        eq_done          <= 1'b0;
        eq_phase_out     <= 2'd0;
        eq_err           <= 1'b0;
    end else begin

        eq_done          <= 1'b0;
        eq_err           <= 1'b0;
        pipe_rxeqeval_out <= 1'b0;

        case (state)
            S_IDLE: begin
                pipe_txdeemph <= 3'b000;
                pipe_txmargin <= 3'b000;
                eq_phase_out  <= 2'd0;
            end

            S_PHASE0: begin

                {pipe_txdeemph, pipe_txmargin} <= preset_to_pipe(4'd0);
                eq_phase_out  <= 2'd0;
            end

            S_PHASE1_REQ: begin
                pipe_rxeqeval_out <= 1'b1;
                eq_phase_out      <= 2'd1;
            end

            S_PHASE1_ACK: begin
                eq_phase_out <= 2'd1;
            end

            S_PHASE2_REQ: begin

                {pipe_txdeemph, pipe_txmargin} <= preset_to_pipe(ts2_eq_preset);
                pipe_rxeqeval_out <= 1'b1;
                eq_phase_out      <= 2'd2;
            end

            S_PHASE2_ACK: begin
                eq_phase_out <= 2'd2;
            end

            S_PHASE3: begin

                eq_phase_out <= 2'd3;
            end

            S_DONE: begin
                eq_done      <= 1'b1;
                eq_phase_out <= 2'd3;
            end

            S_ERROR: begin
                eq_err       <= 1'b1;
                pipe_txdeemph <= 3'b000;
                pipe_txmargin <= 3'b000;
                eq_phase_out  <= 2'd0;
            end
        endcase
    end
end

endmodule
