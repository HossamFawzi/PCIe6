// =============================================================================
// tlp_assembler.v
// PCIe Gen6 — TLP Assembler / Packet Builder (TLP_ASM)
// Transaction Layer — TX Path
//
// Spec ref : PCIe 6.0 Base Spec, Section 2.2 (TLP Structure)
//
// Ports (exact from HTML spec):
//   Inputs  : arb_tlp_in[575:0], arb_tlp_valid,
//             prefix_in[127:0],  prefix_valid,
//             ecrc_in[31:0],     credit_ok,
//             max_payload[2:0],  clk, rst_n
//   Outputs : tlp_out[1023:0], tlp_valid,
//             tlp_sop, tlp_eop,
//             tlp_hdr[127:0], tlp_be[127:0]
//
// arb_tlp_in[575:0] layout (from TX Arbiter):
//   [575:512] = 64-bit condensed header info
//   [511:0]   = 512-bit data payload
//
// Header info field decode:
//   [9:0]   = tlp_length_dw   (DW count)
//   [13:10] = tlp_first_be
//   [17:14] = tlp_last_be
//   [18]    = tlp_has_data    (Fmt[1])
//   [19]    = tlp_4dw_hdr    (Fmt[0])
//   [31:20] = type/fmt flags
//   [47:32] = requester ID
//   [55:48] = tag[7:0]
//   [63:32] = address
//
// tlp_out[1023:0] layout:
//   [1023:896] = 128b prefix  (prefix_in if prefix_valid, else 0)
//   [895:768]  = 128b header  DWs
//   [767:256]  = 512b data    (raw_data if has_data, else 0)
//   [255:224]  = 32b  ECRC DW (ecrc_in)
//   [223:0]    = padding / unused
//
// Output is registered. tlp_valid goes high one cycle after
// arb_tlp_valid & credit_ok. SOP=EOP=1 (single-beat packet).
// When credit_ok=0 the packet is held and tlp_valid stays 0.
// =============================================================================

`timescale 1ns/1ps

module tlp_assembler (
    input  wire         clk,
    input  wire         rst_n,

    // ── From TX Arbiter ───────────────────────────────────────────────────────
    input  wire [575:0] arb_tlp_in,
    input  wire         arb_tlp_valid,

    // ── From TLP Prefix Handler ───────────────────────────────────────────────
    input  wire [127:0] prefix_in,
    input  wire         prefix_valid,

    // ── From ECRC Generator ───────────────────────────────────────────────────
    input  wire [31:0]  ecrc_in,

    // ── From Credit Manager ───────────────────────────────────────────────────
    input  wire         credit_ok,

    // ── From Config Space Handler ─────────────────────────────────────────────
    // 000=128B 001=256B 010=512B 011=1KB 100=2KB 101=4KB
    input  wire [2:0]   max_payload,

    // ── Outputs ───────────────────────────────────────────────────────────────
    output reg  [1023:0] tlp_out,
    output reg           tlp_valid,
    output reg           tlp_sop,
    output reg           tlp_eop,
    output reg  [127:0]  tlp_hdr,
    output reg  [127:0]  tlp_be
);

// =============================================================================
// FIELD EXTRACTION
// =============================================================================
wire [63:0]  raw_hdr_info  = arb_tlp_in[575:512];
wire [511:0] raw_data      = arb_tlp_in[511:0];

wire [9:0]   tlp_length_dw = raw_hdr_info[9:0];
wire [3:0]   tlp_first_be  = raw_hdr_info[13:10];
wire [3:0]   tlp_last_be   = raw_hdr_info[17:14];
wire         tlp_has_data  = raw_hdr_info[18];
wire         tlp_4dw_hdr   = raw_hdr_info[19];

// =============================================================================
// MAX PAYLOAD DECODE
// =============================================================================
function [11:0] decode_max_payload;
    input [2:0] mp;
    begin
        case (mp)
            3'd0: decode_max_payload = 12'd128;
            3'd1: decode_max_payload = 12'd256;
            3'd2: decode_max_payload = 12'd512;
            3'd3: decode_max_payload = 12'd1024;
            3'd4: decode_max_payload = 12'd2048;
            3'd5: decode_max_payload = 12'd4096;
            default: decode_max_payload = 12'd128;
        endcase
    end
endfunction

wire [11:0] max_bytes = decode_max_payload(max_payload);

// =============================================================================
// HEADER DW CONSTRUCTION  (combinational)
// DW0: Fmt+Type+flags | has_data | 4dw | Length | 2b reserved
// DW1: Requester ID   | Tag[7:0] | Last BE | First BE
// DW2: Address[63:32] or Address[31:0]
// DW3: Lower address (4DW only), placeholder otherwise
// =============================================================================
reg [127:0] hdr_dws;

always @(*) begin
    hdr_dws = 128'd0;
    // DW0  — BUG-15 FIX: insert T9(bit19) and T8(bit23) of 10-bit tag into DW0
    // raw_hdr_info[55:48] = tag[7:0], raw_hdr_info[57:56] = tag[9:8]
    hdr_dws[31:0]   = {raw_hdr_info[31:24],
                       raw_hdr_info[57],    // T9 → DW0[23] per PCIe Base Spec Table 2-4
                       raw_hdr_info[31:21], // bits 22:20 (Attr[2], EP, TD)
                       raw_hdr_info[56],    // T8 → DW0[19]
                       raw_hdr_info[18],    // has_data
                       raw_hdr_info[19],    // 4dw_hdr
                       tlp_length_dw[9:0],
                       2'b00};
    // DW1 — tag[7:0] stays in DW1[15:8]
    hdr_dws[63:32]  = {raw_hdr_info[47:32],
                       raw_hdr_info[55:48], // tag[7:0]
                       tlp_last_be,
                       tlp_first_be};
    // DW2
    hdr_dws[95:64]  = raw_hdr_info[63:32];
    // DW3
    hdr_dws[127:96] = tlp_4dw_hdr ? 32'hDEAD_C0DE : 32'h0;
end

// =============================================================================
// BYTE ENABLE MASK  (combinational)
// All bytes enabled by default; last DW uses tlp_last_be
// =============================================================================
reg [127:0] be_mask;

always @(*) begin
    be_mask          = {128{1'b1}};
    be_mask[127:124] = tlp_last_be;
end

// =============================================================================
// REGISTERED OUTPUT STAGE
// Gates on credit_ok — packet only forwarded when credits are available
// SOP and EOP both asserted for single-beat packets
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tlp_out   <= 1024'd0;
        tlp_valid <= 1'b0;
        tlp_sop   <= 1'b0;
        tlp_eop   <= 1'b0;
        tlp_hdr   <= 128'd0;
        tlp_be    <= 128'd0;
    end else begin
        tlp_valid <= 1'b0;
        tlp_sop   <= 1'b0;
        tlp_eop   <= 1'b0;

        if (arb_tlp_valid && credit_ok) begin
            tlp_out[1023:896] <= prefix_valid ? prefix_in : 128'd0;
            tlp_out[895:768]  <= hdr_dws;
            tlp_out[767:256]  <= tlp_has_data ? raw_data : 512'd0;
            tlp_out[255:224]  <= ecrc_in;
            tlp_out[223:0]    <= 224'd0;
            tlp_hdr           <= hdr_dws;
            tlp_be            <= be_mask;
            tlp_valid         <= 1'b1;
            tlp_sop           <= 1'b1;
            tlp_eop           <= 1'b1;
        end
    end
end

endmodule
