// =============================================================================
// Module 9: PIPE RX Interface Controller
// PCIe Gen6 Physical Layer — PIPE 5.1 Interface
// Description: Manages the PIPE RX interface between the analog PHY macro
//              and the digital MAC/PCS layer. Handles:
//              - PIPE RxData / RxDataK (data + K-char flags)
//              - RxValid / RxElecIdle / RxStatus
//              - PowerDown control
//              - Rate control (Gen1–Gen6: 2.5/5/8/16/32/64 GT/s)
//              - TxDetectRx for receiver detection
//              - PhyStatus handshaking
//              - PCLK change acknowledgment
// =============================================================================
module pipe_rx_interface_ctrl (
    input  wire          clk,         // Core/MAC clock
    input  wire          rst_n,

    // ── PIPE RX interface from analog PHY ─────────────────────────────────
    input  wire [255:0]  pipe_rxd,          // Received data (256b for Gen6)
    input  wire [31:0]   pipe_rxdatak,      // K-character flags (1b/byte)
    input  wire          pipe_rx_valid,     // RxValid from PHY
    input  wire [2:0]    pipe_rx_status,    // RxStatus[2:0]
    input  wire          pipe_rx_elec_idle, // RxElecIdle
    input  wire          pipe_clk,          // PCLK from PHY
    input  wire          pipe_phystatus,    // PhyStatus — handshake from PHY

    // ── Control from LTSSM/DLL ────────────────────────────────────────────
    input  wire [1:0]    power_down_req,    // PowerDown[1:0] to PHY
    input  wire [3:0]    pipe_rate_req,     // Rate[3:0] to PHY (0=2.5G,...,5=64G)
    input  wire          tx_detect_rx_req,  // TxDetectRx/Loopback
    input  wire          tx_elec_idle_req,  // TxElecIdle
    input  wire          tx_compliance_req, // TxCompliance
    input  wire          pclk_change_req,   // Initiate PCLK rate change
    input  wire [1:0]    pipe_width_req,    // 0=8b,1=16b,2=32b (PIPE interface width)

    // ── Outputs to PHY (TX side of PIPE) ──────────────────────────────────
    output reg  [1:0]    pipe_powerdown,
    output reg  [3:0]    pipe_rate,
    output reg           pipe_txdetectrx,
    output reg           pipe_txelecidle,
    output reg           pipe_txcompliance,
    output reg           pipe_pclkchangeack,
    output reg  [1:0]    pipe_width,

    // ── Outputs to MAC/PCS (RX data) ──────────────────────────────────────
    output reg  [255:0]  rx_data,
    output reg  [31:0]   rx_datak,
    output reg           rx_valid,
    output reg           rx_elec_idle,
    output reg  [2:0]    rx_status,
    output reg           phystatus_sync,    // Synced PhyStatus to core clock

    // ── Status ────────────────────────────────────────────────────────────
    output reg           pipe_up,           // PIPE interface active
    output reg           rate_change_busy   // Rate change in progress
);

// ---------------------------------------------------------------------------
// 2-FF synchronizers for async PIPE signals into core clock domain
// ---------------------------------------------------------------------------
reg pipe_phystatus_s1, pipe_phystatus_s2;
reg pipe_rxvalid_s1,   pipe_rxvalid_s2;
reg pipe_rxei_s1,      pipe_rxei_s2;
reg [2:0] pipe_rxst_s1, pipe_rxst_s2;

// Synchronize PIPE signals (pipe_clk → clk_core)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_phystatus_s1 <= 1'b0; pipe_phystatus_s2 <= 1'b0;
        pipe_rxvalid_s1   <= 1'b0; pipe_rxvalid_s2   <= 1'b0;
        pipe_rxei_s1      <= 1'b1; pipe_rxei_s2      <= 1'b1;
        pipe_rxst_s1      <= 3'h0; pipe_rxst_s2      <= 3'h0;
    end else begin
        pipe_phystatus_s1 <= pipe_phystatus;    pipe_phystatus_s2 <= pipe_phystatus_s1;
        pipe_rxvalid_s1   <= pipe_rx_valid;     pipe_rxvalid_s2   <= pipe_rxvalid_s1;
        pipe_rxei_s1      <= pipe_rx_elec_idle; pipe_rxei_s2      <= pipe_rxei_s1;
        pipe_rxst_s1      <= pipe_rx_status;    pipe_rxst_s2      <= pipe_rxst_s1;
    end
end

// ---------------------------------------------------------------------------
// RX data latching (sampled on pipe_clk, transferred to core domain)
// In full implementation this would be an async FIFO; here we sample
// synchronously on pipe_clk and present to core clock.
// ---------------------------------------------------------------------------
reg [255:0] rxd_latch;
reg [31:0]  rxdk_latch;
reg         rxv_latch;

always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        rxd_latch  <= {256{1'b0}};
        rxdk_latch <= {32{1'b0}};
        rxv_latch  <= 1'b0;
    end else begin
        rxd_latch  <= pipe_rxd;
        rxdk_latch <= pipe_rxdatak;
        rxv_latch  <= pipe_rx_valid;
    end
end

// ---------------------------------------------------------------------------
// Rate change FSM
// ---------------------------------------------------------------------------
localparam RC_IDLE  = 2'd0;
localparam RC_WAIT  = 2'd1;
localparam RC_ACK   = 2'd2;
localparam RC_DONE  = 2'd3;

reg [1:0] rc_state;
reg [7:0] rc_timer;   // Timeout counter

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_powerdown    <= 2'h0;
        pipe_rate         <= 4'h0;
        pipe_txdetectrx   <= 1'b0;
        pipe_txelecidle   <= 1'b0;
        pipe_txcompliance <= 1'b0;
        pipe_pclkchangeack<= 1'b0;
        pipe_width        <= 2'h2; // Default 32b
        rx_data           <= {256{1'b0}};
        rx_datak          <= {32{1'b0}};
        rx_valid          <= 1'b0;
        rx_elec_idle      <= 1'b1;
        rx_status         <= 3'h0;
        phystatus_sync    <= 1'b0;
        pipe_up           <= 1'b0;
        rate_change_busy  <= 1'b0;
        rc_state          <= RC_IDLE;
        rc_timer          <= 8'h0;
    end else begin
        // Pass through control signals to PHY
        pipe_powerdown    <= power_down_req;
        pipe_txdetectrx   <= tx_detect_rx_req;
        pipe_txelecidle   <= tx_elec_idle_req;
        pipe_txcompliance <= tx_compliance_req;
        pipe_width        <= pipe_width_req;

        // Pass synchronized RX data to MAC
        rx_data      <= rxd_latch;
        rx_datak     <= rxdk_latch;
        rx_valid     <= pipe_rxvalid_s2;
        rx_elec_idle <= pipe_rxei_s2;
        rx_status    <= pipe_rxst_s2;
        phystatus_sync <= pipe_phystatus_s2;

        // PIPE up when RX valid and not in electrical idle
        pipe_up <= pipe_rxvalid_s2 && !pipe_rxei_s2;

        // Rate change FSM
        case (rc_state)
            RC_IDLE: begin
                pipe_pclkchangeack <= 1'b0;
                rate_change_busy   <= 1'b0;
                if (pclk_change_req) begin
                    pipe_rate       <= pipe_rate_req;
                    rate_change_busy<= 1'b1;
                    rc_timer        <= 8'hFF;
                    rc_state        <= RC_WAIT;
                end else begin
                    pipe_rate <= pipe_rate_req;
                end
            end
            RC_WAIT: begin
                // Wait for PhyStatus assertion after rate change
                if (pipe_phystatus_s2) begin
                    pipe_pclkchangeack <= 1'b1;
                    rc_state           <= RC_ACK;
                end else if (rc_timer == 8'h0) begin
                    // Timeout — abort
                    rc_state <= RC_IDLE;
                end else begin
                    rc_timer <= rc_timer - 1'b1;
                end
            end
            RC_ACK: begin
                // Wait for PhyStatus to deassert
                if (!pipe_phystatus_s2) begin
                    pipe_pclkchangeack <= 1'b0;
                    rc_state           <= RC_DONE;
                end
            end
            RC_DONE: begin
                rate_change_busy <= 1'b0;
                rc_state         <= RC_IDLE;
            end
            default: rc_state <= RC_IDLE;
        endcase
    end
end

endmodule
