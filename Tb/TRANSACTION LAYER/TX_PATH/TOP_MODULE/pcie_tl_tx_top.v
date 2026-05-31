
`timescale 1ns/1ps

module pcie_tl_tx_top #(
    parameter REQ_Q_DEPTH_P  = 16,
    parameter REQ_Q_DEPTH_NP = 16,
    parameter ROB_DEPTH      = 32
)(

    input  wire         clk,
    input  wire         rst_n,

    input  wire [3:0]   req_type,
    input  wire [63:0]  req_addr,
    input  wire [9:0]   req_len,
    input  wire [511:0] req_data,
    input  wire         req_valid,
    input  wire [2:0]   req_attr,
    input  wire [2:0]   req_tc,
    input  wire [3:0]   req_first_be,
    input  wire [3:0]   req_last_be,
    output wire         req_ready,

    input  wire [511:0] cpl_data_in,
    input  wire         cpl_valid_in,
    input  wire [2:0]   cpl_status_in,
    input  wire [9:0]   cpl_tag_in,
    output wire [511:0] usr_cpl_data,
    output wire         usr_cpl_valid,
    output wire [2:0]   usr_cpl_status,
    output wire [9:0]   usr_cpl_tag,

    input  wire [511:0] mwr_data_in,
    input  wire         mwr_valid_in,
    input  wire [63:0]  mwr_addr_in,
    output wire [511:0] usr_mwr_data,
    output wire         usr_mwr_valid,
    output wire [63:0]  usr_mwr_addr,

    input  wire [127:0] ltp_data,
    input  wire         ltp_valid,
    input  wire [127:0] eetp_data,
    input  wire         eetp_valid,

    input  wire         ecrc_en,

    input  wire [2:0]   max_payload,
    input  wire         flit_mode_en,

    input  wire         dll_up,
    input  wire         dll_ack,
    input  wire         dll_nak,
    input  wire         dll_flit_ack,
    input  wire [71:0]  cr_update,
    input  wire         cr_update_valid,

    input  wire [71:0]  initfc_rx,
    input  wire         initfc_rx_valid,

    input  wire [9:0]   timeout_tag,

    output wire [2047:0] flit_to_dll,
    output wire          flit_to_dll_valid,
    output wire          dll_ready,

    output wire [1023:0] tlp_rx_out,
    output wire          tlp_rx_valid,

    output wire [71:0]  initfc_tx,
    output wire         initfc_tx_send,

    output wire         fc_init_done,
    output wire         prefix_err,
    output wire         e2e_fwd,
    output wire         ecrc_rx_ok,
    output wire         ecrc_rx_err,
    output wire         ordering_ok,
    output wire         ordering_stall,
    output wire         ordering_err,
    output wire         tag_exhausted,
    output wire [9:0]   tag_alloc,
    output wire         tag_valid,
    output wire [9:0]   outstanding_count,
    output wire [7:0]   dbg_ph_avail,
    output wire [11:0]  dbg_pd_avail,
    output wire [7:0]   dbg_nph_avail,
    output wire [11:0]  dbg_npd_avail,
    output wire         flit_retry_req,
    output wire         flit_overflow_err,
    output wire [23:0]  flit_crc,
    output wire [11:0]  flit_seq
);

wire [603:0] usr_pkt_out;
wire         usr_pkt_valid;
wire         usr_pkt_ready;

wire [575:0] rq_req_out;
wire         rq_req_valid_out;
wire [1:0]   rq_req_type_out;
wire         rq_q_full_p;
wire         rq_q_full_np;

wire         credit_grant_p;
wire         credit_grant_np;
wire         credit_grant_cpl;

wire req_p_valid  = rq_req_valid_out && (rq_req_type_out == 2'b00);
wire req_np_valid = rq_req_valid_out && (rq_req_type_out == 2'b01);

wire [575:0] arb_tlp;
wire         arb_tlp_valid;
wire [1:0]   arb_type;

wire [7:0]   adv_ph;
wire [11:0]  adv_pd;
wire [7:0]   adv_nph;
wire [7:0]   adv_cplh;
wire [11:0]  adv_cpld;

wire [1023:0] tlp_asm_out;
wire          tlp_asm_valid;
wire          tlp_asm_sop;
wire          tlp_asm_eop;
wire [127:0]  tlp_asm_hdr;
wire [127:0]  tlp_asm_be;

wire [1151:0] tlp_prefixed;
wire          tlp_prefixed_valid;

wire [1183:0] tlp_ecrc_tx;
wire          tlp_ecrc_valid;

wire [1023:0] ecrc_to_flit = tlp_ecrc_tx[1055:32];

wire [2047:0] flit_out_w;
wire          flit_valid_w;
wire [23:0]   flit_crc_w;
wire [11:0]   flit_seq_w;

wire tlp_sent_wire  = arb_tlp_valid;
wire tlp_is_np_wire = (arb_type == 2'b01);

wire [9:0] tlp_len_wire = arb_tlp[507:498];

wire ord_ordering_ok;
wire ord_ordering_stall;
wire ord_ordering_err;

wire arb_ordering_ok = ord_ordering_ok | rq_req_valid_out;

wire [15:0] ord_req_id  = req_addr[15:0];
wire [15:0] ord_cpl_id  = {6'b0, cpl_tag_in[9:0]};

wire [575:0] rq_req_in = usr_pkt_out[603:28];

usr_if u_usr_if (
    .clk            (clk),
    .rst_n          (rst_n),

    .req_type       (req_type),
    .req_addr       (req_addr),
    .req_len        (req_len),
    .req_data       (req_data),
    .req_valid      (req_valid),
    .req_attr       (req_attr),
    .req_tc         (req_tc),
    .req_first_be   (req_first_be),
    .req_last_be    (req_last_be),
    .req_ready      (req_ready),

    .pkt_out        (usr_pkt_out),
    .pkt_valid      (usr_pkt_valid),
    .pkt_ready      (usr_pkt_ready),

    .cpl_data       (cpl_data_in),
    .cpl_valid      (cpl_valid_in),
    .cpl_status     (cpl_status_in),
    .cpl_tag        (cpl_tag_in),
    .usr_cpl_data   (usr_cpl_data),
    .usr_cpl_valid  (usr_cpl_valid),
    .usr_cpl_status (usr_cpl_status),
    .usr_cpl_tag    (usr_cpl_tag),

    .mwr_data       (mwr_data_in),
    .mwr_valid      (mwr_valid_in),
    .mwr_addr       (mwr_addr_in),
    .usr_mwr_data   (usr_mwr_data),
    .usr_mwr_valid  (usr_mwr_valid),
    .usr_mwr_addr   (usr_mwr_addr)
);

req_q #(
    .DEPTH_P  (REQ_Q_DEPTH_P),
    .DEPTH_NP (REQ_Q_DEPTH_NP),
    .WIDTH    (576)
) u_req_q (
    .clk            (clk),
    .rst_n          (rst_n),
    .req_in         (rq_req_in),
    .req_valid_in   (usr_pkt_valid),
    .credit_grant_p (credit_grant_p),
    .credit_grant_np(credit_grant_np),
    .req_out        (rq_req_out),
    .req_valid_out  (rq_req_valid_out),
    .req_type_out   (rq_req_type_out),
    .q_full_p       (rq_q_full_p),
    .q_full_np      (rq_q_full_np),
    .q_occ_p        (),
    .q_occ_np       ()
);

assign usr_pkt_ready = !rq_q_full_p && !rq_q_full_np;

tag_manager u_tag_mgr (
    .clk              (clk),
    .rst_n            (rst_n),

    .tag_req          (usr_pkt_valid && req_ready && (req_type != 4'd1)),
    .tag_return       (cpl_tag_in),
    .tag_return_valid (cpl_valid_in),
    .timeout_tag      (timeout_tag),
    .tag_alloc        (tag_alloc),
    .tag_valid        (tag_valid),
    .tag_exhausted    (tag_exhausted),
    .outstanding_count(outstanding_count),
    .req_addr_lkup    (),
    .req_len_lkup     (),
    .req_type_lkup    ()
);

fc_init_fsm u_fc_init (
    .clk            (clk),
    .rst_n          (rst_n),
    .dll_up         (dll_up),
    .initfc_rx      (initfc_rx),
    .initfc_rx_valid(initfc_rx_valid),
    .initfc_tx      (initfc_tx),
    .initfc_tx_send (initfc_tx_send),
    .fc_init_done   (fc_init_done),
    .adv_ph         (adv_ph),
    .adv_pd         (adv_pd),
    .adv_nph        (adv_nph),
    .adv_cplh       (adv_cplh),
    .adv_cpld       (adv_cpld)
);

cr_mgr u_cr_mgr (
    .clk              (clk),
    .rst_n            (rst_n),
    .fc_init_done     (fc_init_done),
    .init_ph          (adv_ph),
    .init_pd          (adv_pd),
    .init_nph         (adv_nph),
    .init_npd         (12'd0),
    .init_cplh        (adv_cplh),
    .init_cpld        (adv_cpld),

    .upd_ph           (cr_update[71:64]),
    .upd_pd           (cr_update[63:52]),
    .upd_nph          (cr_update[51:44]),
    .upd_npd          (cr_update[43:32]),
    .upd_cplh         (cr_update[31:24]),
    .upd_cpld         (cr_update[23:12]),
    .upd_valid        (cr_update_valid),

    .tlp_sent         (tlp_sent_wire),
    .tlp_is_np        (tlp_is_np_wire),
    .tlp_len          (tlp_len_wire),

    .credit_grant_p   (credit_grant_p),
    .credit_grant_np  (credit_grant_np),
    .credit_grant_cpl (credit_grant_cpl),

    .dbg_ph_avail     (dbg_ph_avail),
    .dbg_pd_avail     (dbg_pd_avail),
    .dbg_nph_avail    (dbg_nph_avail),
    .dbg_npd_avail    (dbg_npd_avail)
);

pcie_ordering_rob #(
    .ROB_DEPTH     (ROB_DEPTH),
    .ROB_PTR_WIDTH (5),
    .NUM_TC        (8)
) u_ord (
    .clk           (clk),
    .rst_n         (rst_n),
    .req_id        (ord_req_id),
    .req_type      (req_type),
    .req_tc        (req_tc),
    .req_attr_ro   (req_attr[2]),
    .req_valid     (req_valid && req_ready),
    .cpl_id        (ord_cpl_id[15:0]),
    .cpl_valid     (cpl_valid_in),
    .ordering_ok   (ord_ordering_ok),
    .ordering_stall(ord_ordering_stall),
    .ordering_err  (ord_ordering_err)
);

assign ordering_ok    = ord_ordering_ok;
assign ordering_stall = ord_ordering_stall;
assign ordering_err   = ord_ordering_err;

arb_tx u_arb_tx (
    .clk            (clk),
    .rst_n          (rst_n),
    .req_p_valid    (req_p_valid),
    .req_np_valid   (req_np_valid),
    .req_p          (rq_req_out),
    .req_np         (rq_req_out),
    .credit_grant_p (credit_grant_p),
    .credit_grant_np(credit_grant_np),
    .ordering_ok    (arb_ordering_ok),
    .arb_tlp        (arb_tlp),
    .arb_tlp_valid  (arb_tlp_valid),
    .arb_type       (arb_type)
);

tlp_assembler u_tlp_asm (
    .clk          (clk),
    .rst_n        (rst_n),
    .arb_tlp_in   (arb_tlp),
    .arb_tlp_valid(arb_tlp_valid),
    .prefix_in    (ltp_data),
    .prefix_valid (ltp_valid),
    .ecrc_in      (32'd0),
    .credit_ok    (credit_grant_p || credit_grant_np),
    .max_payload  (max_payload),
    .tlp_out      (tlp_asm_out),
    .tlp_valid    (tlp_asm_valid),
    .tlp_sop      (tlp_asm_sop),
    .tlp_eop      (tlp_asm_eop),
    .tlp_hdr      (tlp_asm_hdr),
    .tlp_be       (tlp_asm_be)
);

tlp_prefix_handler u_pfx (
    .clk               (clk),
    .rst_n             (rst_n),
    .tlp_in            (tlp_asm_out),
    .tlp_valid_in      (tlp_asm_valid),
    .ltp_data          (ltp_data),
    .ltp_valid         (ltp_valid),
    .eetp_data         (eetp_data),
    .eetp_valid        (eetp_valid),
    .tlp_prefixed      (tlp_prefixed),
    .tlp_prefixed_valid(tlp_prefixed_valid),
    .prefix_err        (prefix_err),
    .e2e_fwd           (e2e_fwd)
);

ecrc u_ecrc (
    .clk           (clk),
    .rst_n         (rst_n),
    .tlp_tx        (tlp_prefixed),
    .tlp_tx_valid  (tlp_prefixed_valid),
    .tlp_rx        (tlp_prefixed),
    .tlp_rx_valid  (1'b0),
    .ecrc_en       (ecrc_en),
    .tlp_ecrc_tx   (tlp_ecrc_tx),
    .tlp_ecrc_valid(tlp_ecrc_valid),
    .ecrc_rx_ok    (ecrc_rx_ok),
    .ecrc_rx_err   (ecrc_rx_err)
);

flit_mode_controller u_flit (
    .clk             (clk),
    .rst_n           (rst_n),
    .tlp_in          (ecrc_to_flit),
    .tlp_valid_in    (tlp_ecrc_valid),
    .flit_mode_en    (flit_mode_en),
    .dll_flit_ack    (dll_flit_ack),
    .flit_out        (flit_out_w),
    .flit_valid      (flit_valid_w),
    .flit_crc        (flit_crc_w),
    .flit_seq        (flit_seq_w),
    .flit_retry_req  (flit_retry_req),
    .flit_overflow_err(flit_overflow_err)
);

assign flit_crc = flit_crc_w;
assign flit_seq = flit_seq_w;

DLL_IF u_dll_if (
    .clk             (clk),
    .rst_n           (rst_n),
    .flit_in         (flit_out_w),
    .flit_valid_in   (flit_valid_w),
    .dll_ack         (dll_ack),
    .dll_nak         (dll_nak),
    .dll_up          (dll_up),
    .cr_update       (cr_update),
    .cr_update_valid (cr_update_valid),
    .tlp_rx_out      (tlp_rx_out),
    .tlp_rx_valid    (tlp_rx_valid),
    .flit_to_dll     (flit_to_dll),
    .flit_to_dll_valid(flit_to_dll_valid),
    .dll_ready       (dll_ready)
);

endmodule
