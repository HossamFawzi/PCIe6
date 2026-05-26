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
    output reg           crc_ok,
    output reg           crc_err,
    output reg  [1023:0] tlp_clean,
    output reg           tlp_clean_valid,
    output reg  [11:0]   seq_rx
);

    wire [11:0]  rx_seq  = tlp_rx[1055:1044];
    wire [991:0] rx_body = tlp_rx[1023:32];
    wire [31:0]  rx_crc  = tlp_rx[31:0];

    function [31:0] calc_crc32;
        input [991:0] data;
        integer       byte_idx;
        integer       bit_idx;
        reg [31:0]    crc;
        reg           data_bit;
        reg           xor_flag;
        reg [7:0]     cur_byte;
        begin
            crc = 32'hFFFF_FFFF;
            for (byte_idx = 123; byte_idx >= 0; byte_idx = byte_idx - 1) begin
                cur_byte = data[(byte_idx * 8) +: 8];
                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    data_bit = cur_byte[bit_idx];
                    xor_flag = crc[31] ^ data_bit;
                    crc      = crc << 1;
                    if (xor_flag) crc = crc ^ 32'h04C1_1DB7;
                end
            end
            calc_crc32 = crc;
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
                seq_rx <= rx_seq;
                if (rx_crc == expected_crc) begin
                    tlp_clean       <= {rx_body, 32'd0};
                    tlp_clean_valid <= 1'b1;
                    crc_ok          <= 1'b1;
                end else begin
                    crc_err <= 1'b1;
                end
            end
        end
    end

endmodule