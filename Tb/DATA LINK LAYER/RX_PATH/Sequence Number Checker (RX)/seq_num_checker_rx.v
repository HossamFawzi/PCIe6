// =============================================================================
// Module  : seq_num_checker_rx
// Layer   : Data Link Layer (DLL) — RX Path
// Spec    : PCIe Gen6 Base Specification r1.0 — Section 3.5.2
// Tag     : SEQ_CHK (RX)
//
// Position in RX datapath:
//   FLIT Rx Deframer → LCRC/FLIT CRC Checker → [THIS] → ACK/NAK Scheduler
//
// Description:
//   Verifies that every received TLP arrives with the expected 12-bit sequence
//   number.  The PCIe DLL RX sequence number rule (§3.5.2) is:
//
//     expected_seq = (last_good_seq + 1) mod 4096
//
//   Three outcomes are possible for each received TLP:
//
//   1. seq_rx == expected_seq  →  GOOD
//        - tlp_seq_ok asserted, TLP forwarded, expected_seq advances.
//
//   2. seq_rx == expected_seq - 1 (duplicate)  →  DUPLICATE
//        - Same TLP re-sent after a spurious NAK/replay.
//        - tlp_dup asserted, TLP silently dropped, expected_seq unchanged.
//        - A fresh ACK is generated (seq_dup_ack out).
//
//   3. Any other value  →  SEQ ERROR
//        - tlp_seq_err asserted, TLP dropped, nak_req raised.
//        - seq_err_val carries the offending received sequence number.
//
//   CRC-failed TLPs (tlp_ok=0) bypass sequence checking entirely — the
//   NAK for a bad CRC is handled by ACK_TX reacting to crc_err; the
//   sequence counter is not advanced.
//
//   On link_reset:  expected_seq resets to 12'h000 (spec §3.5.1).
// =============================================================================

module seq_num_checker_rx (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          link_reset,       // DLL link reset (sync, active-high)

    // ── From LCRC / FLIT CRC Checker ─────────────────────────────────────────
    input  wire [11:0]   seq_rx,           // received 12-bit sequence number
    input  wire          tlp_rx_valid,     // new TLP present on bus
    input  wire          tlp_ok,           // CRC check passed (crc_ok)
    input  wire [1023:0] tlp_clean,        // CRC-verified TLP payload

    // ── To ACK / NAK Scheduler (ACK_TX) ──────────────────────────────────────
    output reg           tlp_seq_ok,       // sequence correct → forward + ACK
    output reg           tlp_dup,          // duplicate sequence → re-ACK, drop
    output reg           tlp_seq_err,      // sequence error → NAK, drop
    output reg           nak_req,          // request NAK transmission
    output reg           seq_dup_ack,      // request re-ACK of duplicate seq
    output reg  [11:0]   seq_err_val,      // offending seq number (on error)
    output reg  [11:0]   next_expected,    // expected_seq register (debug/ACK)

    // ── Forwarded TLP to upper DLL / TL ──────────────────────────────────────
    output reg  [1023:0] tlp_fwd,
    output reg           tlp_fwd_valid
);

    // ── 12-bit modular arithmetic helpers ─────────────────────────────────────
    wire [11:0] expected_seq = next_expected;
    wire [11:0] prev_seq     = expected_seq - 12'd1;  // wraps naturally in 12-bit

    // ── Main registered logic ─────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || link_reset) begin
            next_expected <= 12'h000;
            tlp_seq_ok    <= 1'b0;
            tlp_dup       <= 1'b0;
            tlp_seq_err   <= 1'b0;
            nak_req       <= 1'b0;
            seq_dup_ack   <= 1'b0;
            seq_err_val   <= 12'h000;
            tlp_fwd       <= 1024'b0;
            tlp_fwd_valid <= 1'b0;
        end else begin
            // ── Defaults: clear all pulse outputs ─────────────────────────────
            tlp_seq_ok    <= 1'b0;
            tlp_dup       <= 1'b0;
            tlp_seq_err   <= 1'b0;
            nak_req       <= 1'b0;
            seq_dup_ack   <= 1'b0;
            seq_err_val   <= 12'h000;
            tlp_fwd_valid <= 1'b0;

            if (tlp_rx_valid && tlp_ok) begin
                // Only inspect sequence for CRC-clean TLPs
                if (seq_rx == expected_seq) begin
                    // ── GOOD: expected sequence ───────────────────────────────
                    tlp_seq_ok    <= 1'b1;
                    tlp_fwd       <= tlp_clean;
                    tlp_fwd_valid <= 1'b1;
                    next_expected <= expected_seq + 12'd1;   // wraps mod 4096

                end else if (seq_rx == prev_seq) begin
                    // ── DUPLICATE: retransmitted TLP (spec §3.5.2) ───────────
                    tlp_dup     <= 1'b1;
                    seq_dup_ack <= 1'b1;
                    // expected_seq unchanged; TLP dropped (no fwd)

                end else begin
                    // ── SEQUENCE ERROR ────────────────────────────────────────
                    tlp_seq_err <= 1'b1;
                    nak_req     <= 1'b1;
                    seq_err_val <= seq_rx;
                    // expected_seq unchanged; TLP dropped
                end
            end
            // tlp_rx_valid=0 or tlp_ok=0: all outputs stay at default (0)
        end
    end

endmodule
