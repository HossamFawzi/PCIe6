// =============================================================================
// Module   : hrst_fsm
// Tag      : HRST_FSM
// Spec     : PCIe Gen6 PHY Digital Layer – Module 9
// Function : Hot Reset / Disabled FSM
//            Hot Reset: propagates reset across link via TS1 Hot-Reset bit.
//            Disabled : powers down link, drives PIPE P1/P2, asserts done.
// Language : Verilog-2001  (NO SystemVerilog, NO UVM)
// =============================================================================
`timescale 1ns/1ps

module hrst_fsm (
    // -------------------------------------------------------------------------
    // Clock / Reset  (listed as "clk/rst_n" in HTML – treated as two ports)
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Inputs  (exact names + widths from HTML spec)
    // -------------------------------------------------------------------------
    input  wire        hot_reset_req,   // 1 – upstream Hot-Reset request
    input  wire        disable_req,     // 1 – link-disable request
    input  wire        ts1_hr_bit,      // 1 – received TS1 Hot-Reset bit
    input  wire        ts1_dis_bit,     // 1 – received TS1 Disable-Link bit
    input  wire        timer_exp,       // 1 – external timer expiry pulse

    // -------------------------------------------------------------------------
    // Outputs (exact names + widths from HTML spec)
    // -------------------------------------------------------------------------
    output reg         send_ts1_hr,         // 1 – send TS1 with Hot-Reset bit
    output reg         send_ts1_dis,        // 1 – send TS1 with Disable bit
    output reg         hot_reset_done,      // 1 – Hot-Reset sequence complete
    output reg         disabled_done,       // 1 – Disabled sequence complete
    output reg  [1:0]  pipe_power_down      // 2 – PIPE PowerDown[1:0]
);

// =============================================================================
// FSM state encoding
// =============================================================================
localparam [3:0]
    ST_IDLE          = 4'd0,
    // Hot-Reset sub-states
    ST_HR_ASSERT     = 4'd1,   // driving TS1 with HR bit, wait for reflected HR
    ST_HR_CONFIRM    = 4'd2,   // received HR bit back, count confirmations
    ST_HR_DONE       = 4'd3,   // pulse hot_reset_done, wait for deassertion
    // Disabled sub-states
    ST_DIS_SEND      = 4'd4,   // driving TS1 with Disable bit
    ST_DIS_CONFIRM   = 4'd5,   // received Disable bit back
    ST_DIS_POWERDN   = 4'd6,   // apply PIPE P1→P2 ramp
    ST_DIS_DONE      = 4'd7,   // pulse disabled_done, hold PIPE P2
    // Illegal-state recovery landing
    ST_RECOVER       = 4'd15;

// =============================================================================
// PCIe spec timing
//   Hot-Reset:  ≥2 consecutive TS1 with HR bit received  → done
//               Max dwell  ≥2 ms  (~500 000 cy @ 250 MHz)
//   Disabled :  ≥2 consecutive TS1 with Disable bit → PIPE P2 → done
//               Power-down ramp  ≥1 µs  (~250 cy @ 250 MHz)
// Using a simple internal timer to meet the ≥2 ms / ≥1µs requirements.
// The external timer_exp is also honoured (e.g. from LTSSM Top).
// =============================================================================
localparam [15:0]
    HR_CONFIRM_NEEDED  = 16'd2,      // TS1 HR  confirmations required
    DIS_CONFIRM_NEEDED = 16'd2,      // TS1 Dis confirmations required
    HR_DWELL_CY        = 16'd500,    // internal dwell counter (scaled for sim)
    DIS_RAMP_CY        = 16'd10;     // PIPE P1→P2 ramp counter (scaled for sim)

// =============================================================================
// Internal registers
// =============================================================================
reg [3:0]  cur_state, nxt_state;

reg [15:0] hr_confirm_cnt;     // consecutive TS1-HR  received
reg [15:0] dis_confirm_cnt;    // consecutive TS1-Dis received
reg [15:0] dwell_cnt;          // internal dwell / ramp timer

// =============================================================================
// Debug / waveform visibility
// =============================================================================
// (all regs above are already visible; add labelled wires for clarity)
wire [3:0]  dbg_cur_state   = cur_state;
wire [3:0]  dbg_nxt_state   = nxt_state;
wire [15:0] dbg_hr_confirm  = hr_confirm_cnt;
wire [15:0] dbg_dis_confirm = dis_confirm_cnt;
wire [15:0] dbg_dwell       = dwell_cnt;

// =============================================================================
// Sequential block
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cur_state       <= ST_IDLE;
        hr_confirm_cnt  <= 16'd0;
        dis_confirm_cnt <= 16'd0;
        dwell_cnt       <= 16'd0;
    end else begin
        cur_state <= nxt_state;

        // ---- Hot-Reset confirmation counter ----
        case (cur_state)
            ST_HR_ASSERT: begin
                if (ts1_hr_bit)
                    hr_confirm_cnt <= hr_confirm_cnt + 16'd1;
                else
                    hr_confirm_cnt <= 16'd0;
                dwell_cnt <= 16'd0;
            end
            ST_HR_CONFIRM: begin
                dwell_cnt <= dwell_cnt + 16'd1;
            end
            ST_HR_DONE: begin
                dwell_cnt <= 16'd0;
            end
            // ---- Disabled confirmation counter ----
            ST_DIS_SEND: begin
                if (ts1_dis_bit)
                    dis_confirm_cnt <= dis_confirm_cnt + 16'd1;
                else
                    dis_confirm_cnt <= 16'd0;
                dwell_cnt <= 16'd0;
            end
            ST_DIS_CONFIRM: begin
                dwell_cnt <= 16'd0;
            end
            ST_DIS_POWERDN: begin
                dwell_cnt <= dwell_cnt + 16'd1;
            end
            default: begin
                hr_confirm_cnt  <= 16'd0;
                dis_confirm_cnt <= 16'd0;
                dwell_cnt       <= 16'd0;
            end
        endcase
    end
end

// =============================================================================
// Combinational next-state + output logic
// =============================================================================
always @(*) begin
    // ---- Default outputs ----
    nxt_state      = cur_state;
    send_ts1_hr    = 1'b0;
    send_ts1_dis   = 1'b0;
    hot_reset_done = 1'b0;
    disabled_done  = 1'b0;
    pipe_power_down = 2'b00;   // P0 = fully active

    case (cur_state)
        // ------------------------------------------------------------------
        ST_IDLE: begin
            pipe_power_down = 2'b00;
            if (hot_reset_req)
                nxt_state = ST_HR_ASSERT;
            else if (disable_req)
                nxt_state = ST_DIS_SEND;
        end

        // ------------------------------------------------------------------
        // Hot-Reset: drive TS1 with HR bit; wait for partner to reflect it
        // ------------------------------------------------------------------
        ST_HR_ASSERT: begin
            send_ts1_hr    = 1'b1;
            pipe_power_down = 2'b00;
            if (timer_exp && hr_confirm_cnt < HR_CONFIRM_NEEDED) begin
                // timeout without enough confirmations → back to idle
                nxt_state = ST_IDLE;
            end else if (hr_confirm_cnt >= HR_CONFIRM_NEEDED) begin
                nxt_state = ST_HR_CONFIRM;
            end
        end

        // ------------------------------------------------------------------
        // Hot-Reset confirmed: keep driving HR TS1 for minimum dwell
        // ------------------------------------------------------------------
        ST_HR_CONFIRM: begin
            send_ts1_hr    = 1'b1;
            pipe_power_down = 2'b00;
            if (dwell_cnt >= HR_DWELL_CY || timer_exp)
                nxt_state = ST_HR_DONE;
        end

        // ------------------------------------------------------------------
        // Pulse done; stay until requester deasserts hot_reset_req
        // ------------------------------------------------------------------
        ST_HR_DONE: begin
            hot_reset_done  = 1'b1;
            pipe_power_down = 2'b00;
            if (!hot_reset_req)
                nxt_state = ST_IDLE;
        end

        // ------------------------------------------------------------------
        // Disabled: drive TS1 with Disable bit; wait for partner to reflect
        // ------------------------------------------------------------------
        ST_DIS_SEND: begin
            send_ts1_dis   = 1'b1;
            pipe_power_down = 2'b01;   // P1 during disable handshake
            if (timer_exp && dis_confirm_cnt < DIS_CONFIRM_NEEDED) begin
                nxt_state = ST_IDLE;
            end else if (dis_confirm_cnt >= DIS_CONFIRM_NEEDED) begin
                nxt_state = ST_DIS_CONFIRM;
            end
        end

        // ------------------------------------------------------------------
        // Disabled handshake confirmed; begin PIPE ramp to P2
        // ------------------------------------------------------------------
        ST_DIS_CONFIRM: begin
            send_ts1_dis   = 1'b1;
            pipe_power_down = 2'b01;
            nxt_state = ST_DIS_POWERDN;
        end

        // ------------------------------------------------------------------
        // Ramp PIPE to P2; wait for ramp timer
        // ------------------------------------------------------------------
        ST_DIS_POWERDN: begin
            pipe_power_down = 2'b10;   // P2 = disabled / low-power
            if (dwell_cnt >= DIS_RAMP_CY || timer_exp)
                nxt_state = ST_DIS_DONE;
        end

        // ------------------------------------------------------------------
        // Hold P2; pulse done; wait for deassertion
        // ------------------------------------------------------------------
        ST_DIS_DONE: begin
            disabled_done   = 1'b1;
            pipe_power_down = 2'b10;
            if (!disable_req)
                nxt_state = ST_IDLE;
        end

        // ------------------------------------------------------------------
        // Illegal-state recovery
        // ------------------------------------------------------------------
        ST_RECOVER: begin
            pipe_power_down = 2'b00;
            nxt_state = ST_IDLE;
        end

        default: begin
            // Any unencoded state → recovery
            nxt_state = ST_RECOVER;
        end
    endcase
end

endmodule
