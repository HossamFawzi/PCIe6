// =============================================================================
// Module   : tx_datapath_mux
// Project  : PCIe 6.0 Data Link Layer — TX Datapath Multiplexer
// Author   : Generated per PCIe 6.0 Base Specification Rev 1.0
//            & "PCI Express Technology" (Mindshare) reference model
//
// Description:
//   Arbitrates between three upstream sources and serializes them into a
//   256-bit PHY interface at the rate imposed by the 256b/242b FLIT encoding
//   used in PCIe 6.0.
//
//   Priority (highest → lowest):
//     1. Retry TLPs  (retry_tlp / retry_valid)
//     2. New   TLPs  (tlp_tx   / tlp_tx_valid)
//     3. DLLPs       (dllp_out / dllp_valid)
//
//   The PHY interface is 256 bits wide, matching the PCIe 6.0 FLIT container.
//   SOP / EOP strobes frame each packet for the MAC/PHY adapter layer.
//
//   TLP payloads are 1056 bits (132 bytes – max TLP header + payload fragment
//   that fits a single FLIT).  The mux zero-pads shorter packets and signals
//   EOP when the last beat is presented.
//
// Port Widths:
//   tlp_tx      [1055:0]  – current TLP (header + data, up to 132 B)
//   retry_tlp   [1055:0]  – replay-buffer TLP
//   dllp_out    [63:0]    – DLLP (8 bytes, per spec section 2.7)
//   phy_tx_data [255:0]   – one 256-bit FLIT beat to PHY
//
// Framing:
//   A 1056-bit TLP occupies ceil(1056/256) = 5 beats (last beat zero-padded).
//   A 64-bit  DLLP occupies 1 beat (zero-padded to 256 bits).
//   phy_tx_sop is asserted on beat 0, phy_tx_eop on the final beat.
//
// Assumptions / Simplifications:
//   • Single-clock domain; synchronous active-low reset.
//   • Flow control / credit checks are upstream of this block.
//   • The retry buffer holds exactly one TLP (extended for deeper buffers
//     by widening retry_tlp and adding arbitration).
//   • No byte-enable; the PHY layer handles partial-beat stripping.
// =============================================================================

`timescale 1ns / 1ps

module dll_tx_datapath_mux (  // RENAMED: was tx_datapath_mux (duplicate with PHY layer)
    // -------------------------------------------------------------------------
    // Clock / Reset
    // -------------------------------------------------------------------------
    input  wire          clk,
    input  wire          rst_n,

    // -------------------------------------------------------------------------
    // TLP TX input (new TLPs from Transaction Layer)
    // -------------------------------------------------------------------------
    input  wire [1055:0] tlp_tx,
    input  wire          tlp_tx_valid,

    // -------------------------------------------------------------------------
    // Retry TLP input (from Replay Buffer, Data Link layer Ack/Nak)
    // -------------------------------------------------------------------------
    input  wire [1055:0] retry_tlp,
    input  wire          retry_valid,

    // -------------------------------------------------------------------------
    // DLLP input (ACK/NAK/Power-Management DLLPs)
    // -------------------------------------------------------------------------
    input  wire [63:0]   dllp_out,
    input  wire          dllp_valid,

    // -------------------------------------------------------------------------
    // Retry request from Ack/Nak handler (forces retry priority)
    // -------------------------------------------------------------------------
    input  wire          retry_req,

    // -------------------------------------------------------------------------
    // PHY TX interface
    // -------------------------------------------------------------------------
    output reg  [255:0]  phy_tx_data,
    output reg           phy_tx_valid,
    output reg           phy_tx_sop,
    output reg           phy_tx_eop
);

    // =========================================================================
    // Local parameters
    // =========================================================================

    // Number of 256-bit beats required to ship a 1056-bit TLP
    // ceil(1056 / 256) = 5
    localparam TLP_BEATS  = 5;
    // A DLLP is 64 bits → 1 beat
    localparam DLLP_BEATS = 1;

    // FSM states (one-hot for synthesis speed)
    localparam [2:0]
        S_IDLE      = 3'b001,
        S_TLP_SEND  = 3'b010,
        S_DLLP_SEND = 3'b100;

    // Source select encoding
    localparam [1:0]
        SRC_NONE  = 2'b00,
        SRC_RETRY = 2'b01,
        SRC_TLP   = 2'b10,
        SRC_DLLP  = 2'b11;

    // =========================================================================
    // Internal signals
    // =========================================================================

    reg  [2:0]    state, next_state;

    // Registered copies of selected packet (capture on arbitration)
    reg  [1055:0] tlp_reg;
    reg  [63:0]   dllp_reg;
    reg  [1:0]    src_reg;          // which source is being sent

    // Beat counter
    reg  [2:0]    beat_cnt;         // 0..4 for TLP, 0 for DLLP
    wire [2:0]    beat_cnt_max;     // last valid beat index for current src

    // Current 256-bit slice of the registered TLP
    wire [255:0]  tlp_slice;

    // Arbitration winner
    wire [1:0]    arb_winner;

    // =========================================================================
    // Arbitration (combinational)
    // Retry TLPs > New TLPs > DLLPs
    // =========================================================================

    assign arb_winner = (retry_valid || retry_req) ? SRC_RETRY :
                        tlp_tx_valid               ? SRC_TLP   :
                        dllp_valid                 ? SRC_DLLP  :
                                                     SRC_NONE  ;

    // =========================================================================
    // Beat count ceiling
    // =========================================================================

    assign beat_cnt_max = (src_reg == SRC_DLLP) ? (DLLP_BEATS - 1) :
                                                    (TLP_BEATS  - 1) ;

    // =========================================================================
    // 256-bit slicer for TLP register
    // Extracts beat[beat_cnt] from the 1056-bit register.
    // beat 0 → bits[255:0], beat 1 → bits[511:256], … beat 4 → bits[1055:800]
    // (beat 4 is only 256 bits: bits[1055:800] = 256 bits, zero-extended)
    // =========================================================================

    assign tlp_slice = (beat_cnt == 3'd0) ? tlp_reg[255:0]   :
                       (beat_cnt == 3'd1) ? tlp_reg[511:256]  :
                       (beat_cnt == 3'd2) ? tlp_reg[767:512]  :
                       (beat_cnt == 3'd3) ? tlp_reg[1023:768] :
                                            {tlp_reg[1055:1024], {224{1'b0}}} ;
                       // beat 4: top 32 bits of TLP, padded with 224 zeros

    // =========================================================================
    // FSM — state register
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // =========================================================================
    // FSM — next-state logic
    // =========================================================================

    always @(*) begin
        case (state)
            S_IDLE: begin
                if (arb_winner == SRC_DLLP)
                    next_state = S_DLLP_SEND;
                else if (arb_winner != SRC_NONE)
                    next_state = S_TLP_SEND;
                else
                    next_state = S_IDLE;
            end

            S_TLP_SEND: begin
                // Stay until last beat is transmitted
                if (beat_cnt == beat_cnt_max)
                    next_state = S_IDLE;
                else
                    next_state = S_TLP_SEND;
            end

            S_DLLP_SEND: begin
                // Single-beat; always return to IDLE next cycle
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================================
    // Capture selected packet on transition out of IDLE
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_reg  <= {1056{1'b0}};
            dllp_reg <= 64'h0;
            src_reg  <= SRC_NONE;
        end
        else if (state == S_IDLE && arb_winner != SRC_NONE) begin
            src_reg <= arb_winner;
            case (arb_winner)
                SRC_RETRY: tlp_reg <= retry_tlp;
                SRC_TLP:   tlp_reg <= tlp_tx;
                SRC_DLLP:  dllp_reg <= dllp_out;
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Beat counter
    // =========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            beat_cnt <= 3'd0;
        else if (state == S_IDLE)
            beat_cnt <= 3'd0;
        else if (state == S_TLP_SEND || state == S_DLLP_SEND)
            beat_cnt <= (beat_cnt == beat_cnt_max) ? 3'd0 : beat_cnt + 1'b1;
    end

    // =========================================================================
    // PHY output datapath  (combinational — registered one cycle later by PHY)
    // Driving outputs combinationally from current state/beat_cnt ensures
    // SOP, EOP and data are presented in the same clock cycle.
    // =========================================================================

    always @(*) begin
        // Safe defaults
        phy_tx_data  = 256'h0;
        phy_tx_valid = 1'b0;
        phy_tx_sop   = 1'b0;
        phy_tx_eop   = 1'b0;

        case (state)
            // -----------------------------------------------------------------
            S_TLP_SEND: begin
                phy_tx_valid = 1'b1;
                phy_tx_data  = tlp_slice;
                phy_tx_sop   = (beat_cnt == 3'd0);
                phy_tx_eop   = (beat_cnt == beat_cnt_max);
            end
            // -----------------------------------------------------------------
            S_DLLP_SEND: begin
                phy_tx_valid = 1'b1;
                phy_tx_data  = {dllp_reg, {192{1'b0}}};
                phy_tx_sop   = 1'b1;
                phy_tx_eop   = 1'b1;
            end
            // -----------------------------------------------------------------
            default: begin
                // S_IDLE: all outputs remain 0
            end
        endcase
    end

endmodule
