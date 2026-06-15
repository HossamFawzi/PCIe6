// ============================================================
//  Module  : pcie_mwr_hdl
//  Purpose : PCIe Gen6 ? Posted Write Handler (MWr RX)
//            Handles inbound Memory Write (MWr) TLPs.
//            MWr is posted ? no completion is generated.
//
//  Interface (from HTML reference: MWR_HDL / tag "rx"):
//    Inputs :
//      clk              ? system clock
//      rst_n            ? active-low synchronous reset
//      tlp_mwr[1023:0]  ? full inbound MWr TLP (1024-bit bus)
//      tlp_mwr_valid    ? TLP bus carries a valid MWr TLP this cycle
//      tlp_addr[63:0]   ? target address (pre-parsed by HDR_PARSE)
//      tlp_len[9:0]     ? DW length field from TLP header
//    Outputs:
//      mwr_data[511:0]  ? write payload delivered to User Logic
//      mwr_addr[63:0]   ? target write address
//      mwr_be[63:0]     ? byte-enable (1 bit per byte, bit0 = byte0)
//      mwr_valid        ? output valid (level, held until reset)
//      mwr_full         ? back-pressure (=mwr_valid)
//
//  TLP 4-DW header bit layout on the 1024-bit bus:
//    [1023:992] DW0: fmt[1023:1021], type[1020:1016], len[1001:992]
//    [991 :960] DW1: req_id[991:976], tag[975:968],
//                    last_be[967:964], first_be[963:960]
//    [959 :928] DW2: addr[63:32]
//    [927 :896] DW3: addr[31:2], ph[1:0]
//    [895 :384] Data payload (up to 512 bits = 64 bytes)
//
//  Byte-enable mapping:
//    be[3:0]        ? first DW  (controlled by first_be)
//    be[len*4-1:4]  ? middle DWs (all 1s)
//    be[len*4-1:len*4-4] ? last DW (controlled by last_be)
//    be[63:len*4]   ? unused/zero
// ============================================================

module pcie_mwr_hdl (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1023:0] tlp_mwr,
    input  wire          tlp_mwr_valid,
    input  wire [63:0]   tlp_addr,
    input  wire [9:0]    tlp_len,
    output reg  [511:0]  mwr_data,
    output reg  [63:0]   mwr_addr,
    output reg  [63:0]   mwr_be,
    output reg           mwr_valid,
    output wire          mwr_full
);

    // ?? TLP header field extraction (combinatorial) ???????????
    wire [3:0]   first_be = tlp_mwr[963:960];
    wire [3:0]   last_be  = tlp_mwr[967:964];
    wire [9:0]   hdr_len  = tlp_mwr[1001:992];
    wire [511:0] payload  = tlp_mwr[895:384];

    // ?? Byte-enable expansion (combinatorial) ?????????????????
    //
    //  Byte layout (PCIe ordering):
    //    byte 0 = first byte of first DW  ? be[0]  ? first_be[0]
    //    byte 1                           ? be[1]  ? first_be[1]
    //    byte 2                           ? be[2]  ? first_be[2]
    //    byte 3 = last byte of first DW   ? be[3]  ? first_be[3]
    //    bytes 4 .. (len*4-5) = middle    ? be[..]  all 1
    //    bytes (len*4-4)..(len*4-1) last  ? be[..]  ? last_be
    //    bytes len*4 .. 63  (unused)      ? be[..]  0
    //
    //  For len==1: first_be covers the only DW; last_be ignored.
    //
    reg  [63:0] be_expanded;
    integer i;
    reg [31:0] last_start;   // byte index of first byte in last DW
    reg [31:0] total_bytes;  // len * 4 — unsigned to avoid VER-318

    always @(*) begin
        be_expanded  = 64'h0;
        total_bytes  = {22'h0, hdr_len} * 4;   // max = 256*4 = 1024; capped at 64 here
        last_start   = total_bytes - 4;          // byte offset of last DW

        // First DW byte enables
        be_expanded[0] = first_be[0];
        be_expanded[1] = first_be[1];
        be_expanded[2] = first_be[2];
        be_expanded[3] = first_be[3];

        if (hdr_len > 10'd1) begin
            // Middle DWs (bytes 4 .. last_start-1) ? fully enabled
            for (i = 4; i < 60; i = i + 1)
                be_expanded[i] = (i < last_start) ? 1'b1 : 1'b0;

            // Last DW byte enables at bytes [last_start .. last_start+3]
            // Clamped to 63 max
            if (last_start <= 60) begin
                be_expanded[last_start  ] = last_be[0];
                be_expanded[last_start+1] = last_be[1];
                be_expanded[last_start+2] = last_be[2];
                be_expanded[last_start+3] = last_be[3];
            end
        end
        // For len==1: upper bytes remain 0
    end

    // ?? Back-pressure ?????????????????????????????????????????
    assign mwr_full = mwr_valid;

    // ?? Registered datapath ???????????????????????????????????
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mwr_data  <= 512'h0;
            mwr_addr  <= 64'h0;
            mwr_be    <= 64'h0;
            mwr_valid <= 1'b0;
        end else if (tlp_mwr_valid) begin
            mwr_addr  <= tlp_addr;
            mwr_data  <= payload;
            mwr_be    <= be_expanded;
            mwr_valid <= 1'b1;
        end else begin
            // FIX-MWR: auto-clear after one cycle (1-cycle pulse, not sticky level)
            mwr_valid <= 1'b0;
        end
    end

endmodule
