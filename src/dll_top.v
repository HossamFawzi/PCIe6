// =============================================================================
// Module   : dll_top
// Title    : PCIe Gen6 Data Link Layer — Top-Level Integration
// Desc     : Instantiates and wires all 36 DLL sub-modules in the correct
//            RX and TX datapath order as defined by the PCIe 6.0 Base Spec.
//
// TX Path (top-down):
//   TL_INTERFACE → SEQ_NUM_GEN → RETRY_BUF / TX_MUX → SCRAMBLER →
//   DLLP_GEN → DLLP_CRCG → DLLP_ARB → NULL_INS → PCIE6_PHY_TX
//
// RX Path (top-down):
//   PHY_INTERFACE_RX → DESCRAMBLER → FLIT_RX_DEFRAMER →
//   RX_DEMUX → [TLP: LCRC_CHK → SEQ_CHK_RX → ACK_NAK_SCHED_TX]
//              [DLLP: DLLP_CRC_CHK → DLLP_MAL_CHK → DLLP_RX_DEC → ACK_NAK_RX]
//
// Support: DLL_INIT, FC_INIT_FSM, FC_TMR, FC_WDG, ACK_PGB, ACK_TMR,
//          RETRY_FSM, FLIT_SEQ, LBW_FSM, NOP_GEN, NULL_HDL,
//          PM_FSM, PM_TMR, DLL_ERR
// =============================================================================

`timescale 1ns/1ps

module dll_top (
    // ── Clock & Reset ──────────────────────────────────────────────────────
    input  wire          clk,
    input  wire          rst_n,

    // ── PHY RX interface ───────────────────────────────────────────────────
    input  wire [255:0]  phy_rxd,
    input  wire          phy_rx_valid,
    input  wire [2:0]    phy_rx_status,
    input  wire [15:0]   fec_syndrome,
    input  wire          fec_corrected,

    // ── PHY TX interface ───────────────────────────────────────────────────
    output wire [255:0]  phy_txd,
    output wire          phy_tx_valid,
    output wire          phy_tx_elec_idle,
    output wire          phy_tx_compliance,

    // ── TL interface ───────────────────────────────────────────────────────
    input  wire [1023:0] tlp_from_tl,
    input  wire          tlp_from_tl_valid,
    input  wire [2047:0] flit_from_tl,
    input  wire          flit_from_tl_valid,
    input  wire [7:0]    fc_update_ph,
    input  wire          fc_update_valid,

    output wire [1023:0] tlp_to_tl,
    output wire          tlp_to_tl_valid,

    // ── LTSSM interface ────────────────────────────────────────────────────
    input  wire          ltssm_dl_up,
    input  wire          ltssm_dl_down,
    input  wire [3:0]    ltssm_speed,
    input  wire [5:0]    ltssm_width,

    // ── PHY TX control ─────────────────────────────────────────────────────
    input  wire          tx_elec_idle_req,
    input  wire          tx_compliance_req,

    // ── Mode & Config ──────────────────────────────────────────────────────
    input  wire          flit_mode_en,
    input  wire [22:0]   lfsr_seed,
    input  wire          scramble_en,
    input  wire [7:0]    ack_freq,
    input  wire [15:0]   ack_lat_limit,
    input  wire [15:0]   replay_limit,
    input  wire [15:0]   fc_timer_limit,
    input  wire [15:0]   fc_watchdog_limit,
    input  wire [15:0]   l0s_limit,
    input  wire [15:0]   l1_limit,
    input  wire [2:0]    pm_req_sw,

    // ── Status outputs ─────────────────────────────────────────────────────
    output wire          dll_up_to_tl,
    output wire          dll_active,
    output wire          dll_error,
    output wire [5:0]    dll_err_to_aer,
    output wire          dll_err_valid,
    output wire [3:0]    dll_err_type,
    output wire [1:0]    dll_err_severity,
    output wire [2:0]    link_state,
    output wire          fc_deadlock_det,
    output wire          replay_rollover_err,
    // FIX-STUB-2: DLLP arbiter output exposed so system_top can feed phy_top flit_framer
    output wire [63:0]   dllp_arb_out_o,
    output wire          dllp_arb_valid_o,
    // FIX-STUB-3: UpdateFC RX values exposed so system_top can drive TL cr_mgr
    output wire [7:0]    fc_update_ph_rx_o,
    output wire [11:0]   fc_update_pd_rx_o,
    output wire [7:0]    fc_update_nph_rx_o,
    output wire [7:0]    fc_update_cplh_rx_o,
    output wire [11:0]   fc_update_cpld_rx_o,
    output wire          fc_update_valid_rx_o
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // DLL_INIT
    wire dll_reset_seq;
    wire dll_link_down_init;

    // PHY_RX → DESCRAMBLER
    wire [255:0]  rx_data_beat;
    wire          rx_beat_valid;
    wire [2047:0] rx_flit_raw;
    wire          rx_flit_raw_valid;

    // DESCRAMBLER → FLIT_RX / RX path
    wire [255:0]  descram_data;
    wire          descram_valid;
    wire          lfsr_sync_err;

    // FLIT_RX_DEFRAMER outputs
    wire [1023:0] flit_tlp;
    wire          flit_tlp_valid;
    wire [63:0]   flit_dllp;
    wire          flit_dllp_valid;
    wire [11:0]   flit_seq_rx;
    wire          flit_crc_err;
    wire          flit_null_flag;
    wire          flit_uncorr_err;

    // RX_DEMUX outputs
    wire [1055:0] tlp_rx;
    wire          tlp_rx_valid;
    wire [63:0]   dllp_raw;
    wire          dllp_rx_valid;
    wire          rx_parse_err;

    // LCRC_CHK outputs
    wire          lcrc_ok;
    wire          lcrc_err;
    wire [1023:0] tlp_clean;
    wire          tlp_clean_valid;
    wire [11:0]   seq_rx_lcrc;

    // SEQ_CHK outputs
    wire          tlp_seq_ok;
    wire          tlp_dup;
    wire          tlp_seq_err;
    wire          nak_req_seq;
    wire          seq_dup_ack;
    wire [11:0]   seq_err_val;
    wire [11:0]   next_expected;

    // DLLP_CRC_CHK outputs
    wire [47:0]   dllp_body;
    wire          dllp_crc_ok;
    wire          dllp_crc_err;
    wire          dllp_valid_out;

    // DLLP_MAL_CHK outputs
    wire          dllp_type_ok;
    wire          dllp_mal_err;
    wire [47:0]   dllp_clean;
    wire          dllp_clean_valid;

    // DLLP_RX_DEC outputs
    wire [7:0]    fc_update_ph_rx;
    wire [11:0]   fc_update_pd_rx;
    wire [7:0]    fc_update_nph_rx;
    wire [7:0]    fc_update_cplh_rx;
    wire [11:0]   fc_update_cpld_rx;
    wire          fc_update_valid_rx;
    wire [2:0]    pm_type_rx;
    wire          pm_valid_rx;
    wire [23:0]   ack_out;
    wire          ack_out_valid;

    // ACK_NAK_RX outputs
    wire [11:0]   ack_seq;
    wire [11:0]   nak_seq;
    wire          ack_valid;
    wire          nak_valid;
    wire          retry_req_rx;

    // ACK_NAK_SCHED_TX outputs
    wire [63:0]   ack_dllp;
    wire [63:0]   nak_dllp;
    wire          dllp_sched_valid;
    wire [1:0]    dllp_sched_type;

    // TL_INTERFACE outputs
    wire [1023:0] dll_tlp;
    wire          dll_tlp_valid;
    wire [2047:0] dll_flit;
    wire          dll_flit_valid;
    wire          tl_ready;
    wire [71:0]   fc_to_dllp;
    wire          fc_dllp_send;

    // SEQ_NUM_GEN outputs
    wire [11:0]   seq_num_tx;
    wire          seq_valid_tx;
    wire          seq_wrap_tx;

    // RETRY_BUF outputs
    wire [1055:0] retry_tlp;
    wire          retry_valid_buf;
    wire [11:0]   retry_seq_buf;
    wire          buf_full;
    wire [11:0]   buf_occ;
    wire          purge_done;

    // REPLAY_FSM outputs
    wire          retry_req_fsm;
    wire [11:0]   retry_seq_start;
    wire          dll_link_down_fsm;

    // ACK_TMR outputs
    wire          ack_timer_exp;
    wire          replay_timer_exp;
    wire [1:0]    replay_num;

    // ACK_PGB outputs
    wire [11:0]   ack_piggyback_seq;
    wire          ack_piggyback_valid;
    wire          ack_sent;

    // DLLP_GEN outputs
    wire [63:0]   fc_dllp_out;
    wire          fc_dllp_valid_out;
    wire [63:0]   pm_dllp_out;
    wire          pm_dllp_valid_out;
    wire [63:0]   nop_dllp_gen_out;
    wire          nop_valid_gen;

    // DLLP_CRCG outputs
    wire [15:0]   dllp_crc_tx;
    wire          dllp_crc_valid_tx;
    wire [63:0]   dllp_full_tx;

    // DLLP_ARB outputs
    wire [63:0]   dllp_arb_out;
    wire          dllp_arb_valid;
    wire [3:0]    dllp_arb_type;

    // CRC_GEN outputs
    wire [31:0]   lcrc_out_tx;
    wire [23:0]   flit_crc_out_tx;
    wire          crc_valid_tx;

    // SCRAMBLER outputs
    wire [255:0]  scram_data_out;
    wire          scram_valid_out;
    wire [22:0]   lfsr_state_tx;

    // TX_MUX outputs
    wire [255:0]  mux_phy_data;
    wire          mux_phy_valid;
    wire          mux_phy_sop;
    wire          mux_phy_eop;

    // NULL_INS outputs
    wire [2047:0] flit_null_ins_out;
    wire          flit_null_ins_valid;
    wire          null_inserted;
    wire [7:0]    null_count_tx;

    // FLIT_SEQ outputs
    wire [11:0]   oldest_unacked_seq;
    wire          seq_window_full;
    wire          seq_wrap_det;
    wire          seq_err_flit;

    // FC_INIT_FSM outputs
    wire [71:0]   initfc_tx;
    wire          initfc_tx_send;
    wire          fc_init_done;
    wire          fc_init_err;
    wire [2:0]    fc_init_state;

    // FC_TMR outputs
    wire          fc_update_req;
    wire          fc_timer_exp;

    // FC_WDG outputs
    wire          fc_watchdog_err;
    wire          fc_recovery_req;

    // LBW_FSM outputs
    wire [63:0]   bw_notif_dllp;
    wire          bw_notif_valid;
    wire          link_eq_req;
    wire          link_eq_ack;
    wire [7:0]    bw_status;

    // NOP_GEN outputs
    wire          nop_send;
    wire [63:0]   nop_dllp_out;
    wire [7:0]    nop_count;

    // PM_FSM outputs
    wire [2:0]    pm_dllp_type_tx;
    wire          pm_dllp_send;
    wire [2:0]    ltssm_pm_req;

    // PM_TMR outputs
    wire          l0s_timer_exp;
    wire          l1_timer_exp;
    wire          pm_timeout_err;

    // NULL_HDL outputs
    wire          null_drop;
    wire [7:0]    null_hdl_count;

    // Combined dll_link_down
    wire          dll_link_down = dll_link_down_init | dll_link_down_fsm;

    // ack_pending for ACK_PGB (from ack_timer)
    wire          ack_pending_sig;

    // =========================================================================
    // RX PATH
    // =========================================================================

    // -- PHY_INTERFACE_RX -----------------------------------------------------
    phy_interface_rx u_phy_rx (
        .clk            (clk),
        .rst_n          (rst_n),
        .phy_rxd        (phy_rxd),
        .phy_rx_valid   (phy_rx_valid),
        .phy_rx_status  (phy_rx_status),
        .fec_syndrome   (fec_syndrome),
        .fec_corrected  (fec_corrected),
        .ltssm_dl_up    (ltssm_dl_up),
        .rx_data        (rx_data_beat),
        .rx_valid       (rx_beat_valid),
        .rx_flit        (rx_flit_raw),
        .rx_flit_valid  (rx_flit_raw_valid)
    );

    // -- DESCRAMBLER (RX) -----------------------------------------------------
    descrambler u_descrambler (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in        (rx_flit_raw[255:0]),   // first beat for legacy; full for FLIT
        .data_valid_in  (rx_beat_valid),
        .lfsr_seed      (lfsr_seed),
        .scramble_en    (scramble_en),
        .link_reset     (dll_reset_seq),
        .data_out       (descram_data),
        .data_valid_out (descram_valid),
        .lfsr_sync_err  (lfsr_sync_err)
    );

    // -- FLIT_RX_DEFRAMER -----------------------------------------------------
    flit_rx_deframer u_flit_rx (
        .clk            (clk),
        .rst_n          (rst_n),
        .rx_flit        (rx_flit_raw),
        .rx_flit_valid  (rx_flit_raw_valid),
        .fec_syndrome   (fec_syndrome),
        .fec_corrected  (fec_corrected),
        .flit_tlp       (flit_tlp),
        .flit_tlp_valid (flit_tlp_valid),
        .flit_dllp      (flit_dllp),
        .flit_dllp_valid(flit_dllp_valid),
        .flit_seq       (flit_seq_rx),
        .flit_crc_err   (flit_crc_err),
        .flit_null      (flit_null_flag),
        .flit_uncorr_err(flit_uncorr_err)
    );

    // -- NULLIFIED_TLP_HANDLER ------------------------------------------------
    nullified_tlp_handler u_null_hdl (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_null      (flit_null_flag),
        .flit_slot_data (flit_tlp),
        .flit_slot_valid(flit_tlp_valid | flit_dllp_valid),
        .null_drop      (null_drop),
        .null_count     (null_hdl_count)
    );

    // -- RX_DATAPATH_DEMUX ----------------------------------------------------
    rx_datapath_demux u_rx_demux (
        .clk            (clk),
        .rst_n          (rst_n),
        .rx_data        ({8'hFB, descram_data[247:0]}),  // legacy: add STP framing
        .rx_valid       (descram_valid & ~flit_mode_en),
        .flit_tlp       (flit_tlp),
        .flit_tlp_valid (flit_tlp_valid),
        .flit_dllp      (flit_dllp),
        .flit_dllp_valid(flit_dllp_valid),
        .flit_mode_en   (flit_mode_en),
        .tlp_rx         (tlp_rx),
        .tlp_rx_valid   (tlp_rx_valid),
        .dllp_raw       (dllp_raw),
        .dllp_rx_valid  (dllp_rx_valid),
        .rx_parse_err   (rx_parse_err)
    );

    // -- LCRC / FLIT CRC CHECKER ----------------------------------------------
    lcrc_flit_crc_chk u_crc_chk (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_rx         (tlp_rx),
        .tlp_rx_valid   (tlp_rx_valid),
        .flit_mode_en   (flit_mode_en),
        .flit_seq_in    (flit_seq_rx),      // FIX: FLIT seq for seq checker in FLIT mode
        .crc_ok         (lcrc_ok),
        .crc_err        (lcrc_err),
        .tlp_clean      (tlp_clean),
        .tlp_clean_valid(tlp_clean_valid),
        .seq_rx         (seq_rx_lcrc)
    );

    // -- SEQ_NUM_CHECKER_RX ---------------------------------------------------
    seq_num_checker_rx u_seq_chk (
        .clk            (clk),
        .rst_n          (rst_n),
        .link_reset     (dll_reset_seq),
        .seq_rx         (seq_rx_lcrc),
        .tlp_rx_valid   (tlp_clean_valid),
        .tlp_ok         (lcrc_ok),
        .tlp_clean      (tlp_clean),
        .tlp_seq_ok     (tlp_seq_ok),
        .tlp_dup        (tlp_dup),
        .tlp_seq_err    (tlp_seq_err),
        .nak_req        (nak_req_seq),
        .seq_dup_ack    (seq_dup_ack),
        .seq_err_val    (seq_err_val),
        .next_expected  (next_expected),
        .tlp_fwd        (tlp_to_tl),
        .tlp_fwd_valid  (tlp_to_tl_valid)
    );

    // -- ACK_NAK_SCHEDULER_TX -------------------------------------------------
    ack_nak_scheduler_tx u_ack_sched (
        .clk            (clk),
        .rst_n          (rst_n),
        .seq_rx         (seq_rx_lcrc),
        .crc_ok         (lcrc_ok),
        .tlp_rx_valid   (tlp_rx_valid),
        .ack_timer_exp  (ack_timer_exp),
        .ack_freq       (ack_freq),
        .ack_dllp       (ack_dllp),
        .nak_dllp       (nak_dllp),
        .dllp_valid     (dllp_sched_valid),
        .dllp_type      (dllp_sched_type)
    );

    // -- DLLP CRC CHECKER -----------------------------------------------------
    dllp_crc_chk u_dllp_crc_chk (
        .clk            (clk),
        .rst_n          (rst_n),
        .dllp_raw       (dllp_raw),
        .dllp_rx_valid  (dllp_rx_valid),
        .dllp_body      (dllp_body),
        .dllp_crc_ok    (dllp_crc_ok),
        .dllp_crc_err   (dllp_crc_err),
        .dllp_valid_out (dllp_valid_out)
    );

    // -- DLLP MALFORMED CHECKER -----------------------------------------------
    dllp_mal_chk u_dllp_mal (
        .clk            (clk),
        .rst_n          (rst_n),
        .dllp_body      (dllp_body),
        .dllp_crc_ok    (dllp_crc_ok),
        .dllp_valid_in  (dllp_valid_out),
        .dllp_type_ok   (dllp_type_ok),
        .dllp_mal_err   (dllp_mal_err),
        .dllp_clean     (dllp_clean),
        .dllp_clean_valid(dllp_clean_valid)
    );

    // -- DLLP RECEIVER DECODER ------------------------------------------------
    dllp_receiver_decoder u_dllp_rx_dec (
        .clk            (clk),
        .rst_n          (rst_n),
        .dllp_clean     (dllp_clean),
        .dllp_clean_valid(dllp_clean_valid),
        .fc_update_ph   (fc_update_ph_rx),
        .fc_update_pd   (fc_update_pd_rx),
        .fc_update_nph  (fc_update_nph_rx),
        .fc_update_cplh (fc_update_cplh_rx),
        .fc_update_cpld (fc_update_cpld_rx),
        .fc_update_valid(fc_update_valid_rx),
        .pm_type        (pm_type_rx),
        .pm_valid       (pm_valid_rx),
        .ack_out        (ack_out),
        .ack_out_valid  (ack_out_valid)
    );

    // -- ACK_NAK_RECEIVER -----------------------------------------------------
    ack_nak_receiver u_ack_rx (
        .clk            (clk),
        .rst_n          (rst_n),
        .ack_out        (ack_out),
        .ack_out_valid  (ack_out_valid),
        .ack_seq        (ack_seq),
        .nak_seq        (nak_seq),
        .ack_valid      (ack_valid),
        .nak_valid      (nak_valid),
        .retry_req      (retry_req_rx)
    );

    // =========================================================================
    // TX PATH
    // =========================================================================

    // -- TL_INTERFACE ---------------------------------------------------------
    tl_interface u_tl_if (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_in         (tlp_from_tl),
        .tlp_valid_in   (tlp_from_tl_valid),
        .flit_in        (flit_from_tl),
        .flit_valid_in  (flit_from_tl_valid),
        .flit_mode_en   (flit_mode_en),
        .fc_update_ph   (fc_update_ph),
        .fc_update_valid(fc_update_valid),
        .dll_tlp        (dll_tlp),
        .dll_tlp_valid  (dll_tlp_valid),
        .dll_flit       (dll_flit),
        .dll_flit_valid (dll_flit_valid),
        .tl_ready       (tl_ready),
        .fc_to_dllp     (fc_to_dllp),
        .fc_dllp_send   (fc_dllp_send)
    );

    // -- SEQ_NUM_GEN ----------------------------------------------------------
    seq_num_gen u_seq_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_valid_in   (dll_tlp_valid),
        .ack_seq        (ack_seq),
        .nak_seq        (nak_seq),
        .retry_req      (retry_req_fsm),
        .link_reset     (dll_reset_seq),
        .seq_num        (seq_num_tx),
        .seq_valid      (seq_valid_tx),
        .seq_wrap       (seq_wrap_tx)
    );

    // -- RETRY_BUF ------------------------------------------------------------
    retry_buf u_retry_buf (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_in         ({seq_num_tx, 20'h0, dll_tlp}), // FIX-4: 12+20+1024=1056b
        .tlp_write_en   (dll_tlp_valid & ~buf_full),
        .seq_num_in     (seq_num_tx),
        .ack_seq        (ack_seq),
        .nak_seq        (nak_seq),
        .retry_req      (retry_req_fsm),
        .retry_tlp      (retry_tlp),
        .retry_valid    (retry_valid_buf),
        .retry_seq      (retry_seq_buf),
        .buf_full       (buf_full),
        .buf_occ        (buf_occ),
        .purge_done     (purge_done)
    );

    // -- TX_DATAPATH_MUX ------------------------------------------------------
    dll_tx_datapath_mux u_tx_mux (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_tx         ({seq_num_tx, 20'h0, dll_tlp}), // FIX-5: 12+20+1024=1056b
        .tlp_tx_valid   (dll_tlp_valid),
        .retry_tlp      (retry_tlp),
        .retry_valid    (retry_valid_buf),
        .dllp_out       (dllp_arb_out),
        .dllp_valid     (dllp_arb_valid),
        .retry_req      (retry_req_fsm),
        .phy_tx_data    (mux_phy_data),
        .phy_tx_valid   (mux_phy_valid),
        .phy_tx_sop     (mux_phy_sop),
        .phy_tx_eop     (mux_phy_eop)
    );

    // -- SCRAMBLER (TX) -------------------------------------------------------
    scrambler u_scrambler (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in        (mux_phy_data),
        .data_valid_in  (mux_phy_valid),
        .lfsr_seed      (lfsr_seed),
        .scramble_en    (scramble_en),
        .link_reset     (dll_reset_seq),
        .data_out       (scram_data_out),
        .data_valid_out (scram_valid_out),
        .lfsr_state     (lfsr_state_tx)
    );

    // -- PCIE6_PHY_TX ---------------------------------------------------------
    pcie6_phy_tx u_phy_tx (
        .clk                (clk),
        .rst_n              (rst_n),
        .tx_data            (scram_data_out),
        .tx_valid           (scram_valid_out),
        .tx_sop             (mux_phy_sop),
        .tx_eop             (mux_phy_eop),
        .tx_elec_idle_req   (tx_elec_idle_req),
        .tx_compliance_req  (tx_compliance_req),
        .phy_txd            (phy_txd),
        .phy_tx_valid       (phy_tx_valid),
        .phy_tx_elec_idle   (phy_tx_elec_idle),
        .phy_tx_compliance  (phy_tx_compliance)
    );

    // -- CRC_GEN (TX) ---------------------------------------------------------
    crc_gen u_crc_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_in         (dll_tlp),
        .tlp_valid      (dll_tlp_valid),
        .flit_in        (dll_flit),
        .flit_valid     (dll_flit_valid),
        .flit_mode_en   (flit_mode_en),
        .seq_num        (seq_num_tx),
        .lcrc_out       (lcrc_out_tx),
        .flit_crc_out   (flit_crc_out_tx),
        .crc_valid      (crc_valid_tx)
    );

    // =========================================================================
    // DLLP TX PATH
    // =========================================================================

    // -- DLLP_GEN -------------------------------------------------------------
    dllp_gen u_dllp_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .fc_update      (fc_to_dllp),
        .fc_update_valid(fc_update_valid_rx),
        .fc_update_req  (fc_update_req),
        .pm_type        (pm_dllp_type_tx),
        .pm_send        (pm_dllp_send),
        .nop_send       (nop_send),
        .bw_notif       (bw_notif_dllp),
        .bw_notif_valid (bw_notif_valid),
        .fc_dllp        (fc_dllp_out),
        .fc_dllp_valid  (fc_dllp_valid_out),
        .pm_dllp        (pm_dllp_out),
        .pm_dllp_valid  (pm_dllp_valid_out),
        .nop_dllp       (nop_dllp_gen_out),
        .nop_valid      (nop_valid_gen)
    );

    // -- DLLP_CRC_GEN ---------------------------------------------------------
    dllp_crc_gen u_dllp_crcg (
        .clk            (clk),
        .rst_n          (rst_n),
        .dllp_in        (dllp_arb_out[47:0]),
        .dllp_valid_in  (dllp_arb_valid),
        .dllp_crc       (dllp_crc_tx),
        .dllp_crc_valid (dllp_crc_valid_tx),
        .dllp_full      (dllp_full_tx)
    );

    // -- DLLP_ARB -------------------------------------------------------------
    dllp_arb u_dllp_arb (
        .clk            (clk),
        .rst_n          (rst_n),
        .ack_dllp       (dllp_sched_valid ? ack_dllp : nak_dllp),
        .ack_dllp_valid (dllp_sched_valid),
        .fc_dllp        (fc_dllp_out),
        .fc_dllp_valid  (fc_dllp_valid_out),
        .pm_dllp        (pm_dllp_out),
        .pm_dllp_valid  (pm_dllp_valid_out),
        .nop_valid      (nop_valid_gen),
        .bw_dllp_valid  (bw_notif_valid),
        .dllp_out       (dllp_arb_out),
        .dllp_out_valid (dllp_arb_valid),
        .dllp_type      (dllp_arb_type)
    );

    // =========================================================================
    // SUPPORT MODULES
    // =========================================================================

    // -- DLL_INIT -------------------------------------------------------------
    dll_init u_dll_init (
        .clk                (clk),
        .rst_n              (rst_n),
        .ltssm_dl_up        (ltssm_dl_up),
        .ltssm_dl_down      (ltssm_dl_down),
        .fc_init_done       (fc_init_done),
        .replay_rollover_err(replay_rollover_err),
        .dll_link_down      (dll_link_down),
        .dll_up_to_tl       (dll_up_to_tl),
        .dll_reset_seq      (dll_reset_seq),
        .dll_active         (dll_active),
        .dll_error          (dll_error)
    );

    // -- FC_INIT_FSM ----------------------------------------------------------
    fc_init_fsm u_fc_init (
        .clk            (clk),
        .rst_n          (rst_n),
        .dll_active     (dll_active),
        .initfc_rx      (fc_to_dllp),          // FIX-6: fc_to_dllp[71:0] matches port [71:0]
        .initfc_rx_valid(fc_update_valid_rx),
        .fc_init_timeout(fc_timer_exp),
        .initfc_tx      (initfc_tx),
        .initfc_tx_send (initfc_tx_send),
        .fc_init_done   (fc_init_done),
        .fc_init_err    (fc_init_err),
        .fc_init_state  (fc_init_state)
    );

    // -- FC_TMR ---------------------------------------------------------------
    fc_tmr u_fc_tmr (
        .clk            (clk),
        .rst_n          (rst_n),
        .fc_update_sent (fc_dllp_valid_out),
        .fc_timer_limit (fc_timer_limit),
        .dll_active     (dll_active),
        .fc_update_req  (fc_update_req),
        .fc_timer_exp   (fc_timer_exp)
    );

    // -- FC_WDG ---------------------------------------------------------------
    fc_wdg u_fc_wdg (
        .clk                (clk),
        .rst_n              (rst_n),
        .credit_grant_p     (fc_update_valid_rx),
        .credit_grant_np    (fc_update_valid_rx),
        .credit_grant_cpl   (fc_update_valid_rx),
        .tlp_pending        (dll_tlp_valid | buf_occ != 0),
        .fc_watchdog_limit  (fc_watchdog_limit),
        .dll_active         (dll_active),
        .fc_deadlock_det    (fc_deadlock_det),
        .fc_watchdog_err    (fc_watchdog_err),
        .fc_recovery_req    (fc_recovery_req)
    );

    // -- ACK_TMR --------------------------------------------------------------
    ack_tmr u_ack_tmr (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_rx_valid   (tlp_rx_valid),
        .ack_sent       (ack_sent),
        .ack_lat_limit  (ack_lat_limit),
        .replay_limit   (replay_limit),
        .ack_timer_exp  (ack_timer_exp),
        .replay_timer_exp(replay_timer_exp),
        .replay_num     (replay_num)
    );

    // -- ACK_PGB --------------------------------------------------------------
    ack_pgb u_ack_pgb (
        .clk                (clk),
        .rst_n              (rst_n),
        .ack_pending_seq    (seq_rx_lcrc),
        .ack_pending        (dllp_sched_valid),
        .nop_send_req       (nop_send),
        .ack_lat_limit      (ack_lat_limit),
        .ack_piggyback_seq  (ack_piggyback_seq),
        .ack_piggyback_valid(ack_piggyback_valid),
        .ack_sent           (ack_sent)
    );

    // -- REPLAY_FSM -----------------------------------------------------------
    replay_fsm u_replay_fsm (
        .clk                (clk),
        .rst_n              (rst_n),
        .nak_valid          (nak_valid | nak_req_seq),
        .replay_timer_exp   (replay_timer_exp),
        .nak_seq            (nak_seq),
        .replay_num         (replay_num),
        .buf_occ            (buf_occ),
        .retry_req          (retry_req_fsm),
        .retry_seq_start    (retry_seq_start),
        .dll_link_down      (dll_link_down_fsm),
        .replay_rollover_err(replay_rollover_err)
    );

    // -- FLIT_SEQ -------------------------------------------------------------
    flit_seq u_flit_seq (
        .clk                (clk),
        .rst_n              (rst_n),
        .flit_tx_seq        (seq_num_tx),
        .flit_rx_seq        (flit_seq_rx),
        .ack_seq            (ack_seq),
        .nak_seq            (nak_seq),
        .link_reset         (dll_reset_seq),
        .oldest_unacked_seq (oldest_unacked_seq),
        .seq_window_full    (seq_window_full),
        .seq_wrap_det       (seq_wrap_det),
        .seq_err            (seq_err_flit)
    );

    // -- LBW_FSM --------------------------------------------------------------
    lbw_fsm u_lbw_fsm (
        .clk            (clk),
        .rst_n          (rst_n),
        .ltssm_speed    (ltssm_speed),
        .ltssm_width    (ltssm_width),
        .bw_change_det  (1'b0),        // driven by LTSSM in full impl
        .eq_req_from_phy(1'b0),
        .bw_notif_dllp  (bw_notif_dllp),
        .bw_notif_valid (bw_notif_valid),
        .link_eq_req    (link_eq_req),
        .link_eq_ack    (link_eq_ack),
        .bw_status      (bw_status)
    );

    // -- NOP_GEN --------------------------------------------------------------
    nop_gen u_nop_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .dll_active     (dll_active),
        .nop_timer_exp  (fc_timer_exp),
        .nop_inhibit    (dllp_arb_valid),
        .nop_send       (nop_send),
        .nop_dllp       (nop_dllp_out),
        .nop_count      (nop_count)
    );

    // -- PM_FSM ---------------------------------------------------------------
    pm_fsm u_pm_fsm (
        .clk            (clk),
        .rst_n          (rst_n),
        .pm_req_sw      (pm_req_sw),
        .pm_dllp_rx     (pm_type_rx),
        .pm_dllp_valid  (pm_valid_rx),
        .l0s_timer_exp  (l0s_timer_exp),
        .l1_timer_exp   (l1_timer_exp),
        .pm_dllp_type   (pm_dllp_type_tx),
        .pm_dllp_send   (pm_dllp_send),
        .link_state     (link_state),
        .ltssm_pm_req   (ltssm_pm_req)
    );

    // -- PM_TMR ---------------------------------------------------------------
    pm_tmr u_pm_tmr (
        .clk            (clk),
        .rst_n          (rst_n),
        .l0s_entry_req  (pm_dllp_send),
        .l1_entry_req   (pm_dllp_send),
        .l0s_exit_req   (pm_valid_rx),
        .l1_exit_req    (pm_valid_rx),
        .l0s_limit      (l0s_limit),
        .l1_limit       (l1_limit),
        .l0s_timer_exp  (l0s_timer_exp),
        .l1_timer_exp   (l1_timer_exp),
        .pm_timeout_err (pm_timeout_err)
    );

    // -- DLL_ERR --------------------------------------------------------------
    dll_err u_dll_err (
        .clk                (clk),
        .rst_n              (rst_n),
        .replay_rollover_err(replay_rollover_err),
        .dllp_crc_err       (dllp_crc_err),
        .dllp_mal_err       (dllp_mal_err),
        .lcrc_err           (lcrc_err),
        .flit_uncorr_err    (flit_uncorr_err),
        .lfsr_sync_err      (lfsr_sync_err),
        .dll_err_to_aer     (dll_err_to_aer),
        .dll_err_valid      (dll_err_valid),
        .dll_err_type       (dll_err_type),
        .dll_err_severity   (dll_err_severity)
    );

    // -- FLIT_NULL_SLOT_INSERTER (TX side, placeholder 1024-bit pattern) ------
    flit_null_slot_inserter u_null_ins (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_in        ({dll_flit[2047:1024], dll_tlp}),
        .flit_valid     (dll_flit_valid | dll_tlp_valid),
        .flit_slot_used (2'b11),      // both slots used when data valid
        .null_pattern   ({1024{1'b1}}),
        .flit_out       (flit_null_ins_out),
        .flit_out_valid (flit_null_ins_valid),
        .null_inserted  (null_inserted),
        .null_count     (null_count_tx)
    );

    // FIX-STUB-2: expose DLLP arbiter output for flit co-packing in PHY TX
    assign dllp_arb_out_o      = dllp_arb_out;
    assign dllp_arb_valid_o    = dllp_arb_valid;

    // FIX-STUB-3: expose UpdateFC RX values for TL credit manager
    assign fc_update_ph_rx_o   = fc_update_ph_rx;
    assign fc_update_pd_rx_o   = fc_update_pd_rx;
    assign fc_update_nph_rx_o  = fc_update_nph_rx;
    assign fc_update_cplh_rx_o = fc_update_cplh_rx;
    assign fc_update_cpld_rx_o = fc_update_cpld_rx;
    assign fc_update_valid_rx_o= fc_update_valid_rx;

endmodule
