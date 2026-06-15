// =============================================================================
// Module  : spd_chg  ?  Data Rate / Speed Change FSM
// Standard: PCIe All Generations (tag SPD_CHG)
// Source  : pcie_gen6_complete_all_layers_v2.html  (PHY Layer, link group)
//
// Description:
//   Orchestrates a PCIe speed change by driving the PIPE Rate signal through
//   the Recovery.Speed sub-state.  Follows the sequence:
//     1. Receive speed_change_en + target_speed
//     2. Assert new pipe_rate_out
//     3. Wait for recovery_done (link re-trained at new speed)
//     4. Verify pipe_rate echoed back by analog PHY
//     5. Assert speed_change_done or speed_change_err
//
// PIPE Rate encoding (PCIe spec):
//   4'b0001 = Gen1 (2.5  GT/s)
//   4'b0010 = Gen2 (5    GT/s)
//   4'b0011 = Gen3 (8    GT/s)
//   4'b0100 = Gen4 (16   GT/s)
//   4'b0101 = Gen5 (32   GT/s)
//   4'b0110 = Gen6 (64   GT/s)
//
// Interface (verbatim from HTML):
//   Inputs : speed_change_en, target_speed[3:0], recovery_done,
//            pipe_rate[3:0], clk, rst_n
//   Outputs: pipe_rate_out[3:0], speed_change_done, speed_change_err,
//            retrain_req
// =============================================================================

module spd_chg (
    // ?? Clock / Reset ??????????????????????????????????????????????????????
    input  wire        clk,
    input  wire        rst_n,

    // ?? Inputs ?????????????????????????????????????????????????????????????
    input  wire        speed_change_en,    // Assert to start speed change
    input  wire [3:0]  target_speed,       // Desired PIPE rate code
    input  wire        recovery_done,      // LTSSM Recovery complete
    input  wire [3:0]  pipe_rate,          // Echoed PIPE rate from PHY

    // ?? Outputs ????????????????????????????????????????????????????????????
    output reg  [3:0]  pipe_rate_out,      // PIPE Rate to PHY
    output reg         speed_change_done,  // Speed change successful
    output reg         speed_change_err,   // Speed change failed
    output reg         retrain_req         // Request LTSSM Recovery entry
);

// =============================================================================
// Parameters
// =============================================================================
// Timeout: number of clock cycles to wait for recovery_done / pipe_rate echo.
// At 500 MHz core clock, 10 000 cycles ? 20 µs (well within spec margin).
parameter TIMEOUT_VAL = 14'd10_000;

// PIPE rate codes
localparam [3:0]
    RATE_GEN1 = 4'b0001,
    RATE_GEN2 = 4'b0010,
    RATE_GEN3 = 4'b0011,
    RATE_GEN4 = 4'b0100,
    RATE_GEN5 = 4'b0101,
    RATE_GEN6 = 4'b0110;

// =============================================================================
// State Encoding
// =============================================================================
localparam [2:0]
    S_IDLE        = 3'd0,  // Idle ? waiting for speed_change_en
    S_RETRAIN     = 3'd1,  // Assert retrain_req; wait for LTSSM entry
    S_RATE_SET    = 3'd2,  // Drive pipe_rate_out; wait for recovery_done
    S_VERIFY      = 3'd3,  // Verify PHY echoes correct pipe_rate
    S_DONE        = 3'd4,  // Pulse speed_change_done
    S_ERROR       = 3'd5;  // Pulse speed_change_err

reg [2:0]  state, next_state;
reg [13:0] timeout_cnt;
reg        timeout_exp;

// Latched target speed (held while FSM runs)
reg [3:0]  target_speed_r;

// =============================================================================
// Timeout counter
// =============================================================================
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

// =============================================================================
// Sequential state register + latch inputs
// =============================================================================
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

// =============================================================================
// Next-state logic
// =============================================================================
always @(*) begin
    next_state = state;
    case (state)
        S_IDLE:
            if (speed_change_en)
                next_state = S_RETRAIN;

        S_RETRAIN:
            // Wait one cycle then move to rate set
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

// =============================================================================
// Output logic
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_rate_out     <= RATE_GEN1;  // Default: Gen1
        speed_change_done <= 1'b0;
        speed_change_err  <= 1'b0;
        retrain_req       <= 1'b0;
    end else begin
        // Single-cycle pulse defaults
        speed_change_done <= 1'b0;
        speed_change_err  <= 1'b0;

        case (state)
            S_IDLE: begin
                retrain_req   <= 1'b0;
                // Hold current rate
            end

            S_RETRAIN: begin
                retrain_req   <= 1'b1;   // Signal LTSSM to enter Recovery
                pipe_rate_out <= target_speed_r;
            end

            S_RATE_SET: begin
                retrain_req   <= 1'b0;
                pipe_rate_out <= target_speed_r; // Hold rate
            end

            S_VERIFY: begin
                // pipe_rate_out unchanged; checking echo
            end

            S_DONE: begin
                speed_change_done <= 1'b1;
            end

            S_ERROR: begin
                speed_change_err  <= 1'b1;
                pipe_rate_out     <= RATE_GEN1;  // Fall back to Gen1
            end

            default: begin
                retrain_req <= 1'b0;
            end
        endcase
    end
end

endmodule
