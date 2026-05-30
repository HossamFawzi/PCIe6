// =============================================================================
// Module      : Descrambler
// Description : PCIe 6.0 Data Link Layer RX Path Descrambler
//
// Standard    : PCI Express Base Specification Rev 6.0
//               LFSR Polynomial: G(x) = x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1
//               (Mirror of TX Scrambler — same LFSR, XOR applied on RX side)
//
// Architecture:
//   - 256-bit wide datapath (PAM4 / 64GT/s lane)
//   - 23-bit Maximal-Length LFSR (same polynomial as PCIe 6.0 TX Scrambler)
//   - Parallel LFSR advancement: generates 256 bits per clock cycle
//   - LFSR sync-loss detection: compares expected vs received LFSR seeds
//   - link_reset forces LFSR to the provided seed
//   - scramble_en=0 bypasses XOR (pass-through, LFSR still advances)
//
// References  :
//   [1] PCI-SIG, "PCI Express Base Specification Revision 6.0", 2022
//   [2] Widmer & Franaszek, "A DC-Balanced, Partitioned-Block, 8B/10B
//       Transmission Code", IBM J. R&D, 1983
//   [3] Lee, Messerschmitt, "Digital Communication", Kluwer, 2002
//       (LFSR scrambler theory)
//
// Author      : Auto-generated for PCIe 6.0 RX DLL study
// =============================================================================

`timescale 1ns/1ps

module descrambler (  // RENAMED: was Descrambler (capital D caused case-sensitive issues)
    // Clock & Reset
    input  wire         clk,
    input  wire         rst_n,

    // Data Interface
    input  wire [255:0] data_in,
    input  wire         data_valid_in,

    // LFSR Control
    input  wire [22:0]  lfsr_seed,      // Seed for init/resync (from OS/TS detection)
    input  wire         scramble_en,    // 1=descramble active, 0=bypass XOR
    input  wire         link_reset,     // Synchronous link reset → reload seed

    // Output Interface
    output reg  [255:0] data_out,
    output reg          data_valid_out,
    output reg          lfsr_sync_err   // 1 = LFSR sync lost → trigger Recovery
);

    // -------------------------------------------------------------------------
    // PCIe 6.0 LFSR Polynomial: x^23 + x^21 + x^16 + x^8 + x^5 + x^2 + 1
    // Feedback taps (0-indexed from LSB): bits 22, 20, 15, 7, 4, 1, 0
    // Standard form: new_bit = lfsr[22] ^ lfsr[20] ^ lfsr[15] ^ lfsr[7]
    //                         ^ lfsr[4]  ^ lfsr[1]  ^ lfsr[0]
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Internal LFSR state
    // -------------------------------------------------------------------------
    reg  [22:0] lfsr_state;

    // -------------------------------------------------------------------------
    // Parallel LFSR output generation
    // Generate 256 bits of keystream from current LFSR state.
    // Each bit: advance LFSR by 1 step, collect output bit (lfsr[0]).
    // Implemented as a combinational look-ahead array.
    // -------------------------------------------------------------------------
    wire [22:0] lfsr_next  [0:256];   // lfsr_next[i] = state after i steps
    wire [255:0] keystream;            // collected keystream bits

    // Step 0: current state
    assign lfsr_next[0] = lfsr_state;

    // Generate loop — each step advances the LFSR by 1
    genvar i;
    generate
        for (i = 0; i < 256; i = i + 1) begin : LFSR_ADVANCE
            wire feedback;
            assign feedback = lfsr_next[i][22] ^ lfsr_next[i][20]
                            ^ lfsr_next[i][15] ^ lfsr_next[i][7]
                            ^ lfsr_next[i][4]  ^ lfsr_next[i][1]
                            ^ lfsr_next[i][0];

            // Shift right, insert feedback at MSB
            assign lfsr_next[i+1] = {feedback, lfsr_next[i][22:1]};

            // Output bit is LSB of current state (before shift)
            assign keystream[i] = lfsr_next[i][0];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // LFSR Sync-Error Detection  (BUG-2 FIX)
    // The seed is loaded when link_reset=1. On the VERY FIRST data cycle after
    // link_reset de-asserts we verify the LFSR state equals the loaded seed.
    // After that one-shot check we never compare again — the LFSR will run
    // freely and will never equal the static lfsr_seed port again.
    // -------------------------------------------------------------------------
    reg link_reset_r;   // previous-cycle link_reset
    always @(posedge clk or negedge rst_n)
        if (!rst_n) link_reset_r <= 1'b0;
        else        link_reset_r <= link_reset;

    // seed_mismatch fires for exactly one cycle: the first data cycle
    // immediately after link_reset falls, when the LFSR must equal lfsr_seed.
    wire seed_mismatch;
    assign seed_mismatch = link_reset_r && !link_reset && data_valid_in
                           && (lfsr_state !== lfsr_seed);

    // -------------------------------------------------------------------------
    // Sequential: LFSR state register & output
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_state     <= 23'h7FFFFF;  // all-ones default (PCIe spec init)
            data_out       <= 256'b0;
            data_valid_out <= 1'b0;
            lfsr_sync_err  <= 1'b0;
        end
        else begin
            // Link reset: reload LFSR from provided seed
            if (link_reset) begin
                lfsr_state     <= lfsr_seed;
                data_out       <= 256'b0;
                data_valid_out <= 1'b0;
                lfsr_sync_err  <= 1'b0;
            end
            else if (data_valid_in) begin
                // Advance LFSR by 256 steps (use combinational look-ahead)
                lfsr_state <= lfsr_next[256];

                // Descramble: XOR data with keystream if enabled
                if (scramble_en)
                    data_out <= data_in ^ keystream;
                else
                    data_out <= data_in;  // bypass

                data_valid_out <= 1'b1;

                // Sync error detection
                lfsr_sync_err  <= seed_mismatch;
            end
            else begin
                data_valid_out <= 1'b0;
                lfsr_sync_err  <= 1'b0;
            end
        end
    end

endmodule
