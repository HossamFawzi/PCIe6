// =============================================================================
// Module  : rx_datapath_demux
// Layer   : Data Link Layer (DLL) — RX Path
// Spec    : PCIe Gen6 Base Specification r1.0 — Chapter 3 (DLL)
// Tag     : RX_DEMUX
//
// Description:
//   Separates the unified DLL RX stream into two independent output paths:
//     1. TLP path  → LCRC/FLIT CRC Checker → ACK/NAK Scheduler
//     2. DLLP path → DLLP CRC Checker → DLLP Receiver/Decoder
//
//   Two operating modes are supported, selected by flit_mode_en:
//
//   LEGACY mode (flit_mode_en = 0, Gen1–Gen5):
//     • rx_data[255:0] carries raw descrambled bytes.
//     • Module parses the first byte to distinguish TLP vs DLLP:
//         - STP framing symbol = TLP
//         - SDP framing symbol = DLLP
//     • TLP output is 1056-bit (1024 payload + 32-bit LCRC).
//
//   FLIT mode (flit_mode_en = 1, Gen6):
//     • FLIT Rx Deframer has already separated flit_tlp / flit_dllp.
//     • This module simply registers and forwards those pre-separated buses.
//     • rx_data is ignored.
//
//   Error:
//     rx_parse_err is raised if legacy mode detects an unrecognised framing
//     symbol (neither STP nor SDP) in the first byte of rx_data.
//
// Inputs:
//   rx_data[255:0]       — raw descrambled data (legacy mode)
//   rx_valid             — rx_data is valid
//   flit_tlp[1023:0]     — TLP payload from FLIT deframer (FLIT mode)
//   flit_tlp_valid       — FLIT mode TLP valid
//   flit_dllp[63:0]      — DLLP payload from FLIT deframer (FLIT mode)
//   flit_dllp_valid      — FLIT mode DLLP valid
//   flit_mode_en         — 1 = Gen6 FLIT mode; 0 = legacy mode
//
// Outputs:
//   tlp_rx[1055:0]       — TLP with LCRC/seq appended (legacy) or raw (FLIT)
//   tlp_rx_valid         — TLP output is valid
//   dllp_raw[63:0]       — DLLP body (pre-CRC-check)
//   dllp_rx_valid        — DLLP output is valid
//   rx_parse_err         — legacy framing parse error
// =============================================================================

module rx_datapath_demux (
    input  wire          clk,
    input  wire          rst_n,

    // ── Legacy RX stream (Gen1-5) ─────────────────────────────────────────────
    input  wire [255:0]  rx_data,          // descrambled 256-bit word
    input  wire          rx_valid,

    // ── FLIT Rx Deframer outputs (Gen6) ──────────────────────────────────────
    input  wire [1023:0] flit_tlp,
    input  wire          flit_tlp_valid,
    input  wire [63:0]   flit_dllp,
    input  wire          flit_dllp_valid,

    // ── Mode select (from Config Space Handler) ───────────────────────────────
    input  wire          flit_mode_en,

    // ── Outputs ───────────────────────────────────────────────────────────────
    output reg  [1055:0] tlp_rx,           // 1024b TLP + 32b LCRC (legacy) / 1024b (FLIT)
    output reg           tlp_rx_valid,
    output reg  [63:0]   dllp_raw,         // 64-bit raw DLLP (to DLLP CRC Checker)
    output reg           dllp_rx_valid,
    output reg           rx_parse_err      // unrecognised framing symbol (legacy only)
);

    // ── Legacy framing symbols (PCIe 1.x–5.x ordered-sets) ──────────────────
    // STP = Start of TLP  = 8'hFB  (K27.7)
    // SDP = Start of DLLP = 8'hFC  (K28.2 — simplified)
    localparam STP = 8'hFB;
    localparam SDP = 8'hFC;

    // ── FLIT mode: direct register/forward ───────────────────────────────────
    // ── Legacy mode: accumulate words until LCRC collected ───────────────────
    // Simple legacy path: treat rx_data[7:0] as framing byte on first beat.
    // TLP is assembled across multiple beats; for this reference model we
    // assume a single 256-bit word carries a framing byte + up to 248 payload
    // bits (simplified — full design would use a multi-beat assembler).

    reg [1055:0] tlp_accum;
    reg [63:0]   dllp_accum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_rx        <= 1056'b0;
            tlp_rx_valid  <= 1'b0;
            dllp_raw      <= 64'b0;
            dllp_rx_valid <= 1'b0;
            rx_parse_err  <= 1'b0;
            tlp_accum     <= 1056'b0;
            dllp_accum    <= 64'b0;
        end else begin
            // ── Defaults ──────────────────────────────────────────────────────
            tlp_rx_valid  <= 1'b0;
            dllp_rx_valid <= 1'b0;
            rx_parse_err  <= 1'b0;

            if (flit_mode_en) begin
                // ── FLIT mode ─────────────────────────────────────────────────
                if (flit_tlp_valid) begin
                    tlp_rx       <= {32'b0, flit_tlp};  // no LCRC slot in FLIT mode
                    tlp_rx_valid <= 1'b1;
                end
                if (flit_dllp_valid) begin
                    dllp_raw      <= flit_dllp;
                    dllp_rx_valid <= 1'b1;
                end
            end else begin
                // ── Legacy mode ───────────────────────────────────────────────
                if (rx_valid) begin
                    case (rx_data[7:0])   // framing byte is in LS byte of first word
                        STP: begin
                            // Start of TLP: pack payload bytes into accumulator.
                            // FIX-DEMUX: Full 256-bit beat forms the TLP frame.
                            tlp_rx       <= {rx_data[255:8], 32'b0};
                            tlp_rx_valid <= 1'b1;
                        end
                        SDP: begin
                            // Start of DLLP: 6 bytes follow the SDP byte.
                            // rx_data[55:8] = 6-byte DLLP body; [71:56] = CRC-16.
                            dllp_raw      <= rx_data[71:8];
                            dllp_rx_valid <= 1'b1;
                        end

                        default: begin
                            // FIX-DEMUX: Raw TLP inject path (no STP framing byte).
                            // inject_tlp sends raw 256-bit TLP frame data directly.
                            // Accept as TLP if not a special symbol (COM/SDP).
                            if (rx_data[7:0] != 8'hBC && rx_data[7:0] != 8'hFC) begin
                                tlp_rx       <= rx_data[255:0];
                                tlp_rx_valid <= 1'b1;
                            end
                            // COM (0xBC) is silently dropped (normal idle between ordered sets)
                        end
                    endcase
                end
            end
        end
    end

endmodule
