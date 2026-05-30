// ============================================================
// Module 48 : Hot Reset Handler (HOT_RST)
// PCIe Gen6 Physical Layer
// Two consecutive TS1s with Hot Reset bit → downstream reset.
// Must propagate through switch hierarchy.
// ============================================================
module hot_rst (
    input  wire        clk,
    input  wire        rst_n,

    // Inputs
    input  wire        ts1_hot_reset_bit,  // Hot Reset bit from received TS1
    input  wire        hot_reset_req_sw,   // Software-initiated hot reset
    input  wire        ts1_detected,       // TS1 was detected this cycle
    input  wire [5:0]  ltssm_state,        // Current LTSSM state

    // Outputs
    output reg         hot_reset_active,   // Hot reset in progress
    output reg         send_ts1_hot_reset, // Send TS1 with Hot Reset bit set
    output reg         hot_reset_done,     // Reset sequence complete (pulse)
    output reg         pipe_reset_out      // Assert PIPE reset to analog PHY
);

// Two consecutive TS1s with Hot Reset bit needed to trigger
localparam CONSEC_THRESH = 2'd2;

reg [1:0] consec_cnt;    // Consecutive TS1 with hot reset count
reg [3:0] rst_dur_cnt;   // Duration to hold reset

// FSM
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
        hot_reset_done <= 1'b0;  // Default pulse off

        case (state)
            S_IDLE: begin
                hot_reset_active   <= 1'b0;
                send_ts1_hot_reset <= 1'b0;
                pipe_reset_out     <= 1'b0;
                consec_cnt         <= 2'd0;

                if (hot_reset_req_sw) begin
                    // SW-initiated: go straight to hot reset
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
                            // Threshold met
                            state <= S_HOT_RESET;
                        end else begin
                            consec_cnt <= consec_cnt + 2'd1;
                        end
                    end else begin
                        // Not hot reset bit — reset counter
                        consec_cnt <= 2'd0;
                        state      <= S_IDLE;
                    end
                end
            end

            S_HOT_RESET: begin
                hot_reset_active   <= 1'b1;
                pipe_reset_out     <= 1'b1;
                send_ts1_hot_reset <= 1'b1;  // Propagate to downstream
                rst_dur_cnt        <= 4'd0;
                state              <= S_SEND_TS1;
            end

            S_SEND_TS1: begin
                // Hold for a few cycles then done
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
