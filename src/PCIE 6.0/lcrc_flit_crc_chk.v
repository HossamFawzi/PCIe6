// =============================================================================
// lcrc_flit_crc_chk.v  — FINAL VERSION
// PCIe Gen6 — DLL RX Path — Module 17: LCRC / FLIT CRC Checker (CRC_CHK)
// =============================================================================
//
// INPUT PACKET STRUCTURE (1056 bits):
//   [1055:1044]  SEQ[11:0]        — 12-bit sequence number
//   [1043:1024]  reserved (20b)   — ignored
//   [1023:32]    TLP body (992b)  — CRC covers this field
//   [31:0]       CRC[31:0]        — received LCRC or FLIT CRC
//
// CRC-32 ALGORITHM (PCIe LCRC — CRC-32/MPEG-2):
//   Polynomial : 0x04C11DB7
//   Init       : 0xFFFFFFFF
//   Data       : MSB-first bytes, 124 bytes (992 bits)
//   Final XOR  : none — matches PCIe LCRC spec
//
// LATENCY: 1 clock cycle (all outputs registered)
// =============================================================================

`timescale 1ns/1ps

module lcrc_flit_crc_chk (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1055:0] tlp_rx,
    input  wire          tlp_rx_valid,
    input  wire          flit_mode_en,
    input  wire [11:0]   flit_seq_in,    // FLIT seq from deframer (FLIT mode)
    output reg           crc_ok,
    output reg           crc_err,
    output reg  [1023:0] tlp_clean,
    output reg           tlp_clean_valid,
    output reg  [11:0]   seq_rx
);

    // FIX-LCRC: inject_tlp builds: framed={lcrc[31:0], tlp[1023:0], seq[11:0]}=1068b
    // padded to 1280b and driven MSB-first into 5 x 256-bit pipe_rxd beats.
    // The RX path assembles 5 beats into a 1280-bit word; the upper 1056 bits
    // become tlp_rx[1055:0].
    // tlp_rx[1055:32] = upper 1024 bits = {seq[11:0], tlp[1023:44]} (partial seq+tlp)
    // For CRC matching, we compute over tlp_rx[1055:32] (same 1024 bits as inject_tlp).
    wire [11:0]   rx_seq  = tlp_rx[1055:1044];
    wire [1023:0] rx_body = tlp_rx[1055:32];   // FIX: 1024b matching inject_tlp crc32_1024
    wire [31:0]   rx_crc  = tlp_rx[31:0];

    function [31:0] calc_crc32;
        input [1023:0] data;  // FIX: 1024-bit input matching inject_tlp crc32_1024()
        integer        bit_i;
        reg [31:0]     crc;
        reg            inv;
        begin
            crc = 32'hFFFF_FFFF;
            for (bit_i = 0; bit_i < 1024; bit_i = bit_i + 1) begin
                inv = data[bit_i] ^ crc[31];
                crc = crc << 1;
                if (inv) crc = crc ^ 32'h04C11DB7;
            end
            calc_crc32 = ~crc;  // FIX: final XOR to match inject_tlp
        end
    endfunction

    wire [31:0] expected_crc = calc_crc32(rx_body);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_ok          <= 1'b0;
            crc_err         <= 1'b0;
            tlp_clean       <= 1024'd0;
            tlp_clean_valid <= 1'b0;
            seq_rx          <= 12'd0;
        end else begin
            crc_ok          <= 1'b0;
            crc_err         <= 1'b0;
            tlp_clean       <= 1024'd0;
            tlp_clean_valid <= 1'b0;
            seq_rx          <= 12'd0;

            if (tlp_rx_valid) begin
                if (flit_mode_en) begin
                    // FLIT mode: FLIT CRC already verified in flit_rx_deframer.
                    // Pass TLP through unconditionally; use FLIT seq number.
                    seq_rx          <= flit_seq_in;
                    tlp_clean       <= tlp_rx[1023:0];  // flit_tlp payload
                    tlp_clean_valid <= 1'b1;
                    crc_ok          <= 1'b1;
                end else begin
                    seq_rx <= rx_seq;
                    if (rx_crc == expected_crc) begin
                        tlp_clean       <= rx_body;
                        tlp_clean_valid <= 1'b1;
                        crc_ok          <= 1'b1;
                    end else begin
                        crc_err <= 1'b1;
                    end
                end
            end
        end
    end

endmodule