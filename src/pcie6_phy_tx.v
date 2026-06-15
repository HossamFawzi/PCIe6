// =============================================================================
// Module : pcie6_phy_tx
// Title  : PCIe 6.0 Data Link Layer – PHY Interface TX (PIPE Boundary)
// Spec   : PCI Express Base Specification 6.0, Section 4 (Data Link Layer)
//          PHY Interface for PCI Express (PIPE) Specification 5.1
// Ref    : - PCI-SIG PCIe 6.0 Base Spec (2021)
//          - PIPE Spec Rev 5.1 (PHY Interface for PCI Express)
//          - Agrawal & Sood, "PCIe 6.0 Architecture", IEEE 2022
//          - Transmission Encoding: PAM-4 @ 64 GT/s, 1b/1b FEC, FLIT-mode
//
// Description:
//   Implements the TX side of the PIPE (PHY Interface for PCI Express)
//   boundary between the Data Link Layer and the analog PHY SERDES.
//   Operates at 256-bit datapath width matching PCIe 6.0 FLIT (256B FLIT).
//
//   Key functions (per PCIe 6.0 spec):
//     1. Forward data from DLL to SERDES (phy_txd)
//     2. Assert phy_tx_valid when valid data is presented
//     3. Assert phy_tx_elec_idle when no data → lane goes to electrical idle
//     4. Assert phy_tx_compliance during LTSSM compliance substate
//     5. SOP / EOP boundary detection for FLIT framing
//
// Data path width: 256 bits (matching 256B FLIT in PCIe 6.0)
// Clock domain  : Single synchronous clock (link clock, PAM-4 64 GT/s ÷ 32)
// Reset         : Active-low synchronous reset (rst_n)
// =============================================================================

`timescale 1ns / 1ps

module pcie6_phy_tx (
    // -------------------------------------------------------------------------
    // Global signals
    // -------------------------------------------------------------------------
    input  wire         clk,            // Link TX clock (SERDES clock / 32)
    input  wire         rst_n,          // Active-low synchronous reset

    // -------------------------------------------------------------------------
    // Inputs from Data Link Layer
    // -------------------------------------------------------------------------
    input  wire [255:0] tx_data,        // 256-bit TX data from DLL (FLIT word)
    input  wire         tx_valid,       // Data on tx_data is valid this cycle
    input  wire         tx_sop,         // Start of Packet (FLIT boundary start)
    input  wire         tx_eop,         // End   of Packet (FLIT boundary end)

    // -------------------------------------------------------------------------
    // Control inputs (from LTSSM / Power Management)
    // -------------------------------------------------------------------------
    input  wire         tx_elec_idle_req,   // Request lane to enter Electrical Idle
    input  wire         tx_compliance_req,  // Request compliance pattern TX (LTSSM)

    // -------------------------------------------------------------------------
    // Outputs to PHY SERDES (PIPE interface TX boundary)
    // -------------------------------------------------------------------------
    output reg  [255:0] phy_txd,            // 256-bit parallel data to SERDES
    output reg          phy_tx_valid,       // Data on phy_txd is valid
    output reg          phy_tx_elec_idle,   // Lane in Electrical Idle
    output reg          phy_tx_compliance   // Lane transmitting compliance pattern
);

    // =========================================================================
    // Internal signals
    // =========================================================================

    // Pipeline stage 1 registers (capture DLL outputs)
    reg [255:0] pipe1_data;
    reg         pipe1_valid;
    reg         pipe1_sop;
    reg         pipe1_eop;
    reg         pipe1_elec_idle;
    reg         pipe1_compliance;

    // FLIT framing state machine
    // States: IDLE, SOP_SEEN, PAYLOAD, EOP_SEEN
    localparam ST_IDLE     = 2'b00;
    localparam ST_SOP      = 2'b01;
    localparam ST_PAYLOAD  = 2'b10;
    localparam ST_EOP      = 2'b11;

    reg [1:0] flit_state;
    reg [1:0] flit_state_nxt;

    // Electrical Idle / Compliance override
    wire elec_idle_active;
    wire compliance_active;

    // =========================================================================
    // PIPE ELEC IDLE / COMPLIANCE priority:
    //   Electrical Idle > Compliance > Normal Data
    // Per PIPE 5.1 §4.3: when ElecIdle is asserted, txd is ignored by SERDES.
    //   Compliance assertion is only valid outside of ElecIdle.
    // =========================================================================
    assign elec_idle_active  = tx_elec_idle_req;
    assign compliance_active = tx_compliance_req & ~tx_elec_idle_req;

    // =========================================================================
    // Stage 1: Pipeline register – latch DLL side inputs
    // Adds one cycle of pipeline to ease timing closure at 64 GT/s equivalent.
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pipe1_data       <= 256'b0;
            pipe1_valid      <= 1'b0;
            pipe1_sop        <= 1'b0;
            pipe1_eop        <= 1'b0;
            pipe1_elec_idle  <= 1'b0;
            pipe1_compliance <= 1'b0;
        end else begin
            pipe1_data       <= tx_data;
            pipe1_valid      <= tx_valid & ~elec_idle_active & ~compliance_active;
            pipe1_sop        <= tx_sop;
            pipe1_eop        <= tx_eop;
            pipe1_elec_idle  <= elec_idle_active;
            pipe1_compliance <= compliance_active;
        end
    end

    // =========================================================================
    // FLIT Framing FSM
    // PCIe 6.0 uses 256-byte FLITs; this FSM tracks SOP→EOP boundaries.
    // TX side: validates that data stream is properly framed before SERDES.
    // =========================================================================
    always @(*) begin
        flit_state_nxt = flit_state;
        case (flit_state)
            ST_IDLE: begin
                if (pipe1_valid && pipe1_sop && !pipe1_eop)
                    flit_state_nxt = ST_PAYLOAD;
                else if (pipe1_valid && pipe1_sop && pipe1_eop)
                    flit_state_nxt = ST_IDLE;   // Single-word FLIT
            end
            ST_PAYLOAD: begin
                if (pipe1_valid && pipe1_eop)
                    flit_state_nxt = ST_IDLE;
            end
            ST_SOP: begin
                flit_state_nxt = ST_PAYLOAD;
            end
            ST_EOP: begin
                flit_state_nxt = ST_IDLE;
            end
            default: flit_state_nxt = ST_IDLE;
        endcase

        // Override: electrical idle or compliance resets framing
        if (pipe1_elec_idle || pipe1_compliance)
            flit_state_nxt = ST_IDLE;
    end

    always @(posedge clk) begin
        if (!rst_n)
            flit_state <= ST_IDLE;
        else
            flit_state <= flit_state_nxt;
    end

    // =========================================================================
    // Stage 2 / Output: Drive PIPE TX outputs
    //
    // Priority (PIPE 5.1 §4.3):
    //   1. ElecIdle  → phy_txd=0, phy_tx_valid=0, phy_tx_elec_idle=1, compliance=0
    //   2. Compliance→ phy_txd=compliance_pattern, valid=1, elec_idle=0, compliance=1
    //   3. Normal    → pass pipe1_data, valid from FSM
    //
    // phy_tx_valid qualification:
    //   Only assert when FSM is in PAYLOAD or at SOP/EOP, and not overridden.
    //   Per PIPE: phy_tx_valid may be de-asserted to insert idle symbols.
    // =========================================================================

    // Compliance pattern: 256-bit repeating 8b compliance pattern
    // PCIe 6.0 PAM-4 compliance uses K28.5 / D21.5 pattern (64B/66B encoded).
    // Represented here as a 256-bit repeating pattern (simplified constant).
    localparam [255:0] COMPLIANCE_PATTERN = {
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5,
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5,
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5,
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5
    };

    // Valid qualifier from framing FSM
    // A word is valid for SERDES when:
    //   a) In PAYLOAD state with valid data
    //   b) SOP presented in IDLE state (first word of FLIT)
    //   c) EOP presented in PAYLOAD state (last word of FLIT)
    //   d) SOP+EOP in same cycle (single-word FLIT, state=IDLE)
    wire flit_data_valid;
    assign flit_data_valid = pipe1_valid &&
                             (flit_state == ST_PAYLOAD ||
                              (flit_state == ST_IDLE && pipe1_sop));

    always @(posedge clk) begin
        if (!rst_n) begin
            phy_txd           <= 256'b0;
            phy_tx_valid      <= 1'b0;
            phy_tx_elec_idle  <= 1'b1;   // Default: idle after reset
            phy_tx_compliance <= 1'b0;
        end else begin
            // ---- Priority 1: Electrical Idle --------------------------------
            if (pipe1_elec_idle) begin
                phy_txd           <= 256'b0;
                phy_tx_valid      <= 1'b0;
                phy_tx_elec_idle  <= 1'b1;
                phy_tx_compliance <= 1'b0;

            // ---- Priority 2: Compliance mode --------------------------------
            end else if (pipe1_compliance) begin
                phy_txd           <= COMPLIANCE_PATTERN;
                phy_tx_valid      <= 1'b1;
                phy_tx_elec_idle  <= 1'b0;
                phy_tx_compliance <= 1'b1;

            // ---- Priority 3: Normal FLIT data --------------------------------
            end else if (flit_data_valid) begin
                phy_txd           <= pipe1_data;
                phy_tx_valid      <= 1'b1;
                phy_tx_elec_idle  <= 1'b0;
                phy_tx_compliance <= 1'b0;

            // ---- Default: No valid data (inter-FLIT gap) --------------------
            end else begin
                phy_txd           <= 256'b0;
                phy_tx_valid      <= 1'b0;
                phy_tx_elec_idle  <= 1'b0;
                phy_tx_compliance <= 1'b0;
            end
        end
    end

endmodule
// =============================================================================
// End of pcie6_phy_tx.v
// =============================================================================
