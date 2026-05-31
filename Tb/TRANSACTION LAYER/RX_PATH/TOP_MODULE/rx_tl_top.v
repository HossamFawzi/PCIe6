
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

    wire [3:0]  w_tlp_first_be = tlp_rx[35:32];
    wire [3:0]  w_tlp_last_be  = tlp_rx[39:36];

    reg [7:0]  w_msg_code_r;
    reg [63:0] w_atomic_operand_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_msg_code_r       <= 8'h00;
            w_atomic_operand_r <= 64'h0;
        end else if (tlp_rx_valid && tlp_rx_sop) begin

            w_msg_code_r       <= tlp_rx[47:40];

            w_atomic_operand_r <= tlp_rx[255:192];
        end
    end

    wire [1:0] w_atomic_type = w_tlp_type[1:0];

    wire        w_malformed_err;
    wire [3:0]  w_malformed_type;
    wire        w_tlp_ok;

    wire        w_poisoned_detected;
    wire        w_poison_drop;
    wire [2:0]  w_poison_to_aer;
    wire        w_tlp_fwd_valid;

    wire        w_to_cpl_valid;
    wire        w_to_mwr_valid;
    wire        w_to_cfg_valid;
    wire        w_to_msg_valid;
    wire        w_to_atomic_valid;
    wire [1023:0] w_routed_tlp;

    wire [1023:0] w_cpl_out;
    wire          w_cpl_valid_out;

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

    pcie_msg_hdl u_msg_hdl (
        .clk          (clk),
        .rst_n        (rst_n),
        .tlp_msg      (w_routed_tlp),
        .tlp_msg_valid(w_to_msg_valid),
        .msg_code     (w_msg_code_r),
        .intx_assert  (intx_assert),
        .intx_deassert(intx_deassert),
        .pme_msg      (pme_msg),
        .err_msg_type (err_msg_type),
        .err_msg_valid(err_msg_valid),
        .vdm_data     (vdm_data),
        .vdm_valid    (vdm_valid),
        .msg_to_aer   (msg_to_aer)
    );

    pcie_atomic_op_handler u_atop (
        .clk             (clk),
        .rst_n           (rst_n),
        .tlp_atomic      (w_routed_tlp),
        .tlp_atomic_valid(w_to_atomic_valid),
        .atomic_type     (w_atomic_type),
        .atomic_addr     (w_tlp_addr),
        .atomic_operand  (w_atomic_operand_r),
        .atop_rd_addr    (atop_rd_addr),
        .atop_wr_data    (atop_wr_data),
        .atop_wr_en      (atop_wr_en),
        .atop_cpl_data   (atop_cpl_data),
        .atop_cpl_valid  (atop_cpl_valid),
        .atop_tag        (atop_tag)
    );

endmodule
