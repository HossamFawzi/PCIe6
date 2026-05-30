// =============================================================================
// Module  : pam4_gray_enc
// BUG-13 FIX: Bypass mode now passes all 256 bits correctly.
//             In PAM4 mode: 256 binary bits → 128 two-bit Gray symbols (correct)
//             In bypass mode: pass data_in[255:0] unmodified as 256-bit output.
//             Output port widened to 256 bits; top-level must use [127:0] for
//             Gen6 PAM4 and [255:0] for Gen1-5 NRZ.
// =============================================================================
`timescale 1ns/1ps
module pam4_gray_enc (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [255:0]  data_in,
    input  wire          data_valid,
    input  wire          pam4_en,
    output reg  [255:0]  pam4_symbols,  // [255:128] used Gen1-5; [127:0] used Gen6 PAM4
    output reg           pam4_valid
);

    function [1:0] bin2gray;
        input [1:0] bin;
        begin
            bin2gray[1] = bin[1];
            bin2gray[0] = bin[1] ^ bin[0];
        end
    endfunction

    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin
            pam4_symbols <= 256'b0;
            pam4_valid   <= 1'b0;
        end else begin
            pam4_valid <= data_valid;
            if (data_valid) begin
                if (pam4_en) begin
                    // Gray-encode all 128 two-bit symbols from data_in[255:0]
                    // Output occupies lower 128 bits; upper 128 are zero in PAM4 mode
                    pam4_symbols[255:128] <= 128'b0;
                    for (k = 0; k < 128; k = k + 1)
                        pam4_symbols[2*k +: 2] <= bin2gray(data_in[2*k +: 2]);
                end else begin
                    // BUG-13 FIX: bypass passes full 256-bit word unchanged (Gen1-5 NRZ)
                    pam4_symbols <= data_in;
                end
            end
        end
    end
endmodule
