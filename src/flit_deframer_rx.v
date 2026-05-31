
module flit_deframer_rx (
    input  wire           clk,
    input  wire           rst_n,
    input  wire [2303:0]  flit_in,
    input  wire           flit_valid,
    input  wire           fec_corrected,
    input  wire [255:0]   fec_syndrome,
    input  wire           flit_mode_en,
    output reg  [1023:0]  tlp_out,
    output reg            tlp_valid,
    output reg  [63:0]    dllp_out,
    output reg            dllp_valid,
    output reg  [11:0]    flit_seq,
    output reg            flit_crc_err,
    output reg            flit_null,
    output reg            flit_sync_err
);

    localparam [3:0] FTYPE_NULL = 4'h0;
    localparam [3:0] FTYPE_DATA = 4'h1;
    localparam [3:0] FTYPE_TLP  = 4'h2;
    localparam [3:0] FTYPE_DLLP = 4'h3;

    function [31:0] crc32_mpeg2;
        input [2015:0] data;
        reg   [31:0]   crc;
        integer        i;
        begin
            crc = 32'hFFFF_FFFF;
            for (i = 2015; i >= 0; i = i - 1) begin
                if (crc[31] ^ data[i])
                    crc = {crc[30:0], 1'b0} ^ 32'h04C1_1DB7;
                else
                    crc = {crc[30:0], 1'b0};
            end
            crc32_mpeg2 = crc;
        end
    endfunction

    wire [255:0]  fec_embedded    = flit_in[2303:2048];
    wire [31:0]   crc_stored      = flit_in[2047:2016];
    wire [11:0]   seq_w           = flit_in[2015:2004];
    wire [3:0]    ftype_w         = flit_in[2003:2000];
    wire [63:0]   dllp_w          = flit_in[1999:1936];
    wire [1023:0] tlp_w           = flit_in[1935:912];

    wire [31:0]   crc_calc        = crc32_mpeg2(flit_in[2015:0]);

    wire          crc_ok          = (crc_calc == crc_stored);
    wire          fec_error       = (fec_syndrome != 256'h0) && !fec_corrected;
    wire          type_invalid    = (ftype_w != FTYPE_NULL) &&
                                    (ftype_w != FTYPE_DATA) &&
                                    (ftype_w != FTYPE_TLP)  &&
                                    (ftype_w != FTYPE_DLLP);

    wire          tlp_present     = (ftype_w == FTYPE_DATA) || (ftype_w == FTYPE_TLP);
    wire          dllp_present    = (ftype_w == FTYPE_DATA) || (ftype_w == FTYPE_DLLP);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_out       <= 1024'h0;
            tlp_valid     <= 1'b0;
            dllp_out      <= 64'h0;
            dllp_valid    <= 1'b0;
            flit_seq      <= 12'h0;
            flit_crc_err  <= 1'b0;
            flit_null     <= 1'b0;
            flit_sync_err <= 1'b0;
        end else if (flit_valid && flit_mode_en) begin

            flit_seq      <= seq_w;
            flit_crc_err  <= !crc_ok;
            flit_null     <= (ftype_w == FTYPE_NULL);
            flit_sync_err <= type_invalid | fec_error;

            if (tlp_present && crc_ok && !type_invalid && !fec_error) begin
                tlp_out   <= tlp_w;
                tlp_valid <= 1'b1;
            end else begin
                tlp_out   <= 1024'h0;
                tlp_valid <= 1'b0;
            end

            if (dllp_present && crc_ok && !type_invalid && !fec_error) begin
                dllp_out   <= dllp_w;
                dllp_valid <= 1'b1;
            end else begin
                dllp_out   <= 64'h0;
                dllp_valid <= 1'b0;
            end

        end else begin
            tlp_valid     <= 1'b0;
            dllp_valid    <= 1'b0;
            flit_crc_err  <= 1'b0;
            flit_null     <= 1'b0;
            flit_sync_err <= 1'b0;
        end
    end

endmodule
