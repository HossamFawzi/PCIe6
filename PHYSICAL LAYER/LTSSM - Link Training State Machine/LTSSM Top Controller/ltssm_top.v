// =============================================================================
// Module : ltssm_top
// Project: PCIe Gen6 Physical Layer
// Function: LTSSM Top Controller — Top dispatcher managing all LTSSM states
//           and driving all sub-FSMs (Detect, Polling, Configuration,
//           Recovery, L0/L0s, L1, Hot Reset/Disabled, Loopback).
//           Compatible with DLL signals: dl_up, dl_down consumed by DLL_INIT FSM.
//           ltssm_state[5:0] consumed by SPD_NEG, WDT_NEG, PIPE_CTRL etc.
// Standard: PCIe Base Specification 6.0
// Language: Verilog-2001 (no SystemVerilog)
// =============================================================================

module ltssm_top (
    input  wire        clk,
    input  wire        rst_n,

    // ── PIPE / PHY status inputs ──────────────────────────────────────────
    input  wire [2:0]  pipe_rx_status,     // PIPE RxStatus[2:0]
    input  wire        pipe_detect_lane,   // receiver detected on any lane

    // ── DLL / upper-layer requests ────────────────────────────────────────
    input  wire        dll_up_req,         // DLL requests link-up (DL_Init done)
    input  wire [2:0]  pm_req,             // PM request: 000=none,001=L0s,010=L1,011=L1.1,100=L1.2
    input  wire        hot_reset_req,      // hot-reset request (from TS1 HR bit or SW)
    input  wire        link_down_req,      // DLL replay rollover / fatal error
    input  wire        compliance_req,     // compliance test entry request

    // ── LTSSM outputs ─────────────────────────────────────────────────────
    output reg  [5:0]  ltssm_state,        // current LTSSM state encoding
    output reg         dl_up,              // DL_Up: link is active (DL_Active)
    output reg         dl_down,            // DL_Down: link just went down
    output reg  [1:0]  pipe_power_down,    // PIPE PowerDown[1:0]
    output reg         pipe_tx_elec_idle,  // assert electrical idle on TX
    output reg  [3:0]  link_speed,         // negotiated speed: 1=Gen1 … 6=Gen6
    output reg  [5:0]  link_width,         // active lane width: 1,2,4,8,16
    output reg         ltssm_reset_out     // assert to reset PHY / DLL
);

// =============================================================================
// STATE ENCODING  (6-bit, one-hot style numbering kept decimal for readability)
// =============================================================================
localparam [5:0]
    ST_DETECT_QUIET       = 6'd0,
    ST_DETECT_ACTIVE      = 6'd1,
    ST_POLLING_ACTIVE     = 6'd2,
    ST_POLLING_COMPLIANCE = 6'd3,
    ST_POLLING_CONFIG     = 6'd4,
    ST_CFG_LINKWD_START   = 6'd5,
    ST_CFG_LINKWD_ACCEPT  = 6'd6,
    ST_CFG_LANENUM_WAIT   = 6'd7,
    ST_CFG_LANENUM_ACCEPT = 6'd8,
    ST_CFG_COMPLETE       = 6'd9,
    ST_CFG_IDLE           = 6'd10,
    ST_RECOVERY_RCVLOCK   = 6'd11,
    ST_RECOVERY_RCVCONFIG = 6'd12,
    ST_RECOVERY_IDLE      = 6'd13,
    ST_RECOVERY_SPEED     = 6'd14,
    ST_RECOVERY_EQ_PHASE0 = 6'd15,
    ST_L0                 = 6'd16,
    ST_L0S_TX             = 6'd17,
    ST_L0S_RX             = 6'd18,
    ST_L1_ENTRY           = 6'd19,
    ST_L1                 = 6'd20,
    ST_L1_EXIT            = 6'd21,
    ST_HOT_RESET          = 6'd22,
    ST_DISABLED           = 6'd23,
    ST_LOOPBACK_ENTRY     = 6'd24,
    ST_LOOPBACK_ACTIVE    = 6'd25,
    ST_LOOPBACK_EXIT      = 6'd26;

// =============================================================================
// PIPE RxStatus codes (3-bit)
// =============================================================================
localparam [2:0]
    RXST_RECV_OK   = 3'b001,
    RXST_RECV_DET  = 3'b011,
    RXST_ELEC_IDLE = 3'b000;

// =============================================================================
// PIPE PowerDown encoding
// =============================================================================
localparam [1:0]
    PD_P0  = 2'b00,
    PD_P1  = 2'b01,
    PD_P2  = 2'b10,
    PD_P2S = 2'b11;

// =============================================================================
// PM request encoding
// =============================================================================
localparam [2:0]
    PM_NONE  = 3'b000,
    PM_L0S   = 3'b001,
    PM_L1    = 3'b010,
    PM_L1_1  = 3'b011,
    PM_L1_2  = 3'b100;

// =============================================================================
// INTERNAL SIGNALS
// =============================================================================

// state register
reg [5:0] state, next_state;

// timeout counters  (all measured in clock cycles)
reg [15:0] timer;
reg        timer_load;
reg [15:0] timer_load_val;
wire       timer_exp = (timer == 16'd1);

// sub-FSM handshake flags (registered, set/cleared by this top controller)
reg detect_done;        // Detect found receiver
reg detect_timeout;
reg polling_ts1_seen;   // TS1 received in Polling
reg polling_ts2_seen;   // TS2 received in Polling
reg cfg_done;           // Configuration complete
reg cfg_timeout;
reg recovery_done;      // Recovery complete
reg recovery_timeout;
reg idle_detected;      // Electrical Idle detected in Recovery

// internal state of ordered-set counters (simplified model)
reg [7:0]  ts1_tx_cnt;
reg [7:0]  ts2_tx_cnt;

// speed / width registers (defaults Gen1 x1 until negotiated)
reg [3:0]  speed_reg;
reg [5:0]  width_reg;

// sticky flags
reg        hot_reset_latch;
reg        link_down_latch;
reg        compliance_latch;

// =============================================================================
// TIMEOUT VALUES  (representative cycle counts; real values set by config regs)
// PCIe spec minimums / maximums used as defaults.
// =============================================================================
localparam [15:0]
    TMO_DETECT    = 16'd200,   // Detect.Active receiver check
    TMO_POLLING   = 16'd1000,  // Polling.Active TS1/TS2 window
    TMO_CFG       = 16'd2000,  // Configuration negotiation window
    TMO_RECOVERY  = 16'd2000,  // Recovery lock window
    TMO_HOT_RESET = 16'd50,    // Hot Reset TS1 transmission window
    TMO_L1_ENTRY  = 16'd100,   // L1 EIOS handshake window
    TMO_LOOPBACK  = 16'd500;   // Loopback entry

// =============================================================================
// TS1/TS2 minimum counts to advance (PCIe spec: 2 consecutive TS2 in Polling)
// =============================================================================
localparam [7:0]
    TS1_POLLING_MIN = 8'd1,
    TS2_POLLING_MIN = 8'd2,
    TS1_CFG_MIN     = 8'd8,
    TS2_CFG_MIN     = 8'd8;

// =============================================================================
// LATCH EXTERNAL ASYNC REQUESTS
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hot_reset_latch  <= 1'b0;
        link_down_latch  <= 1'b0;
        compliance_latch <= 1'b0;
    end else begin
        if (hot_reset_req)
            hot_reset_latch <= 1'b1;
        if (link_down_req)
            link_down_latch <= 1'b1;
        if (compliance_req)
            compliance_latch <= 1'b1;
        // clear latches when we enter the corresponding handling state
        if (state == ST_HOT_RESET)
            hot_reset_latch <= 1'b0;
        if (state == ST_DETECT_QUIET)
            link_down_latch <= 1'b0;
        if (state == ST_POLLING_COMPLIANCE)
            compliance_latch <= 1'b0;
    end
end

// =============================================================================
// TIMER
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        timer <= 16'd0;
    end else if (timer_load) begin
        timer <= timer_load_val;
    end else if (timer != 16'd0) begin
        timer <= timer - 16'd1;
    end
end

// =============================================================================
// DETECT DONE SIMULATION  
// Driven by pipe_detect_lane and pipe_rx_status RECV_DET code
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        detect_done    <= 1'b0;
        detect_timeout <= 1'b0;
    end else begin
        if (state == ST_DETECT_ACTIVE) begin
            if (pipe_detect_lane && (pipe_rx_status == RXST_RECV_DET)) begin
                detect_done    <= 1'b1;
                detect_timeout <= 1'b0;
            end else if (timer_exp) begin
                detect_timeout <= 1'b1;
                detect_done    <= 1'b0;
            end
        end else begin
            detect_done    <= 1'b0;
            detect_timeout <= 1'b0;
        end
    end
end

// =============================================================================
// POLLING ORDERED SET COUNTERS  (simplified — real impl driven by TS det module)
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ts1_tx_cnt       <= 8'd0;
        ts2_tx_cnt       <= 8'd0;
        polling_ts1_seen <= 1'b0;
        polling_ts2_seen <= 1'b0;
    end else begin
        if (state == ST_POLLING_ACTIVE) begin
            // Increment TX counters each cycle (one per 4-cycle burst model)
            ts1_tx_cnt <= ts1_tx_cnt + 8'd1;
            // Accept incoming TS1/TS2 reflected on pipe_rx_status
            if (pipe_rx_status == RXST_RECV_OK && ts1_tx_cnt >= TS1_POLLING_MIN)
                polling_ts1_seen <= 1'b1;
        end else if (state == ST_POLLING_CONFIG) begin
            ts2_tx_cnt <= ts2_tx_cnt + 8'd1;
            if (pipe_rx_status == RXST_RECV_OK && ts2_tx_cnt >= TS2_POLLING_MIN)
                polling_ts2_seen <= 1'b1;
        end else begin
            ts1_tx_cnt       <= 8'd0;
            ts2_tx_cnt       <= 8'd0;
            polling_ts1_seen <= 1'b0;
            polling_ts2_seen <= 1'b0;
        end
    end
end

// =============================================================================
// CONFIGURATION DONE / IDLE DETECTION  
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cfg_done     <= 1'b0;
        cfg_timeout  <= 1'b0;
        idle_detected<= 1'b0;
    end else begin
        if (state == ST_CFG_IDLE) begin
            // When pipe_rx_status shows idle-equivalent, cfg considered done
            if (pipe_rx_status == RXST_ELEC_IDLE || dll_up_req)
                cfg_done <= 1'b1;
            else if (timer_exp)
                cfg_timeout <= 1'b1;
        end else begin
            cfg_done    <= 1'b0;
            cfg_timeout <= 1'b0;
        end

        // idle detected in recovery
        if (state == ST_RECOVERY_RCVCONFIG &&
            (pipe_rx_status == RXST_ELEC_IDLE))
            idle_detected <= 1'b1;
        else if (state == ST_L0)
            idle_detected <= 1'b0;
    end
end

// =============================================================================
// RECOVERY DONE / TIMEOUT
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        recovery_done    <= 1'b0;
        recovery_timeout <= 1'b0;
    end else begin
        if (state == ST_RECOVERY_IDLE) begin
            if (idle_detected || (pipe_rx_status == RXST_ELEC_IDLE))
                recovery_done <= 1'b1;
            else if (timer_exp)
                recovery_timeout <= 1'b1;
        end else begin
            recovery_done    <= 1'b0;
            recovery_timeout <= 1'b0;
        end
    end
end

// =============================================================================
// MAIN SEQUENTIAL STATE REGISTER + TIMER LOAD
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state      <= ST_DETECT_QUIET;
        timer_load <= 1'b0;
        timer_load_val <= 16'd0;
        speed_reg  <= 4'd1;   // Gen1 default
        width_reg  <= 6'd1;   // x1 default
    end else begin
        timer_load <= 1'b0;
        state      <= next_state;

        // update speed/width when entering L0
        if (next_state == ST_L0) begin
            // In a real system these come from SPD_NEG / WDT_NEG outputs.
            // Here we advance speed to Gen6 after recovery, x1 for simplicity.
            speed_reg <= 4'd6;
            width_reg <= 6'd1;
        end

        // load timer on state transition
        if (next_state != state) begin
            timer_load <= 1'b1;
            case (next_state)
                ST_DETECT_ACTIVE      : timer_load_val <= TMO_DETECT;
                ST_POLLING_ACTIVE     : timer_load_val <= TMO_POLLING;
                ST_POLLING_CONFIG     : timer_load_val <= TMO_POLLING;
                ST_CFG_LINKWD_START   : timer_load_val <= TMO_CFG;
                ST_CFG_LINKWD_ACCEPT  : timer_load_val <= TMO_CFG;
                ST_CFG_LANENUM_WAIT   : timer_load_val <= TMO_CFG;
                ST_CFG_LANENUM_ACCEPT : timer_load_val <= TMO_CFG;
                ST_CFG_COMPLETE       : timer_load_val <= TMO_CFG;
                ST_CFG_IDLE           : timer_load_val <= TMO_CFG;
                ST_RECOVERY_RCVLOCK   : timer_load_val <= TMO_RECOVERY;
                ST_RECOVERY_RCVCONFIG : timer_load_val <= TMO_RECOVERY;
                ST_RECOVERY_IDLE      : timer_load_val <= TMO_RECOVERY;
                ST_RECOVERY_SPEED     : timer_load_val <= TMO_RECOVERY;
                ST_RECOVERY_EQ_PHASE0 : timer_load_val <= TMO_RECOVERY;
                ST_HOT_RESET          : timer_load_val <= TMO_HOT_RESET;
                ST_L1_ENTRY           : timer_load_val <= TMO_L1_ENTRY;
                ST_LOOPBACK_ENTRY     : timer_load_val <= TMO_LOOPBACK;
                ST_LOOPBACK_ACTIVE    : timer_load_val <= TMO_LOOPBACK;
                default               : timer_load_val <= 16'd0;
            endcase
        end
    end
end

// =============================================================================
// NEXT-STATE COMBINATIONAL LOGIC
// =============================================================================
always @(*) begin
    next_state = state; // default hold

    case (state)

        // ── DETECT ─────────────────────────────────────────────────────────
        ST_DETECT_QUIET: begin
            // Always move to active to check for receiver
            next_state = ST_DETECT_ACTIVE;
        end

        ST_DETECT_ACTIVE: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (detect_done)
                next_state = ST_POLLING_ACTIVE;
            else if (detect_timeout)
                next_state = ST_DETECT_QUIET; // retry
        end

        // ── POLLING ─────────────────────────────────────────────────────────
        ST_POLLING_ACTIVE: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (compliance_latch)
                next_state = ST_POLLING_COMPLIANCE;
            else if (polling_ts1_seen)
                next_state = ST_POLLING_CONFIG;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_POLLING_COMPLIANCE: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            // stays in compliance until reset
        end

        ST_POLLING_CONFIG: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (polling_ts2_seen)
                next_state = ST_CFG_LINKWD_START;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        // ── CONFIGURATION ──────────────────────────────────────────────────
        ST_CFG_LINKWD_START: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_CFG_LINKWD_ACCEPT;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_CFG_LINKWD_ACCEPT: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_CFG_LANENUM_WAIT;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_CFG_LANENUM_WAIT: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_CFG_LANENUM_ACCEPT;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_CFG_LANENUM_ACCEPT: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_CFG_COMPLETE;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_CFG_COMPLETE: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else
                next_state = ST_CFG_IDLE;
        end

        ST_CFG_IDLE: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (cfg_done || dll_up_req)
                next_state = ST_L0;
            else if (cfg_timeout)
                next_state = ST_RECOVERY_RCVLOCK;
        end

        // ── L0 ──────────────────────────────────────────────────────────────
        ST_L0: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (pm_req == PM_L0S)
                next_state = ST_L0S_TX;
            else if (pm_req == PM_L1 || pm_req == PM_L1_1 || pm_req == PM_L1_2)
                next_state = ST_L1_ENTRY;
            // Recovery only if none of the above and we see an unexpected OK
            // (DLL sends link_down_req on real errors, so this is a fallback)
        end

        // ── L0s ─────────────────────────────────────────────────────────────
        ST_L0S_TX: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            // TX side: EIOS sent, go to RX side idle
            else if (pipe_rx_status == RXST_ELEC_IDLE)
                next_state = ST_L0S_RX;
        end

        ST_L0S_RX: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            // FTS received (pipe_rx_status shows data)
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_L0;
            else if (timer_exp)
                next_state = ST_RECOVERY_RCVLOCK;
        end

        // ── L1 ──────────────────────────────────────────────────────────────
        ST_L1_ENTRY: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (pipe_rx_status == RXST_ELEC_IDLE)
                next_state = ST_L1;
            else if (timer_exp)
                next_state = ST_RECOVERY_RCVLOCK;
        end

        ST_L1: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (pm_req == PM_NONE || pipe_rx_status == RXST_RECV_OK)
                next_state = ST_L1_EXIT;
        end

        ST_L1_EXIT: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else
                // L1 exit always goes through Recovery per PCIe spec
                next_state = ST_RECOVERY_RCVLOCK;
        end

        // ── RECOVERY ────────────────────────────────────────────────────────
        ST_RECOVERY_RCVLOCK: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_RECOVERY_RCVCONFIG;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_RECOVERY_RCVCONFIG: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (idle_detected)
                next_state = ST_RECOVERY_IDLE;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_RECOVERY_IDLE: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (recovery_done)
                next_state = ST_L0;
            else if (recovery_timeout)
                next_state = ST_DETECT_QUIET;
        end

        ST_RECOVERY_SPEED: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_RECOVERY_EQ_PHASE0;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_RECOVERY_EQ_PHASE0: begin
            if (hot_reset_latch)
                next_state = ST_HOT_RESET;
            else if (link_down_latch)
                next_state = ST_DETECT_QUIET;
            else if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_RECOVERY_RCVCONFIG;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        // ── HOT RESET ────────────────────────────────────────────────────────
        ST_HOT_RESET: begin
            if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        // ── DISABLED ─────────────────────────────────────────────────────────
        ST_DISABLED: begin
            // stays disabled until external release (link_down de-asserts)
            if (!link_down_latch && !link_down_req)
                next_state = ST_DETECT_QUIET;
        end

        // ── LOOPBACK ─────────────────────────────────────────────────────────
        ST_LOOPBACK_ENTRY: begin
            if (pipe_rx_status == RXST_RECV_OK)
                next_state = ST_LOOPBACK_ACTIVE;
            else if (timer_exp)
                next_state = ST_DETECT_QUIET;
        end

        ST_LOOPBACK_ACTIVE: begin
            if (hot_reset_latch || link_down_latch)
                next_state = ST_LOOPBACK_EXIT;
        end

        ST_LOOPBACK_EXIT: begin
            next_state = ST_DETECT_QUIET;
        end

        default: next_state = ST_DETECT_QUIET;
    endcase
end

// =============================================================================
// OUTPUT LOGIC — registered Moore outputs
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ltssm_state      <= ST_DETECT_QUIET;
        dl_up            <= 1'b0;
        dl_down          <= 1'b0;
        pipe_power_down  <= PD_P2;         // full power-down at reset
        pipe_tx_elec_idle<= 1'b1;          // TX electrically idle at reset
        link_speed       <= 4'd1;
        link_width       <= 6'd1;
        ltssm_reset_out  <= 1'b1;          // assert reset until out of Detect
    end else begin
        ltssm_state <= state;

        // ── dl_up / dl_down ────────────────────────────────────────────────
        // dl_up: assert when in L0 (or L0s — link still "up" at DLL level)
        //        clear only when entering a reset/down state
        if (state == ST_L0 || state == ST_L0S_TX || state == ST_L0S_RX) begin
            dl_up   <= 1'b1;
            dl_down <= 1'b0;
        end else if (state == ST_DETECT_QUIET || state == ST_HOT_RESET ||
                     state == ST_DISABLED) begin
            dl_up   <= 1'b0;
            dl_down <= 1'b0;
        end else begin
            // In all other states (Recovery, Config, etc.) hold dl_up as-is
            dl_down <= 1'b0;
        end

        // ── dl_down pulse on departure from L0/L0s to a non-L0/L0s state ─
        if ((state == ST_L0 || state == ST_L0S_TX || state == ST_L0S_RX) &&
            (next_state != ST_L0) &&
            (next_state != ST_L0S_TX) &&
            (next_state != ST_L0S_RX)) begin
            if (next_state == ST_DETECT_QUIET || next_state == ST_HOT_RESET ||
                next_state == ST_DISABLED     || next_state == ST_RECOVERY_RCVLOCK) begin
                dl_down <= 1'b1;
                dl_up   <= 1'b0;
            end
        end

        // ── pipe_power_down ────────────────────────────────────────────────
        case (state)
            ST_L0, ST_L0S_TX, ST_L0S_RX,
            ST_POLLING_ACTIVE, ST_POLLING_CONFIG,
            ST_CFG_LINKWD_START, ST_CFG_LINKWD_ACCEPT,
            ST_CFG_LANENUM_WAIT, ST_CFG_LANENUM_ACCEPT,
            ST_CFG_COMPLETE, ST_CFG_IDLE,
            ST_RECOVERY_RCVLOCK, ST_RECOVERY_RCVCONFIG,
            ST_RECOVERY_IDLE, ST_RECOVERY_SPEED,
            ST_RECOVERY_EQ_PHASE0 : pipe_power_down <= PD_P0;

            ST_L1_ENTRY, ST_L1   : pipe_power_down <= PD_P1;
            ST_L1_EXIT            : pipe_power_down <= PD_P0;
            ST_DISABLED           : pipe_power_down <= PD_P2;
            ST_HOT_RESET          : pipe_power_down <= PD_P0;
            default               : pipe_power_down <= PD_P2;
        endcase

        // ── pipe_tx_elec_idle ──────────────────────────────────────────────
        case (state)
            ST_L0,
            ST_POLLING_ACTIVE, ST_POLLING_CONFIG,
            ST_POLLING_COMPLIANCE,
            ST_CFG_LINKWD_START, ST_CFG_LINKWD_ACCEPT,
            ST_CFG_LANENUM_WAIT, ST_CFG_LANENUM_ACCEPT,
            ST_CFG_COMPLETE, ST_CFG_IDLE,
            ST_RECOVERY_RCVLOCK, ST_RECOVERY_RCVCONFIG,
            ST_RECOVERY_IDLE, ST_RECOVERY_SPEED,
            ST_RECOVERY_EQ_PHASE0,
            ST_LOOPBACK_ACTIVE    : pipe_tx_elec_idle <= 1'b0;
            // L0s TX side: assert elec idle on TX to signal peer
            ST_L0S_TX             : pipe_tx_elec_idle <= 1'b1;
            // L0s RX side: TX stays idle until FTS
            ST_L0S_RX             : pipe_tx_elec_idle <= 1'b1;
            ST_L1, ST_L1_ENTRY,
            ST_DISABLED           : pipe_tx_elec_idle <= 1'b1;
            default               : pipe_tx_elec_idle <= 1'b1;
        endcase

        // ── ltssm_reset_out ────────────────────────────────────────────────
        ltssm_reset_out <= (state == ST_DETECT_QUIET  ||
                            state == ST_HOT_RESET      ||
                            state == ST_DISABLED);

        // ── link speed / width to outputs ─────────────────────────────────
        link_speed <= speed_reg;
        link_width <= width_reg;
    end
end

endmodule
