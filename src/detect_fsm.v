// =============================================================================
// Module : detect_fsm
// Project: PCIe Gen6 Physical Layer ? LTSSM Sub-FSM
// Function: Detect FSM ? Detects receiver termination per lane via
//           PIPE PhyStatus / RxElecIdle signals.
//           Implements Detect.Quiet and Detect.Active sub-states per
//           PCIe Base Specification 6.0 Section 4.2.4.
//
// Interface compatibility:
//   - detect_done / receiver_detected consumed by ltssm_top internal logic
//   - lanes_detected[15:0] consumed by PIPE_CTRL and WDT_NEG modules
//   - detect_timeout feeds ltssm_top to loop back to Detect.Quiet
//   - detect_timer_exp: external one-cycle pulse when the Detect window
//     (12 ms Quiet / probe Active window) expires
//   - pipe_status[2:0] = PIPE PhyStatus-equivalent RxStatus bus
//
// PIPE pipe_status[2:0] encoding:
//   3'b000 = Idle / Electrical Idle on all lanes
//   3'b001 = Receiver Detected (PIPE PhyStatus asserted after TxDetectRx)
//   3'b010 = Receiver Not Detected
//   3'b011 = RxElecIdle de-asserted (signal present, not idle)
//   other  = reserved
//
// FSM states:
//   ST_IDLE      ? waits for detect_req from LTSSM             [FIX-1]
//   ST_QUIET     ? Detect.Quiet: TX elec-idle, wait for RX idle + timer
//   ST_ACTIVE    ? Detect.Active: per-lane probe, collect PhyStatus
//   ST_LANE_EVAL ? evaluate per-lane results
//   ST_DONE      ? one-cycle pulse: detect_done, receiver_detected valid
//   ST_TIMEOUT   ? one-cycle pulse: detect_timeout, back to IDLE
//
// Language: Verilog-2001 (no SystemVerilog)
// =============================================================================
`timescale 1ns/1ps
module detect_fsm (
    input  wire        clk,
    input  wire        rst_n,
    // ?? PIPE interface ????????????????????????????????????????????????????
    input  wire        detect_req,          // [FIX-1] start pulse from LTSSM
    input  wire        pipe_rx_elec_idle,   // 1 = all lanes electrically idle
    input  wire        detect_timer_exp,    // 1-cycle pulse: window expired
    input  wire [2:0]  pipe_status,         // PIPE PhyStatus result bus
    // ?? Outputs ???????????????????????????????????????????????????????????
    output wire        detect_done,         // 1-cycle pulse: result ready
    output wire        receiver_detected,   // level: at least one lane found
    output wire [15:0] lanes_detected,      // bitmap: which lanes detected
    output wire        detect_timeout       // 1-cycle pulse: timed out
);
// =============================================================================
// STATE ENCODING
// =============================================================================
localparam [2:0]
    ST_IDLE      = 3'd0,
    ST_QUIET     = 3'd1,
    ST_ACTIVE    = 3'd2,
    ST_LANE_EVAL = 3'd3,
    ST_DONE      = 3'd4,
    ST_TIMEOUT   = 3'd5;
// =============================================================================
// PIPE STATUS CODES
// =============================================================================
localparam [2:0]
    PIPE_ST_IDLE    = 3'b000,
    PIPE_ST_RX_DET  = 3'b001,
    PIPE_ST_NO_RX   = 3'b010,
    PIPE_ST_EI_EXIT = 3'b011;
// =============================================================================
// PARAMETERS
// =============================================================================
// Per-lane probe window: 20 cycles @ 100 MHz ? 200 ns
// (real value = ~1 µs; kept short for simulation speed)
localparam [7:0]  PROBE_WAIT_INIT = 8'd20;
// Maximum lane index to probe (0?15 ? 16 lanes for x16)
localparam [3:0]  MAX_LANE        = 4'd15;
// =============================================================================
// INTERNAL REGISTERS
// =============================================================================
reg [2:0]  state, next_state;
reg [3:0]  lane_ptr;          // lane currently being probed
reg [15:0] lane_det_reg;      // per-lane detection bitmap (accumulator)
reg [7:0]  probe_wait;        // per-lane probe countdown
// [FIX-3] any_det removed ? was assigned in ST_LANE_EVAL but never read
//         anywhere in next-state or output logic. Synthesis warning eliminated.
// =============================================================================
// SEQUENTIAL STATE REGISTER
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        state <= ST_IDLE;
    else
        state <= next_state;
end
// =============================================================================
// NEXT-STATE COMBINATIONAL LOGIC
// =============================================================================
always @(*) begin
    next_state = state;
    case (state)
        // ?? ST_IDLE ?????????????????????????????????????????????????????????
        // [FIX-1] Gate on detect_req from LTSSM instead of auto-starting.
        // Original unconditionally jumped to ST_QUIET, causing the FSM to
        // loop continuously after reset with no external enable.
        ST_IDLE: begin
            if (detect_req)
                next_state = ST_QUIET;
        end
        // ?? ST_QUIET ? Detect.Quiet ??????????????????????????????????????????
        // TX driven to electrical idle.
        // Advance to Active when both conditions are met:
        //   1. All RX lanes show electrical idle (pipe_rx_elec_idle)
        //   2. Quiet timer has expired (detect_timer_exp)
        // If the timer expires but RX is NOT idle, restart the quiet period.
        ST_QUIET: begin
            if (detect_timer_exp) begin
                if (pipe_rx_elec_idle)
                    next_state = ST_ACTIVE;
                else
                    next_state = ST_QUIET;  // restart quiet period
            end
        end
        // ?? ST_ACTIVE ? Detect.Active ????????????????????????????????????????
        // PHY sends probe pulse (TxDetectRx) on each lane in turn.
        // probe_wait counts down per-lane; advance to next lane when done.
        // If the overall window (detect_timer_exp) fires before all lanes
        // are probed, time out.
        ST_ACTIVE: begin
            if (detect_timer_exp) begin
                next_state = ST_TIMEOUT;
            end else if (probe_wait == 8'd0) begin
                if (lane_ptr == MAX_LANE)
                    next_state = ST_LANE_EVAL;
                // else hold ? sequential block will bump lane_ptr next cycle
            end
        end
        // ?? ST_LANE_EVAL ?????????????????????????????????????????????????????
        // Single-cycle evaluation: check if any lane detected.
        ST_LANE_EVAL: begin
            if (lane_det_reg != 16'd0)
                next_state = ST_DONE;
            else
                next_state = ST_TIMEOUT;
        end
        // ?? ST_DONE ??????????????????????????????????????????????????????????
        // One-cycle output pulse; return to IDLE for the next detect request.
        ST_DONE: begin
            next_state = ST_IDLE;
        end
        // ?? ST_TIMEOUT ???????????????????????????????????????????????????????
        // One-cycle timeout pulse; return to IDLE.
        ST_TIMEOUT: begin
            next_state = ST_IDLE;
        end
        default: next_state = ST_IDLE;
    endcase
end
// =============================================================================
// LANE PROBE DATAPATH ? sequential
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lane_ptr     <= 4'd0;
        lane_det_reg <= 16'd0;
        probe_wait   <= PROBE_WAIT_INIT;
        // [FIX-3] any_det initialisation removed with the register
    end else begin
        case (state)
            ST_IDLE: begin
                lane_ptr     <= 4'd0;
                lane_det_reg <= 16'd0;
                probe_wait   <= PROBE_WAIT_INIT;
            end
            ST_QUIET: begin
                // Reset lane probing state so Active starts clean
                lane_ptr     <= 4'd0;
                lane_det_reg <= 16'd0;
                probe_wait   <= PROBE_WAIT_INIT;
            end
            ST_ACTIVE: begin
                if (!detect_timer_exp) begin
                    // [FIX-2] Sample pipe_status on EVERY cycle including the
                    // probe_wait == 0 cycle.  Original put the sample only
                    // inside the "if (probe_wait != 0)" branch, silently
                    // skipping one valid sample cycle per lane on the
                    // transition edge ? dangerous if PHY asserts exactly then.
                    if (pipe_status == PIPE_ST_RX_DET)
                        lane_det_reg[lane_ptr] <= 1'b1;

                    if (probe_wait != 8'd0) begin
                        probe_wait <= probe_wait - 8'd1;
                    end else begin
                        // Per-lane window done; advance to next lane
                        if (lane_ptr != MAX_LANE) begin
                            lane_ptr   <= lane_ptr + 4'd1;
                            probe_wait <= PROBE_WAIT_INIT;
                        end
                        // If lane_ptr == MAX_LANE, next_state = ST_LANE_EVAL
                    end
                end
            end
            ST_LANE_EVAL: begin
                // [FIX-3] any_det <= (lane_det_reg != 16'd0) removed here.
                // next_state logic reads lane_det_reg directly ? any_det
                // was dead code never consumed by any logic.
            end
            default: begin end
        endcase
    end
end
// =============================================================================
// OUTPUT LOGIC
// detect_done / detect_timeout / receiver_detected / lanes_detected are
// ALL COMBINATIONAL from state and lane_det_reg ? zero pipeline lag.
// After the ST_DONE / ST_TIMEOUT cycle, held registers preserve the result.
// =============================================================================
// Hold registers: updated when we leave ST_DONE / ST_TIMEOUT
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
// Combinational outputs: show live result during ST_DONE/ST_TIMEOUT,
// hold the last result otherwise.
assign detect_done       = (state == ST_DONE);
assign detect_timeout    = (state == ST_TIMEOUT);
assign receiver_detected = (state == ST_DONE)    ? (lane_det_reg != 16'd0) :
                           (state == ST_TIMEOUT)  ? 1'b0 :
                                                    recv_det_hold;
assign lanes_detected    = (state == ST_DONE)    ? lane_det_reg :
                           (state == ST_TIMEOUT)  ? 16'd0 :
                                                    lanes_hold;
endmodule