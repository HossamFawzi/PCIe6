
module crc_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [1023:0] tlp_in,
    input  wire          tlp_valid,

    input  wire [2047:0] flit_in,
    input  wire          flit_valid,

    input  wire          flit_mode_en,

    input  wire [11:0]   seq_num,

    output reg  [31:0]   lcrc_out,
    output reg  [23:0]   flit_crc_out,
    output reg           crc_valid
);

    function automatic [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0]  data_in;
        reg   [31:0] crc;
        integer      i;
        begin
            crc = crc_in;

            for (i = 0; i < 8; i = i + 1) begin
                if ((crc[0]) ^ data_in[i])
                    crc = (crc >> 1) ^ 32'hEDB88320;
                else
                    crc = crc >> 1;
            end
            crc32_byte = crc;
        end
    endfunction

    function automatic [31:0] calc_lcrc;
        input [1023:0] data;
        reg   [31:0]   crc;
        integer        b;
        begin
            crc = 32'hFFFF_FFFF;
            for (b = 0; b < 128; b = b + 1) begin

                crc = crc32_byte(crc, data[b*8 +: 8]);
            end
            calc_lcrc = ~crc;
        end
    endfunction

    localparam [23:0] CRC24_POLY = 24'h864CFB;
    localparam [23:0] CRC24_SEED = 24'hB704CE;

    function automatic [23:0] crc24_byte;
        input [23:0] crc_in;
        input [7:0]  data_in;
        reg   [23:0] crc;
        integer      i;
        begin
            crc = crc_in;
            for (i = 7; i >= 0; i = i - 1) begin
                if (crc[23] ^ data_in[i])
                    crc = (crc << 1) ^ CRC24_POLY;
                else
                    crc = crc << 1;
            end
            crc24_byte = crc;
        end
    endfunction

    function automatic [23:0] calc_flit_crc;
        input [2047:0] flit;
        input [11:0]   seq;
        reg   [23:0]   crc;
        integer        b;
        begin
            crc = CRC24_SEED;

            crc = crc24_byte(crc, {4'h0, seq[11:8]});
            crc = crc24_byte(crc, seq[7:0]);

            for (b = 255; b >= 0; b = b - 1) begin

                crc = crc24_byte(crc, flit[b*8 +: 8]);
            end
            calc_flit_crc = crc;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lcrc_out     <= 32'h0;
            flit_crc_out <= 24'h0;
            crc_valid    <= 1'b0;
        end else begin
            crc_valid <= 1'b0;

            if (!flit_mode_en && tlp_valid) begin

                lcrc_out  <= calc_lcrc(tlp_in);
                crc_valid <= 1'b1;
            end else if (flit_mode_en && flit_valid) begin

                flit_crc_out <= calc_flit_crc(flit_in, seq_num);
                crc_valid    <= 1'b1;
            end
        end
    end

endmodule
