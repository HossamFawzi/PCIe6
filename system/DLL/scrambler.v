// =============================================================================
// Module      : scrambler
// Project     : PCIe 6.0 – Data Link Layer
// Description : 256-bit parallel LFSR scrambler
//
// Standard / Literature References
// ---------------------------------------------------------------------------
//  [1] PCI Express Base Specification Rev 6.0, Section 4.2.2
//      "Scrambling" – polynomial G(x) = x^23 + x^18 + 1 (same as Gen1/2/3/4/5)
//      Applied per-byte in the 256-bit FLIT datapath.
//  [2] "PCI Express Technology 3.0", MindShare Press (Budruk, Anderson, Shanley)
//      Ch.17 – Scrambling & DC Balance.
//  [3] "Serial Interface for High-Speed Backplane Applications", IEEE 802.3ap
//      annex – parallel LFSR expansion technique (identical polynomial family).
//  [4] Xilinx WP382 – "Parallel Scrambler/Descrambler" application note;
//      method used to derive 256 parallel taps below.
//
// LFSR Polynomial
// ---------------------------------------------------------------------------
//  G(x) = x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1  (PCIe Gen6, BUG FIX: was x^23+x^18+1)
//  Feedback taps: bit 22 XOR bit 17 → inserted at bit 0 each clock.
//  Maximal-length sequence: 2^23 – 1 = 8,388,607 bits before repetition.
//
//  Standard seed per PCIe spec: 23'h7FFFFF (all ones at link-up).
//  lfsr_seed input overrides this for compliance / test modes.
//
// Parallel Expansion (256-bit / clock)
// ---------------------------------------------------------------------------
//  Each output byte b[k] = data_in byte XOR scramble_byte[k], where
//  scramble_byte[k] is the k-th byte of the LFSR output stream.
//  The 256 consecutive LFSR bits are computed combinationally from the
//  current 23-bit state using the recurrence:
//
//    s[n] = s[n-23] XOR s[n-18]        (LFSR serial output bit)
//    new_state = { s[255], s[254], ..., s[233] }  (top 23 of 256 new bits)
//
//  All 256+23 bits of the extended sequence are derived below.
//
// Datapath
// ---------------------------------------------------------------------------
//  • Byte 0  of data_in is XORed with LFSR bits [7:0]   (earliest bits)
//  • Byte 31 of data_in is XORed with LFSR bits [255:248](latest bits)
//  • Bit ordering within each byte: MSB first (bit 7 = earliest LFSR bit)
//
//  When scramble_en = 0 : data passes through unchanged (compliance test).
//  When link_reset  = 1 : LFSR reloads with lfsr_seed on next rising edge.
//
// Port Widths (as specified)
// ---------------------------------------------------------------------------
//  data_in      [255:0] – 256-bit raw data (one PCIe 6.0 FLIT beat)
//  data_valid_in  [1]   – upstream data valid
//  lfsr_seed     [22:0] – initial / reload value (typically 23'h7FFFFF)
//  scramble_en    [1]   – 1 = scramble active; 0 = bypass (compliance mode)
//  link_reset     [1]   – synchronous: reload LFSR from lfsr_seed
//  clk / rst_n    [-]   – system clock / active-low async reset
//
//  data_out     [255:0] – scrambled (or bypassed) output data
//  data_valid_out [1]   – registered, matches data_out pipeline stage
//  lfsr_state    [22:0] – post-cycle LFSR state (for debug / verification)
// =============================================================================

`timescale 1ns / 1ps

module scrambler (
    // Clock / Reset
    input  wire          clk,
    input  wire          rst_n,

    // Data interface
    input  wire [255:0]  data_in,
    input  wire          data_valid_in,

    // Scrambler control
    input  wire [22:0]   lfsr_seed,
    input  wire          scramble_en,
    input  wire          link_reset,

    // Outputs
    output reg  [255:0]  data_out,
    output reg           data_valid_out,
    output reg  [22:0]   lfsr_state
);

    // =========================================================================
    // LFSR state register (23 bits, G(x) = x^23 + x^18 + 1)
    // =========================================================================
    reg  [22:0] lfsr_reg;

    // =========================================================================
    // Parallel LFSR expansion
    // ---------------------------------------------------------------------------
    // We need 256 consecutive output bits from the LFSR starting at state
    // lfsr_reg.  Let s[i] denote the i-th bit produced AFTER the current state:
    //
    //   For i < 23 : s[i] = lfsr_reg[22-i]   (shift-register contents)
    //   For i >= 23: s[i] = s[i-23] ^ s[i-18]
    //
    // We compute s[0..278] (256 output bits + 23 next-state bits).
    // =========================================================================

    // Extended sequence: indices 0..278 = 279 bits
    // Index 0 = first bit shifted out (MSB of current LFSR = lfsr_reg[22])
    wire [278:0] seq;

    // Seed the first 23 positions from current LFSR state (MSB-first output)
    genvar gi;
    generate
        for (gi = 0; gi < 23; gi = gi + 1) begin : seed_bits
            assign seq[gi] = lfsr_reg[22 - gi];
        end
    endgenerate

    // Extend the sequence using PCIe Gen6 polynomial:
    // G(x) = x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1
    // Recurrence: s[i] = s[i-23] ^ s[i-21] ^ s[i-16] ^ s[i-8] ^ s[i-5] ^ s[i-2] ^ s[i-1]
    // BUG FIX: was using Gen1-5 polynomial (x^23+x^18+1), now matches Descrambler
    generate
        for (gi = 23; gi < 279; gi = gi + 1) begin : extend_bits
            assign seq[gi] = seq[gi-23] ^ seq[gi-21] ^ seq[gi-16] ^ seq[gi-8]
                           ^ seq[gi-5]  ^ seq[gi-2]  ^ seq[gi-1];
        end
    endgenerate

    // =========================================================================
    // Build the 256-bit scramble word from seq[0..255]
    // Byte 0 uses seq[0..7], byte 1 uses seq[8..15], ..., byte 31 uses seq[248..255]
    // Within each byte: MSB = earliest LFSR bit
    // =========================================================================
    wire [255:0] scramble_word;
    generate
        for (gi = 0; gi < 256; gi = gi + 1) begin : build_word
            // data_out bit position: byte k, bit b → index k*8+(7-b)
            // scramble_word[255] = seq[0], scramble_word[254] = seq[1], ...
            assign scramble_word[255 - gi] = seq[gi];
        end
    endgenerate

    // =========================================================================
    // Next LFSR state: top 23 bits of the extended sequence (seq[256..278])
    // =========================================================================
    wire [22:0] lfsr_next;
    generate
        for (gi = 0; gi < 23; gi = gi + 1) begin : next_state
            assign lfsr_next[22 - gi] = seq[256 + gi];
        end
    endgenerate

    // =========================================================================
    // Sequential logic
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_reg       <= 23'h7FFFFF;   // PCIe spec default seed
            data_out       <= 256'h0;
            data_valid_out <= 1'b0;
            lfsr_state     <= 23'h7FFFFF;
        end
        else begin
            // -------------------------------------------------------------------
            // LFSR state update
            // -------------------------------------------------------------------
            if (link_reset) begin
                // Synchronous reload from external seed (link-up / compliance)
                lfsr_reg   <= lfsr_seed;
                lfsr_state <= lfsr_seed;
            end
            else if (data_valid_in && scramble_en) begin
                // Advance LFSR by 256 bits only when consuming data
                lfsr_reg   <= lfsr_next;
                lfsr_state <= lfsr_next;
            end
            else begin
                // Hold state when idle or scrambling disabled
                lfsr_state <= lfsr_reg;
            end

            // -------------------------------------------------------------------
            // Data path
            // -------------------------------------------------------------------
            data_valid_out <= data_valid_in;

            if (data_valid_in) begin
                if (scramble_en)
                    data_out <= data_in ^ scramble_word;
                else
                    data_out <= data_in;   // Bypass for compliance testing
            end
            else begin
                data_out <= 256'h0;
            end
        end
    end

endmodule
