
`timescale 1ns/1ps

module tb_dll_top;

reg clk, rst_n;
initial clk = 0;
always  #5 clk = ~clk;

task do_reset;
    begin
        rst_n = 0;
        repeat(6) @(posedge clk);
        @(negedge clk); rst_n = 1;
        @(posedge clk);
    end
endtask

integer pass_cnt, fail_cnt;
initial begin pass_cnt = 0; fail_cnt = 0; end

task check;
    input        cond;
    input [239:0] name;
    begin
        if (cond) begin
            $display("[PASS] %0s", name);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] %0s  @ %0t ns", name, $realtime);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

function [31:0] crc32_lcrc;
    input [991:0] data;
    integer b, k;
    reg [31:0] c;
    reg [7:0]  byt;
    reg        xf;
    begin
        c = 32'hFFFF_FFFF;
        for (b = 123; b >= 0; b = b - 1) begin
            byt = data[b*8 +: 8];
            for (k = 7; k >= 0; k = k - 1) begin
                xf = c[31] ^ byt[k];
                c  = c << 1;
                if (xf) c = c ^ 32'h04C1_1DB7;
            end
        end
        crc32_lcrc = c;
    end
endfunction

integer      i, beat;
reg [991:0]  body992;
reg [31:0]   crc32_val;
reg [255:0]  beat_data;

reg  [11:0] m1_seq_rx;
reg         m1_crc_ok, m1_tlp_valid, m1_timer_exp;
reg  [7:0]  m1_ack_freq;
wire [63:0] m1_ack_dllp, m1_nak_dllp;
wire        m1_dllp_valid;
wire [1:0]  m1_dllp_type;

ack_nak_scheduler_tx u_ack_sched (
    .clk(clk),.rst_n(rst_n),.seq_rx(m1_seq_rx),.crc_ok(m1_crc_ok),
    .tlp_rx_valid(m1_tlp_valid),.ack_timer_exp(m1_timer_exp),.ack_freq(m1_ack_freq),
    .ack_dllp(m1_ack_dllp),.nak_dllp(m1_nak_dllp),
    .dllp_valid(m1_dllp_valid),.dllp_type(m1_dllp_type));

reg  [23:0] m2_ack_out;
reg         m2_ack_valid_in;
wire [11:0] m2_ack_seq, m2_nak_seq;
wire        m2_ack_valid, m2_nak_valid, m2_retry_req;

ack_nak_receiver u_ack_rx (
    .clk(clk),.rst_n(rst_n),.ack_out(m2_ack_out),.ack_out_valid(m2_ack_valid_in),
    .ack_seq(m2_ack_seq),.nak_seq(m2_nak_seq),
    .ack_valid(m2_ack_valid),.nak_valid(m2_nak_valid),.retry_req(m2_retry_req));

reg  [47:0] m3_dllp_in;
reg         m3_valid_in;
wire [15:0] m3_crc_out;
wire        m3_crc_valid;
wire [63:0] m3_full_out;

dllp_crc_gen u_crc_gen (
    .clk(clk),.rst_n(rst_n),.dllp_in(m3_dllp_in),.dllp_valid_in(m3_valid_in),
    .dllp_crc(m3_crc_out),.dllp_crc_valid(m3_crc_valid),.dllp_full(m3_full_out));

reg  [63:0] m4_raw;
reg         m4_rx_valid;
wire [47:0] m4_body;
wire        m4_crc_ok, m4_crc_err, m4_valid_out;

dllp_crc_chk u_crc_chk (
    .clk(clk),.rst_n(rst_n),.dllp_raw(m4_raw),.dllp_rx_valid(m4_rx_valid),
    .dllp_body(m4_body),.dllp_crc_ok(m4_crc_ok),
    .dllp_crc_err(m4_crc_err),.dllp_valid_out(m4_valid_out));

reg  [47:0] m5_body;
reg         m5_crc_ok, m5_valid_in;
wire        m5_type_ok, m5_mal_err, m5_clean_valid;
wire [47:0] m5_clean;

dllp_mal_chk u_mal (
    .clk(clk),.rst_n(rst_n),.dllp_body(m5_body),
    .dllp_crc_ok(m5_crc_ok),.dllp_valid_in(m5_valid_in),
    .dllp_type_ok(m5_type_ok),.dllp_mal_err(m5_mal_err),
    .dllp_clean(m5_clean),.dllp_clean_valid(m5_clean_valid));

reg  [47:0] m6_clean;
reg         m6_clean_valid;
wire [7:0]  m6_fc_ph, m6_fc_nph, m6_fc_cplh;
wire [11:0] m6_fc_pd, m6_fc_cpld;
wire        m6_fc_valid, m6_pm_valid;
wire [2:0]  m6_pm_type;
wire [23:0] m6_ack_out;
wire        m6_ack_out_valid;

dllp_receiver_decoder u_dec (
    .clk(clk),.rst_n(rst_n),.dllp_clean(m6_clean),.dllp_clean_valid(m6_clean_valid),
    .fc_update_ph(m6_fc_ph),.fc_update_pd(m6_fc_pd),.fc_update_nph(m6_fc_nph),
    .fc_update_cplh(m6_fc_cplh),.fc_update_cpld(m6_fc_cpld),.fc_update_valid(m6_fc_valid),
    .pm_type(m6_pm_type),.pm_valid(m6_pm_valid),
    .ack_out(m6_ack_out),.ack_out_valid(m6_ack_out_valid));

reg  [63:0] m7_ack_dllp, m7_fc_dllp, m7_pm_dllp;
reg         m7_ack_v, m7_fc_v, m7_pm_v, m7_nop_v, m7_bw_v;
wire [63:0] m7_out;
wire        m7_out_v;
wire [3:0]  m7_type;

dllp_arb u_arb (
    .clk(clk),.rst_n(rst_n),
    .ack_dllp(m7_ack_dllp),.ack_dllp_valid(m7_ack_v),
    .fc_dllp(m7_fc_dllp),.fc_dllp_valid(m7_fc_v),
    .pm_dllp(m7_pm_dllp),.pm_dllp_valid(m7_pm_v),
    .nop_valid(m7_nop_v),.bw_dllp_valid(m7_bw_v),
    .dllp_out(m7_out),.dllp_out_valid(m7_out_v),.dllp_type(m7_type));

reg  [255:0] m8_data_in;
reg          m8_valid_in, m8_link_rst, m8_sc_en;
reg  [22:0]  m8_seed;
wire [255:0] m8_sc_out, m8_dsc_out;
wire         m8_sc_vout, m8_dsc_vout, m8_dsc_err;
wire [22:0]  m8_sc_state;

scrambler u_scr (
    .clk(clk),.rst_n(rst_n),.data_in(m8_data_in),.data_valid_in(m8_valid_in),
    .lfsr_seed(m8_seed),.scramble_en(m8_sc_en),.link_reset(m8_link_rst),
    .data_out(m8_sc_out),.data_valid_out(m8_sc_vout),.lfsr_state(m8_sc_state));

Descrambler u_dsc (
    .clk(clk),.rst_n(rst_n),.data_in(m8_sc_out),.data_valid_in(m8_sc_vout),
    .lfsr_seed(m8_seed),.scramble_en(m8_sc_en),.link_reset(m8_link_rst),
    .data_out(m8_dsc_out),.data_valid_out(m8_dsc_vout),.lfsr_sync_err(m8_dsc_err));

reg         m9_tlp_valid, m9_retry_req, m9_link_rst;
reg  [11:0] m9_ack_seq, m9_nak_seq;
wire [11:0] m9_seq_num;
wire        m9_seq_valid, m9_seq_wrap;

seq_num_gen u_sg (
    .clk(clk),.rst_n(rst_n),.tlp_valid_in(m9_tlp_valid),
    .ack_seq(m9_ack_seq),.nak_seq(m9_nak_seq),.retry_req(m9_retry_req),
    .link_reset(m9_link_rst),.seq_num(m9_seq_num),
    .seq_valid(m9_seq_valid),.seq_wrap(m9_seq_wrap));

reg  [1055:0] m10_tlp_in;
reg           m10_write_en;
reg  [11:0]   m10_seq_in, m10_ack_seq, m10_nak_seq;
reg           m10_retry_req;
wire [1055:0] m10_retry_tlp;
wire          m10_retry_valid;
wire [11:0]   m10_retry_seq;
wire          m10_full;
wire [11:0]   m10_occ;
wire          m10_purge_done;

retry_buf #(.BUF_DEPTH(16),.TLP_WIDTH(1056),.PTR_W(4)) u_rb (
    .clk(clk),.rst_n(rst_n),.tlp_in(m10_tlp_in),.tlp_write_en(m10_write_en),
    .seq_num_in(m10_seq_in),.ack_seq(m10_ack_seq),.nak_seq(m10_nak_seq),
    .retry_req(m10_retry_req),.retry_tlp(m10_retry_tlp),.retry_valid(m10_retry_valid),
    .retry_seq(m10_retry_seq),.buf_full(m10_full),.buf_occ(m10_occ),
    .purge_done(m10_purge_done));

reg         m11_nak_valid, m11_replay_timer;
reg  [11:0] m11_nak_seq;
reg  [1:0]  m11_replay_num;
reg  [11:0] m11_buf_occ;
wire        m11_retry_req, m11_link_down, m11_rollover;
wire [11:0] m11_retry_seq;

replay_fsm u_rf (
    .clk(clk),.rst_n(rst_n),.nak_valid(m11_nak_valid),
    .replay_timer_exp(m11_replay_timer),.nak_seq(m11_nak_seq),
    .replay_num(m11_replay_num),.buf_occ(m11_buf_occ),
    .retry_req(m11_retry_req),.retry_seq_start(m11_retry_seq),
    .dll_link_down(m11_link_down),.replay_rollover_err(m11_rollover));

reg  [1055:0] m12_tlp_rx;
reg           m12_valid, m12_flit_mode;
wire          m12_ok, m12_err;
wire [1023:0] m12_clean;
wire          m12_clean_v;
wire [11:0]   m12_seq;

lcrc_flit_crc_chk u_lcrc (
    .clk(clk),.rst_n(rst_n),.tlp_rx(m12_tlp_rx),.tlp_rx_valid(m12_valid),
    .flit_mode_en(m12_flit_mode),.crc_ok(m12_ok),.crc_err(m12_err),
    .tlp_clean(m12_clean),.tlp_clean_valid(m12_clean_v),.seq_rx(m12_seq));

reg  [11:0]   m13_seq_rx;
reg           m13_tlp_valid, m13_tlp_ok, m13_link_rst;
reg  [1023:0] m13_tlp_clean;
wire          m13_seq_ok, m13_dup, m13_seq_err, m13_nak_req, m13_dup_ack;
wire [11:0]   m13_err_val, m13_next_exp;
wire [1023:0] m13_fwd;
wire          m13_fwd_valid;

seq_num_checker_rx u_snc (
    .clk(clk),.rst_n(rst_n),.link_reset(m13_link_rst),
    .seq_rx(m13_seq_rx),.tlp_rx_valid(m13_tlp_valid),.tlp_ok(m13_tlp_ok),
    .tlp_clean(m13_tlp_clean),.tlp_seq_ok(m13_seq_ok),.tlp_dup(m13_dup),
    .tlp_seq_err(m13_seq_err),.nak_req(m13_nak_req),.seq_dup_ack(m13_dup_ack),
    .seq_err_val(m13_err_val),.next_expected(m13_next_exp),
    .tlp_fwd(m13_fwd),.tlp_fwd_valid(m13_fwd_valid));

reg         m14_rollover, m14_dllp_crc, m14_dllp_mal;
reg         m14_lcrc, m14_flit_uncorr, m14_lfsr;
wire [5:0]  m14_aer;
wire        m14_valid;
wire [3:0]  m14_type;
wire [1:0]  m14_sev;

dll_err u_de (
    .clk(clk),.rst_n(rst_n),.replay_rollover_err(m14_rollover),
    .dllp_crc_err(m14_dllp_crc),.dllp_mal_err(m14_dllp_mal),
    .lcrc_err(m14_lcrc),.flit_uncorr_err(m14_flit_uncorr),.lfsr_sync_err(m14_lfsr),
    .dll_err_to_aer(m14_aer),.dll_err_valid(m14_valid),
    .dll_err_type(m14_type),.dll_err_severity(m14_sev));

reg         m15_active, m15_timer_exp, m15_inhibit;
wire        m15_send;
wire [63:0] m15_dllp;
wire [7:0]  m15_count;

nop_gen u_ng (
    .clk(clk),.rst_n(rst_n),.dll_active(m15_active),
    .nop_timer_exp(m15_timer_exp),.nop_inhibit(m15_inhibit),
    .nop_send(m15_send),.nop_dllp(m15_dllp),.nop_count(m15_count));

reg         m16_sent, m16_active;
reg  [15:0] m16_limit;
wire        m16_req, m16_exp;

fc_tmr u_ft (
    .clk(clk),.rst_n(rst_n),.fc_update_sent(m16_sent),
    .fc_timer_limit(m16_limit),.dll_active(m16_active),
    .fc_update_req(m16_req),.fc_timer_exp(m16_exp));

reg         m17_p, m17_np, m17_cpl, m17_pending, m17_active;
reg  [15:0] m17_limit;
wire        m17_deadlock, m17_err, m17_recov;

fc_wdg u_fw (
    .clk(clk),.rst_n(rst_n),.credit_grant_p(m17_p),.credit_grant_np(m17_np),
    .credit_grant_cpl(m17_cpl),.tlp_pending(m17_pending),
    .fc_watchdog_limit(m17_limit),.dll_active(m17_active),
    .fc_deadlock_det(m17_deadlock),.fc_watchdog_err(m17_err),.fc_recovery_req(m17_recov));

reg         m18_tlp_valid, m18_ack_sent;
reg  [15:0] m18_ack_lim, m18_replay_lim;
wire        m18_ack_exp, m18_replay_exp;
wire [1:0]  m18_replay_num;

ack_tmr u_at (
    .clk(clk),.rst_n(rst_n),.tlp_rx_valid(m18_tlp_valid),.ack_sent(m18_ack_sent),
    .ack_lat_limit(m18_ack_lim),.replay_limit(m18_replay_lim),
    .ack_timer_exp(m18_ack_exp),.replay_timer_exp(m18_replay_exp),
    .replay_num(m18_replay_num));

reg  [255:0] m19_rxd;
reg          m19_valid;
reg  [2:0]   m19_status;
reg  [15:0]  m19_syndrome;
reg          m19_corrected, m19_dl_up;
wire [255:0] m19_rx_data;
wire         m19_rx_valid;
wire [2047:0] m19_rx_flit;
wire          m19_rx_flit_valid;

phy_interface_rx u_pr (
    .clk(clk),.rst_n(rst_n),.phy_rxd(m19_rxd),.phy_rx_valid(m19_valid),
    .phy_rx_status(m19_status),.fec_syndrome(m19_syndrome),.fec_corrected(m19_corrected),
    .ltssm_dl_up(m19_dl_up),.rx_data(m19_rx_data),.rx_valid(m19_rx_valid),
    .rx_flit(m19_rx_flit),.rx_flit_valid(m19_rx_flit_valid));

reg         m20_ltssm_up, m20_ltssm_down, m20_fc_done;
reg         m20_rollover, m20_link_down;
wire        m20_dll_up, m20_rst_seq, m20_active, m20_error;

dll_init u_di (
    .clk(clk),.rst_n(rst_n),.ltssm_dl_up(m20_ltssm_up),.ltssm_dl_down(m20_ltssm_down),
    .fc_init_done(m20_fc_done),.replay_rollover_err(m20_rollover),
    .dll_link_down(m20_link_down),.dll_up_to_tl(m20_dll_up),
    .dll_reset_seq(m20_rst_seq),.dll_active(m20_active),.dll_error(m20_error));

reg         m21_l0s_entry, m21_l1_entry, m21_l0s_exit, m21_l1_exit;
reg  [15:0] m21_l0s_lim, m21_l1_lim;
wire        m21_l0s_exp, m21_l1_exp, m21_pm_err;

pm_tmr u_pt (
    .clk(clk),.rst_n(rst_n),.l0s_entry_req(m21_l0s_entry),.l1_entry_req(m21_l1_entry),
    .l0s_exit_req(m21_l0s_exit),.l1_exit_req(m21_l1_exit),
    .l0s_limit(m21_l0s_lim),.l1_limit(m21_l1_lim),
    .l0s_timer_exp(m21_l0s_exp),.l1_timer_exp(m21_l1_exp),.pm_timeout_err(m21_pm_err));

reg  [11:0] m22_pending_seq;
reg         m22_pending, m22_nop_req;
reg  [15:0] m22_lat_lim;
wire [11:0] m22_pgb_seq;
wire        m22_pgb_valid, m22_ack_sent;

ack_pgb u_apgb (
    .clk(clk),.rst_n(rst_n),.ack_pending_seq(m22_pending_seq),
    .ack_pending(m22_pending),.nop_send_req(m22_nop_req),.ack_lat_limit(m22_lat_lim),
    .ack_piggyback_seq(m22_pgb_seq),.ack_piggyback_valid(m22_pgb_valid),
    .ack_sent(m22_ack_sent));

reg         m23_active, m23_rx_valid, m23_timeout;
reg  [71:0] m23_rx;
wire [71:0] m23_tx;
wire        m23_tx_send, m23_done, m23_err;
wire [2:0]  m23_state;

fc_init_fsm u_fi (
    .clk(clk),.rst_n(rst_n),.dll_active(m23_active),.initfc_rx(m23_rx),
    .initfc_rx_valid(m23_rx_valid),.fc_init_timeout(m23_timeout),
    .initfc_tx(m23_tx),.initfc_tx_send(m23_tx_send),
    .fc_init_done(m23_done),.fc_init_err(m23_err),.fc_init_state(m23_state));

reg  [3:0]  m24_speed;
reg  [5:0]  m24_width;
reg         m24_bw_change, m24_eq_req;
wire [63:0] m24_bw_dllp;
wire        m24_bw_valid, m24_eq_req_out, m24_eq_ack;
wire [7:0]  m24_bw_status;

lbw_fsm u_lbw (
    .clk(clk),.rst_n(rst_n),.ltssm_speed(m24_speed),.ltssm_width(m24_width),
    .bw_change_det(m24_bw_change),.eq_req_from_phy(m24_eq_req),
    .bw_notif_dllp(m24_bw_dllp),.bw_notif_valid(m24_bw_valid),
    .link_eq_req(m24_eq_req_out),.link_eq_ack(m24_eq_ack),.bw_status(m24_bw_status));

reg  [2:0]  m25_req_sw, m25_pm_rx;
reg         m25_pm_rx_valid, m25_l0s_exp, m25_l1_exp;
wire [2:0]  m25_pm_type, m25_ls, m25_ltssm_req;
wire        m25_pm_send;

pm_fsm u_pmfsm (
    .clk(clk),.rst_n(rst_n),.pm_req_sw(m25_req_sw),.pm_dllp_rx(m25_pm_rx),
    .pm_dllp_valid(m25_pm_rx_valid),.l0s_timer_exp(m25_l0s_exp),.l1_timer_exp(m25_l1_exp),
    .pm_dllp_type(m25_pm_type),.pm_dllp_send(m25_pm_send),
    .link_state(m25_ls),.ltssm_pm_req(m25_ltssm_req));

reg  [11:0] m26_tx_seq, m26_rx_seq, m26_ack_seq, m26_nak_seq;
reg         m26_link_rst;
wire [11:0] m26_oldest;
wire        m26_win_full, m26_wrap, m26_err;

flit_seq u_fs (
    .clk(clk),.rst_n(rst_n),.flit_tx_seq(m26_tx_seq),.flit_rx_seq(m26_rx_seq),
    .ack_seq(m26_ack_seq),.nak_seq(m26_nak_seq),.link_reset(m26_link_rst),
    .oldest_unacked_seq(m26_oldest),.seq_window_full(m26_win_full),
    .seq_wrap_det(m26_wrap),.seq_err(m26_err));

task init_all;
    begin
        m1_seq_rx=0;m1_crc_ok=0;m1_tlp_valid=0;m1_timer_exp=0;m1_ack_freq=4;
        m2_ack_out=0;m2_ack_valid_in=0;
        m3_dllp_in=0;m3_valid_in=0;
        m4_raw=0;m4_rx_valid=0;
        m5_body=0;m5_crc_ok=0;m5_valid_in=0;
        m6_clean=0;m6_clean_valid=0;
        m7_ack_dllp=0;m7_fc_dllp=0;m7_pm_dllp=0;
        m7_ack_v=0;m7_fc_v=0;m7_pm_v=0;m7_nop_v=0;m7_bw_v=0;
        m8_data_in=0;m8_valid_in=0;m8_link_rst=0;m8_sc_en=1;m8_seed=23'h7FFFFF;
        m9_tlp_valid=0;m9_retry_req=0;m9_link_rst=0;m9_ack_seq=0;m9_nak_seq=0;
        m10_tlp_in=0;m10_write_en=0;m10_seq_in=0;m10_ack_seq=0;m10_nak_seq=0;m10_retry_req=0;
        m11_nak_valid=0;m11_replay_timer=0;m11_nak_seq=0;m11_replay_num=0;m11_buf_occ=0;
        m12_tlp_rx=0;m12_valid=0;m12_flit_mode=0;
        m13_seq_rx=0;m13_tlp_valid=0;m13_tlp_ok=0;m13_link_rst=0;m13_tlp_clean=0;
        m14_rollover=0;m14_dllp_crc=0;m14_dllp_mal=0;m14_lcrc=0;m14_flit_uncorr=0;m14_lfsr=0;
        m15_active=0;m15_timer_exp=0;m15_inhibit=0;
        m16_sent=0;m16_active=0;m16_limit=16'd5;
        m17_p=0;m17_np=0;m17_cpl=0;m17_pending=0;m17_active=0;m17_limit=16'd4;
        m18_tlp_valid=0;m18_ack_sent=0;m18_ack_lim=16'd4;m18_replay_lim=16'd8;
        m19_rxd=0;m19_valid=0;m19_status=0;m19_syndrome=0;m19_corrected=0;m19_dl_up=0;
        m20_ltssm_up=0;m20_ltssm_down=0;m20_fc_done=0;m20_rollover=0;m20_link_down=0;
        m21_l0s_entry=0;m21_l1_entry=0;m21_l0s_exit=0;m21_l1_exit=0;
        m21_l0s_lim=16'd3;m21_l1_lim=16'd5;
        m22_pending_seq=0;m22_pending=0;m22_nop_req=0;m22_lat_lim=16'd3;
        m23_active=0;m23_rx=0;m23_rx_valid=0;m23_timeout=0;
        m24_speed=4;m24_width=16;m24_bw_change=0;m24_eq_req=0;
        m25_req_sw=0;m25_pm_rx=0;m25_pm_rx_valid=0;m25_l0s_exp=0;m25_l1_exp=0;
        m26_tx_seq=0;m26_rx_seq=0;m26_ack_seq=0;m26_nak_seq=0;m26_link_rst=0;
    end
endtask

initial begin
    $dumpfile("tb_dll_top.vcd");
    $dumpvars(0, tb_dll_top);
    init_all; do_reset;

    m1_ack_freq=8'd4;
    repeat(3) begin
        @(negedge clk);m1_tlp_valid=1;m1_crc_ok=1;m1_seq_rx=12'd5;
        @(posedge clk);@(negedge clk);m1_tlp_valid=0;@(posedge clk);
    end
    check(!m1_dllp_valid,"TC01: No ACK when count<freq");

    @(negedge clk);m1_tlp_valid=1;m1_crc_ok=1;m1_seq_rx=12'd10;
    @(posedge clk);@(negedge clk);m1_tlp_valid=0;@(posedge clk);
    check(m1_dllp_valid && m1_dllp_type==2'b01,"TC02: ACK fires at freq=4");

    @(negedge clk);m1_tlp_valid=1;m1_crc_ok=0;m1_seq_rx=12'd20;
    @(posedge clk);@(negedge clk);m1_tlp_valid=0;@(posedge clk);
    check(m1_dllp_valid && m1_dllp_type==2'b10,"TC03: NAK on CRC fail");

    m1_ack_freq=8'd8;
    @(negedge clk);m1_tlp_valid=1;m1_crc_ok=1;m1_seq_rx=12'd30;
    @(posedge clk);@(negedge clk);m1_tlp_valid=0;
    @(negedge clk);m1_timer_exp=1;
    @(posedge clk);@(negedge clk);m1_timer_exp=0;@(posedge clk);
    check(m1_dllp_valid && m1_dllp_type==2'b01,"TC04: Timer flush ACK");

    m1_ack_freq=8'd8;
    @(posedge clk);@(posedge clk);
    check(!m1_dllp_valid,"TC05: No spurious DLLP when idle");
    do_reset;

    @(negedge clk);m2_ack_out={8'h00,12'd7,4'h0};m2_ack_valid_in=1;
    @(posedge clk);@(negedge clk);m2_ack_valid_in=0;@(posedge clk);
    check(m2_ack_valid && m2_ack_seq==12'd7,"TC06: ACK seq=7 accepted");

    @(negedge clk);m2_ack_out={8'h01,12'd10,4'h0};m2_ack_valid_in=1;
    @(posedge clk);@(negedge clk);m2_ack_valid_in=0;@(posedge clk);
    check(m2_nak_valid && m2_retry_req,"TC07: NAK triggers retry_req");

    @(negedge clk);m2_ack_out={8'h00,12'd5,4'h0};m2_ack_valid_in=1;
    @(posedge clk);@(negedge clk);m2_ack_valid_in=0;@(posedge clk);
    check(!m2_ack_valid,"TC08: Out-of-window ACK rejected (BUG FIX)");

    do_reset;
    @(negedge clk);m2_ack_out={8'h00,12'd2047,4'h0};m2_ack_valid_in=1;
    @(posedge clk);@(negedge clk);m2_ack_valid_in=0;@(posedge clk);
    check(m2_ack_valid && m2_ack_seq==12'd2047,"TC09: Max-window ACK accepted");

    do_reset;
    @(negedge clk);m2_ack_out={8'h00,12'd2048,4'h0};m2_ack_valid_in=1;
    @(posedge clk);@(negedge clk);m2_ack_valid_in=0;@(posedge clk);
    check(!m2_ack_valid,"TC10: dist=2048 rejected (outside window)");
    do_reset;

    @(negedge clk);m3_dllp_in=48'h001234_567890;m3_valid_in=1;
    @(posedge clk);@(negedge clk);m3_valid_in=0;
    m4_raw=m3_full_out;m4_rx_valid=1;
    @(posedge clk);@(negedge clk);m4_rx_valid=0;@(posedge clk);
    check(m4_crc_ok && !m4_crc_err,"TC11: DLLP CRC round-trip OK (BUG FIX)");

    @(negedge clk);m4_raw={m3_full_out[63:48]^16'hBEEF,m3_full_out[47:0]};m4_rx_valid=1;
    @(posedge clk);@(negedge clk);m4_rx_valid=0;@(posedge clk);
    check(!m4_crc_ok && m4_crc_err,"TC12: CRC error detected");

    check(m4_body==48'h0,"TC13: Body=0 on CRC fail");

    @(negedge clk);m3_dllp_in=48'hABCDEF_123456;m3_valid_in=1;
    @(posedge clk);@(negedge clk);m3_valid_in=0;
    m4_raw=m3_full_out;m4_rx_valid=1;
    @(posedge clk);@(negedge clk);m4_rx_valid=0;@(posedge clk);
    check(m4_valid_out && m4_body==48'hABCDEF_123456,"TC14: Body forwarded on pass");

    @(negedge clk);m3_dllp_in={8'h31,40'h0};m3_valid_in=1;
    @(posedge clk);@(negedge clk);m3_valid_in=0;
    m4_raw=m3_full_out;m4_rx_valid=1;
    @(posedge clk);@(negedge clk);m4_rx_valid=0;@(posedge clk);
    check(m4_crc_ok && m4_body[47:40]==8'h31,"TC15: NOP 0x31 CRC OK");
    do_reset;

    @(negedge clk);m5_body={8'h00,16'h0000,12'hABC,12'h000};m5_crc_ok=1;m5_valid_in=1;
    @(posedge clk);@(negedge clk);m5_valid_in=0;@(posedge clk);
    check(m5_type_ok && m5_clean_valid && !m5_mal_err,"TC16: Valid ACK passes");

    @(negedge clk);m5_body={8'hFF,40'h0};m5_crc_ok=1;m5_valid_in=1;
    @(posedge clk);@(negedge clk);m5_valid_in=0;@(posedge clk);
    check(m5_mal_err && !m5_clean_valid,"TC17: Unknown 0xFF rejected");

    @(negedge clk);m5_body={8'h40,4'd3,36'h0};m5_crc_ok=1;m5_valid_in=1;
    @(posedge clk);@(negedge clk);m5_valid_in=0;@(posedge clk);
    check(m5_mal_err,"TC18: Non-zero VC_ID rejected");

    @(negedge clk);m5_body={8'h31,40'h0};m5_crc_ok=1;m5_valid_in=1;
    @(posedge clk);@(negedge clk);m5_valid_in=0;@(posedge clk);
    check(!m5_mal_err && m5_clean_valid,"TC19: NOP=0x31 passes (BUG FIX)");

    @(negedge clk);m5_body={8'h10,16'h0000,12'h123,12'h000};m5_crc_ok=1;m5_valid_in=1;
    @(posedge clk);@(negedge clk);m5_valid_in=0;@(posedge clk);
    check(!m5_mal_err && m5_clean_valid,"TC20: NAK=0x10 passes");
    do_reset;

    @(negedge clk);m6_clean={8'h00,16'h0000,12'hBCD,12'h000};m6_clean_valid=1;
    @(posedge clk);@(negedge clk);m6_clean_valid=0;@(posedge clk);
    check(m6_ack_out_valid && m6_ack_out[15:4]==12'hBCD,"TC21: ACK seq=BCD (BUG FIX)");

    @(negedge clk);m6_clean={8'h10,16'h0000,12'h123,12'h000};m6_clean_valid=1;
    @(posedge clk);@(negedge clk);m6_clean_valid=0;@(posedge clk);
    check(m6_ack_out_valid && m6_ack_out[23:16]==8'h01,"TC22: NAK flag=0x01");

    @(negedge clk);m6_clean={8'h40,4'h0,8'hAB,12'h123,16'h0};m6_clean_valid=1;
    @(posedge clk);@(negedge clk);m6_clean_valid=0;@(posedge clk);
    check(m6_fc_valid,"TC23: UpdateFC → fc_update_valid");

    @(negedge clk);m6_clean={8'h20,40'h0};m6_clean_valid=1;
    @(posedge clk);@(negedge clk);m6_clean_valid=0;@(posedge clk);
    check(m6_pm_valid && m6_pm_type==3'd0,"TC24: PM L1 decoded");

    @(negedge clk);m6_clean={8'h31,40'h0};m6_clean_valid=1;
    @(posedge clk);@(negedge clk);m6_clean_valid=0;@(posedge clk);
    check(!m6_ack_out_valid && !m6_fc_valid && !m6_pm_valid,"TC25: NOP silent (BUG FIX)");
    do_reset;

    @(negedge clk);m7_ack_dllp={8'h00,56'h0};m7_fc_dllp={8'h40,56'h0};
    m7_pm_dllp={8'h20,56'h0};m7_ack_v=1;m7_fc_v=1;m7_pm_v=1;m7_nop_v=1;m7_bw_v=1;
    @(posedge clk);@(negedge clk);m7_ack_v=0;m7_fc_v=0;m7_pm_v=0;m7_nop_v=0;m7_bw_v=0;
    @(posedge clk);
    check(m7_out_v && m7_type==4'h0,"TC26: ACK wins priority");

    @(negedge clk);m7_fc_v=1;m7_pm_v=1;m7_nop_v=1;
    @(posedge clk);@(negedge clk);m7_fc_v=0;m7_pm_v=0;m7_nop_v=0;@(posedge clk);
    check(m7_out_v && m7_type==4'h2,"TC27: FC over PM/NOP");

    @(negedge clk);m7_nop_v=1;
    @(posedge clk);@(negedge clk);m7_nop_v=0;@(posedge clk);
    check(m7_out_v && m7_type==4'h5 && m7_out[63:56]==8'h31,"TC28: NOP=0x31 (BUG FIX)");

    @(posedge clk);@(posedge clk);
    check(!m7_out_v,"TC29: Idle no output");
    do_reset;

    m8_seed=23'h7FFFFF;m8_sc_en=1;
    m8_link_rst=1;@(posedge clk);@(negedge clk);m8_link_rst=0;@(posedge clk);
    @(negedge clk);
    m8_data_in=256'hDEAD_BEEF_1234_5678_ABCD_EF01_9876_5432_DEAD_BEEF_1234_5678_ABCD_EF01_9876_5432;
    m8_valid_in=1;
    @(posedge clk);@(negedge clk);m8_valid_in=0;
    @(posedge clk);@(posedge clk);
    check(m8_dsc_vout &&
        m8_dsc_out==256'hDEAD_BEEF_1234_5678_ABCD_EF01_9876_5432_DEAD_BEEF_1234_5678_ABCD_EF01_9876_5432,
        "TC30: Scram/Descram round-trip (BUG FIX)");

    m8_link_rst=1;@(posedge clk);@(negedge clk);m8_link_rst=0;@(posedge clk);
    @(negedge clk);m8_data_in=256'hA5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5;
    m8_valid_in=1;
    @(posedge clk);@(negedge clk);m8_valid_in=0;@(posedge clk);
    check(m8_sc_vout &&
        m8_sc_out!=256'hA5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5_A5A5A5A5,
        "TC31: Scrambler changes data");

    m8_link_rst=1;@(posedge clk);@(negedge clk);m8_link_rst=0;m8_sc_en=0;@(posedge clk);
    @(negedge clk);m8_data_in=256'hCAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE;
    m8_valid_in=1;
    @(posedge clk);@(negedge clk);m8_valid_in=0;@(posedge clk);
    check(m8_sc_vout &&
        m8_sc_out==256'hCAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE_CAFE,
        "TC32: Passthrough when disabled");
    m8_sc_en=1;
    do_reset;

    repeat(3) begin
        @(negedge clk);m9_tlp_valid=1;
        @(posedge clk);@(negedge clk);m9_tlp_valid=0;@(posedge clk);
    end
    check(m9_seq_valid && m9_seq_num==12'd2,"TC33: SEQ 0→2 sequential");

    @(negedge clk);m9_link_rst=1;@(posedge clk);@(negedge clk);m9_link_rst=0;
    @(negedge clk);m9_tlp_valid=1;
    @(posedge clk);@(negedge clk);m9_tlp_valid=0;@(posedge clk);
    check(m9_seq_valid && m9_seq_num==12'd0,"TC34: Link reset restarts seq");

    repeat(5) begin
        @(negedge clk);m9_tlp_valid=1;
        @(posedge clk);@(negedge clk);m9_tlp_valid=0;@(posedge clk);
    end
    @(negedge clk);m9_nak_seq=12'd2;m9_retry_req=1;
    @(posedge clk);@(negedge clk);m9_retry_req=0;m9_tlp_valid=1;
    @(posedge clk);@(negedge clk);m9_tlp_valid=0;@(posedge clk);
    check(m9_seq_valid && m9_seq_num==12'd2,"TC35: Retry from nak_seq=2");

    @(posedge clk);@(posedge clk);
    check(!m9_seq_valid,"TC36: No seq when idle");
    do_reset;

    for(i=0;i<4;i=i+1) begin
        @(negedge clk);m10_tlp_in={{1044{1'b0}},i[11:0]};m10_seq_in=i[11:0];m10_write_en=1;
        @(posedge clk);@(negedge clk);m10_write_en=0;
    end
    @(posedge clk);@(posedge clk);
    check(m10_occ>=12'd3,"TC37: 4 TLPs written");

    @(negedge clk);m10_ack_seq=12'd1;repeat(5)@(posedge clk);
    check(m10_occ<=12'd2,"TC38: ACK purges entries");

    @(negedge clk);m10_retry_req=1;
    @(posedge clk);@(negedge clk);m10_retry_req=0;
    @(posedge clk);@(posedge clk);
    check(m10_retry_valid,"TC39: NAK → retry_valid");

    do_reset;
    @(negedge clk);m10_tlp_in={{1044{1'b0}},12'hFFE};m10_seq_in=12'hFFE;m10_write_en=1;
    @(posedge clk);@(negedge clk);
    m10_tlp_in={{1044{1'b0}},12'hFFF};m10_seq_in=12'hFFF;
    @(posedge clk);@(negedge clk);m10_write_en=0;
    m10_ack_seq=12'h01D;repeat(5)@(posedge clk);
    check(m10_occ>=12'd1,"TC40: Wrap no spurious purge (BUG FIX)");
    do_reset;

    @(negedge clk);m11_nak_valid=1;m11_nak_seq=12'd5;m11_replay_num=2'd0;
    @(posedge clk);@(negedge clk);m11_nak_valid=0;@(posedge clk);
    check(m11_retry_req && m11_retry_seq==12'd5,"TC41: NAK → retry_req");

    @(posedge clk);
    @(negedge clk);m11_replay_timer=1;m11_replay_num=2'd1;
    @(posedge clk);@(negedge clk);m11_replay_timer=0;@(posedge clk);
    check(m11_retry_req,"TC42: Replay timer → retry");

    @(posedge clk);
    @(negedge clk);m11_nak_valid=1;m11_replay_num=2'd3;
    @(posedge clk);@(negedge clk);m11_nak_valid=0;@(posedge clk);
    check(m11_link_down && m11_rollover,"TC43: 3 replays → link_down");
    do_reset;

    body992=992'hDEAD_CAFE_1234;crc32_val=crc32_lcrc(body992);
    @(negedge clk);m12_tlp_rx={12'd42,20'h0,body992,crc32_val};m12_valid=1;m12_flit_mode=0;
    @(posedge clk);@(negedge clk);m12_valid=0;@(posedge clk);
    check(m12_ok && !m12_err && m12_seq==12'd42,"TC44: LCRC good CRC");

    @(negedge clk);m12_tlp_rx[31:0]=m12_tlp_rx[31:0]^32'hDEAD_BEEF;m12_valid=1;
    @(posedge clk);@(negedge clk);m12_valid=0;@(posedge clk);
    check(!m12_ok && m12_err,"TC45: LCRC error detected");

    body992=992'h0;crc32_val=crc32_lcrc(body992);
    @(negedge clk);m12_tlp_rx={12'd999,20'h0,body992,crc32_val};m12_valid=1;
    @(posedge clk);@(negedge clk);m12_valid=0;@(posedge clk);
    check(m12_ok && m12_seq==12'd999,"TC46: Seq=999 extracted");
    do_reset;

    @(negedge clk);m13_seq_rx=0;m13_tlp_ok=1;m13_tlp_valid=1;m13_tlp_clean=1024'hCAFE;
    @(posedge clk);@(negedge clk);m13_tlp_valid=0;@(posedge clk);
    check(m13_seq_ok && m13_fwd_valid && m13_next_exp==12'd1,"TC47: seq=0 forwarded");

    @(negedge clk);m13_seq_rx=0;m13_tlp_ok=1;m13_tlp_valid=1;
    @(posedge clk);@(negedge clk);m13_tlp_valid=0;@(posedge clk);
    check(m13_dup && !m13_fwd_valid,"TC48: Duplicate dropped");

    @(negedge clk);m13_seq_rx=5;m13_tlp_ok=1;m13_tlp_valid=1;
    @(posedge clk);@(negedge clk);m13_tlp_valid=0;@(posedge clk);
    check(m13_seq_err && m13_nak_req,"TC49: Seq error NAK");

    @(negedge clk);m13_seq_rx=1;m13_tlp_ok=0;m13_tlp_valid=1;
    @(posedge clk);@(negedge clk);m13_tlp_valid=0;@(posedge clk);
    check(!m13_seq_ok && m13_next_exp==12'd1,"TC50: CRC fail no advance");
    do_reset;

    @(negedge clk);m14_rollover=1;@(posedge clk);@(negedge clk);m14_rollover=0;@(posedge clk);
    check(m14_valid && m14_type==4'd1 && m14_sev==2'd2,"TC51: Rollover=FATAL");

    @(negedge clk);m14_dllp_crc=1;@(posedge clk);@(negedge clk);m14_dllp_crc=0;@(posedge clk);
    check(m14_valid && m14_type==4'd2 && m14_sev==2'd0,"TC52: DLLP CRC=COR");

    @(negedge clk);m14_lcrc=1;@(posedge clk);@(negedge clk);m14_lcrc=0;@(posedge clk);
    check(m14_valid && m14_type==4'd4 && m14_sev==2'd1,"TC53: LCRC=NONFATAL");

    @(negedge clk);m14_flit_uncorr=1;@(posedge clk);@(negedge clk);m14_flit_uncorr=0;@(posedge clk);
    check(m14_valid && m14_sev==2'd2,"TC54: FLIT_UE=FATAL");
    do_reset;

    @(negedge clk);m15_active=1;m15_timer_exp=1;m15_inhibit=0;
    @(posedge clk);@(negedge clk);m15_timer_exp=0;@(posedge clk);
    check(m15_send && m15_dllp[63:56]==8'h31,"TC55: NOP=0x31 fires (BUG FIX)");

    @(negedge clk);m15_timer_exp=1;m15_inhibit=1;
    @(posedge clk);@(negedge clk);m15_timer_exp=0;m15_inhibit=0;@(posedge clk);
    check(!m15_send,"TC56: NOP inhibited");

    @(negedge clk);m15_active=0;m15_timer_exp=1;
    @(posedge clk);@(negedge clk);m15_timer_exp=0;@(posedge clk);
    check(!m15_send,"TC57: NOP suppressed inactive");
    m15_active=1;
    do_reset;

    m16_active=1;m16_limit=16'd4;
    repeat(7)@(posedge clk);
    check(m16_exp && m16_req,"TC58: FC timer fires");

    @(negedge clk);m16_sent=1;
    @(posedge clk);@(negedge clk);m16_sent=0;@(posedge clk);
    check(!m16_exp,"TC59: FC timer clears on sent (BUG FIX)");

    @(negedge clk);m16_active=0;repeat(10)@(posedge clk);
    check(!m16_exp,"TC60: FC inactive when not active");
    m16_active=1;
    do_reset;

    m17_active=1;m17_pending=1;m17_limit=16'd3;
    repeat(6)@(posedge clk);
    check(m17_deadlock && m17_err,"TC61: FC watchdog fires");

    @(negedge clk);m17_p=1;@(posedge clk);@(negedge clk);m17_p=0;
    @(posedge clk);@(posedge clk);
    check(!m17_deadlock,"TC62: Watchdog clears on credit");
    do_reset;

    m18_ack_lim=16'd4;m18_replay_lim=16'd8;
    @(negedge clk);m18_tlp_valid=1;@(posedge clk);@(negedge clk);m18_tlp_valid=0;
    repeat(6)@(posedge clk);
    check(m18_ack_exp,"TC63: ACK timer fires");

    repeat(5)@(posedge clk);
    check(m18_replay_exp,"TC64: Replay timer fires");

    @(negedge clk);m18_ack_sent=1;@(posedge clk);@(negedge clk);m18_ack_sent=0;
    @(posedge clk);@(posedge clk);
    check(!m18_ack_exp,"TC65: ACK timer clears");
    do_reset;

    m19_dl_up=1;m19_status=0;m19_syndrome=0;m19_corrected=0;
    for(beat=0;beat<8;beat=beat+1) begin
        @(negedge clk);m19_rxd={244'h0,beat[11:0]};m19_valid=1;@(posedge clk);
    end
    @(negedge clk);m19_valid=0;@(posedge clk);
    check(m19_rx_flit_valid,"TC66: 8-beat FLIT assembled");

    do_reset;m19_dl_up=1;m19_status=0;m19_syndrome=16'hBEEF;m19_corrected=0;
    for(beat=0;beat<8;beat=beat+1) begin
        @(negedge clk);m19_rxd=256'h0;m19_valid=1;@(posedge clk);
    end
    @(negedge clk);m19_valid=0;@(posedge clk);
    check(!m19_rx_flit_valid,"TC67: FEC UE suppresses FLIT");

    do_reset;m19_dl_up=0;m19_syndrome=0;
    for(beat=0;beat<8;beat=beat+1) begin
        @(negedge clk);m19_rxd=256'h0;m19_valid=1;@(posedge clk);
    end
    @(negedge clk);m19_valid=0;@(posedge clk);
    check(!m19_rx_flit_valid,"TC68: DL not up suppresses FLIT");
    do_reset;

    @(negedge clk);m20_ltssm_up=1;@(posedge clk);@(negedge clk);m20_ltssm_up=0;@(posedge clk);
    check(!m20_active,"TC69: DL_INIT not active");
    @(negedge clk);m20_fc_done=1;@(posedge clk);@(negedge clk);m20_fc_done=0;@(posedge clk);
    check(m20_active && m20_dll_up,"TC70: DL_ACTIVE after fc_done");

    @(negedge clk);m20_rollover=1;@(posedge clk);@(negedge clk);m20_rollover=0;@(posedge clk);
    check(m20_error && !m20_active,"TC71: Rollover → DL_ERROR");

    @(negedge clk);m20_ltssm_down=1;@(posedge clk);@(negedge clk);m20_ltssm_down=0;
    @(posedge clk);@(posedge clk);
    check(!m20_error && !m20_active,"TC72: Down → INACTIVE");
    do_reset;

    m21_l0s_lim=16'd3;
    @(negedge clk);m21_l0s_entry=1;
    repeat(5)@(posedge clk);
    check(m21_l0s_exp,"TC73: L0s timer fires");

    @(negedge clk);m21_l0s_exit=1;m21_l0s_entry=0;
    @(posedge clk);@(negedge clk);m21_l0s_exit=0;
    @(posedge clk);@(posedge clk);
    check(!m21_l0s_exp,"TC74: L0s exit resets");

    do_reset;
    @(negedge clk);m25_req_sw=3'd4;
    @(posedge clk);@(negedge clk);m25_req_sw=0;@(posedge clk);
    check(m25_pm_send && m25_ls==3'd1,"TC75: PM sends L0s DLLP");

    @(negedge clk);m25_pm_rx=3'd3;m25_pm_rx_valid=1;
    @(posedge clk);@(negedge clk);m25_pm_rx_valid=0;@(posedge clk);
    check(m25_ls==3'd0,"TC76: PM exits L0s on ACK");
    do_reset;

    m22_lat_lim=16'd3;
    @(negedge clk);m22_pending=1;m22_pending_seq=12'd55;
    repeat(5)@(posedge clk);
    check(m22_pgb_valid && m22_pgb_seq==12'd55,"TC77: ACK piggybacked at timer");

    do_reset;
    @(negedge clk);m22_pending=1;m22_pending_seq=12'd99;m22_nop_req=1;
    @(posedge clk);@(negedge clk);m22_nop_req=0;@(posedge clk);
    check(m22_pgb_valid && m22_pgb_seq==12'd99,"TC78: ACK piggybacked on NOP");

    @(negedge clk);m22_pending=0;@(posedge clk);@(posedge clk);
    check(!m22_pgb_valid,"TC79: No ACK when pending=0");
    do_reset;

    @(negedge clk);m23_active=1;
    @(posedge clk);@(posedge clk);
    @(negedge clk);m23_rx={64'h0,8'hC0};m23_rx_valid=1;
    @(posedge clk);@(negedge clk);m23_rx_valid=0;
    @(posedge clk);@(posedge clk);
    @(negedge clk);m23_rx={64'h0,8'hD0};m23_rx_valid=1;
    @(posedge clk);@(negedge clk);m23_rx_valid=0;
    repeat(5)@(posedge clk);
    check(m23_done,"TC80: FC init handshake done");
    do_reset;

    m24_speed=4'd8;m24_width=6'd16;
    @(negedge clk);m24_bw_change=1;@(posedge clk);@(negedge clk);m24_bw_change=0;
    @(posedge clk);@(posedge clk);
    check(m24_bw_valid,"TC81: BW notification DLLP sent");

    do_reset;
    @(negedge clk);m24_eq_req=1;
    @(posedge clk);@(posedge clk);@(posedge clk);
    check(m24_eq_req_out,"TC82: EQ req forwarded");
    @(negedge clk);m24_eq_req=0;
    @(posedge clk);@(posedge clk);
    check(m24_eq_ack,"TC82b: EQ ack on de-assert");
    do_reset;

    @(negedge clk);m26_tx_seq=12'd2048;m26_ack_seq=12'd0;
    @(posedge clk);@(posedge clk);
    check(m26_win_full,"TC83: Window full at 2048");

    @(negedge clk);m26_ack_seq=12'd2047;
    @(posedge clk);@(posedge clk);@(posedge clk);
    check(!m26_win_full,"TC84: Window clears after ACK");

    @(negedge clk);m26_tx_seq=12'd4095;@(posedge clk);
    @(negedge clk);m26_tx_seq=12'd0;
    @(posedge clk);@(posedge clk);
    check(m26_wrap,"TC85: Wrap 4095→0 detected");

    $display("\n========================================");
    $display("  RESULTS: %0d PASSED  |  %0d FAILED", pass_cnt, fail_cnt);
    $display("========================================");
    if(fail_cnt==0) $display("ALL %0d TESTS PASSED ✓", pass_cnt);
    else $display("*** %0d FAILED — review above ***", fail_cnt);
    $finish;
end

initial begin #10_000_000; $display("[WATCHDOG] Timeout"); $finish; end

endmodule
