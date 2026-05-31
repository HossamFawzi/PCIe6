
`timescale 1ns/1ps

module lcrc_flit_crc_chk (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1055:0] tlp_rx,
    input  wire          tlp_rx_valid,
    input  wire          flit_mode_en,
    input  wire [11:0]   flit_seq_in,
    output reg           crc_ok,
    output reg           crc_err,
    output reg  [1023:0] tlp_clean,
    output reg           tlp_clean_valid,
    output reg  [11:0]   seq_rx
);

    wire [11:0]   rx_seq  = tlp_rx[1055:1044];
    wire [1023:0] rx_body = tlp_rx[1055:32];
    wire [31:0]   rx_crc  = tlp_rx[31:0];

    function [31:0] calc_crc32;
        input [1023:0] data;
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
            calc_crc32 = ~crc;
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

                    seq_rx          <= flit_seq_in;
                    tlp_clean       <= tlp_rx[1023:0];
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