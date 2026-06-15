//============================================================
// PCIe 6.0 Physical Link Layer
// Module: flit_deframer_rx
// FLIT Deframer RX
//
// flit_in[2303:0] field map
//   [2303:2048]  FEC parity      (256b) — stripped, cross-checked
//                                         against fec_syndrome port
//   [2047:2016]  FLIT CRC-32     (32b)  — CRC-32/MPEG-2 over [2015:0]
//   [2015:2004]  Sequence number (12b)  -> flit_seq
//   [2003:2000]  FLIT type       (4b)
//                  4'h0 = Null
//                  4'h1 = Data   (TLP + DLLP)
//                  4'h2 = TLP-only
//                  4'h3 = DLLP-only
//                  others -> flit_sync_err
//   [1999:1936]  DLLP payload    (64b)  -> dllp_out
//   [1935:912]   TLP payload     (1024b)-> tlp_out
//   [911:0]      Reserved        (912b)
//
// flit_crc_err  : computed CRC != stored CRC
// flit_null     : FLIT type == 4'h0
// flit_sync_err : invalid FLIT type OR uncorrectable FEC error
//                 (fec_syndrome != 0 and fec_corrected == 0)
// tlp_valid     : type in {1,2} AND no CRC error AND flit_valid AND flit_mode_en
// dllp_valid    : type in {1,3} AND no CRC error AND flit_valid AND flit_mode_en
//
// CRC-32/MPEG-2 : poly=0x04C11DB7, init=0xFFFFFFFF,
//                 no reflection, no final XOR
//============================================================
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

    // -----------------------------------------------------------------
    // CRC-32/MPEG-2 over flit_in[2015:0] (2016 bits, MSB-first)
    // Poly=0x04C11DB7, Init=0xFFFFFFFF, RefIn=false, RefOut=false,
    // XorOut=0x00000000
    // -----------------------------------------------------------------
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

    // -----------------------------------------------------------------
    // Combinational field extraction
    // -----------------------------------------------------------------
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

    // -----------------------------------------------------------------
    // Registered outputs
    // -----------------------------------------------------------------
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
