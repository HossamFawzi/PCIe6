
module spd_chg (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        speed_change_en,
    input  wire [3:0]  target_speed,
    input  wire        recovery_done,
    input  wire [3:0]  pipe_rate,

    output reg  [3:0]  pipe_rate_out,
    output reg         speed_change_done,
    output reg         speed_change_err,
    output reg         retrain_req
);

parameter TIMEOUT_VAL = 14'd10_000;

localparam [3:0]
    RATE_GEN1 = 4'b0001,
    RATE_GEN2 = 4'b0010,
    RATE_GEN3 = 4'b0011,
    RATE_GEN4 = 4'b0100,
    RATE_GEN5 = 4'b0101,
    RATE_GEN6 = 4'b0110;

localparam [2:0]
    S_IDLE        = 3'd0,
    S_RETRAIN     = 3'd1,
    S_RATE_SET    = 3'd2,
    S_VERIFY      = 3'd3,
    S_DONE        = 3'd4,
    S_ERROR       = 3'd5;

reg [2:0]  state, next_state;
reg [13:0] timeout_cnt;
reg        timeout_exp;

reg [3:0]  target_speed_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        timeout_cnt <= 14'd0;
        timeout_exp <= 1'b0;
    end else if (state == S_IDLE || state == S_DONE || state == S_ERROR) begin
        timeout_cnt <= 14'd0;
        timeout_exp <= 1'b0;
    end else begin
        if (timeout_cnt == TIMEOUT_VAL) begin
            timeout_exp <= 1'b1;
        end else begin
            timeout_cnt <= timeout_cnt + 14'd1;
            timeout_exp <= 1'b0;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= S_IDLE;
        target_speed_r <= 4'd0;
    end else begin
        state <= next_state;
        if (state == S_IDLE && speed_change_en)
            target_speed_r <= target_speed;
    end
end

always @(*) begin
    next_state = state;
    case (state)
        S_IDLE:
            if (speed_change_en)
                next_state = S_RETRAIN;

        S_RETRAIN:

            next_state = S_RATE_SET;

        S_RATE_SET:
            if (timeout_exp)    next_state = S_ERROR;
            else if (recovery_done) next_state = S_VERIFY;

        S_VERIFY:
            if (timeout_exp)               next_state = S_ERROR;
            else if (pipe_rate == target_speed_r) next_state = S_DONE;

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
        pipe_rate_out     <= RATE_GEN1;
        speed_change_done <= 1'b0;
        speed_change_err  <= 1'b0;
        retrain_req       <= 1'b0;
    end else begin

        speed_change_done <= 1'b0;
        speed_change_err  <= 1'b0;

        case (state)
            S_IDLE: begin
                retrain_req   <= 1'b0;

            end

            S_RETRAIN: begin
                retrain_req   <= 1'b1;
                pipe_rate_out <= target_speed_r;
            end

            S_RATE_SET: begin
                retrain_req   <= 1'b0;
                pipe_rate_out <= target_speed_r;
            end

            S_VERIFY: begin

            end

            S_DONE: begin
                speed_change_done <= 1'b1;
            end

            S_ERROR: begin
                speed_change_err  <= 1'b1;
                pipe_rate_out     <= RATE_GEN1;
            end

            default: begin
                retrain_req <= 1'b0;
            end
        endcase
    end
end

endmodule
