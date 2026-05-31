
`timescale 1ns/1ps

module dllp_crc_chk (

    input  wire         clk,
    input  wire         rst_n,

    input  wire [63:0]  dllp_raw,
    input  wire         dllp_rx_valid,

    output reg  [47:0]  dllp_body,
    output reg          dllp_crc_ok,
    output reg          dllp_crc_err,
    output reg          dllp_valid_out
);

    wire [15:0] rx_crc       = dllp_raw[63:48];
    wire [47:0] rx_body      = dllp_raw[47:0];

    function [15:0] calc_crc16;
        input [47:0] data;
        integer      byte_idx;
        integer      bit_idx;
        reg [15:0]   crc;
        reg          data_bit;
        reg          xor_flag;
        reg [7:0]    cur_byte;
        begin
            crc = 16'hFFFF;

            for (byte_idx = 5; byte_idx >= 0; byte_idx = byte_idx - 1) begin
                cur_byte = data[(byte_idx * 8) +: 8];

                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    data_bit = cur_byte[bit_idx];
                    xor_flag = crc[15] ^ data_bit;
                    crc      = crc << 1;
                    if (xor_flag) begin
                        crc = crc ^ 16'h1021;
                    end
                end
            end

            calc_crc16 = crc;
        end
    endfunction

    wire [15:0] expected_crc = calc_crc16(rx_body);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            dllp_body      <= 48'd0;
            dllp_crc_ok    <= 1'b0;
            dllp_crc_err   <= 1'b0;
            dllp_valid_out <= 1'b0;
        end else begin

            dllp_crc_ok    <= 1'b0;
            dllp_crc_err   <= 1'b0;
            dllp_valid_out <= 1'b0;
            dllp_body      <= 48'd0;

            if (dllp_rx_valid) begin

                if (rx_crc == expected_crc) begin

                    dllp_body      <= rx_body;
                    dllp_crc_ok    <= 1'b1;
                    dllp_valid_out <= 1'b1;

                end else begin

                    dllp_body      <= 48'd0;
                    dllp_crc_err   <= 1'b1;
                    dllp_valid_out <= 1'b0;

                end
            end

        end
    end

endmodule
