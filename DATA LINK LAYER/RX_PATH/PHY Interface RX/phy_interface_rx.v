//=============================================================================
// Module  : phy_interface_rx
// Project : PCIe 6.0 Data Link Layer — RX Path
// Purpose : PIPE RX Boundary — Gen6 PHY Interface Receiver
//
// Reference:
//   [1] PCI Express Base Specification, Revision 6.0, §4 (Physical Layer),
//       §7 (Data Link Layer), §8 (Transaction Layer)
//   [2] PCI-SIG PIPE Specification, Revision 5.1 – PHY Interface for
//       PCI Express
//   [3] PCIe 6.0 Flit Mode & FEC — PCI-SIG White Paper (2021)
//   [4] Thaler et al., "Forward Error Correction for PCIe Gen6,"
//       IEEE Hot Interconnects 2020
//
// Description:
//   Implements the PIPE RX boundary for PCIe 6.0 x16.
//   In Flit Mode (Gen6) the PHY delivers pre-decoded 256-byte FLITs
//   together with FEC syndrome information. This module:
//     1. Accepts 256-bit wide raw RX data from the PHY at 32 GHz
//        effective rate (PAM4, 64 GT/s per lane, x16 = 256 b/cycle).
//     2. Validates PHY status and FEC syndrome.
//     3. Accumulates eight consecutive 256-bit beats to assemble one
//        complete 2048-bit (256-byte) Flit.
//     4. Presents the completed flit with rx_flit_valid to the DLL.
//     5. Passes beat-level data through as rx_data / rx_valid for
//        optional low-latency consumption.
//
// Flit accumulation:
//   PCIe 6.0 defines a 256-byte Flit.
//   PHY bus width  = 256 bits  = 32 bytes per beat.
//   Beats per Flit = 2048 / 256 = 8.
//   A 3-bit beat counter (0-7) controls accumulation.
//
// FEC handling:
//   The PHY supplies a 16-bit syndrome per beat. A non-zero syndrome
//   with fec_corrected=0 signals an uncorrectable error (UE). A non-zero
//   syndrome with fec_corrected=1 indicates a corrected error (CE).
//   UE events set rx_flit_valid=0 and assert the internal error flag.
//
// LTSSM gate:
//   All outputs are suppressed unless ltssm_dl_up=1 (DL_Up state).
//
// Port widths match the PCI-SIG PIPE Specification §6 and PCIe 6.0
// Base Spec §4.2.
//=============================================================================

`timescale 1ns/1ps

module phy_interface_rx (
    //--------------------------------------------------------------------
    // Clock / Reset
    //--------------------------------------------------------------------
    input  wire          clk,          // PIPE clock (recovered, 1 GHz symbol clock)
    input  wire          rst_n,        // Active-low synchronous reset

    //--------------------------------------------------------------------
    // PHY Inputs  (PIPE RX interface)
    //--------------------------------------------------------------------
    input  wire [255:0]  phy_rxd,      // Raw 256-bit RX data from PHY
    input  wire          phy_rx_valid, // PHY RX data valid qualifier
    input  wire [2:0]    phy_rx_status,// PIPE RxStatus[2:0] — §6.4.2
                                       //   3'b000 = Received Data OK
                                       //   3'b001 = 1 Symbol Error
                                       //   3'b010 = Training Sequence
                                       //   3'b011 = deskew still in progress
                                       //   3'b100 = Receiver Detect
                                       //   3'b101 = reserved
                                       //   3'b110 = reserved
                                       //   3'b111 = receiver not detected

    //--------------------------------------------------------------------
    // FEC Inputs  (from on-die FEC decoder, delivered with each beat)
    //--------------------------------------------------------------------
    input  wire [15:0]   fec_syndrome, // Reed-Solomon syndrome per beat
    input  wire          fec_corrected,// 1 = errors corrected, 0 = UE or clean

    //--------------------------------------------------------------------
    // LTSSM Control
    //--------------------------------------------------------------------
    input  wire          ltssm_dl_up,  // 1 = Data Link layer in DL_Up state

    //--------------------------------------------------------------------
    // Outputs  (to Data Link Layer)
    //--------------------------------------------------------------------
    output reg  [255:0]  rx_data,      // Beat-level passthrough data
    output reg           rx_valid,     // Beat-level valid

    output reg  [2047:0] rx_flit,      // Assembled 256-byte Flit
    output reg           rx_flit_valid // Flit valid (high for exactly one cycle)
);

    //====================================================================
    // Local parameters
    //====================================================================
    localparam BEATS_PER_FLIT   = 3'd7;   // 8 beats, counter 0-7
    localparam RX_STATUS_OK     = 3'b000;
    localparam RX_STATUS_TS     = 3'b010; // Training Sequence — ignore

    //====================================================================
    // Internal registers / wires
    //====================================================================

    // Flit accumulation buffer: 8 x 256 = 2048 bits
    reg [2047:0] flit_buf;

    // Beat counter [0..7]
    reg [2:0]    beat_cnt;

    // Per-flit FEC error tracking
    reg          flit_has_ue;   // Uncorrectable error in current flit window
    reg          flit_has_ce;   // Correctable error flagged (informational)

    // Qualify incoming beat
    wire beat_ok;
    wire fec_ue;
    wire phy_status_ok;

    //====================================================================
    // Combinational qualifiers
    //====================================================================

    // PHY status must be RX_STATUS_OK for data to be valid
    assign phy_status_ok = (phy_rx_status == RX_STATUS_OK);

    // Uncorrectable FEC error: syndrome non-zero AND not corrected by FEC
    assign fec_ue = (fec_syndrome != 16'h0000) && !fec_corrected;

    // A beat is accepted when the link is up, PHY reports OK, and data is valid
    assign beat_ok = ltssm_dl_up && phy_rx_valid && phy_status_ok;

    //====================================================================
    // Beat counter & flit accumulation
    //====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat_cnt      <= 3'd0;
            flit_buf      <= {2048{1'b0}};
            flit_has_ue   <= 1'b0;
            flit_has_ce   <= 1'b0;
            rx_data       <= {256{1'b0}};
            rx_valid      <= 1'b0;
            rx_flit       <= {2048{1'b0}};
            rx_flit_valid <= 1'b0;
        end else begin
            //--------------------------------------------------------------
            // Default: de-assert single-cycle strobes
            //--------------------------------------------------------------
            rx_flit_valid <= 1'b0;
            rx_valid      <= 1'b0;

            if (!ltssm_dl_up) begin
                //-----------------------------------------------------------
                // Link not up — flush state, suppress all outputs
                //-----------------------------------------------------------
                beat_cnt    <= 3'd0;
                flit_has_ue <= 1'b0;
                flit_has_ce <= 1'b0;
            end else if (beat_ok) begin
                //-----------------------------------------------------------
                // Valid beat received
                //-----------------------------------------------------------

                // 1. Beat-level passthrough
                rx_data  <= phy_rxd;
                rx_valid <= 1'b1;

                // 2. Track FEC errors across this flit window
                if (fec_ue)
                    flit_has_ue <= 1'b1;

                if (fec_corrected && (fec_syndrome != 16'h0000))
                    flit_has_ce <= 1'b1;

                // 3. Accumulate beat into flit buffer
                //    Bit slice: beat N occupies [(N+1)*256-1 : N*256]
                //    Shift existing content up and insert at MSB or
                //    use indexed assignment for clarity.
                case (beat_cnt)
                    3'd0: flit_buf[255:0]    <= phy_rxd;
                    3'd1: flit_buf[511:256]   <= phy_rxd;
                    3'd2: flit_buf[767:512]   <= phy_rxd;
                    3'd3: flit_buf[1023:768]  <= phy_rxd;
                    3'd4: flit_buf[1279:1024] <= phy_rxd;
                    3'd5: flit_buf[1535:1280] <= phy_rxd;
                    3'd6: flit_buf[1791:1536] <= phy_rxd;
                    3'd7: flit_buf[2047:1792] <= phy_rxd;
                    default: ;
                endcase

                // 4. On last beat: present flit and reset window
                //    flit_buf[2047:1792] was just written above in the case.
                //    We must combine those bits with the lower 1792 bits.
                if (beat_cnt == BEATS_PER_FLIT) begin
                    // Commit flit only if no uncorrectable FEC error
                    if (!flit_has_ue && !fec_ue) begin
                        rx_flit       <= {phy_rxd, flit_buf[1791:0]};
                        rx_flit_valid <= 1'b1;
                    end else begin
                        // UE: suppress flit, leave rx_flit unchanged
                        rx_flit_valid <= 1'b0;
                    end

                    // Reset per-flit error tracking
                    beat_cnt    <= 3'd0;
                    flit_has_ue <= 1'b0;
                    flit_has_ce <= 1'b0;

                end else begin
                    beat_cnt <= beat_cnt + 3'd1;
                end

            end
            // beat_ok=0: stall — counter and buffer hold; no outputs
        end
    end

`ifdef FORMAL
    //====================================================================
    // Formal / Assertion helpers  (synthesised away in normal flows)
    //====================================================================
    // beat_cnt never exceeds 7
    always @(posedge clk) begin
        if (rst_n)
            assert (beat_cnt <= 3'd7);
    end
    // rx_flit_valid may only be high for one cycle
    reg flit_valid_prev;
    always @(posedge clk) flit_valid_prev <= rx_flit_valid;
    always @(posedge clk) begin
        if (rst_n && flit_valid_prev)
            assert (!rx_flit_valid || (beat_cnt == 3'd0));
    end
`endif

endmodule
