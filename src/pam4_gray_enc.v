
`timescale 1ns/1ps
module pam4_gray_enc (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [255:0]  data_in,
    input  wire          data_valid,
    input  wire          pam4_en,
    output reg  [255:0]  pam4_symbols,
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

                    pam4_symbols[255:128] <= 128'b0;
                    for (k = 0; k < 128; k = k + 1)
                        pam4_symbols[2*k +: 2] <= bin2gray(data_in[2*k +: 2]);
                end else begin

                    pam4_symbols <= data_in;
                end
            end
        end
    end
endmodule
