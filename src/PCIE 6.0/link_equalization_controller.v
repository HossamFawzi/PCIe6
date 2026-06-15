// =============================================================================
// Module  : eq_ctrl  ?  Link Equalization Controller
// Standard: PCIe Gen3+ (tag EQ_CTRL)
// Source  : pcie_gen6_complete_all_layers_v2.html  (PHY Layer, link group)
//
// Description:
//   Implements the Gen3+ equalization handshake (Phases 0-3).
//   Drives PIPE TX de-emphasis and TX margin while coordinating the
//   pipe_rxeqeval evaluation handshake with the analog PHY.
//
// Interface (verbatim from HTML):
//   Inputs :  eq_req, eq_phase[1:0], ts1_eq_req_bit, ts2_eq_preset[3:0],
//             pipe_rxeqeval, eq_timer_exp, clk, rst_n
//   Outputs:  pipe_txdeemph[2:0], pipe_txmargin[2:0], pipe_rxeqeval_out,
//             eq_done, eq_phase_out[1:0], eq_err
// =============================================================================

module eq_ctrl (
    // ?? Clock / Reset ??????????????????????????????????????????????????????
    input  wire        clk,
    input  wire        rst_n,

    // ?? Inputs ?????????????????????????????????????????????????????????????
    input  wire        eq_req,            // Start equalization
    input  wire [1:0]  eq_phase,          // Requested phase (0-3)
    input  wire        ts1_eq_req_bit,    // EQ request bit seen in TS1
    input  wire [3:0]  ts2_eq_preset,     // Preset from TS2 (P0-P10)
    input  wire        pipe_rxeqeval,     // PHY evaluation complete
    input  wire        eq_timer_exp,      // Guard-band timer expired

    // ?? Outputs ????????????????????????????????????????????????????????????
    output reg  [2:0]  pipe_txdeemph,     // PIPE TX de-emphasis control
    output reg  [2:0]  pipe_txmargin,     // PIPE TX margin control
    output reg         pipe_rxeqeval_out, // Start RX equalization eval
    output reg         eq_done,           // Equalization complete
    output reg  [1:0]  eq_phase_out,      // Current phase being executed
    output reg         eq_err             // Equalization error / timeout
);

// =============================================================================
// State Encoding
// =============================================================================
localparam [3:0]
    S_IDLE       = 4'd0,  // Waiting for eq_req
    S_PHASE0     = 4'd1,  // Phase 0: apply default preset
    S_PHASE1_REQ = 4'd2,  // Phase 1: assert pipe_rxeqeval, wait ACK
    S_PHASE1_ACK = 4'd3,  // Phase 1: waiting for PHY eval done
    S_PHASE2_REQ = 4'd4,  // Phase 2: TX preset from TS2 applied
    S_PHASE2_ACK = 4'd5,  // Phase 2: wait PHY confirmation
    S_PHASE3     = 4'd6,  // Phase 3: final coefficients locked
    S_DONE       = 4'd7,  // Assert eq_done for one cycle
    S_ERROR      = 4'd8;  // Assert eq_err

reg [3:0] state, next_state;

// =============================================================================
// Preset-to-PIPE mapping (simplified PCIe preset table)
// preset ? {pipe_txdeemph[2:0], pipe_txmargin[2:0]}
// =============================================================================
function [5:0] preset_to_pipe;
    input [3:0] preset;
    case (preset)
        4'd0:  preset_to_pipe = 6'b000_000; // P0:  0 dB deemph, 0 margin
        4'd1:  preset_to_pipe = 6'b001_000; // P1:  -1 dB
        4'd2:  preset_to_pipe = 6'b010_000; // P2:  -2 dB
        4'd3:  preset_to_pipe = 6'b011_001; // P3:  -3 dB, +1 margin
        4'd4:  preset_to_pipe = 6'b100_001; // P4:  -3.5 dB
        4'd5:  preset_to_pipe = 6'b101_010; // P5:  -6 dB
        4'd6:  preset_to_pipe = 6'b110_010; // P6:  -8 dB
        4'd7:  preset_to_pipe = 6'b111_011; // P7:  full de-emphasis
        default: preset_to_pipe = 6'b000_000;
    endcase
endfunction

// =============================================================================
// Sequential state register
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
end

// =============================================================================
// Next-state logic
// =============================================================================
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
            // Phase 0: immediately transition after one cycle setup
            next_state = S_PHASE1_REQ;

        S_PHASE1_REQ:
            // Assert pipe_rxeqeval_out; wait for PHY to echo back
            if (eq_timer_exp) next_state = S_ERROR;
            else if (pipe_rxeqeval) next_state = S_PHASE1_ACK;

        S_PHASE1_ACK:
            // PHY acknowledged; move to Phase 2
            next_state = S_PHASE2_REQ;

        S_PHASE2_REQ:
            // Apply TS2 preset; wait eval
            if (eq_timer_exp) next_state = S_ERROR;
            else if (pipe_rxeqeval) next_state = S_PHASE2_ACK;

        S_PHASE2_ACK:
            next_state = S_PHASE3;

        S_PHASE3:
            // Coefficients locked ? TS1 eq request must now clear
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

// =============================================================================
// Output logic
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_txdeemph    <= 3'b000;
        pipe_txmargin    <= 3'b000;
        pipe_rxeqeval_out <= 1'b0;
        eq_done          <= 1'b0;
        eq_phase_out     <= 2'd0;
        eq_err           <= 1'b0;
    end else begin
        // Defaults (pulse signals)
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
                // Apply default (P0) preset
                {pipe_txdeemph, pipe_txmargin} <= preset_to_pipe(4'd0);
                eq_phase_out  <= 2'd0;
            end

            S_PHASE1_REQ: begin
                pipe_rxeqeval_out <= 1'b1;  // Request PHY eval
                eq_phase_out      <= 2'd1;
            end

            S_PHASE1_ACK: begin
                eq_phase_out <= 2'd1;
            end

            S_PHASE2_REQ: begin
                // Apply preset received in TS2
                {pipe_txdeemph, pipe_txmargin} <= preset_to_pipe(ts2_eq_preset);
                pipe_rxeqeval_out <= 1'b1;
                eq_phase_out      <= 2'd2;
            end

            S_PHASE2_ACK: begin
                eq_phase_out <= 2'd2;
            end

            S_PHASE3: begin
                // Hold current coefficients; wait for remote to clear eq request
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
