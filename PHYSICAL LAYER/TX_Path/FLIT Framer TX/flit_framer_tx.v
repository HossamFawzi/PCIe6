// =============================================================================
// Module: FLIT Framer TX
// PCIe Gen6 Physical Layer (Mandatory)
// Description: Packs TLPs and DLLPs into 256-byte (2048-bit) FLITs.
//              Adds 2-bit sync header, 12-bit sequence number, 24-bit CRC.
//              Inserts Null FLITs when no data. Zero encoding overhead.
// FLIT structure (256 bytes = 2048 bits):
//   [2047:2036] Sequence Number (12b)
//   [2035:2012] FLIT CRC (24b)
//   [2011:0]    TLP/DLLP payload (2012b usable)
// =============================================================================
module flit_framer_tx (
    input  wire          clk,
    input  wire          rst_n,

    // TLP input (from DLL)
    input  wire [1023:0] tlp_data,
    input  wire          tlp_valid,

    // DLLP input (for credit updates, ACK/NAK)
    input  wire [63:0]   dllp_data,
    input  wire          dllp_valid,

    // FEC parity (informational)
    input  wire [255:0]  fec_parity,

    // Control
    input  wire          flit_mode_en,
    input  wire          link_reset,

    // Output FLIT
    output reg  [2047:0] flit_out,
    output reg           flit_valid,
    output reg  [1:0]    flit_sync_hdr,
    output reg  [11:0]   flit_seq,
    output reg  [23:0]   flit_crc,
    output reg  [3:0]    flit_null_slots
);

// ---------------------------------------------------------------------------
// Sequence number counter (12-bit, wraps 0→4095)
// ---------------------------------------------------------------------------
reg [11:0] seq_cnt;

// ---------------------------------------------------------------------------
// FLIT field offsets
//  [2047:2036] = Seq[11:0]
//  [2035:2012] = CRC[23:0]
//  [2011:0]    = Payload
// ---------------------------------------------------------------------------
localparam SEQ_HI   = 2047;
localparam SEQ_LO   = 2036;
localparam CRC_HI   = 2035;
localparam CRC_LO   = 2012;
localparam PAY_HI   = 2011;
localparam PAY_LO   = 0;

localparam [2011:0] NULL_PAYLOAD = {2012{1'b0}};

// ---------------------------------------------------------------------------
// CRC-24 (CRC-24/LTE: x^24+x^23+x^6+x^5+x+1 → 0x800063)
// ---------------------------------------------------------------------------
function [23:0] crc24_update;
    input [23:0] crc_in;
    input [7:0]  byte_in;
    reg [23:0] crc;
    reg [7:0]  d;
    integer    i;
    begin
        crc = crc_in;
        d   = byte_in;
        for (i = 0; i < 8; i = i+1) begin
            if ((crc[23] ^ d[7]) == 1'b1)
                crc = {crc[22:0], 1'b0} ^ 24'h800063;
            else
                crc = {crc[22:0], 1'b0};
            d = {d[6:0], 1'b0};
        end
        crc24_update = crc;
    end
endfunction

function [23:0] compute_flit_crc;
    input [2047:0] flit_data;
    reg [23:0] crc;
    integer    b;
    begin
        crc = 24'hFFFFFF;
        for (b = 255; b >= 0; b = b-1)
            crc = crc24_update(crc, flit_data[b*8 +: 8]);
        compute_flit_crc = crc ^ 24'hFFFFFF;
    end
endfunction

// ---------------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------------
localparam ST_IDLE = 2'd0;
localparam ST_PACK = 2'd1;
localparam ST_EMIT = 2'd2;

reg [1:0]  state;
reg [10:0] pay_fill;
reg [2011:0] payload_reg;

// Temp registers (replace automatic)
reg [23:0]   crc_tmp;
reg [2047:0] flit_pre_crc;
reg [4:0]    null_timer;    // Throttle for NULL FLIT generation

// ---------------------------------------------------------------------------
// NULL FLIT throttle counter — spec limits continuous NULL FLITs.
// We emit a NULL FLIT only every NULL_INTERVAL cycles of idle.
// ---------------------------------------------------------------------------
localparam NULL_INTERVAL = 16; // tunable

always @(posedge clk or negedge rst_n) begin
    if (!rst_n || link_reset) begin
        state          <= ST_IDLE;
        seq_cnt        <= 12'h0;
        flit_out       <= {2048{1'b0}};
        flit_valid     <= 1'b0;
        flit_sync_hdr  <= 2'b00;
        flit_seq       <= 12'h0;
        flit_crc       <= 24'h0;
        flit_null_slots<= 4'h0;
        payload_reg    <= {2012{1'b0}};
        pay_fill       <= 11'h0;
        crc_tmp        <= 24'h0;
        flit_pre_crc   <= {2048{1'b0}};
        null_timer     <= 5'h0;
    end else begin
        flit_valid <= 1'b0;

        if (!flit_mode_en) begin
            flit_valid <= 1'b0;
            null_timer <= 5'h0;
        end else begin
            case (state)
                ST_IDLE: begin
                    flit_null_slots <= 4'h0;
                    payload_reg     <= {2012{1'b0}};
                    pay_fill        <= 11'h0;
                    if (tlp_valid || dllp_valid) begin
                        null_timer <= 5'h0;
                        state      <= ST_PACK;
                    end else begin
                        // Throttle NULL FLITs — only emit every NULL_INTERVAL cycles
                        if (null_timer == NULL_INTERVAL-1) begin
                            null_timer = 5'h0;
                            crc_tmp = compute_flit_crc({seq_cnt, 24'h0, NULL_PAYLOAD});
                            flit_out       <= {seq_cnt, crc_tmp, NULL_PAYLOAD};
                            flit_crc       <= crc_tmp;
                            flit_sync_hdr  <= 2'b01;
                            flit_seq       <= seq_cnt;
                            seq_cnt        <= seq_cnt + 1'b1;
                            flit_valid     <= 1'b1;
                            flit_null_slots<= 4'hF;
                        end else begin
                            null_timer <= null_timer + 1'b1;
                        end
                    end
                end

                ST_PACK: begin
                    // Pack TLP at bits [2011:988] (1024b slot)
                    if (tlp_valid && pay_fill == 0) begin
                        payload_reg[2011:988] <= tlp_data;
                        pay_fill <= 11'd1024;
                    end
                    // Pack DLLP at bits [987:924] (64b slot) — only if TLP already loaded
                    // and there is room (2012 - 1024 - 64 = 924 bits remaining)
                    if (dllp_valid && pay_fill == 11'd1024) begin
                        payload_reg[987:924] <= dllp_data;
                        pay_fill <= pay_fill + 11'd64;
                    end
                    state <= ST_EMIT;
                end

                ST_EMIT: begin
                    flit_pre_crc = {seq_cnt, 24'h0, payload_reg};
                    crc_tmp      = compute_flit_crc(flit_pre_crc);
                    flit_out     <= {seq_cnt, crc_tmp, payload_reg};
                    flit_crc     <= crc_tmp;
                    flit_sync_hdr   <= 2'b01;
                    flit_seq        <= seq_cnt;
                    seq_cnt         <= seq_cnt + 1'b1;
                    flit_valid      <= 1'b1;
                    flit_null_slots <= 4'h0;
                    state           <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
end

endmodule
