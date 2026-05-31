
`timescale 1ns/1ps

module pcie_tl_top (

    input  wire          clk,
    input  wire          rst_n,

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

    output wire [511:0]  usr_cpl_data,
    output wire          usr_cpl_valid,
    output wire [2:0]    usr_cpl_status,
    output wire [9:0]    usr_cpl_tag,
    output wire [511:0]  usr_mwr_data,
    output wire          usr_mwr_valid,
    output wire [63:0]   usr_mwr_addr,

    input  wire          dll_ack,
    input  wire          dll_nak,
    input  wire          dll_up,
    input  wire [71:0]   cr_update,
    input  wire          cr_update_valid,

    output wire [2047:0] flit_to_dll,
    output wire          flit_to_dll_valid,
    output wire          dll_ready,

    input  wire [255:0]  tlp_cfg_in,
    input  wire          tlp_cfg_valid,
    input  wire [11:0]   cfg_addr,
    input  wire [31:0]   cfg_wr_data,
    input  wire          cfg_wr_en,
    output wire [31:0]   cfg_rd_data,
    output wire          cfg_rd_valid,

    output wire [31:0]   aer_status,
    output wire          aer_int,
    output wire [255:0]  err_msg_tlp,
    output wire          err_msg_valid,

    input  wire          vc0_req,
    input  wire          vc1_req,
    input  wire          vc2_req,
    input  wire          vc3_req,
    input  wire [1:0]    vc_arb_scheme,
    input  wire [31:0]   vc_weight,
    output wire [3:0]    vc_grant,
    output wire [2:0]    vc_grant_id,
    output wire          vc_arb_valid,

    output wire          fc_init_done_out,
    output wire          ordering_ok_out,
    output wire          tag_exhausted_out,
    output wire [9:0]    outstanding_count_out
);

wire [603:0] usrif_pkt_out;
wire         usrif_pkt_valid;
wire         usrif_pkt_ready;

wire [575:0] reqq_out;
wire         reqq_valid_out;
wire [1:0]   reqq_type_out;
wire         reqq_full_p, reqq_full_np;
wire [7:0]   reqq_occ_p,  reqq_occ_np;

wire         cr_grant_p, cr_grant_np, cr_grant_cpl;

wire [575:0] arb_tlp;
wire         arb_tlp_valid;
wire [1:0]   arb_type;

wire         ordering_ok, ordering_stall, ordering_err;

reg [3:0]    ord_req_type_reg;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) ord_req_type_reg <= 4'h0;
    else if (usrif_pkt_valid) ord_req_type_reg <= req_type;
end

wire ordering_ok_gated = ordering_ok | reqq_valid_out;

wire [9:0]   tag_alloc;
wire         tag_valid_w;
wire         tag_exhausted;
wire [9:0]   outstanding_count;

wire [71:0]  initfc_tx_w;
wire         initfc_tx_send_w;
wire         fc_init_done;
wire [7:0]   adv_ph, adv_nph, adv_cplh;
wire [11:0]  adv_pd, adv_cpld;

wire [1023:0] asm_tlp_out;
wire          asm_tlp_valid;
wire          asm_tlp_sop, asm_tlp_eop;
wire [127:0]  asm_tlp_hdr, asm_tlp_be;

wire [1151:0] pfx_tlp_out;
wire          pfx_tlp_valid;
wire          pfx_err, pfx_e2e_fwd;

wire [1183:0] ecrc_tx_out;
wire          ecrc_tx_valid;
wire          ecrc_rx_ok_w, ecrc_rx_err_w;

wire [2047:0] flit_out_w;
wire          flit_valid_w;
wire [23:0]   flit_crc_w;
wire [11:0]   flit_seq_w;
wire          flit_retry_req_w, flit_overflow_err_w;

wire [1023:0] dll_tlp_rx;
wire          dll_tlp_rx_valid;

wire [2:0]   max_payload_cfg;
wire         flit_mode_en_cfg;
wire         ecrc_en_cfg;
wire         ro_en_cfg;

wire          ecrc_ok_gated = ecrc_rx_ok_w | ~ecrc_en_cfg;

wire [4:0]   rx_tlp_type;
wire [2:0]   rx_tlp_fmt;
wire [2:0]   rx_tlp_tc;
wire [2:0]   rx_tlp_attr;
wire [9:0]   rx_tlp_len;
wire [9:0]   rx_tlp_tag;
wire [15:0]  rx_tlp_req_id;
wire [63:0]  rx_tlp_addr;
wire         rx_tlp_ep_bit;
wire         rx_tlp_td_bit;
wire         rx_parse_err;
wire         rx_parse_valid;

wire         mal_err;
wire [3:0]   mal_type;
wire         tlp_ok;

wire         poisoned_detected;
wire         poison_drop;
wire [2:0]   poison_to_aer;
wire         tlp_fwd_valid;

wire         to_cpl_valid, to_mwr_valid, to_cfg_valid;
wire         to_msg_valid, to_atomic_valid;
wire [1023:0] routed_tlp;

wire [1023:0] cpl_q_out;
wire          cpl_q_valid_out;
wire          cpl_q_full;
wire [7:0]    cpl_q_occ;

wire [511:0] cpl_data_w;
wire         cpl_valid_w;
wire [9:0]   cpl_tag_w;
wire [2:0]   cpl_status_w;
wire         cpl_match_err;
wire [9:0]   cpl_tag_return;
wire         cpl_tag_return_valid;
wire         cr_return_cplh;
wire [3:0]   cr_return_cpld;

wire [511:0] mwr_data_w;
wire [63:0]  mwr_addr_w;
wire [63:0]  mwr_be_w;
wire         mwr_valid_w;
wire         mwr_full_w;

wire [3:0]   intx_assert_w, intx_deassert_w;
wire         pme_msg_w;
wire [2:0]   err_msg_type_w;
wire         err_msg_valid_w;
wire [511:0] vdm_data_w;
wire         vdm_valid_w;
wire         msg_to_aer_w;

wire [63:0]  atop_rd_addr_w;
wire [63:0]  atop_wr_data_w;
wire         atop_wr_en_w;
wire [63:0]  atop_cpl_data_w;
wire         atop_cpl_valid_w;
wire [9:0]   atop_tag_w;

wire [7:0]   msg_code_w = routed_tlp[55:48];

wire [1:0]   atomic_type_w    = routed_tlp[28:27];
wire [63:0]  atomic_addr_w    = rx_tlp_addr;
wire [63:0]  atomic_operand_w = routed_tlp[159:96];

wire [9:0]   tmo_timeout_tag;
wire         tmo_timeout_valid;
wire         tmo_cpl_timeout_err;
wire [3:0]   tmo_err_to_aer;

wire [9:0]   cpltmo_timeout_tag;
wire         cpltmo_timeout_fired;
wire         cpltmo_cpl_abort_req;
wire [3:0]   cpltmo_err_to_aer;

wire         fc_init_timeout_w;
wire         fc_init_retry_req_w;
wire         fc_init_err_w;

wire         ro_bypass_ok_w;
wire         ordering_override_w;
wire         ro_err_w;

wire [31:0]  aer_mask_w;

wire [7:0]   upd_ph   = cr_update[71:64];
wire [11:0]  upd_pd   = {4'b0, cr_update[63:56]};
wire [7:0]   upd_nph  = cr_update[55:48];
wire [11:0]  upd_npd  = {4'b0, cr_update[47:40]};
wire [7:0]   upd_cplh = cr_update[39:32];
wire [11:0]  upd_cpld = {4'b0, cr_update[31:24]};

wire [575:0] reqq_in_data = usrif_pkt_out[575:0];

wire         req_p_valid_arb  = reqq_valid_out & (reqq_type_out == 2'd0);
wire         req_np_valid_arb = reqq_valid_out & (reqq_type_out == 2'd1);

wire [127:0] pfx_stub_data  = 128'h0;
wire         pfx_stub_valid = 1'b0;

wire [31:0]  ecrc_for_asm = 32'h0;

wire [9:0]   tmo_tag_to_tagmgr = cpltmo_timeout_tag;

wire [15:0]  ord_req_id   = arb_tlp[575:560];
wire [3:0]   ord_req_type = arb_tlp[575:572];
wire [2:0]   ord_req_tc   = arb_tlp[522:520];
wire         ord_req_ro   = arb_tlp[525];

wire [15:0]  ord_cpl_id = routed_tlp[79:64];

usr_if U_USR_IF (
    .clk           (clk),
    .rst_n         (rst_n),
    .req_type      (req_type),
    .req_addr      (req_addr),
    .req_len       (req_len),
    .req_data      (req_data),
    .req_valid     (req_valid),
    .req_attr      (req_attr),
    .req_tc        (req_tc),
    .req_first_be  (req_first_be),
    .req_last_be   (req_last_be),
    .req_ready     (req_ready),
    .pkt_out       (usrif_pkt_out),
    .pkt_valid     (usrif_pkt_valid),
    .pkt_ready     (usrif_pkt_ready),
    .cpl_data      (cpl_data_w),
    .cpl_valid     (cpl_valid_w),
    .cpl_status    (cpl_status_w),
    .cpl_tag       (cpl_tag_w),
    .usr_cpl_data  (usr_cpl_data),
    .usr_cpl_valid (usr_cpl_valid),
    .usr_cpl_status(usr_cpl_status),
    .usr_cpl_tag   (usr_cpl_tag),
    .mwr_data      (mwr_data_w),
    .mwr_valid     (mwr_valid_w),
    .mwr_addr      (mwr_addr_w),
    .usr_mwr_data  (usr_mwr_data),
    .usr_mwr_valid (usr_mwr_valid),
    .usr_mwr_addr  (usr_mwr_addr)
);

req_q #(.DEPTH_P(16), .DEPTH_NP(16), .WIDTH(576)) U_REQ_Q (
    .clk            (clk),
    .rst_n          (rst_n),
    .req_in         (reqq_in_data),
    .req_valid_in   (usrif_pkt_valid),
    .credit_grant_p (cr_grant_p),
    .credit_grant_np(cr_grant_np),
    .req_out        (reqq_out),
    .req_valid_out  (reqq_valid_out),
    .req_type_out   (reqq_type_out),
    .q_full_p       (reqq_full_p),
    .q_full_np      (reqq_full_np),
    .q_occ_p        (reqq_occ_p),
    .q_occ_np       (reqq_occ_np)
);
assign usrif_pkt_ready = ~reqq_full_p & ~reqq_full_np;

tag_manager U_TAG_MGR (
    .clk               (clk),
    .rst_n             (rst_n),
    .tag_req           (arb_tlp_valid),
    .tag_return        (cpl_tag_return),
    .tag_return_valid  (cpl_tag_return_valid),
    .timeout_tag       (tmo_tag_to_tagmgr),
    .tag_alloc         (tag_alloc),
    .tag_valid         (tag_valid_w),
    .tag_exhausted     (tag_exhausted),
    .outstanding_count (outstanding_count),
    .req_addr_lkup     (),
    .req_len_lkup      (),
    .req_type_lkup     ()
);

fc_init_fsm U_FC_INIT (
    .clk             (clk),
    .rst_n           (rst_n),
    .dll_up          (dll_up),
    .initfc_rx       (cr_update),
    .initfc_rx_valid (cr_update_valid),
    .initfc_tx       (initfc_tx_w),
    .initfc_tx_send  (initfc_tx_send_w),
    .fc_init_done    (fc_init_done),
    .adv_ph          (adv_ph),
    .adv_pd          (adv_pd),
    .adv_nph         (adv_nph),
    .adv_cplh        (adv_cplh),
    .adv_cpld        (adv_cpld)
);

cr_mgr U_CR_MGR (
    .clk             (clk),
    .rst_n           (rst_n),
    .fc_init_done    (fc_init_done),
    .init_ph         (adv_ph),
    .init_pd         (adv_pd),
    .init_nph        (adv_nph),
    .init_npd        (12'd64),
    .init_cplh       (adv_cplh),
    .init_cpld       (adv_cpld),
    .upd_ph          (upd_ph),
    .upd_pd          (upd_pd),
    .upd_nph         (upd_nph),
    .upd_npd         (upd_npd),
    .upd_cplh        (upd_cplh),
    .upd_cpld        (upd_cpld),
    .upd_valid       (cr_update_valid),
    .tlp_sent        (arb_tlp_valid),
    .tlp_is_np       (arb_type[0]),
    .tlp_len         (arb_tlp[9:0]),
    .credit_grant_p  (cr_grant_p),
    .credit_grant_np (cr_grant_np),
    .credit_grant_cpl(cr_grant_cpl),
    .dbg_ph_avail    (),
    .dbg_pd_avail    (),
    .dbg_nph_avail   (),
    .dbg_npd_avail   ()
);

pcie_ordering_rob U_ORD (
    .clk          (clk),
    .rst_n        (rst_n),
    .req_id       (ord_req_id),
    .req_type     (ord_req_type_reg),
    .req_tc       (ord_req_tc),
    .req_attr_ro  (ord_req_ro),
    .req_valid    (reqq_valid_out),
    .cpl_id       (ord_cpl_id),
    .cpl_valid    (to_cpl_valid),
    .ordering_ok  (ordering_ok),
    .ordering_stall(ordering_stall),
    .ordering_err (ordering_err)
);

arb_tx U_ARB_TX (
    .clk             (clk),
    .rst_n           (rst_n),
    .req_p_valid     (req_p_valid_arb),
    .req_np_valid    (req_np_valid_arb),
    .req_p           (reqq_out),
    .req_np          (reqq_out),
    .credit_grant_p  (cr_grant_p),
    .credit_grant_np (cr_grant_np),
    .ordering_ok     (ordering_ok_gated),
    .arb_tlp         (arb_tlp),
    .arb_tlp_valid   (arb_tlp_valid),
    .arb_type        (arb_type)
);

tlp_assembler U_TLP_ASM (
    .clk           (clk),
    .rst_n         (rst_n),
    .arb_tlp_in    (arb_tlp),
    .arb_tlp_valid (arb_tlp_valid),
    .prefix_in     (pfx_stub_data),
    .prefix_valid  (pfx_stub_valid),
    .ecrc_in       (ecrc_for_asm),
    .credit_ok     (cr_grant_p | cr_grant_np),
    .max_payload   (max_payload_cfg),
    .tlp_out       (asm_tlp_out),
    .tlp_valid     (asm_tlp_valid),
    .tlp_sop       (asm_tlp_sop),
    .tlp_eop       (asm_tlp_eop),
    .tlp_hdr       (asm_tlp_hdr),
    .tlp_be        (asm_tlp_be)
);

tlp_prefix_handler U_PFX (
    .clk               (clk),
    .rst_n             (rst_n),
    .tlp_in            (asm_tlp_out),
    .tlp_valid_in      (asm_tlp_valid),
    .ltp_data          (128'h0),
    .ltp_valid         (1'b0),
    .eetp_data         (128'h0),
    .eetp_valid        (1'b0),
    .tlp_prefixed      (pfx_tlp_out),
    .tlp_prefixed_valid(pfx_tlp_valid),
    .prefix_err        (pfx_err),
    .e2e_fwd           (pfx_e2e_fwd)
);

ecrc U_ECRC (
    .clk           (clk),
    .rst_n         (rst_n),
    .tlp_tx        (pfx_tlp_out),
    .tlp_tx_valid  (pfx_tlp_valid),
    .tlp_rx        ({128'h0, dll_tlp_rx}),
    .tlp_rx_valid  (dll_tlp_rx_valid),
    .ecrc_en       (ecrc_en_cfg),
    .tlp_ecrc_tx   (ecrc_tx_out),
    .tlp_ecrc_valid(ecrc_tx_valid),
    .ecrc_rx_ok    (ecrc_rx_ok_w),
    .ecrc_rx_err   (ecrc_rx_err_w)
);

flit_mode_controller U_FLIT (
    .clk              (clk),
    .rst_n            (rst_n),
    .tlp_in           (asm_tlp_out),
    .tlp_valid_in     (asm_tlp_valid),
    .flit_mode_en     (flit_mode_en_cfg),
    .dll_flit_ack     (dll_ack),
    .flit_out         (flit_out_w),
    .flit_valid       (flit_valid_w),
    .flit_crc         (flit_crc_w),
    .flit_seq         (flit_seq_w),
    .flit_retry_req   (flit_retry_req_w),
    .flit_overflow_err(flit_overflow_err_w)
);

DLL_IF U_DLL_IF (
    .clk              (clk),
    .rst_n            (rst_n),
    .flit_in          (flit_out_w),
    .flit_valid_in    (flit_valid_w),
    .dll_ack          (dll_ack),
    .dll_nak          (dll_nak),
    .dll_up           (dll_up),
    .cr_update        (cr_update),
    .cr_update_valid  (cr_update_valid),
    .tlp_rx_out       (dll_tlp_rx),
    .tlp_rx_valid     (dll_tlp_rx_valid),
    .flit_to_dll      (flit_to_dll),
    .flit_to_dll_valid(flit_to_dll_valid),
    .dll_ready        (dll_ready)
);

tlp_header_parser U_HDR_PARSE (
    .clk         (clk),
    .rst_n       (rst_n),
    .tlp_rx      (dll_tlp_rx),
    .tlp_rx_valid(dll_tlp_rx_valid),
    .tlp_rx_sop  (dll_tlp_rx_valid),
    .tlp_type    (rx_tlp_type),
    .tlp_fmt     (rx_tlp_fmt),
    .tlp_tc      (rx_tlp_tc),
    .tlp_attr    (rx_tlp_attr),
    .tlp_len     (rx_tlp_len),
    .tlp_tag     (rx_tlp_tag),
    .tlp_req_id  (rx_tlp_req_id),
    .tlp_addr    (rx_tlp_addr),
    .tlp_ep_bit  (rx_tlp_ep_bit),
    .tlp_td_bit  (rx_tlp_td_bit),
    .parse_err   (rx_parse_err),
    .parse_valid (rx_parse_valid)
);

tlp_malformed_checker U_MAL_CHK (
    .clk           (clk),
    .rst_n         (rst_n),
    .tlp_type      (rx_tlp_type),
    .tlp_fmt       (rx_tlp_fmt),
    .tlp_len       (rx_tlp_len),
    .tlp_first_be  (dll_tlp_rx[35:32]),
    .tlp_last_be   (dll_tlp_rx[39:36]),
    .parse_valid   (rx_parse_valid),
    .malformed_err (mal_err),
    .malformed_type(mal_type),
    .tlp_ok        (tlp_ok)
);

poisoned_tlp_handler U_PSND (
    .clk               (clk),
    .rst_n             (rst_n),
    .tlp_ep_bit        (rx_tlp_ep_bit),
    .tlp_type          (rx_tlp_type),
    .tlp_ok            (tlp_ok),
    .tlp_rx            (dll_tlp_rx),
    .poisoned_detected (poisoned_detected),
    .poison_drop       (poison_drop),
    .poison_to_aer     (poison_to_aer),
    .tlp_fwd_valid     (tlp_fwd_valid)
);

rx_tlp_router U_RX_RTR (
    .clk             (clk),
    .rst_n           (rst_n),
    .tlp_type        (rx_tlp_type),
    .tlp_fwd_valid   (tlp_fwd_valid),
    .tlp_rx          (dll_tlp_rx),
    .ecrc_ok         (ecrc_ok_gated),
    .to_cpl_valid    (to_cpl_valid),
    .to_mwr_valid    (to_mwr_valid),
    .to_cfg_valid    (to_cfg_valid),
    .to_msg_valid    (to_msg_valid),
    .to_atomic_valid (to_atomic_valid),
    .routed_tlp      (routed_tlp)
);

pcie_completion_queue U_CPL_Q (
    .clk             (clk),
    .rst_n           (rst_n),
    .cpl_tlp         (routed_tlp),
    .cpl_valid_in    (to_cpl_valid),
    .credit_grant_cpl(cr_grant_cpl),
    .cpl_out         (cpl_q_out),
    .cpl_valid_out   (cpl_q_valid_out),
    .q_full_cpl      (cpl_q_full),
    .q_occ_cpl       (cpl_q_occ)
);

pcie_completion_handler U_CPL_HDL (
    .clk             (clk),
    .rst_n           (rst_n),
    .tlp_cpl         (cpl_q_out),
    .tlp_cpl_valid   (cpl_q_valid_out),
    .outstanding_tag (tag_alloc),
    .expected_len    (rx_tlp_len),
    .cpl_data        (cpl_data_w),
    .cpl_valid       (cpl_valid_w),
    .cpl_tag         (cpl_tag_w),
    .cpl_status      (cpl_status_w),
    .cpl_match_err   (cpl_match_err),
    .tag_return      (cpl_tag_return),
    .tag_return_valid(cpl_tag_return_valid),
    .cr_return_cplh  (cr_return_cplh),
    .cr_return_cpld  (cr_return_cpld)
);

pcie_mwr_hdl U_MWR_HDL (
    .clk          (clk),
    .rst_n        (rst_n),
    .tlp_mwr      (routed_tlp),
    .tlp_mwr_valid(to_mwr_valid),
    .tlp_addr     (rx_tlp_addr),
    .tlp_len      (rx_tlp_len),
    .mwr_data     (mwr_data_w),
    .mwr_addr     (mwr_addr_w),
    .mwr_be       (mwr_be_w),
    .mwr_valid    (mwr_valid_w),
    .mwr_full     (mwr_full_w)
);

pcie_msg_hdl U_MSG_HDL (
    .clk           (clk),
    .rst_n         (rst_n),
    .tlp_msg       (routed_tlp),
    .tlp_msg_valid (to_msg_valid),
    .msg_code      (msg_code_w),
    .intx_assert   (intx_assert_w),
    .intx_deassert (intx_deassert_w),
    .pme_msg       (pme_msg_w),
    .err_msg_type  (err_msg_type_w),
    .err_msg_valid (err_msg_valid_w),
    .vdm_data      (vdm_data_w),
    .vdm_valid     (vdm_valid_w),
    .msg_to_aer    (msg_to_aer_w)
);

pcie_atomic_op_handler U_ATOP (
    .clk             (clk),
    .rst_n           (rst_n),
    .tlp_atomic      (routed_tlp),
    .tlp_atomic_valid(to_atomic_valid),
    .atomic_type     (atomic_type_w),
    .atomic_addr     (atomic_addr_w),
    .atomic_operand  (atomic_operand_w),
    .atop_rd_addr    (atop_rd_addr_w),
    .atop_wr_data    (atop_wr_data_w),
    .atop_wr_en      (atop_wr_en_w),
    .atop_cpl_data   (atop_cpl_data_w),
    .atop_cpl_valid  (atop_cpl_valid_w),
    .atop_tag        (atop_tag_w)
);

cfg_space_handler U_CFG (
    .clk          (clk),
    .rst_n        (rst_n),
    .tlp_cfg      (tlp_cfg_in),
    .tlp_cfg_valid(tlp_cfg_valid),
    .cfg_addr     (cfg_addr),
    .cfg_wr_data  (cfg_wr_data),
    .cfg_wr_en    (cfg_wr_en),
    .cfg_rd_data  (cfg_rd_data),
    .cfg_rd_valid (cfg_rd_valid),
    .cfg_cpl_tlp  (),
    .cfg_cpl_valid(),
    .max_payload  (max_payload_cfg),
    .flit_mode_en (flit_mode_en_cfg),
    .ecrc_en      (ecrc_en_cfg),
    .ro_en        (ro_en_cfg)
);

tmo_err_manager U_TMO_ERR (
    .clk             (clk),
    .rst_n           (rst_n),
    .tag_start       (tag_alloc),
    .tag_start_valid (tag_valid_w),
    .tag_return_valid(cpl_tag_return_valid),
    .tag_returned    (cpl_tag_return),
    .timeout_limit   (16'd50000),
    .timeout_tag     (tmo_timeout_tag),
    .timeout_valid   (tmo_timeout_valid),
    .cpl_timeout_err (tmo_cpl_timeout_err),
    .err_to_aer      (tmo_err_to_aer)
);

aer_error_logger U_AER (
    .clk          (clk),
    .rst_n        (rst_n),
    .err_from_tmo (tmo_err_to_aer),
    .err_from_cpl ({3'b0, cpl_match_err}),
    .err_from_mal (mal_err),
    .err_from_psnd(poisoned_detected),
    .err_from_msg (msg_to_aer_w),
    .err_from_flit(flit_overflow_err_w),
    .dll_err      (4'h0),
    .err_severity (2'b01),
    .aer_status   (aer_status),
    .aer_mask     (aer_mask_w),
    .aer_int      (aer_int),
    .err_msg_tlp  (err_msg_tlp),
    .err_msg_valid(err_msg_valid)
);

cpl_timeout_logic U_CPL_TMO (
    .clk             (clk),
    .rst_n           (rst_n),
    .tag_alloc       (tag_alloc),
    .tag_alloc_valid (tag_valid_w),
    .tag_return      (cpl_tag_return),
    .tag_return_valid(cpl_tag_return_valid),
    .cpl_timeout_val (20'd100000),
    .timeout_tag     (cpltmo_timeout_tag),
    .timeout_fired   (cpltmo_timeout_fired),
    .cpl_abort_req   (cpltmo_cpl_abort_req),
    .err_to_aer      (cpltmo_err_to_aer)
);

fc_init_timer U_FC_INIT_TMR (
    .clk                (clk),
    .rst_n              (rst_n),
    .fc_init_start      (dll_up),
    .fc_init_done       (fc_init_done),
    .fc_init_timeout_val(16'd10000),
    .fc_init_timeout    (fc_init_timeout_w),
    .fc_init_retry_req  (fc_init_retry_req_w),
    .fc_init_err        (fc_init_err_w)
);

ro_ctrl U_RO_CTRL (
    .clk              (clk),
    .rst_n            (rst_n),
    .req_attr_ro      (ord_req_ro),
    .req_type         (ord_req_type),
    .req_tc           (ord_req_tc),
    .ro_en            (ro_en_cfg),
    .ordering_stall   (ordering_stall),
    .ro_bypass_ok     (ro_bypass_ok_w),
    .ordering_override(ordering_override_w),
    .ro_err           (ro_err_w)
);

vc_arbiter U_VC_ARB (
    .clk         (clk),
    .rst_n       (rst_n),
    .vc0_req     (vc0_req),
    .vc1_req     (vc1_req),
    .vc2_req     (vc2_req),
    .vc3_req     (vc3_req),
    .vc_arb_scheme(vc_arb_scheme),
    .vc_weight   (vc_weight),
    .vc_grant    (vc_grant),
    .vc_grant_id (vc_grant_id),
    .vc_arb_valid(vc_arb_valid)
);

assign fc_init_done_out      = fc_init_done;
assign ordering_ok_out       = ordering_ok;
assign tag_exhausted_out     = tag_exhausted;
assign outstanding_count_out = outstanding_count;

endmodule
