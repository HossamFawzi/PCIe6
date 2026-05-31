
module hot_rst (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        ts1_hot_reset_bit,
    input  wire        hot_reset_req_sw,
    input  wire        ts1_detected,
    input  wire [5:0]  ltssm_state,

    output reg         hot_reset_active,
    output reg         send_ts1_hot_reset,
    output reg         hot_reset_done,
    output reg         pipe_reset_out
);

localparam CONSEC_THRESH = 2'd2;

reg [1:0] consec_cnt;
reg [3:0] rst_dur_cnt;

localparam S_IDLE        = 3'd0;
localparam S_COUNTING    = 3'd1;
localparam S_HOT_RESET   = 3'd2;
localparam S_SEND_TS1    = 3'd3;
localparam S_DONE        = 3'd4;

reg [2:0] state;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hot_reset_active   <= 1'b0;
        send_ts1_hot_reset <= 1'b0;
        hot_reset_done     <= 1'b0;
        pipe_reset_out     <= 1'b0;
        consec_cnt         <= 2'd0;
        rst_dur_cnt        <= 4'd0;
        state              <= S_IDLE;
    end else begin
        hot_reset_done <= 1'b0;

        case (state)
            S_IDLE: begin
                hot_reset_active   <= 1'b0;
                send_ts1_hot_reset <= 1'b0;
                pipe_reset_out     <= 1'b0;
                consec_cnt         <= 2'd0;

                if (hot_reset_req_sw) begin

                    state <= S_HOT_RESET;
                end else if (ts1_detected && ts1_hot_reset_bit) begin
                    consec_cnt <= 2'd1;
                    state      <= S_COUNTING;
                end
            end

            S_COUNTING: begin
                if (ts1_detected) begin
                    if (ts1_hot_reset_bit) begin
                        if (consec_cnt >= CONSEC_THRESH - 2'd1) begin

                            state <= S_HOT_RESET;
                        end else begin
                            consec_cnt <= consec_cnt + 2'd1;
                        end
                    end else begin

                        consec_cnt <= 2'd0;
                        state      <= S_IDLE;
                    end
                end
            end

            S_HOT_RESET: begin
                hot_reset_active   <= 1'b1;
                pipe_reset_out     <= 1'b1;
                send_ts1_hot_reset <= 1'b1;
                rst_dur_cnt        <= 4'd0;
                state              <= S_SEND_TS1;
            end

            S_SEND_TS1: begin

                if (rst_dur_cnt >= 4'd8) begin
                    send_ts1_hot_reset <= 1'b0;
                    pipe_reset_out     <= 1'b0;
                    state              <= S_DONE;
                end else begin
                    rst_dur_cnt <= rst_dur_cnt + 4'd1;
                end
            end

            S_DONE: begin
                hot_reset_active <= 1'b0;
                hot_reset_done   <= 1'b1;
                state            <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
