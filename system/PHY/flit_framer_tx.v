// =============================================================================
// Module: FLIT Framer TX   (FIXED — BUG-1 layout + BUG-4 DLLP packing)
// PCIe Gen6 Physical Layer
//
// FLIT layout (2048 bits):
//   [2047:2016]  CRC-32/MPEG-2  (32b)  over bits [2015:0]
//   [2015:2004]  Sequence number (12b)
//   [2003:2000]  FLIT type       (4b): 0=Null,1=Data,2=TLP-only,3=DLLP-only
//   [1999:1936]  DLLP payload    (64b)
//   [1935: 912]  TLP payload    (1024b)
//   [ 911:   0]  Reserved/pad   (912b)
//
// FIX-CRC: compute_crc32 now uses identical bit-MSB-first loop as
//          flit_deframer_rx and flit_rx_deframer (iterates i from 2015
//          down to 0, testing data[i]).  The old byte-oriented loop
//          (b=251 downto 0, data[b*8+:8]) produced a different bit order
//          and caused every TX CRC to mismatch the RX check.
// =============================================================================
`timescale 1ns/1ps
module flit_framer_tx (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1023:0] tlp_data,
    input  wire          tlp_valid,
    input  wire [63:0]   dllp_data,
    input  wire          dllp_valid,
    input  wire [255:0]  fec_parity,
    input  wire          flit_mode_en,
    input  wire          link_reset,
    output reg  [2047:0] flit_out,
    output reg           flit_valid,
    output reg  [1:0]    flit_sync_hdr,
    output reg  [11:0]   flit_seq,
    output reg  [31:0]   flit_crc,
    output reg  [3:0]    flit_null_slots
);

reg [11:0] seq_cnt;

localparam [3:0] FTYPE_NULL = 4'h0;
localparam [3:0] FTYPE_DATA = 4'h1;
localparam [3:0] FTYPE_TLP  = 4'h2;
localparam [3:0] FTYPE_DLLP = 4'h3;

// ---------------------------------------------------------------------------
// CRC-32/MPEG-2: poly=0x04C11DB7, init=0xFFFFFFFF, no reflection, no final XOR
// FIX: iterate MSB-first (i=2015 downto 0) — identical to flit_deframer_rx
//      so TX-generated CRC always matches RX-computed CRC.
// ---------------------------------------------------------------------------
function [31:0] crc32_mpeg2;
    input [2015:0] data;
    reg [31:0] crc;
    integer i;
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

localparam ST_IDLE=3'd0, ST_PACK_TLP=3'd1, ST_PACK_DLLP=3'd2,
           ST_EMIT=3'd3, ST_NULL=3'd4;
reg [2:0] state;
reg [1023:0] tlp_reg;
reg [63:0]   dllp_reg;
reg has_tlp, has_dllp;
localparam [4:0] NULL_INTERVAL=5'd16;
reg [4:0] null_timer;
reg [31:0]   crc_tmp;
reg [2015:0] crc_input;
reg [3:0]    ftype_tmp;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n||link_reset) begin
        state<=ST_IDLE; seq_cnt<=12'h0;
        flit_out<={2048{1'b0}}; flit_valid<=1'b0;
        flit_sync_hdr<=2'b00; flit_seq<=12'h0;
        flit_crc<=32'h0; flit_null_slots<=4'h0;
        tlp_reg<={1024{1'b0}}; dllp_reg<=64'h0;
        has_tlp<=1'b0; has_dllp<=1'b0; null_timer<=5'h0;
    end else begin
        flit_valid<=1'b0;
        if(!flit_mode_en) begin state<=ST_IDLE; null_timer<=5'h0; end
        else case(state)
            ST_IDLE: begin
                has_tlp<=1'b0; has_dllp<=1'b0; flit_null_slots<=4'h0;
                if(tlp_valid||dllp_valid) begin null_timer<=5'h0; state<=ST_PACK_TLP; end
                else if(null_timer==NULL_INTERVAL-1) begin null_timer<=5'h0; state<=ST_NULL; end
                else null_timer<=null_timer+1'b1;
            end
            ST_PACK_TLP: begin
                if(tlp_valid) begin tlp_reg<=tlp_data; has_tlp<=1'b1; end
                state<=ST_PACK_DLLP;
            end
            ST_PACK_DLLP: begin
                if(dllp_valid) begin dllp_reg<=dllp_data; has_dllp<=1'b1; end
                state<=ST_EMIT;
            end
            ST_EMIT: begin
                if(has_tlp&&has_dllp) ftype_tmp=FTYPE_DATA;
                else if(has_tlp)      ftype_tmp=FTYPE_TLP;
                else if(has_dllp)     ftype_tmp=FTYPE_DLLP;
                else                  ftype_tmp=FTYPE_NULL;
                crc_input={seq_cnt, ftype_tmp,
                           (has_dllp?dllp_reg:64'h0),
                           (has_tlp?tlp_reg:{1024{1'b0}}),
                           912'h0};
                crc_tmp=crc32_mpeg2(crc_input);
                flit_out<={crc_tmp,crc_input};
                flit_crc<=crc_tmp; flit_seq<=seq_cnt;
                flit_sync_hdr<=2'b01; flit_valid<=1'b1;
                flit_null_slots<=(ftype_tmp==FTYPE_NULL)?4'hF:4'h0;
                seq_cnt<=seq_cnt+1'b1;
                has_tlp<=1'b0; has_dllp<=1'b0; state<=ST_IDLE;
            end
            ST_NULL: begin
                crc_input={seq_cnt,FTYPE_NULL,64'h0,{1024{1'b0}},912'h0};
                crc_tmp=crc32_mpeg2(crc_input);
                flit_out<={crc_tmp,crc_input}; flit_crc<=crc_tmp;
                flit_seq<=seq_cnt; flit_sync_hdr<=2'b01;
                flit_valid<=1'b1; flit_null_slots<=4'hF;
                seq_cnt<=seq_cnt+1'b1; state<=ST_IDLE;
            end
            default: state<=ST_IDLE;
        endcase
    end
end
endmodule
