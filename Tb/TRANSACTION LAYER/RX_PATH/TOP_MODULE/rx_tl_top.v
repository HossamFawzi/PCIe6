// ============================================================
//  Module  : pcie_rx_tl_top
//  Purpose : PCIe Gen6 - RX Transaction Layer Top-Level
//            Integrates all 9 RX Path sub-modules.
//
//  Pipeline timing (after fixes):
//    Cycle 0 : SOP / tlp_rx_valid asserted
//    Cycle 1 : HDR_PARSE registers and produces all parsed
//              fields combinatorially: tlp_type, tlp_fmt,
//              tlp_len, tlp_addr, tlp_ep_bit, parse_valid,
//              w_msg_code_r, w_atomic_operand_r (registered
//              alongside HDR_PARSE in the same always block).
//              MAL_CHK / PSND / RX_RTR are ALL combinatorial,
//              so to_xxx_valid and routed_tlp are also valid
//              at cycle 1.
//    Cycle 2 : MWR_HDL / MSG_HDL / ATOP-s1 / CPL_Q(bypass)
//              register their inputs -> outputs valid.
//              CPL_HDL s1 captures queue output.
//    Cycle 3 : CPL_HDL s2 outputs cpl_valid / cpl_match_err
//              / tag_return_valid.
//              ATOP s2 reads memory.
//    Cycle 4 : ATOP s3 outputs atop_wr_en / atop_cpl_valid.
//
//  KEY FIXES vs original:
//    1. tlp_malformed_checker  : converted to combinatorial.
//    2. poisoned_tlp_handler   : converted to combinatorial.
//    3. rx_tlp_router          : converted to combinatorial.
//    4. pcie_completion_queue  : added fall-through bypass.
//    5. w_msg_code             : replaced live-bus tap with a
//                                registered copy pipelined with
//                                HDR_PARSE (w_msg_code_r).
//    6. w_atomic_operand       : same - replaced live-bus tap
//                                with registered w_atomic_operand_r.
// ============================================================

module pcie_rx_tl_top #(
    parameter CPL_Q_DEPTH      = 16,
    parameter CPL_Q_DATA_WIDTH = 1024,
    parameter CPL_Q_ADDR_BITS  = 4
)(
    input  wire          clk,
    input  wire          rst_n,

    input  wire [1023:0] tlp_rx,
    input  wire          tlp_rx_valid,
    input  wire          tlp_rx_sop,

    input  wire          ecrc_ok,
    input  wire          credit_grant_cpl,

    input  wire [9:0]    outstanding_tag,
    input  wire [9:0]    expected_len,

    output wire          parse_err,
    output wire          malformed_err,
    output wire [3:0]    malformed_type,
    output wire          poisoned_detected,
    output wire          poison_drop,
    output wire [2:0]    poison_to_aer,

    output wire [4:0]    tlp_type_out,
    output wire [2:0]    tlp_fmt_out,
    output wire [2:0]    tlp_tc_out,
    output wire [2:0]    tlp_attr_out,
    output wire [9:0]    tlp_len_out,
    output wire [9:0]    tlp_tag_out,
    output wire [15:0]   tlp_req_id_out,
    output wire [63:0]   tlp_addr_out,

    output wire [511:0]  cpl_data,
    output wire          cpl_valid,
    output wire [9:0]    cpl_tag,
    output wire [2:0]    cpl_status,
    output wire          cpl_match_err,
    output wire [9:0]    tag_return,
    output wire          tag_return_valid,
    output wire          cr_return_cplh,
    output wire [3:0]    cr_return_cpld,

    output wire          q_full_cpl,
    output wire [7:0]    q_occ_cpl,

    output wire [511:0]  mwr_data,
    output wire [63:0]   mwr_addr,
    output wire [63:0]   mwr_be,
    output wire          mwr_valid,
    output wire          mwr_full,

    output wire [3:0]    intx_assert,
    output wire [3:0]    intx_deassert,
    output wire          pme_msg,
    output wire [2:0]    err_msg_type,
    output wire          err_msg_valid,
    output wire [511:0]  vdm_data,
    output wire          vdm_valid,
    output wire          msg_to_aer,

    output wire [63:0]   atop_rd_addr,
    output wire [63:0]   atop_wr_data,
    output wire          atop_wr_en,
    output wire [63:0]   atop_cpl_data,
    output wire          atop_cpl_valid,
    output wire [9:0]    atop_tag,

    output wire          to_cfg_valid
);

    // -------------------------------------------------------
    //  Internal wires between sub-modules
    // -------------------------------------------------------

    // HDR_PARSE outputs (registered)
    wire [4:0]  w_tlp_type;
    wire [2:0]  w_tlp_fmt;
    wire [2:0]  w_tlp_tc;
    wire [2:0]  w_tlp_attr;
    wire [9:0]  w_tlp_len;
    wire [9:0]  w_tlp_tag;
    wire [15:0] w_tlp_req_id;
    wire [63:0] w_tlp_addr;
    wire        w_tlp_ep_bit;
    wire        w_tlp_td_bit;
    wire        w_parse_err;
    wire        w_parse_valid;

    // BE fields extracted from raw TLP bus DW1 [63:32]:
    //   first_be = bits [35:32],  last_be = bits [39:36]
    wire [3:0]  w_tlp_first_be = tlp_rx[35:32];
    wire [3:0]  w_tlp_last_be  = tlp_rx[39:36];

    // -------------------------------------------------------
    //  FIX 5 & 6: Pipeline msg_code and atomic_operand
    //
    //  The original code tapped these directly from the live
    //  tlp_rx bus (combinatorial).  By the time to_msg_valid /
    //  to_atomic_valid assert (cycle 1, same as parse_valid),
    //  the MSG_HDL and ATOP modules register those values on
    //  the NEXT rising edge (cycle 2).  At that edge tlp_rx
    //  may already have changed, so we must capture the fields
    //  on the same rising edge as HDR_PARSE does.
    // -------------------------------------------------------
    reg [7:0]  w_msg_code_r;       // registered alongside HDR_PARSE
    reg [63:0] w_atomic_operand_r; // registered alongside HDR_PARSE

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_msg_code_r       <= 8'h00;
            w_atomic_operand_r <= 64'h0;
        end else if (tlp_rx_valid && tlp_rx_sop) begin
            // DW1 bits [15:8] = msg_code  -> bus [47:40]
            w_msg_code_r       <= tlp_rx[47:40];
            // Atomic operand: payload DW0-1 after 4DW hdr -> bus [255:192]
            w_atomic_operand_r <= tlp_rx[255:192];
        end
    end

    // atomic_type is derived from the registered tlp_type (HDR_PARSE output)
    wire [1:0] w_atomic_type = w_tlp_type[1:0];

    // MAL_CHK outputs (now combinatorial wires)
    wire        w_malformed_err;
    wire [3:0]  w_malformed_type;
    wire        w_tlp_ok;

    // PSND outputs (now combinatorial wires)
    wire        w_poisoned_detected;
    wire        w_poison_drop;
    wire [2:0]  w_poison_to_aer;
    wire        w_tlp_fwd_valid;

    // RX_RTR outputs (now combinatorial wires)
    wire        w_to_cpl_valid;
    wire        w_to_mwr_valid;
    wire        w_to_cfg_valid;
    wire        w_to_msg_valid;
    wire        w_to_atomic_valid;
    wire [1023:0] w_routed_tlp;

    // CPL_Q outputs
    wire [1023:0] w_cpl_out;
    wire          w_cpl_valid_out;

    // -------------------------------------------------------
    //  Forward parsed / error fields to top-level outputs
    // -------------------------------------------------------
    assign tlp_type_out    = w_tlp_type;
    assign tlp_fmt_out     = w_tlp_fmt;
    assign tlp_tc_out      = w_tlp_tc;
    assign tlp_attr_out    = w_tlp_attr;
    assign tlp_len_out     = w_tlp_len;
    assign tlp_tag_out     = w_tlp_tag;
    assign tlp_req_id_out  = w_tlp_req_id;
    assign tlp_addr_out    = w_tlp_addr;

    assign parse_err        = w_parse_err;
    assign malformed_err    = w_malformed_err;
    assign malformed_type   = w_malformed_type;
    assign poisoned_detected= w_poisoned_detected;
    assign poison_drop      = w_poison_drop;
    assign poison_to_aer    = w_poison_to_aer;
    assign to_cfg_valid     = w_to_cfg_valid;

    // -------------------------------------------------------
    //  Stage 1 - HDR_PARSE: TLP Header Parser  (REGISTERED)
    // -------------------------------------------------------
    tlp_header_parser u_hdr_parse (
        .clk          (clk),
        .rst_n        (rst_n),
        .tlp_rx       (tlp_rx),
        .tlp_rx_valid (tlp_rx_valid),
        .tlp_rx_sop   (tlp_rx_sop),
        .tlp_type     (w_tlp_type),
        .tlp_fmt      (w_tlp_fmt),
        .tlp_tc       (w_tlp_tc),
        .tlp_attr     (w_tlp_attr),
        .tlp_len      (w_tlp_len),
        .tlp_tag      (w_tlp_tag),
        .tlp_req_id   (w_tlp_req_id),
        .tlp_addr     (w_tlp_addr),
        .tlp_ep_bit   (w_tlp_ep_bit),
        .tlp_td_bit   (w_tlp_td_bit),
        .parse_err    (w_parse_err),
        .parse_valid  (w_parse_valid)
    );

    // -------------------------------------------------------
    //  Stage 2 - MAL_CHK: Malformed Checker  (COMBINATORIAL)
    // -------------------------------------------------------
    tlp_malformed_checker u_mal_chk (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_type       (w_tlp_type),
        .tlp_fmt        (w_tlp_fmt),
        .tlp_len        (w_tlp_len),
        .tlp_first_be   (w_tlp_first_be),
        .tlp_last_be    (w_tlp_last_be),
        .parse_valid    (w_parse_valid),
        .malformed_err  (w_malformed_err),
        .malformed_type (w_malformed_type),
        .tlp_ok         (w_tlp_ok)
    );

    // -------------------------------------------------------
    //  Stage 3 - PSND: Poisoned TLP Handler  (COMBINATORIAL)
    // -------------------------------------------------------
    poisoned_tlp_handler u_psnd (
        .clk               (clk),
        .rst_n             (rst_n),
        .tlp_ep_bit        (w_tlp_ep_bit),
        .tlp_type          (w_tlp_type),
        .tlp_ok            (w_tlp_ok),
        .tlp_rx            (tlp_rx),
        .poisoned_detected (w_poisoned_detected),
        .poison_drop       (w_poison_drop),
        .poison_to_aer     (w_poison_to_aer),
        .tlp_fwd_valid     (w_tlp_fwd_valid)
    );

    // -------------------------------------------------------
    //  Stage 4 - RX_RTR: RX TLP Router  (COMBINATORIAL)
    // -------------------------------------------------------
    rx_tlp_router u_rx_rtr (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_type       (w_tlp_type),
        .tlp_fwd_valid  (w_tlp_fwd_valid),
        .tlp_rx         (tlp_rx),
        .ecrc_ok        (ecrc_ok),
        .to_cpl_valid   (w_to_cpl_valid),
        .to_mwr_valid   (w_to_mwr_valid),
        .to_cfg_valid   (w_to_cfg_valid),
        .to_msg_valid   (w_to_msg_valid),
        .to_atomic_valid(w_to_atomic_valid),
        .routed_tlp     (w_routed_tlp)
    );

    // -------------------------------------------------------
    //  Stage 5a - CPL_Q: Completion Queue  (fall-through fix)
    // -------------------------------------------------------
    pcie_completion_queue #(
        .DEPTH      (CPL_Q_DEPTH),
        .DATA_WIDTH (CPL_Q_DATA_WIDTH),
        .ADDR_BITS  (CPL_Q_ADDR_BITS)
    ) u_cpl_q (
        .clk             (clk),
        .rst_n           (rst_n),
        .cpl_tlp         (w_routed_tlp),
        .cpl_valid_in    (w_to_cpl_valid),
        .credit_grant_cpl(credit_grant_cpl),
        .cpl_out         (w_cpl_out),
        .cpl_valid_out   (w_cpl_valid_out),
        .q_full_cpl      (q_full_cpl),
        .q_occ_cpl       (q_occ_cpl)
    );

    // -------------------------------------------------------
    //  Stage 5b - CPL_HDL: Completion Handler  (REGISTERED x2)
    // -------------------------------------------------------
    pcie_completion_handler u_cpl_hdl (
        .clk              (clk),
        .rst_n            (rst_n),
        .tlp_cpl          (w_cpl_out),
        .tlp_cpl_valid    (w_cpl_valid_out),
        .outstanding_tag  (outstanding_tag),
        .expected_len     (expected_len),
        .cpl_data         (cpl_data),
        .cpl_valid        (cpl_valid),
        .cpl_tag          (cpl_tag),
        .cpl_status       (cpl_status),
        .cpl_match_err    (cpl_match_err),
        .tag_return       (tag_return),
        .tag_return_valid (tag_return_valid),
        .cr_return_cplh   (cr_return_cplh),
        .cr_return_cpld   (cr_return_cpld)
    );

    // -------------------------------------------------------
    //  Stage 5c - MWR_HDL: Posted Write Handler  (REGISTERED)
    // -------------------------------------------------------
    pcie_mwr_hdl u_mwr_hdl (
        .clk          (clk),
        .rst_n        (rst_n),
        .tlp_mwr      (w_routed_tlp),
        .tlp_mwr_valid(w_to_mwr_valid),
        .tlp_addr     (w_tlp_addr),
        .tlp_len      (w_tlp_len),
        .mwr_data     (mwr_data),
        .mwr_addr     (mwr_addr),
        .mwr_be       (mwr_be),
        .mwr_valid    (mwr_valid),
        .mwr_full     (mwr_full)
    );

    // -------------------------------------------------------
    //  Stage 5d - MSG_HDL: Message Handler  (REGISTERED)
    //  FIX: uses w_msg_code_r (registered) instead of live bus
    // -------------------------------------------------------
    pcie_msg_hdl u_msg_hdl (
        .clk          (clk),
        .rst_n        (rst_n),
        .tlp_msg      (w_routed_tlp),
        .tlp_msg_valid(w_to_msg_valid),
        .msg_code     (w_msg_code_r),       // <-- registered copy
        .intx_assert  (intx_assert),
        .intx_deassert(intx_deassert),
        .pme_msg      (pme_msg),
        .err_msg_type (err_msg_type),
        .err_msg_valid(err_msg_valid),
        .vdm_data     (vdm_data),
        .vdm_valid    (vdm_valid),
        .msg_to_aer   (msg_to_aer)
    );

    // -------------------------------------------------------
    //  Stage 5e - ATOP: Atomic Operation Handler  (REGISTERED x3)
    //  FIX: uses w_atomic_operand_r (registered) instead of live bus
    // -------------------------------------------------------
    pcie_atomic_op_handler u_atop (
        .clk             (clk),
        .rst_n           (rst_n),
        .tlp_atomic      (w_routed_tlp),
        .tlp_atomic_valid(w_to_atomic_valid),
        .atomic_type     (w_atomic_type),
        .atomic_addr     (w_tlp_addr),
        .atomic_operand  (w_atomic_operand_r),  // <-- registered copy
        .atop_rd_addr    (atop_rd_addr),
        .atop_wr_data    (atop_wr_data),
        .atop_wr_en      (atop_wr_en),
        .atop_cpl_data   (atop_cpl_data),
        .atop_cpl_valid  (atop_cpl_valid),
        .atop_tag        (atop_tag)
    );

endmodule
