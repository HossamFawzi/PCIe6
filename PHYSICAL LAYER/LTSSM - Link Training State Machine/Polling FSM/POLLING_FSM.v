// =============================================================================
// File        : DESIGN.v
// Module      : polling_fsm
// Description : PCIe Gen6 LTSSM Polling State Machine
//               Implements Polling.Active, Polling.Configuration, and
//               Polling.Compliance sub-states per PCIe Base Spec 6.0 r1.0
//               Section 4.2.6.  Operates at Gen1 speed (2.5 GT/s) during
//               link training.  Interfaces to the upstream detect_fsm
//               (via lanes_detected) and the PIPE_CTRL block.
//
// Coding Style: Verilog-2001, synchronous, purely synthesizable, no latches.
// =============================================================================

`timescale 1ns / 1ps

// ---------------------------------------------------------------------------
// Parameter defaults (cycle counts at 250 MHz):
//   POLL_ACTIVE_TIMEOUT  : 24 ms  = 24_000_000 ns / 4 ns = 6_000_000 cycles
//   POLL_CONFIG_TIMEOUT  : 48 ms  = 48_000_000 ns / 4 ns = 12_000_000 cycles
//   TS2_REQUIRED_COUNT   : 8 consecutive TS2s required per spec
//   TS1_REQUIRED_COUNT   : 1024 TS1s sent before TS2 phase (spec min)
// ---------------------------------------------------------------------------
module polling_fsm #(
    parameter POLL_ACTIVE_TIMEOUT  = 6_000_000,   // cycles for 24 ms @ 250 MHz
    parameter POLL_CONFIG_TIMEOUT  = 12_000_000,  // cycles for 48 ms @ 250 MHz
    parameter TS2_REQUIRED_COUNT   = 8,            // consecutive TS2 RX needed
    parameter TS1_TX_COUNT         = 1024          // TS1 TX before switching to TS2
) (
    // -------------------------------------------------------------------------
    // Global
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,             // Active-low synchronous reset

    // -------------------------------------------------------------------------
    // Handshake from top-level LTSSM / detect_fsm
    // -------------------------------------------------------------------------
    input  wire        polling_req,       // Start training (from top LTSSM)
    input  wire [15:0] lanes_detected,    // Active lanes bitmap from detect_fsm

    // -------------------------------------------------------------------------
    // PIPE RX interface (per-lane mux collapsed to 1 status word here;
    // actual per-lane arbitration done in PIPE_CTRL which drives these)
    // -------------------------------------------------------------------------
    input  wire        rx_valid,          // PIPE RxValid (any active lane)
    input  wire        rx_datak,          // PIPE RxDataK (K-character flag)
    input  wire [31:0] rx_data,           // PIPE RxData  (8b/10b symbols)
    input  wire        rx_elec_idle,      // PIPE RxElecIdle

    // -------------------------------------------------------------------------
    // Compliance request (from compliance pattern generator)
    // -------------------------------------------------------------------------
    input  wire        compliance_req,

    // -------------------------------------------------------------------------
    // PIPE TX control outputs (to PIPE_CTRL)
    // -------------------------------------------------------------------------
    output reg         tx_elec_idle,      // Drive 0 to transmit; 1 = idle
    output reg         send_ts1,          // Instruct PIPE_CTRL to emit TS1 OS
    output reg         send_ts2,          // Instruct PIPE_CTRL to emit TS2 OS
    output reg         enter_compliance,  // Assert to enter Polling.Compliance
    output reg         rx_polarity,       // Assert if inverted TS1 detected

    // -------------------------------------------------------------------------
    // Outputs to top-level LTSSM
    // -------------------------------------------------------------------------
    output reg         polling_done,      // Training complete, go to Config
    output reg         polling_success,   // Qualified success (link up)
    output reg         polling_timeout    // Fatal timeout, go to Detect
);

    // =========================================================================
    // State Encoding
    // =========================================================================
    localparam [2:0]
        ST_IDLE             = 3'd0,
        ST_POLLING_ACTIVE   = 3'd1,
        ST_POLARITY_CHECK   = 3'd2,
        ST_COMPLIANCE       = 3'd3,
        ST_POLLING_CONFIG   = 3'd4,
        ST_DONE             = 3'd5,
        ST_TIMEOUT          = 3'd6;

    // =========================================================================
    // TS1 / TS2 Ordered Set Detection
    // PCIe Base Spec Table 4-12: TS1 OS starts with COM (K28.5 = 8'hBC) +
    // Link# + Lane# + N_FTS + Rate ID + Train_Ctrl + TS_ID (K28.5 again)
    // TS2 OS: same preamble but TS_ID = K29.7 (8'hFD) — simplified detect here
    // ---------------------------------------------------------------------------
    // COM  = K28.5 = 8'hBC (datak=1)
    // TS1_ID = 8'h4A   (second COM in TS1, per 8b/10b symbol after fields)
    // TS2_ID = 8'hB5   (second COM in TS2)
    //
    // For simulation clarity we check the bottom byte of rx_data alongside
    // rx_datak and a simplified pattern.  Production PIPE_CTRL would expose
    // a decoded ts1_detected / ts2_detected pulse, which we also accept below.
    // =========================================================================
    localparam [7:0] K28_5 = 8'hBC;    // COM symbol
    localparam [7:0] TS1_IDENT = 8'h4A; // TS1 identifier symbol
    localparam [7:0] TS2_IDENT = 8'hB5; // TS2 identifier symbol

    // Internal symbol-based detection from raw PIPE data
    wire rx_com_det  = rx_valid && rx_datak && (rx_data[7:0] == K28_5);
    wire rx_ts1_raw  = rx_valid && !rx_datak && (rx_data[7:0] == TS1_IDENT);
    wire rx_ts2_raw  = rx_valid && !rx_datak && (rx_data[7:0] == TS2_IDENT);

    // Detect inverted TS1: complement of K28.5 = 8'h43 (and datak still set)
    localparam [7:0] K28_5_INV = 8'h43;
    wire rx_inv_ts1  = rx_valid && rx_datak && (rx_data[7:0] == K28_5_INV);

    // =========================================================================
    // Registers
    // =========================================================================
    reg [2:0]  state,       next_state;

    // Active timeout counter (24 ms / 48 ms)
    reg [26:0] timer;                            // Must fit POLL_CONFIG_TIMEOUT
    wire       active_timeout = (timer == POLL_ACTIVE_TIMEOUT[26:0] - 1);
    wire       config_timeout = (timer == POLL_CONFIG_TIMEOUT[26:0] - 1);

    // TS1 transmit counter (send at least TS1_TX_COUNT before switching)
    reg [19:0] ts1_tx_cnt;
    wire       ts1_tx_done = (ts1_tx_cnt >= TS1_TX_COUNT[19:0]);

    // TS2 consecutive receive counter
    reg [3:0]  ts2_rx_cnt;
    wire       ts2_rx_done = (ts2_rx_cnt >= TS2_REQUIRED_COUNT[3:0]);

    // TS2 consecutive transmit counter (must send ≥8 TS2 after receiving ≥8)
    reg [3:0]  ts2_tx_cnt;
    wire       ts2_tx_done = (ts2_tx_cnt >= TS2_REQUIRED_COUNT[3:0]);

    // Polarity inversion detected flag
    reg        inv_detected;

    // Bit/Symbol lock flag (simplified: asserted when first valid TS1 seen)
    reg        bit_lock;
    reg        symbol_lock;

    // Number of active lanes (count of set bits in lanes_detected)
    reg [4:0]  lane_count;
    integer    lc_i;
    always @(*) begin
        lane_count = 5'd0;
        for (lc_i = 0; lc_i < 16; lc_i = lc_i + 1)
            lane_count = lane_count + {4'd0, lanes_detected[lc_i]};
    end

    // =========================================================================
    // Timer
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            timer <= 27'd0;
        end else begin
            case (state)
                ST_POLLING_ACTIVE,
                ST_POLARITY_CHECK,      // active timeout continues during polarity recovery
                ST_POLLING_CONFIG : timer <= timer + 27'd1;
                default           : timer <= 27'd0;
            endcase
        end
    end

    // =========================================================================
    // TS1 TX Counter
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            ts1_tx_cnt <= 20'd0;
        end else begin
            if ((state == ST_POLLING_ACTIVE || state == ST_POLARITY_CHECK) && send_ts1)
                ts1_tx_cnt <= ts1_tx_cnt + 20'd1;
            else if (state != ST_POLLING_ACTIVE && state != ST_POLARITY_CHECK)
                ts1_tx_cnt <= 20'd0;
        end
    end

    // =========================================================================
    // TS2 RX Consecutive Counter
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            ts2_rx_cnt <= 4'd0;
        end else begin
            if (state == ST_POLLING_CONFIG) begin
                if (rx_ts2_raw)
                    ts2_rx_cnt <= ts2_rx_cnt + 4'd1;
                else if (rx_valid && !rx_ts2_raw)
                    ts2_rx_cnt <= 4'd0;   // non-TS2 breaks the run
            end else begin
                ts2_rx_cnt <= 4'd0;
            end
        end
    end

    // =========================================================================
    // TS2 TX Counter (only counts after ts2_rx_done)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            ts2_tx_cnt <= 4'd0;
        end else begin
            if (state == ST_POLLING_CONFIG && ts2_rx_done && send_ts2)
                ts2_tx_cnt <= ts2_tx_cnt + 4'd1;
            else if (state != ST_POLLING_CONFIG)
                ts2_tx_cnt <= 4'd0;
        end
    end

    // =========================================================================
    // Polarity Inversion Detection and Lock
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            inv_detected <= 1'b0;
        end else begin
            if (state == ST_POLLING_ACTIVE && rx_inv_ts1)
                inv_detected <= 1'b1;
            else if (state == ST_IDLE)
                inv_detected <= 1'b0;
        end
    end

    // =========================================================================
    // Bit Lock / Symbol Lock (simplified: first COM seen = bit lock,
    // first TS1 identifier = symbol lock)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            bit_lock    <= 1'b0;
            symbol_lock <= 1'b0;
        end else begin
            if (state == ST_POLLING_ACTIVE || state == ST_POLARITY_CHECK) begin
                if (rx_com_det || rx_inv_ts1)
                    bit_lock <= 1'b1;
                if (rx_ts1_raw && bit_lock)
                    symbol_lock <= 1'b1;
            end else if (state == ST_IDLE) begin
                bit_lock    <= 1'b0;
                symbol_lock <= 1'b0;
            end
        end
    end

    // =========================================================================
    // State Register (synchronous)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // Next-State Logic (combinational)
    // =========================================================================
    always @(*) begin
        next_state = state;   // default: hold

        case (state)
            // -----------------------------------------------------------------
            ST_IDLE: begin
                if (polling_req && (lanes_detected != 16'd0))
                    next_state = ST_POLLING_ACTIVE;
            end

            // -----------------------------------------------------------------
            // Polling.Active
            // Send TS1 on all active lanes.  Wait for bit/symbol lock.
            // If inverted TS1 detected → polarity recovery sub-state.
            // If compliance_req → Polling.Compliance.
            // Timeout → back to Detect (via ST_TIMEOUT).
            // -----------------------------------------------------------------
            ST_POLLING_ACTIVE: begin
                if (active_timeout)
                    next_state = ST_TIMEOUT;
                else if (compliance_req)
                    next_state = ST_COMPLIANCE;
                else if (rx_inv_ts1 && !inv_detected)
                    next_state = ST_POLARITY_CHECK;
                else if (symbol_lock && ts1_tx_done)
                    next_state = ST_POLLING_CONFIG;
            end

            // -----------------------------------------------------------------
            // Polarity Recovery: assert rx_polarity, wait for symbol lock,
            // then return to Polling.Active flow (continue to Config).
            // Timer continues from Polling.Active.
            // -----------------------------------------------------------------
            ST_POLARITY_CHECK: begin
                if (active_timeout)
                    next_state = ST_TIMEOUT;
                else if (symbol_lock && ts1_tx_done)
                    next_state = ST_POLLING_CONFIG;
            end

            // -----------------------------------------------------------------
            // Polling.Compliance
            // Stay until compliance_req deasserts (external agent controls exit)
            // -----------------------------------------------------------------
            ST_COMPLIANCE: begin
                if (!compliance_req)
                    next_state = ST_POLLING_ACTIVE;
            end

            // -----------------------------------------------------------------
            // Polling.Configuration
            // Switch to TS2.  Must receive ≥8 TS2 then send ≥8 TS2.
            // 48 ms overall timeout.
            // -----------------------------------------------------------------
            ST_POLLING_CONFIG: begin
                if (config_timeout)
                    next_state = ST_TIMEOUT;
                else if (ts2_rx_done && ts2_tx_done)
                    next_state = ST_DONE;
            end

            // -----------------------------------------------------------------
            ST_DONE: begin
                next_state = ST_IDLE;   // pulse for one cycle then idle
            end

            // -----------------------------------------------------------------
            ST_TIMEOUT: begin
                next_state = ST_IDLE;   // pulse for one cycle then idle
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // =========================================================================
    // Output Logic (registered for clean timing)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_elec_idle    <= 1'b1;
            send_ts1        <= 1'b0;
            send_ts2        <= 1'b0;
            enter_compliance<= 1'b0;
            rx_polarity     <= 1'b0;
            polling_done    <= 1'b0;
            polling_success <= 1'b0;
            polling_timeout <= 1'b0;
        end else begin
            // Defaults each cycle
            send_ts1        <= 1'b0;
            send_ts2        <= 1'b0;
            polling_done    <= 1'b0;
            polling_success <= 1'b0;
            polling_timeout <= 1'b0;
            enter_compliance<= 1'b0;

            case (state)
                ST_IDLE: begin
                    tx_elec_idle <= 1'b1;
                    rx_polarity  <= 1'b0;
                end

                ST_POLLING_ACTIVE: begin
                    tx_elec_idle <= 1'b0;
                    send_ts1     <= 1'b1;
                end

                ST_POLARITY_CHECK: begin
                    tx_elec_idle <= 1'b0;
                    send_ts1     <= 1'b1;
                    rx_polarity  <= 1'b1;   // tell PIPE_CTRL to invert RX
                end

                ST_COMPLIANCE: begin
                    tx_elec_idle    <= 1'b0;
                    enter_compliance<= 1'b1;
                end

                ST_POLLING_CONFIG: begin
                    tx_elec_idle <= 1'b0;
                    if (!ts2_rx_done)
                        send_ts1 <= 1'b1;   // keep sending TS1 until TS2 seen
                    else
                        send_ts2 <= 1'b1;   // switch to TS2 after rx ≥8 TS2
                end

                ST_DONE: begin
                    tx_elec_idle    <= 1'b1;
                    polling_done    <= 1'b1;
                    polling_success <= 1'b1;
                end

                ST_TIMEOUT: begin
                    tx_elec_idle    <= 1'b1;
                    polling_done    <= 1'b1;
                    polling_timeout <= 1'b1;
                end

                default: begin
                    tx_elec_idle <= 1'b1;
                end
            endcase
        end
    end

endmodule
