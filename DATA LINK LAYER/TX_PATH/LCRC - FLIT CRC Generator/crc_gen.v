// =============================================================================
// Module: crc_gen
// Description: LCRC / FLIT CRC Generator (DLL TX path)
//              Gen1–5 : computes 32-bit LCRC (CRC-32 / IEEE 802.3)
//                        over the TLP header+data bytes (seed = all-ones,
//                        output bit-inverted, bit-reflected per PCIe spec).
//              Gen6   : computes 24-bit CRC over the 256-byte FLIT payload
//                        (CRC-24/OpenPGP polynomial 0x864CFB) combined with
//                        the 12-bit embedded sequence number.
//              flit_mode_en selects which CRC is produced.
//              Both CRCs run in parallel; the selected one drives crc_valid.
// =============================================================================

module crc_gen (
    input  wire        clk,
    input  wire        rst_n,

    // ── Inputs ────────────────────────────────────────────────────────────────
    input  wire [1023:0] tlp_in,       // TLP data (legacy mode, up to 128 B here)
    input  wire          tlp_valid,    // TLP valid — latch & start LCRC

    input  wire [2047:0] flit_in,      // 256-byte FLIT (Gen6 mode)
    input  wire          flit_valid,   // FLIT valid — latch & start FLIT CRC

    input  wire          flit_mode_en, // 0 = Gen1-5 LCRC,  1 = Gen6 FLIT CRC

    input  wire [11:0]   seq_num,      // Sequence number embedded in FLIT header

    // ── Outputs ───────────────────────────────────────────────────────────────
    output reg  [31:0]   lcrc_out,     // 32-bit LCRC result (valid in TLP mode)
    output reg  [23:0]   flit_crc_out, // 24-bit FLIT CRC   (valid in FLIT mode)
    output reg           crc_valid     // Result is valid this cycle
);

    // =========================================================================
    // CRC-32 / PCIe LCRC
    //   Polynomial : 0x04C11DB7 (normal form)
    //   Seed       : 32'hFFFF_FFFF
    //   Input refl : yes   Output refl : yes   Output XOR : 32'hFFFF_FFFF
    //
    // For simulation clarity a byte-serial implementation is shown.
    // A synthesisable parallel implementation uses the same recurrence
    // unrolled across all bytes.
    // =========================================================================

    // ── CRC-32 step (1 byte) ─────────────────────────────────────────────────
    function automatic [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0]  data_in;
        reg   [31:0] crc;
        integer      i;
        begin
            crc = crc_in;
            // Reflect byte before processing
            for (i = 0; i < 8; i = i + 1) begin
                if ((crc[0]) ^ data_in[i])
                    crc = (crc >> 1) ^ 32'hEDB88320; // reflected poly
                else
                    crc = crc >> 1;
            end
            crc32_byte = crc;
        end
    endfunction

    // ── LCRC over TLP (128 bytes = 1024 bits) ────────────────────────────────
    function automatic [31:0] calc_lcrc;
        input [1023:0] data;
        reg   [31:0]   crc;
        integer        b;
        begin
            crc = 32'hFFFF_FFFF;
            for (b = 0; b < 128; b = b + 1) begin
                // PCIe: LSByte first (little-endian)
                crc = crc32_byte(crc, data[b*8 +: 8]);
            end
            calc_lcrc = ~crc; // final XOR
        end
    endfunction

    // =========================================================================
    // CRC-24 / FLIT CRC
    //   Polynomial : 0x864CFB (CRC-24/OpenPGP — also used by PCIe Gen6 spec)
    //   Seed       : 24'hB704CE
    //   No bit-reflection (Gen6 FLIT CRC spec)
    //
    // Covers 256 bytes of FLIT body prepended by the 12-bit seq_num
    // (padded to 2 bytes, LSB-aligned, per Gen6 spec section 4.2.6).
    // =========================================================================

    localparam [23:0] CRC24_POLY = 24'h864CFB;
    localparam [23:0] CRC24_SEED = 24'hB704CE;

    function automatic [23:0] crc24_byte;
        input [23:0] crc_in;
        input [7:0]  data_in;
        reg   [23:0] crc;
        integer      i;
        begin
            crc = crc_in;
            for (i = 7; i >= 0; i = i - 1) begin
                if (crc[23] ^ data_in[i])
                    crc = (crc << 1) ^ CRC24_POLY;
                else
                    crc = crc << 1;
            end
            crc24_byte = crc;
        end
    endfunction

    function automatic [23:0] calc_flit_crc;
        input [2047:0] flit;
        input [11:0]   seq;
        reg   [23:0]   crc;
        integer        b;
        begin
            crc = CRC24_SEED;
            // Prepend sequence number (2 bytes, big-endian, 4 MSBs padding=0)
            crc = crc24_byte(crc, {4'h0, seq[11:8]});
            crc = crc24_byte(crc, seq[7:0]);
            // Followed by 256 FLIT bytes
            for (b = 255; b >= 0; b = b - 1) begin
                // Big-endian byte order for Gen6 FLIT
                crc = crc24_byte(crc, flit[b*8 +: 8]);
            end
            calc_flit_crc = crc;
        end
    endfunction

    // ── Registered output stage ───────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcrc_out     <= 32'h0;
            flit_crc_out <= 24'h0;
            crc_valid    <= 1'b0;
        end else begin
            crc_valid <= 1'b0; // default: pulse only

            if (!flit_mode_en && tlp_valid) begin
                // Gen1-5: compute LCRC on arriving TLP
                lcrc_out  <= calc_lcrc(tlp_in);
                crc_valid <= 1'b1;
            end else if (flit_mode_en && flit_valid) begin
                // Gen6: compute 24-bit FLIT CRC
                flit_crc_out <= calc_flit_crc(flit_in, seq_num);
                crc_valid    <= 1'b1;
            end
        end
    end

endmodule
