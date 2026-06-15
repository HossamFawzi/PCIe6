// =============================================================
//  MODULE : td_handler
//  TAG    : TD_HDL  🔴 MUST  ★ GEN6
//  LAYER  : Transaction Layer — Support Group
//  DESC   : TLP Digest (TD) append/strip handler.
//           TX path: if ecrc_en=1 and tlp_td_bit=1, appends
//                    the 32-bit ECRC value as a digest after
//                    the TLP, growing the packet by 1 DW.
//           RX path: if TD bit is set in received TLP,
//                    strips the last 4 bytes and validates.
//           Mismatch → td_err.
//  SPEC   : PCIe 6.0 Base Spec §2.7.1 (TLP Digest / ECRC)
// =============================================================
module td_handler (
    input  wire           clk,
    input  wire           rst_n,

    // ── TX Inputs ─────────────────────────────────────────────
    input  wire [1183:0]  tlp_tx,           // TLP (header + data)
    input  wire           tlp_tx_valid,
    input  wire           tlp_td_bit,       // TD bit from TLP header
    input  wire [31:0]    ecrc_val,         // ECRC computed upstream
    input  wire           ecrc_en,          // Global ECRC enable

    // ── TX Output ─────────────────────────────────────────────
    // tlp_with_digest = tlp_tx[1183:0] + ecrc[31:0] = 1216 bits
    output reg [1215:0]   tlp_with_digest,
    output reg            digest_valid,

    // ── RX strip outputs ──────────────────────────────────────
    // (Reuse same port: when td_bit set, strip last 32-bit DW)
    output reg            td_strip_ok,      // Digest stripped cleanly
    output reg            td_err            // ECRC mismatch on RX
);

    // Internal: saved ecrc for RX compare
    // In a real design the ECRC checker would feed back here.
    // We model a simple pass-through check.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_with_digest <= 1216'h0;
            digest_valid    <= 1'b0;
            td_strip_ok     <= 1'b0;
            td_err          <= 1'b0;
        end
        else begin
            // Defaults
            digest_valid <= 1'b0;
            td_strip_ok  <= 1'b0;
            td_err       <= 1'b0;

            if (tlp_tx_valid) begin
                if (ecrc_en && tlp_td_bit) begin
                    // ── TX: append ECRC digest ────────────────
                    // Shift TLP up by 32 bits, insert ECRC at LSBs
                    tlp_with_digest[1215:32] <= tlp_tx[1183:0];
                    tlp_with_digest[31:0]    <= ecrc_val;
                    digest_valid             <= 1'b1;
                    td_strip_ok              <= 1'b0;
                end
                else if (!ecrc_en && tlp_td_bit) begin
                    // ── RX strip mode: TD bit set, validate ───
                    // In RX mode, tlp_tx carries the received TLP+digest.
                    // Last 32 bits = received ECRC. We compare against
                    // ecrc_val which is the locally computed reference.
                    // If match → strip OK. If mismatch → td_err.
                    if (tlp_tx[31:0] == ecrc_val) begin
                        // Strip the last DW, forward rest
                        tlp_with_digest[1215:1184] <= 32'h0;   // pad top
                        tlp_with_digest[1183:0]    <= tlp_tx[1183:0];
                        td_strip_ok                <= 1'b1;
                    end
                    else begin
                        tlp_with_digest <= 1216'h0;
                        td_err          <= 1'b1;
                    end
                end
                else begin
                    // No digest: pass through unchanged
                    tlp_with_digest[1215:32] <= tlp_tx;
                    tlp_with_digest[31:0]    <= 32'h0;
                    digest_valid             <= 1'b1;
                end
            end
        end
    end

endmodule
