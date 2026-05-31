// =============================================================================
// Module  : flit_rx_deframer
// Layer   : Data Link Layer (DLL) — RX Path
// Spec    : PCIe Gen6 Base Specification r1.0 — Chapter 3 (DLL)
// Tag     : FLIT_RX
// 
// Description:
//   Gen6-MANDATORY deframer for 256B (2048-bit) FLITs received from the PHY.
//   Extracts TLPs and DLLPs embedded in each FLIT, recovers the 12-bit
//   sequence number from the FLIT header, verifies the 24-bit FLIT CRC, and
//   flags null-slot FLITs.  Un-correctable FEC errors are propagated upstream.
//
//   FLIT layout assumed (PCIe 6.0 §3.x):
//     [2047:2024]  FLIT CRC  (24 bits)
//     [2023:2012]  SEQ_NUM   (12 bits)
//     [2011:2008]  FLIT TYPE (4 bits): 4'h0=NULL, 4'h1=TLP, 4'h2=DLLP, 4'h3=MIXED
//     [2007:1024]  DLLP slot (64 bits used when type contains DLLP)
//     [1023:0]     TLP  slot (1024 bits)
//
// Outputs:
//   flit_tlp[1023:0]   — extracted TLP payload
//   flit_tlp_valid     — TLP slot is valid
//   flit_dllp[63:0]    — extracted DLLP payload
//   flit_dllp_valid    — DLLP slot is valid
//   flit_seq[11:0]     — recovered FLIT sequence number
//   flit_crc_err       — 24-bit FLIT CRC mismatch
//   flit_null          — FLIT carries a null (padding) slot
//   flit_uncorr_err    — uncorrectable FEC error forwarded from PHY
// =============================================================================

module flit_rx_deframer (
    input  wire          clk,
    input  wire          rst_n,

    // ── From Descrambler / PHY Interface RX ──────────────────────────────────
    input  wire [2047:0] rx_flit,          // 256B FLIT (raw, post-descramble)
    input  wire          rx_flit_valid,    // FLIT word on the bus is valid
    input  wire [15:0]   fec_syndrome,     // FEC syndrome (0 = no error)
    input  wire          fec_corrected,    // PHY corrected a symbol error

    // ── To LCRC/CRC Checker & upper DLL ─────────────────────────────────────
    output reg  [1023:0] flit_tlp,         // TLP extracted from FLIT
    output reg           flit_tlp_valid,
    output reg  [63:0]   flit_dllp,        // DLLP extracted from FLIT
    output reg           flit_dllp_valid,
    output reg  [11:0]   flit_seq,         // FLIT sequence number
    output reg           flit_crc_err,     // 24-bit CRC mismatch
    output reg           flit_null,        // null slot detected
    output reg           flit_uncorr_err   // uncorrectable FEC error
);

    // ── FLIT field extraction ─────────────────────────────────────────────────
    localparam FLIT_TYPE_NULL  = 4'h0;
    localparam FLIT_TYPE_TLP   = 4'h1;
    localparam FLIT_TYPE_DLLP  = 4'h2;
    localparam FLIT_TYPE_MIXED = 4'h3;

    wire [23:0] rx_crc      = rx_flit[2047:2024];
    wire [11:0] rx_seq      = rx_flit[2023:2012];
    wire [3:0]  rx_type     = rx_flit[2011:2008];
    wire [63:0] rx_dllp_raw = rx_flit[2007:1944];   // 64-bit DLLP field
    wire [1023:0] rx_tlp_raw= rx_flit[1023:0];

    // ── 24-bit CRC computation (CRC-24/FLIT) ─────────────────────────────────
    // Polynomial: x^24 + x^23 + x^6 + x^5 + x + 1  (simplified serial model)
    // For RTL synthesis a parallel LUT-based CRC is used; here a compact
    // Galois-LFSR reference model is instantiated.
    wire [23:0] computed_crc;

    flit_crc24 u_crc24 (
        .data  (rx_flit[2023:0]),   // all bits except the CRC field itself
        .crc   (computed_crc)
    );

    // ── FEC uncorrectable detection ───────────────────────────────────────────
    // An uncorrectable error is indicated when the FEC syndrome is non-zero
    // AND the PHY has NOT flagged it as corrected.
    wire uncorr = (fec_syndrome != 16'h0) && !fec_corrected;

    // ── Pipeline register (one-cycle latency for CRC) ─────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_tlp        <= 1024'b0;
            flit_tlp_valid  <= 1'b0;
            flit_dllp       <= 64'b0;
            flit_dllp_valid <= 1'b0;
            flit_seq        <= 12'b0;
            flit_crc_err    <= 1'b0;
            flit_null       <= 1'b0;
            flit_uncorr_err <= 1'b0;
        end else begin
            // defaults
            flit_tlp_valid  <= 1'b0;
            flit_dllp_valid <= 1'b0;
            flit_crc_err    <= 1'b0;
            flit_null       <= 1'b0;
            flit_uncorr_err <= 1'b0;

            if (rx_flit_valid) begin
                flit_seq        <= rx_seq;
                flit_uncorr_err <= uncorr;

                // CRC check — suppress further processing on CRC error
                if (computed_crc != rx_crc) begin
                    flit_crc_err <= 1'b1;
                end else if (!uncorr) begin
                    // Route by FLIT type
                    case (rx_type)
                        FLIT_TYPE_NULL: begin
                            flit_null <= 1'b1;
                        end

                        FLIT_TYPE_TLP: begin
                            flit_tlp       <= rx_tlp_raw;
                            flit_tlp_valid <= 1'b1;
                        end

                        FLIT_TYPE_DLLP: begin
                            flit_dllp       <= rx_dllp_raw;
                            flit_dllp_valid <= 1'b1;
                        end

                        FLIT_TYPE_MIXED: begin
                            flit_tlp        <= rx_tlp_raw;
                            flit_tlp_valid  <= 1'b1;
                            flit_dllp       <= rx_dllp_raw;
                            flit_dllp_valid <= 1'b1;
                        end

                        default: begin
                            // Reserved FLIT type — treat as error (CRC still OK)
                            flit_crc_err <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

endmodule


// =============================================================================
// Sub-module : flit_crc24
// Parallel 24-bit CRC over 2024 input bits.
// Polynomial : 0xC60001  (CRC-24 variant, illustrative)
// NOTE: In a real implementation this would be fully unrolled via script.
//       This compact version uses a byte-serial loop unrolled over 253 bytes.
// =============================================================================
module flit_crc24 (
    input  wire [2023:0] data,
    output wire [23:0]   crc
);
    // Combinational CRC using function (synthesis tool will unroll)
    function [23:0] crc24_byte;
        input [23:0] crc_in;
        input [7:0]  byte_in;
        integer i;
        reg [23:0] c;
        begin
            c = crc_in ^ {byte_in, 16'h0};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[23])
                    c = (c << 1) ^ 24'hC60001;
                else
                    c = c << 1;
            end
            crc24_byte = c;
        end
    endfunction

    integer j;
    reg [23:0] crc_reg;
    always @(*) begin
        crc_reg = 24'hFFFFFF;
        for (j = 0; j < 253; j = j + 1)
            crc_reg = crc24_byte(crc_reg, data[j*8 +: 8]);
    end

    assign crc = crc_reg;
endmodule
