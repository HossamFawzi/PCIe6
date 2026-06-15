// =============================================================================
// dllp_crc_chk.v
// PCIe Gen6 — DLL RX Path — Module 15: DLLP CRC Checker (DLLP_CRKC)
// =============================================================================
//
// PURPOSE:
//   Receives a raw 64-bit DLLP from RX_DEMUX (which split it from the FLIT
//   stream). The 64-bit word is structured as:
//
//       [63:48]  =  16-bit CRC-16  (appended by the far-end DLLP_CRCG)
//       [47:0]   =  48-bit DLLP body (type + payload fields)
//
//   This module:
//     1. Recomputes CRC-16 over the 48-bit DLLP body using the same
//        CRC-16/CCITT polynomial (0x1021) the TX side used.
//     2. Compares the recomputed CRC against the received CRC [63:48].
//     3. On MATCH  → strips the CRC, outputs the clean 48-bit body,
//                    asserts dllp_crc_ok for one cycle.
//     4. On MISMATCH → discards the DLLP (body NOT forwarded),
//                      asserts dllp_crc_err for one cycle.
//     5. dllp_valid_out is only asserted on a PASS — a failing DLLP is
//        silently dropped (PCIe spec: DLLPs have NO retry mechanism).
//
// PORT CONNECTIONS (from block diagram):
//   Input  dllp_raw[63:0]     — from RX_DEMUX.dllp_raw[63:0]
//   Input  dllp_rx_valid      — from RX_DEMUX.dllp_rx_valid
//   Output dllp_body[47:0]    — to DLLP_MAL.dllp_body[47:0]
//   Output dllp_crc_ok        — to DLLP_MAL.dllp_crc_ok
//                             — to DLL_ERR (indirectly, via dllp_crc_err)
//   Output dllp_crc_err       — to DLL_ERR.dllp_crc_err
//   Output dllp_valid_out     — to DLLP_MAL.dllp_valid_in
//
// CRC-16/CCITT ALGORITHM:
//   Polynomial : 0x1021  (x^16 + x^12 + x^5 + 1)
//   Init value : 0xFFFF
//   Input data : 48-bit DLLP body processed MSB-first, byte by byte
//   Final XOR  : 0x0000  (no final inversion)
//   This is the same polynomial used by the TX DLLP_CRCG module.
//
// LATENCY:
//   1 clock cycle (fully registered outputs — no glitches on QuestaSim)
//
// MISTAKES AVOIDED (from chat review):
//   - No static variable collision: CRC function uses only local variables
//   - Registered outputs: all outputs clocked, stable for full cycle
//   - No silent data leakage: dllp_body forced to zero on CRC error
//   - No valid-without-check: dllp_valid_out only asserted on CRC pass
//   - All ports match block diagram names and widths exactly
//   - No combinational output glitches (all registered)
//
// =============================================================================

`timescale 1ns/1ps

module dllp_crc_chk (
    // ── Clock & Reset ──────────────────────────────────────────────────────
    input  wire         clk,
    input  wire         rst_n,

    // ── Input: raw DLLP from RX_DEMUX ──────────────────────────────────────
    // Full 64-bit DLLP: [63:48] = received CRC-16, [47:0] = DLLP body
    input  wire [63:0]  dllp_raw,
    input  wire         dllp_rx_valid,

    // ── Outputs to DLLP_MAL ────────────────────────────────────────────────
    output reg  [47:0]  dllp_body,       // Clean 48-bit DLLP body (zero on error)
    output reg          dllp_crc_ok,     // 1-cycle pulse: CRC matched
    output reg          dllp_crc_err,    // 1-cycle pulse: CRC mismatch → DLLP dropped
    output reg          dllp_valid_out   // 1-cycle pulse: body is valid (only on OK)
);

    // =========================================================================
    // INTERNAL WIRES: split raw input into received CRC and body
    // =========================================================================

    wire [15:0] rx_crc       = dllp_raw[63:48]; // CRC received from far end
    wire [47:0] rx_body      = dllp_raw[47:0];  // 48-bit DLLP body to check

    // =========================================================================
    // CRC-16/CCITT COMPUTATION FUNCTION
    //
    // Processes 6 bytes (48 bits) of the DLLP body MSB-first.
    // Each byte is XOR'd into the 16-bit shift register one bit at a time.
    // Polynomial: 0x1021
    // Init:       0xFFFF
    // No final inversion (Final XOR = 0x0000)
    //
    // Uses ONLY local variables — no static variables — avoids the
    // Verilog static variable collision bug seen in the ECRC module.
    // =========================================================================
    function [15:0] calc_crc16;
        input [47:0] data;       // 48-bit DLLP body
        integer      byte_idx;  // loop: 0..5 (6 bytes)
        integer      bit_idx;   // loop: 7..0 (MSB first per byte)
        reg [15:0]   crc;       // working CRC register
        reg          data_bit;  // current data bit
        reg          xor_flag;  // feedback bit
        reg [7:0]    cur_byte;  // current byte being processed
        begin
            crc = 16'hFFFF;     // CRC-16 standard initial value

            // Process each byte from MSB of the 48-bit field (byte 5) to LSB (byte 0)
            // byte_idx=5 → data[47:40], byte_idx=4 → data[39:32], ... byte_idx=0 → data[7:0]
            for (byte_idx = 5; byte_idx >= 0; byte_idx = byte_idx - 1) begin
                cur_byte = data[(byte_idx * 8) +: 8];

                // Process each bit MSB first within the byte
                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    data_bit = cur_byte[bit_idx];
                    xor_flag = crc[15] ^ data_bit;   // feedback = MSB of CRC XOR data bit
                    crc      = crc << 1;              // shift left
                    if (xor_flag) begin
                        crc = crc ^ 16'h1021;         // XOR with polynomial
                    end
                end
            end

            calc_crc16 = crc;   // no final XOR inversion (matches TX side)
        end
    endfunction

    // =========================================================================
    // COMBINATIONAL: compute expected CRC from received body
    // This is purely combinational and is sampled in the registered block below.
    // =========================================================================
    wire [15:0] expected_crc = calc_crc16(rx_body);

    // =========================================================================
    // SEQUENTIAL: registered output stage
    //
    // All outputs are registered to:
    //   (a) Eliminate combinational glitches visible on QuestaSim waveform
    //   (b) Ensure stable 1-cycle pulse outputs for downstream modules
    //   (c) Match the 1-cycle latency of other DLL RX path modules
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // ── Reset state ─────────────────────────────────────────────────
            dllp_body      <= 48'd0;
            dllp_crc_ok    <= 1'b0;
            dllp_crc_err   <= 1'b0;
            dllp_valid_out <= 1'b0;
        end else begin
            // ── Default: de-assert all pulse outputs every cycle ─────────────
            // This ensures all outputs are 1-cycle pulses, not sticky
            dllp_crc_ok    <= 1'b0;
            dllp_crc_err   <= 1'b0;
            dllp_valid_out <= 1'b0;
            dllp_body      <= 48'd0;  // body is zero unless CRC passes

            if (dllp_rx_valid) begin
                // ── A DLLP arrived — check its CRC ──────────────────────────
                if (rx_crc == expected_crc) begin
                    // ── CRC PASS ─────────────────────────────────────────────
                    // Forward the body and assert OK + valid
                    dllp_body      <= rx_body;    // pass clean body downstream
                    dllp_crc_ok    <= 1'b1;       // 1-cycle pulse: CRC passed
                    dllp_valid_out <= 1'b1;       // 1-cycle pulse: body is valid
                    // dllp_crc_err stays 0 (default)

                end else begin
                    // ── CRC FAIL ─────────────────────────────────────────────
                    // DLLP is dropped silently per PCIe spec section 7.1.2:
                    // "DLLPs received with CRC errors are discarded silently.
                    //  There is no retry mechanism for DLLPs."
                    dllp_body      <= 48'd0;      // do NOT forward bad data
                    dllp_crc_err   <= 1'b1;       // 1-cycle pulse: CRC failed
                    dllp_valid_out <= 1'b0;       // do NOT assert valid
                    // dllp_crc_ok stays 0 (default)
                end
            end
            // If dllp_rx_valid=0: all outputs stay at default (0) — no action
        end
    end

endmodule
// =============================================================================
// END OF dllp_crc_chk.v
// =============================================================================
