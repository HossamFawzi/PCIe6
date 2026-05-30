// ============================================================
//  PCIe Gen6 — Data Link Layer
//  Module  : DLLP CRC Generator  (DLLP_CRCG)
//  Tag     : DLLP_CRCG
//  Group   : TX Path  |  Gen6 New
//
//  Function:
//    Computes a 16-bit CRC-CCITT (polynomial x^16+x^12+x^5+1,
//    i.e. 0x1021) over the 48-bit DLLP body.
//    The CRC is appended to produce a 64-bit "full DLLP"
//    that downstream modules (DLLP_ARB, TX_MUX) can forward
//    directly to the PHY.
//
//  Latency optimisation (graduation project):
//    • Single-cycle combinational CRC — no pipeline stages.
//    • Output registered only by the 1-cycle flop that samples
//      dllp_valid_in, so total latency = 1 clock cycle.
//    • Parallel CRC-16 look-up matrix (Galois-form unrolling)
//      keeps combinational depth to O(log2 48) gate levels.
//
//  Port list (matches reference HTML exactly):
//    Inputs : dllp_in[47:0], dllp_valid_in, clk, rst_n
//    Outputs: dllp_crc[15:0], dllp_crc_valid, dllp_full[63:0]
// ============================================================
`timescale 1ns/1ps

module dllp_crc_gen (
    input  wire        clk,
    input  wire        rst_n,

    // Inputs
    input  wire [47:0] dllp_in,
    input  wire        dllp_valid_in,

    // Outputs
    output reg  [15:0] dllp_crc,
    output reg         dllp_crc_valid,
    output reg  [63:0] dllp_full
);

    // ----------------------------------------------------------
    // CRC-16/CCITT  (poly = 0x1021, init = 0xFFFF, no reflect)
    // Parallel implementation — compute all 16 output bits from
    // the 48-bit input in one combinational pass.
    // ----------------------------------------------------------
    function [15:0] crc16_ccitt;
        input [47:0] data;
        integer      i;
        reg   [15:0] crc;
        begin
            crc = 16'hFFFF;             // initialisation
            for (i = 47; i >= 0; i = i - 1) begin
                if ((crc[15]) ^ data[i])
                    crc = {crc[14:0], 1'b0} ^ 16'h1021;
                else
                    crc = {crc[14:0], 1'b0};
            end
            crc16_ccitt = crc;
        end
    endfunction

    // ----------------------------------------------------------
    // Wire: combinational CRC result
    // ----------------------------------------------------------
    wire [15:0] crc_comb;
    assign crc_comb = crc16_ccitt(dllp_in);

    // ----------------------------------------------------------
    // Output register — 1 clock latency
    // ----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dllp_crc       <= 16'h0000;
            dllp_crc_valid <= 1'b0;
            dllp_full      <= 64'h0;
        end else begin
            dllp_crc_valid <= dllp_valid_in;
            if (dllp_valid_in) begin
                dllp_crc  <= crc_comb;
                // Full DLLP = [47:0] body || [15:0] CRC
                dllp_full <= {crc_comb, dllp_in}; // BUG FIX: CRC at [63:48] per dllp_crc_chk spec
            end
        end
    end

endmodule
