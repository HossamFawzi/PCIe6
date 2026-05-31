
`timescale 1ns/1ps

module ecrc (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [1151:0] tlp_tx,
    input  wire          tlp_tx_valid,

    input  wire [1151:0] tlp_rx,
    input  wire          tlp_rx_valid,

    input  wire          ecrc_en,

    output reg  [1183:0] tlp_ecrc_tx,
    output reg           tlp_ecrc_valid,

    output wire          ecrc_rx_ok,
    output wire          ecrc_rx_err
);

function [7:0] reflect_byte;
    input [7:0] d;
    integer i;
    begin
        for (i = 0; i < 8; i = i + 1)
            reflect_byte[i] = d[7-i];
    end
endfunction

function [31:0] reflect32;
    input [31:0] d;
    integer i;
    begin
        for (i = 0; i < 32; i = i + 1)
            reflect32[i] = d[31-i];
    end
endfunction

function [31:0] crc32_byte;
    input [31:0] crc_in;
    input [7:0]  data_byte;
    reg   [31:0] crc;
    reg   [7:0]  d;
    integer      i;
    begin
        d   = reflect_byte(data_byte);
        crc = crc_in;
        for (i = 0; i < 8; i = i + 1) begin
            if (crc[31] ^ d[7-i])
                crc = (crc << 1) ^ 32'h04C11DB7;
            else
                crc = crc << 1;
        end
        crc32_byte = crc;
    end
endfunction

function [31:0] crc32_over_header;
    input [127:0] hdr;
    input [31:0]  crc_init;
    reg   [31:0]  c;
    integer       i;
    begin
        c = crc_init;
        for (i = 15; i >= 0; i = i - 1)
            c = crc32_byte(c, hdr[i*8 +: 8]);
        crc32_over_header = c;
    end
endfunction

function [31:0] crc32_over_data;
    input [511:0] dat;
    input [31:0]  crc_init;
    reg   [31:0]  c;
    integer       i;
    begin
        c = crc_init;
        for (i = 63; i >= 0; i = i - 1)
            c = crc32_byte(c, dat[i*8 +: 8]);
        crc32_over_data = c;
    end
endfunction

function [31:0] compute_ecrc;
    input [127:0] hdr;
    input [511:0] data;
    input         has_data;
    reg   [127:0] hdr_masked;
    reg   [31:0]  crc;
    begin
        hdr_masked      = hdr;
        hdr_masked[112] = 1'b0;
        crc = 32'hFFFF_FFFF;
        crc = crc32_over_header(hdr_masked, crc);
        if (has_data)
            crc = crc32_over_data(data, crc);
        compute_ecrc = reflect32(crc) ^ 32'hFFFF_FFFF;
    end
endfunction

wire [127:0] tx_hdr      = tlp_tx[895:768];
wire [511:0] tx_data     = tlp_tx[767:256];
wire         tx_has_data = tlp_tx[893];
wire         tx_td_bit   = tlp_tx[880];

wire [31:0]  tx_ecrc_comb = compute_ecrc(tx_hdr, tx_data, tx_has_data);

wire [127:0] rx_hdr       = tlp_rx[895:768];
wire [511:0] rx_data      = tlp_rx[767:256];
wire         rx_has_data  = tlp_rx[893];
wire         rx_td_bit    = tlp_rx[880];
wire [31:0]  rx_ecrc_rcv  = tlp_rx[255:224];

wire [31:0]  rx_ecrc_cmp  = compute_ecrc(rx_hdr, rx_data, rx_has_data);
wire         rx_ecrc_match = (rx_ecrc_cmp == rx_ecrc_rcv);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tlp_ecrc_tx    <= 1184'd0;
        tlp_ecrc_valid <= 1'b0;
    end else begin
        tlp_ecrc_valid <= 1'b0;
        if (tlp_tx_valid) begin
            tlp_ecrc_tx[1183:1152] <= tlp_tx[1151:1120];
            tlp_ecrc_tx[1151:1056] <= tlp_tx[1119:1024];
            tlp_ecrc_tx[1055:1024] <= tlp_tx[1023:992];
            tlp_ecrc_tx[1023:928]  <= tlp_tx[991:896];
            tlp_ecrc_tx[927:800]   <= tx_hdr;
            tlp_ecrc_tx[912]       <= ecrc_en ? 1'b1 : tx_td_bit;
            tlp_ecrc_tx[799:288]   <= tx_data;
            tlp_ecrc_tx[287:256]   <= ecrc_en ? tx_ecrc_comb : 32'd0;
            tlp_ecrc_tx[255:0]     <= 256'd0;
            tlp_ecrc_valid         <= 1'b1;
        end
    end
end

reg ecrc_rx_ok_r;
reg ecrc_rx_err_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ecrc_rx_ok_r  <= 1'b1;
        ecrc_rx_err_r <= 1'b0;
    end else if (tlp_rx_valid) begin

        ecrc_rx_ok_r  <= !ecrc_en || !rx_td_bit || rx_ecrc_match;
        ecrc_rx_err_r <=  ecrc_en &&  rx_td_bit && !rx_ecrc_match;
    end

end

assign ecrc_rx_ok  = ecrc_rx_ok_r;
assign ecrc_rx_err = ecrc_rx_err_r;

endmodule
