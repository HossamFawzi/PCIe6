// =============================================================================
// Module   : pipe_tx
// Tag      : PIPE_TX
// Spec     : PCIe Gen6 PHY Digital Layer – Module 10
// Function : PIPE 5.1 TX Interface Controller
//            Registers/synchronises all TX data and PIPE control signals
//            to pipe_clk domain; drives analog PHY macro inputs.
// Language : Verilog-2001  (NO SystemVerilog, NO UVM)
// =============================================================================
`timescale 1ns/1ps

module pipe_tx (
    // -------------------------------------------------------------------------
    // Clock / Reset
    // pipe_clk  – PIPE interface clock (from PHY macro / PLL)
    // clk       – core digital clock
    // rst_n     – active-low async reset (synchronised externally)
    // -------------------------------------------------------------------------
    input  wire         pipe_clk,
    input  wire         clk,
    input  wire         rst_n,

    // -------------------------------------------------------------------------
    // Inputs  (exact names + widths from HTML spec)
    // -------------------------------------------------------------------------
    input  wire [255:0] tx_data,         // 256 – parallel TX data from DLL/PHY
    input  wire         tx_valid,        // 1   – tx_data is valid
    input  wire [31:0]  tx_datak,        // 32  – data/K-char byte enables
    input  wire         tx_elec_idle,    // 1   – request electrical idle
    input  wire         tx_compliance,   // 1   – compliance pattern mode

    // -------------------------------------------------------------------------
    // Outputs (exact names + widths from HTML spec)
    // -------------------------------------------------------------------------
    output reg  [255:0] pipe_txd,            // 256 – PIPE TXData to analog macro
    output reg  [31:0]  pipe_txdatak,        // 32  – PIPE TXDataK
    output reg          pipe_tx_elec_idle,   // 1   – PIPE TXElecIdle
    output reg          pipe_tx_compliance,  // 1   – PIPE TXCompliance
    output reg  [1:0]   pipe_power_down,     // 2   – PIPE PowerDown[1:0]
    output reg          pipe_tx_swing        // 1   – PIPE TXSwing (full/half)
);

// =============================================================================
// PIPE PowerDown encoding (PIPE 5.1 §6.2)
//   2'b00 = P0  (normal operation)
//   2'b01 = P1  (L0s / low-latency standby)
//   2'b10 = P2  (L1 / deep standby)
//   2'b11 = P3  (L2/L3 / power removed)
// =============================================================================
localparam [1:0] PIPE_P0 = 2'b00;
localparam [1:0] PIPE_P1 = 2'b01;
localparam [1:0] PIPE_P2 = 2'b10;
localparam [1:0] PIPE_P3 = 2'b11;

// =============================================================================
// Internal CDC stage: core clock → pipe_clk
// Two-stage synchroniser for control signals; data registered directly
// because tx_valid gates acceptance.
// =============================================================================
reg         tx_elec_idle_s1, tx_elec_idle_s2;
reg         tx_compliance_s1, tx_compliance_s2;
reg         tx_valid_s1,      tx_valid_s2;

// Data / datak captured on pipe_clk when tx_valid is high
reg [255:0] txd_reg;
reg [31:0]  txdatak_reg;
reg         txd_valid_reg;

// Power-state derivation
// Rule: 
//   ElecIdle + Compliance  → P0  (compliance test – PHY must be active)
//   ElecIdle only          → P1  (L0s standby)
//   !valid for >0 cycles   → P0  (default, PHY manages deeper states via LTSSM)
//   normal data            → P0
// This module exposes pipe_power_down as a combinational function of the
// synchronised control inputs; the LTSSM Top Controller may override via
// a higher-level arbitration outside this block.
// =============================================================================

// TX Swing: full swing (1) unless compliance pattern (half swing per spec)
// pipe_tx_swing = 1 → full voltage swing
// pipe_tx_swing = 0 → reduced / half swing (compliance)

// =============================================================================
// Synchroniser for control signals into pipe_clk domain
// =============================================================================
always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_elec_idle_s1  <= 1'b0;
        tx_elec_idle_s2  <= 1'b0;
        tx_compliance_s1 <= 1'b0;
        tx_compliance_s2 <= 1'b0;
        tx_valid_s1      <= 1'b0;
        tx_valid_s2      <= 1'b0;
    end else begin
        tx_elec_idle_s1  <= tx_elec_idle;
        tx_elec_idle_s2  <= tx_elec_idle_s1;
        tx_compliance_s1 <= tx_compliance;
        tx_compliance_s2 <= tx_compliance_s1;
        tx_valid_s1      <= tx_valid;
        tx_valid_s2      <= tx_valid_s1;
    end
end

// =============================================================================
// Data capture register in pipe_clk domain
// =============================================================================
always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        txd_reg       <= 256'h0;
        txdatak_reg   <= 32'h0;
        txd_valid_reg <= 1'b0;
    end else begin
        if (tx_valid_s2) begin
            txd_reg       <= tx_data;
            txdatak_reg   <= tx_datak;
            txd_valid_reg <= 1'b1;
        end else begin
            txd_valid_reg <= 1'b0;
        end
    end
end

// =============================================================================
// Registered PIPE outputs (all driven on pipe_clk)
// =============================================================================
always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_txd            <= 256'h0;
        pipe_txdatak        <= 32'h0;
        pipe_tx_elec_idle   <= 1'b1;   // default: electrical idle on reset
        pipe_tx_compliance  <= 1'b0;
        pipe_power_down     <= PIPE_P2; // P2 until link comes up (safe default)
        pipe_tx_swing       <= 1'b1;   // full swing default
    end else begin
        // ---- Data / K path ----
        if (tx_elec_idle_s2) begin
            // Drive idle pattern – all zeros, all K, hold position
            pipe_txd     <= 256'h0;
            pipe_txdatak <= 32'hFFFF_FFFF; // K28.5 idles in 8b/10b; 
                                            // all-K in Gen6 = EIOS pattern
        end else if (txd_valid_reg) begin
            pipe_txd     <= txd_reg;
            pipe_txdatak <= txdatak_reg;
        end
        // else hold last value – pipeline bubble, no update

        // ---- Electrical Idle ----
        pipe_tx_elec_idle  <= tx_elec_idle_s2;

        // ---- Compliance ----
        pipe_tx_compliance <= tx_compliance_s2;

        // ---- TX Swing ----
        // Half-swing during compliance pattern (spec §4.2.1)
        pipe_tx_swing <= tx_compliance_s2 ? 1'b0 : 1'b1;

        // ---- PowerDown ----
        // Compliance active → must stay P0 (PHY on)
        // ElecIdle only     → P1
        // Normal operation  → P0
        if (tx_compliance_s2) begin
            pipe_power_down <= PIPE_P0;
        end else if (tx_elec_idle_s2) begin
            pipe_power_down <= PIPE_P1;
        end else begin
            pipe_power_down <= PIPE_P0;
        end
    end
end

endmodule
