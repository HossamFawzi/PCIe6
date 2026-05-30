// ============================================================
// Module: rx_tlp_router
// PCIe Gen6 Transaction Layer - RX TLP Router / MUX
// FIX: All routing outputs are now COMBINATORIAL (always @*).
//      Removing the register stage here means downstream
//      handlers (MWR_HDL, MSG_HDL, ATOP, CPL_Q) see their
//      valid and data in the same cycle as tlp_fwd_valid,
//      which is itself combinatorial from MAL_CHK/PSND.
//      The net pipeline is therefore:
//        HDR_PARSE (1 reg) -> MAL_CHK/PSND/RTR (comb) -> handler (1 reg)
//      = 2 clock cycles from SOP to output, matching the TB.
// ============================================================

module rx_tlp_router (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [4:0]    tlp_type,
    input  wire [2:0]    tlp_fmt,   // FIX-RTR: needed to distinguish MWr vs MRd
    input  wire          tlp_fwd_valid,
    input  wire [1023:0] tlp_rx,
    input  wire          ecrc_ok,

    output wire          to_cpl_valid,
    output wire          to_mwr_valid,
    output wire          to_cfg_valid,
    output wire          to_msg_valid,
    output wire          to_atomic_valid,
    output wire [1023:0] routed_tlp
);

    wire is_mem    = (tlp_type == 5'b00000);
    wire is_io     = (tlp_type == 5'b00010);
    wire is_cfg    = (tlp_type == 5'b00100) || (tlp_type == 5'b00101);
    wire is_msg    = (tlp_type[4:3] == 2'b10);
    wire is_cpl    = (tlp_type == 5'b01010);
    wire is_atomic = (tlp_type == 5'b01100) ||
                     (tlp_type == 5'b01101) ||
                     (tlp_type == 5'b01110);

    // Route only when tlp_fwd_valid AND ECRC passed
    wire route_en = tlp_fwd_valid && ecrc_ok;

    // -------------------------------------------------------
    // Combinatorial routing (no clock, no register)
    // -------------------------------------------------------
    assign to_cpl_valid    = route_en & is_cpl;
    // FIX-RTR: MWr = is_mem && fmt[1]=1 (has data). MRd = is_mem && fmt[1]=0.
    // Without this, every MRd (including TC12 reads) was erroneously routed to MWR_HDL.
    wire is_mwr = is_mem & tlp_fmt[1];   // fmt[1]=1 means TLP carries data payload
    assign to_mwr_valid    = route_en & is_mwr;
    assign to_cfg_valid    = route_en & (is_cfg | is_io);
    assign to_msg_valid    = route_en & is_msg;
    assign to_atomic_valid = route_en & is_atomic;

    // Forward the raw TLP bus to all handlers (only one valid asserted)
    assign routed_tlp = route_en ? tlp_rx : 1024'b0;

endmodule
