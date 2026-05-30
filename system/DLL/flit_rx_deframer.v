// =============================================================================
// Module  : flit_rx_deframer
// Layer   : Data Link Layer (DLL) — RX Path
// BUG-1 FIX: Field layout and CRC algorithm now EXACTLY match flit_deframer_rx
//   FLIT layout (2048 bits):
//     [2047:2016]  CRC-32/MPEG-2  (32b) over bits [2015:0]
//     [2015:2004]  Sequence number (12b)
//     [2003:2000]  FLIT type       (4b): 0=Null,1=Data(TLP+DLLP),2=TLP-only,3=DLLP-only
//     [1999:1936]  DLLP payload   (64b)
//     [1935: 912]  TLP  payload  (1024b)
//     [ 911:   0]  Reserved       (912b)
//   Previously used CRC-24 with old field positions — every FLIT failed CRC.
// =============================================================================
`timescale 1ns/1ps
module flit_rx_deframer (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [2047:0] rx_flit,
    input  wire          rx_flit_valid,
    input  wire [15:0]   fec_syndrome,
    input  wire          fec_corrected,
    output reg  [1023:0] flit_tlp,
    output reg           flit_tlp_valid,
    output reg  [63:0]   flit_dllp,
    output reg           flit_dllp_valid,
    output reg  [11:0]   flit_seq,
    output reg           flit_crc_err,
    output reg           flit_null,
    output reg           flit_uncorr_err
);
    localparam [3:0] FTYPE_NULL=4'h0, FTYPE_DATA=4'h1, FTYPE_TLP=4'h2, FTYPE_DLLP=4'h3;

    function [31:0] crc32_mpeg2;
        input [2015:0] data; reg [31:0] crc; integer i;
        begin
            crc=32'hFFFF_FFFF;
            for(i=2015;i>=0;i=i-1) begin
                if(crc[31]^data[i]) crc={crc[30:0],1'b0}^32'h04C1_1DB7;
                else                crc={crc[30:0],1'b0};
            end
            crc32_mpeg2=crc;
        end
    endfunction

    wire [31:0]   rx_crc  = rx_flit[2047:2016];
    wire [11:0]   rx_seq  = rx_flit[2015:2004];
    wire [3:0]    rx_type = rx_flit[2003:2000];
    wire [63:0]   rx_dllp = rx_flit[1999:1936];
    wire [1023:0] rx_tlp  = rx_flit[1935:912];

    wire [31:0] crc_calc = crc32_mpeg2(rx_flit[2015:0]);
    wire        crc_ok   = (crc_calc == rx_crc);
    wire        uncorr   = (fec_syndrome != 16'h0) && !fec_corrected;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_tlp<=1024'b0; flit_tlp_valid<=0; flit_dllp<=64'b0;
            flit_dllp_valid<=0; flit_seq<=12'b0; flit_crc_err<=0;
            flit_null<=0; flit_uncorr_err<=0;
        end else begin
            flit_tlp_valid<=0; flit_dllp_valid<=0;
            flit_crc_err<=0;   flit_null<=0; flit_uncorr_err<=0;
            if (rx_flit_valid) begin
                flit_seq        <= rx_seq;
                flit_uncorr_err <= uncorr;
                if (!crc_ok) begin
                    flit_crc_err <= 1'b1;
                end else if (!uncorr) begin
                    flit_null       <= (rx_type==FTYPE_NULL);
                    flit_tlp        <= rx_tlp;
                    flit_dllp       <= rx_dllp;
                    flit_tlp_valid  <= (rx_type==FTYPE_DATA)||(rx_type==FTYPE_TLP);
                    flit_dllp_valid <= (rx_type==FTYPE_DATA)||(rx_type==FTYPE_DLLP);
                end
            end
        end
    end
endmodule
