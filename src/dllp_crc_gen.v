
`timescale 1ns/1ps

module dllp_crc_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [47:0] dllp_in,
    input  wire        dllp_valid_in,

    output reg  [15:0] dllp_crc,
    output reg         dllp_crc_valid,
    output reg  [63:0] dllp_full
);

    function [15:0] crc16_ccitt;
        input [47:0] data;
        integer      i;
        reg   [15:0] crc;
        begin
            crc = 16'hFFFF;
            for (i = 47; i >= 0; i = i - 1) begin
                if ((crc[15]) ^ data[i])
                    crc = {crc[14:0], 1'b0} ^ 16'h1021;
                else
                    crc = {crc[14:0], 1'b0};
            end
            crc16_ccitt = crc;
        end
    endfunction

    wire [15:0] crc_comb;
    assign crc_comb = crc16_ccitt(dllp_in);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dllp_crc       <= 16'h0000;
            dllp_crc_valid <= 1'b0;
            dllp_full      <= 64'h0;
        end else begin
            dllp_crc_valid <= dllp_valid_in;
            if (dllp_valid_in) begin
                dllp_crc  <= crc_comb;

                dllp_full <= {crc_comb, dllp_in};
            end
        end
    end

endmodule
