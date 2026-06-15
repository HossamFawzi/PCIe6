// ============================================================
// Module  : usr_if.v
// Project : PCIe Gen6 Transaction Layer — TX Path
// Block   : User Logic Interface (USR_IF)
// ============================================================
//
// Position in TX Path:
//
//   Driver/Software
//        |
//      USR_IF        <-- هنا
//        |
//      REQ_Q
//        |
//      ARB_TX
//        |
//      TLP_ASM ...
//
// What it does:
//   1. Accepts request from Driver (valid/ready handshake)
//   2. Packs all fields into one 604-bit word → REQ_Q
//   3. Returns completions from CPL_Q → Driver
//   4. Returns inbound write data from MWR_HDL → Driver
//
// Packet Format [603:0]:
//   [603:600]  req_type      4-bit
//   [599:536]  req_addr     64-bit
//   [535:526]  req_len      10-bit
//   [525:523]  req_attr      3-bit
//   [522:520]  req_tc        3-bit
//   [519:516]  req_first_be  4-bit
//   [515:512]  req_last_be   4-bit
//   [511:  0]  req_data    512-bit
//
// Handshake Rule:
//   Transfer happens when: valid=1 AND ready=1
//   on the same rising clock edge
//
// ============================================================

module usr_if (

    // ── Clock & Reset ────────────────────────────────────────
    input  wire          clk,
    input  wire          rst_n,

    // ── From Driver (Outbound Request) ───────────────────────
    input  wire [3:0]    req_type,
    input  wire [63:0]   req_addr,
    input  wire [9:0]    req_len,
    input  wire [511:0]  req_data,
    input  wire          req_valid,
    input  wire [2:0]    req_attr,
    input  wire [2:0]    req_tc,
    input  wire [3:0]    req_first_be,
    input  wire [3:0]    req_last_be,
    output wire          req_ready,

    // ── To REQ_Q ─────────────────────────────────────────────
    output wire [603:0]  pkt_out,
    output wire          pkt_valid,
    input  wire          pkt_ready,

    // ── From CPL_Q → Driver ───────────────────────────────────
    input  wire [511:0]  cpl_data,
    input  wire          cpl_valid,
    input  wire [2:0]    cpl_status,
    input  wire [9:0]    cpl_tag,
    output wire [511:0]  usr_cpl_data,
    output wire          usr_cpl_valid,
    output wire [2:0]    usr_cpl_status,
    output wire [9:0]    usr_cpl_tag,

    // ── From MWR_HDL → Driver ─────────────────────────────────
    input  wire [511:0]  mwr_data,
    input  wire          mwr_valid,
    input  wire [63:0]   mwr_addr,
    output wire [511:0]  usr_mwr_data,
    output wire          usr_mwr_valid,
    output wire [63:0]   usr_mwr_addr

);

// ============================================================
// PACK — combinational only — no flops here
// REQ_Q owns the FIFOs and registers
// ============================================================

assign pkt_out = {
    req_type,         // [603:600]
    req_addr,         // [599:536]
    req_len,          // [535:526]
    req_attr,         // [525:523]
    req_tc,           // [522:520]
    req_first_be,     // [519:516]
    req_last_be,      // [515:512]
    req_data          // [511:  0]
};

// ============================================================
// HANDSHAKE — transparent pass-through
// ============================================================

assign pkt_valid = req_valid;
assign req_ready = pkt_ready;

// ============================================================
// RETURN PATH — pass-through, no logic needed
// ============================================================

assign usr_cpl_data   = cpl_data;
assign usr_cpl_valid  = cpl_valid;
assign usr_cpl_status = cpl_status;
assign usr_cpl_tag    = cpl_tag;

assign usr_mwr_data   = mwr_data;
assign usr_mwr_valid  = mwr_valid;
assign usr_mwr_addr   = mwr_addr;

// ============================================================
// ASSERTIONS — simulation only
// ============================================================
`ifdef SIMULATION
always @(posedge clk) begin
    if (rst_n && req_valid && req_ready) begin
        if (req_type > 4'd5)
            $error("[USR_IF] Unknown req_type=%0d", req_type);
        if (req_len == 10'd0)
            $error("[USR_IF] req_len=0 illegal");
    end
end
`endif

endmodule
