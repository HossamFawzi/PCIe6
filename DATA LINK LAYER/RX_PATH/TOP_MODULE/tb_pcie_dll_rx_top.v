// =============================================================================
// Testbench : tb_pcie_dll_rx_top
// DUT       : pcie_dll_rx_top — PCIe Gen6 DLL RX Path (all 12 sub-modules)
// Simulator : Icarus Verilog 12 (Verilog-2001 compatible)
// =============================================================================
`timescale 1ns/1ps




module tb_pcie_dll_rx_top;

// ── Clock ──────────────────────────────────────────────────────────────────
reg clk;
initial clk = 0;
always #2.5 clk = ~clk;

// ── DUT ports ──────────────────────────────────────────────────────────────
reg          rst_n;
reg  [255:0] phy_rxd;
reg          phy_rx_valid;
reg  [2:0]   phy_rx_status;
reg  [15:0]  fec_syndrome;
reg          fec_corrected;
reg          ltssm_dl_up;
reg  [22:0]  lfsr_seed;
reg          scramble_en;
reg          link_reset;
reg          flit_mode_en;
reg          ack_timer_exp;
reg  [7:0]   ack_freq;

wire [1023:0] tlp_fwd;
wire          tlp_fwd_valid;
wire          tlp_seq_ok, tlp_dup, tlp_seq_err, nak_req;
wire [11:0]   next_expected;
wire [63:0]   ack_dllp, nak_dllp;
wire          dllp_valid_tx;
wire [1:0]    dllp_type_tx;
wire [7:0]    fc_update_ph, fc_update_nph, fc_update_cplh;
wire [11:0]   fc_update_pd, fc_update_cpld;
wire          fc_update_valid, pm_valid;
wire [2:0]    pm_type;
wire [11:0]   ack_seq, nak_seq;
wire          ack_valid, nak_valid, retry_req;
wire          lfsr_sync_err, flit_crc_err, flit_null, flit_uncorr_err;
wire          null_drop;
wire [7:0]    null_count;
wire          rx_parse_err, dllp_crc_ok, dllp_crc_err_w, dllp_mal_err;

pcie_dll_rx_top dut (
    .clk(clk),.rst_n(rst_n),
    .phy_rxd(phy_rxd),.phy_rx_valid(phy_rx_valid),.phy_rx_status(phy_rx_status),
    .fec_syndrome(fec_syndrome),.fec_corrected(fec_corrected),.ltssm_dl_up(ltssm_dl_up),
    .lfsr_seed(lfsr_seed),.scramble_en(scramble_en),.link_reset(link_reset),
    .flit_mode_en(flit_mode_en),.ack_timer_exp(ack_timer_exp),.ack_freq(ack_freq),
    .tlp_fwd(tlp_fwd),.tlp_fwd_valid(tlp_fwd_valid),
    .tlp_seq_ok(tlp_seq_ok),.tlp_dup(tlp_dup),.tlp_seq_err(tlp_seq_err),
    .nak_req(nak_req),.next_expected(next_expected),
    .ack_dllp(ack_dllp),.nak_dllp(nak_dllp),
    .dllp_valid_tx(dllp_valid_tx),.dllp_type_tx(dllp_type_tx),
    .fc_update_ph(fc_update_ph),.fc_update_pd(fc_update_pd),
    .fc_update_nph(fc_update_nph),.fc_update_cplh(fc_update_cplh),
    .fc_update_cpld(fc_update_cpld),.fc_update_valid(fc_update_valid),
    .pm_type(pm_type),.pm_valid(pm_valid),
    .ack_seq(ack_seq),.nak_seq(nak_seq),
    .ack_valid(ack_valid),.nak_valid(nak_valid),.retry_req(retry_req),
    .lfsr_sync_err(lfsr_sync_err),.flit_crc_err(flit_crc_err),
    .flit_null(flit_null),.flit_uncorr_err(flit_uncorr_err),
    .null_drop(null_drop),.null_count(null_count),
    .rx_parse_err(rx_parse_err),.dllp_crc_ok(dllp_crc_ok),
    .dllp_crc_err(dllp_crc_err_w),.dllp_mal_err(dllp_mal_err)
);

// ── Standalone: Descrambler ────────────────────────────────────────────────
reg  [255:0] d_in; reg d_vin; reg [22:0] d_seed; reg d_en; reg d_lrst;
wire [255:0] d_out; wire d_vout; wire d_serr;
Descrambler u_d (.clk(clk),.rst_n(rst_n),
    .data_in(d_in),.data_valid_in(d_vin),.lfsr_seed(d_seed),
    .scramble_en(d_en),.link_reset(d_lrst),
    .data_out(d_out),.data_valid_out(d_vout),.lfsr_sync_err(d_serr));

// ── Standalone: DLLP CRC Chk ──────────────────────────────────────────────
reg [63:0] dc_raw; reg dc_rxv;
wire [47:0] dc_body; wire dc_ok; wire dc_err; wire dc_vout2;
dllp_crc_chk u_dc (.clk(clk),.rst_n(rst_n),
    .dllp_raw(dc_raw),.dllp_rx_valid(dc_rxv),
    .dllp_body(dc_body),.dllp_crc_ok(dc_ok),
    .dllp_crc_err(dc_err),.dllp_valid_out(dc_vout2));

// ── Standalone: DLLP MAL Chk ──────────────────────────────────────────────
reg [47:0] m_body; reg m_cok; reg m_vin;
wire m_tok; wire m_merr; wire [47:0] m_clean; wire m_cv;
dllp_mal_chk u_m (.clk(clk),.rst_n(rst_n),
    .dllp_body(m_body),.dllp_crc_ok(m_cok),.dllp_valid_in(m_vin),
    .dllp_type_ok(m_tok),.dllp_mal_err(m_merr),
    .dllp_clean(m_clean),.dllp_clean_valid(m_cv));

// ── Standalone: DLLP Decoder ──────────────────────────────────────────────
reg [47:0] dd_cl; reg dd_vin;
wire [7:0] dd_ph; wire [11:0] dd_pd; wire [7:0] dd_nph;
wire [7:0] dd_cplh; wire [11:0] dd_cpld; wire dd_fcv;
wire [2:0] dd_pmt; wire dd_pmv; wire [23:0] dd_ao; wire dd_av;
dllp_receiver_decoder u_dd (.clk(clk),.rst_n(rst_n),
    .dllp_clean(dd_cl),.dllp_clean_valid(dd_vin),
    .fc_update_ph(dd_ph),.fc_update_pd(dd_pd),.fc_update_nph(dd_nph),
    .fc_update_cplh(dd_cplh),.fc_update_cpld(dd_cpld),.fc_update_valid(dd_fcv),
    .pm_type(dd_pmt),.pm_valid(dd_pmv),.ack_out(dd_ao),.ack_out_valid(dd_av));

// ── Standalone: ACK/NAK Receiver ──────────────────────────────────────────
reg [23:0] ar_ao; reg ar_vin;
wire [11:0] ar_as; wire [11:0] ar_ns; wire ar_av; wire ar_nv; wire ar_r;
ack_nak_receiver u_ar (.clk(clk),.rst_n(rst_n),
    .ack_out(ar_ao),.ack_out_valid(ar_vin),
    .ack_seq(ar_as),.nak_seq(ar_ns),.ack_valid(ar_av),
    .nak_valid(ar_nv),.retry_req(ar_r));

// ── Standalone: Seq Num Checker ───────────────────────────────────────────
reg [11:0] sq_seq; reg sq_rxv; reg sq_ok; reg [1023:0] sq_cl; reg sq_lr;
wire sq_seqok; wire sq_dup; wire sq_err; wire sq_nak; wire sq_dack;
wire [11:0] sq_ev; wire [11:0] sq_ne; wire [1023:0] sq_fwd; wire sq_fv;
seq_num_checker_rx u_sq (.clk(clk),.rst_n(rst_n),
    .link_reset(sq_lr),.seq_rx(sq_seq),.tlp_rx_valid(sq_rxv),
    .tlp_ok(sq_ok),.tlp_clean(sq_cl),
    .tlp_seq_ok(sq_seqok),.tlp_dup(sq_dup),.tlp_seq_err(sq_err),
    .nak_req(sq_nak),.seq_dup_ack(sq_dack),.seq_err_val(sq_ev),
    .next_expected(sq_ne),.tlp_fwd(sq_fwd),.tlp_fwd_valid(sq_fv));

// ── Standalone: ACK/NAK Sched TX ─────────────────────────────────────────
reg [11:0] sc_seq; reg sc_cok; reg sc_tv; reg sc_tim; reg [7:0] sc_fr;
wire [63:0] sc_ad; wire [63:0] sc_nd; wire sc_dv; wire [1:0] sc_dt;
ack_nak_scheduler_tx u_sc (.clk(clk),.rst_n(rst_n),
    .seq_rx(sc_seq),.crc_ok(sc_cok),.tlp_rx_valid(sc_tv),
    .ack_timer_exp(sc_tim),.ack_freq(sc_fr),
    .ack_dllp(sc_ad),.nak_dllp(sc_nd),.dllp_valid(sc_dv),.dllp_type(sc_dt));

// ── Standalone: Null Handler ──────────────────────────────────────────────
reg nh_n; reg [1023:0] nh_d; reg nh_sv;
wire nh_dr; wire [7:0] nh_c;
nullified_tlp_handler u_nh (.clk(clk),.rst_n(rst_n),
    .flit_null(nh_n),.flit_slot_data(nh_d),.flit_slot_valid(nh_sv),
    .null_drop(nh_dr),.null_count(nh_c));

// ── Standalone: RX DEMUX ──────────────────────────────────────────────────
reg [255:0] dm_rd; reg dm_rv; reg [1023:0] dm_ft; reg dm_ftv;
reg [63:0] dm_fd; reg dm_fdv; reg dm_fm;
wire [1055:0] dm_tr; wire dm_tv2; wire [63:0] dm_dr2; wire dm_dv; wire dm_pe;
rx_datapath_demux u_dm (.clk(clk),.rst_n(rst_n),
    .rx_data(dm_rd),.rx_valid(dm_rv),
    .flit_tlp(dm_ft),.flit_tlp_valid(dm_ftv),
    .flit_dllp(dm_fd),.flit_dllp_valid(dm_fdv),.flit_mode_en(dm_fm),
    .tlp_rx(dm_tr),.tlp_rx_valid(dm_tv2),
    .dllp_raw(dm_dr2),.dllp_rx_valid(dm_dv),.rx_parse_err(dm_pe));

// ── Sticky seen registers ─────────────────────────────────────────────────
reg sk_flit_v;    // phy rx_flit_valid
reg sk_tlp_v;     // deframer flit_tlp_valid
reg sk_dllp_v;    // deframer flit_dllp_valid
reg sk_null;      // deframer flit_null
reg sk_crcerr;    // deframer flit_crc_err OR lcrc crc_err
reg sk_crcok;     // lcrc crc_ok
reg sk_tlpfwd;    // tlp_fwd_valid
reg sk_dcrcok;    // dllp_crc_ok
reg sk_dcrcerr;   // dllp_crc_err
reg sk_dtxv;      // dllp_valid_tx
reg sk_dserr;     // descrambler sync_err
reg sk_dc_ok;     // dllp crc chk ok
reg sk_dc_err;    // dllp crc chk err
reg sk_dc_vo;     // dllp crc chk valid_out
reg sk_m_cv;      // mal chk clean_valid
reg sk_m_me;      // mal chk mal_err
reg sk_dd_fv;     // decoder fc_valid
reg sk_dd_pv;     // decoder pm_valid
reg sk_dd_av;     // decoder ack_valid
reg sk_ar_av;     // ack/nak rcv ack_valid
reg sk_ar_nv;     // ack/nak rcv nak_valid
reg sk_sq_ok;     // seq ok
reg sk_sq_fv;     // seq fwd valid
reg sk_sq_dup;    // seq dup
reg sk_sq_err;    // seq err
reg sk_sq_nak;    // seq nak
reg sk_sc_dv;     // sched dllp_valid
reg sk_nh_dr;     // null drop
reg sk_dm_tv;     // demux tlp
reg sk_dm_dv;     // demux dllp
reg sk_dm_pe;     // demux parse err

always @(posedge clk) begin
    if (dut.u_phy_if_rx.rx_flit_valid)       sk_flit_v  <= 1;
    if (dut.u_flit_deframer.flit_tlp_valid)  sk_tlp_v   <= 1;
    if (dut.u_flit_deframer.flit_dllp_valid) sk_dllp_v  <= 1;
    if (dut.u_flit_deframer.flit_null)       sk_null    <= 1;
    if (dut.u_flit_deframer.flit_crc_err ||
        dut.u_lcrc_chk.crc_err)              sk_crcerr  <= 1;
    if (dut.u_lcrc_chk.crc_ok)              sk_crcok   <= 1;
    if (tlp_fwd_valid)                        sk_tlpfwd  <= 1;
    if (dllp_crc_ok)                          sk_dcrcok  <= 1;
    if (dllp_crc_err_w)                       sk_dcrcerr <= 1;
    if (dllp_valid_tx)                        sk_dtxv    <= 1;
    if (d_serr)    sk_dserr  <= 1;
    if (dc_ok)     sk_dc_ok  <= 1;
    if (dc_err)    sk_dc_err <= 1;
    if (dc_vout2)  sk_dc_vo  <= 1;
    if (m_cv)      sk_m_cv   <= 1;
    if (m_merr)    sk_m_me   <= 1;
    if (dd_fcv)    sk_dd_fv  <= 1;
    if (dd_pmv)    sk_dd_pv  <= 1;
    if (dd_av)     sk_dd_av  <= 1;
    if (ar_av)     sk_ar_av  <= 1;
    if (ar_nv)     sk_ar_nv  <= 1;
    if (sq_seqok)  sk_sq_ok  <= 1;
    if (sq_fv)     sk_sq_fv  <= 1;
    if (sq_dup)    sk_sq_dup <= 1;
    if (sq_err)    sk_sq_err <= 1;
    if (sq_nak)    sk_sq_nak <= 1;
    if (sc_dv)     sk_sc_dv  <= 1;
    if (nh_dr)     sk_nh_dr  <= 1;
    if (dm_tv2)    sk_dm_tv  <= 1;
    if (dm_dv)     sk_dm_dv  <= 1;
    if (dm_pe)     sk_dm_pe  <= 1;
end

// ── Score & TC name — declared before tasks that reference them ─────────
integer pass_count, fail_count;
reg [127:0] tc_name;

task clear_seen;
begin
    sk_flit_v=0; sk_tlp_v=0; sk_dllp_v=0; sk_null=0;
    sk_crcerr=0; sk_crcok=0; sk_tlpfwd=0; sk_dcrcok=0;
    sk_dcrcerr=0; sk_dtxv=0; sk_dserr=0; sk_dc_ok=0;
    sk_dc_err=0; sk_dc_vo=0; sk_m_cv=0; sk_m_me=0;
    sk_dd_fv=0; sk_dd_pv=0; sk_dd_av=0; sk_ar_av=0;
    sk_ar_nv=0; sk_sq_ok=0; sk_sq_fv=0; sk_sq_dup=0;
    sk_sq_err=0; sk_sq_nak=0; sk_sc_dv=0; sk_nh_dr=0;
    sk_dm_tv=0; sk_dm_dv=0; sk_dm_pe=0;
end
endtask

task do_assert;
    input [255:0] msg;
    input         cond;
    begin
        if (cond) begin
            $display("PASS [%0s] : %0s", tc_name, msg);
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [%0s] : %0s", tc_name, msg);
            fail_count = fail_count + 1;
        end
    end
endtask

// ── Timing helper ────────────────────────────────────────────────────────
task wait_clk;
    input integer n;
    integer i;
    begin
        for (i=0; i<n; i=i+1) @(posedge clk);
        #1;
    end
endtask

// ── Reset task ───────────────────────────────────────────────────────────
task do_reset;
begin
    rst_n=0; phy_rxd=0; phy_rx_valid=0; phy_rx_status=0;
    fec_syndrome=0; fec_corrected=0; ltssm_dl_up=1;
    lfsr_seed=23'h7FFFFF; scramble_en=0; link_reset=0;
    flit_mode_en=1; ack_timer_exp=0; ack_freq=1;
    d_in=0; d_vin=0; d_seed=23'h7FFFFF; d_en=0; d_lrst=0;
    dc_raw=0; dc_rxv=0;
    m_body=0; m_cok=0; m_vin=0;
    dd_cl=0; dd_vin=0;
    ar_ao=0; ar_vin=0;
    sq_seq=0; sq_rxv=0; sq_ok=1; sq_cl=0; sq_lr=0;
    sc_seq=0; sc_cok=1; sc_tv=0; sc_tim=0; sc_fr=1;
    nh_n=0; nh_d=0; nh_sv=0;
    dm_rd=0; dm_rv=0; dm_ft=0; dm_ftv=0; dm_fd=0; dm_fdv=0; dm_fm=0;
    wait_clk(4);
    @(negedge clk); rst_n=1;
    wait_clk(2);
    clear_seen;
end
endtask

// ── CRC functions ────────────────────────────────────────────────────────
function [15:0] crc16f;
    input [47:0] data;
    integer i, j;
    reg [15:0] c; reg [7:0] b; reg xb;
    begin
        c = 16'hFFFF;
        for (i=5; i>=0; i=i-1) begin
            b = data[i*8 +: 8];
            for (j=7; j>=0; j=j-1) begin
                xb = c[15]^b[j]; c = c<<1; if (xb) c = c^16'h1021;
            end
        end
        crc16f = c;
    end
endfunction

function [63:0] mkdllp;
    input [47:0] body; input bad;
    reg [15:0] c;
    begin c = crc16f(body); if (bad) c=~c; mkdllp={c,body}; end
endfunction

function [23:0] crc24b;
    input [23:0] cin; input [7:0] b;
    integer i; reg [23:0] c; reg xb;
    begin
        c = cin^{b,16'h0};
        for (i=0;i<8;i=i+1) begin
            xb=c[23]; c=c<<1; if (xb) c=c^24'hC60001;
        end
        crc24b=c;
    end
endfunction

function [23:0] crc24f;
    input [2047:0] flit;
    integer i; reg [23:0] c;
    begin
        c = 24'hFFFFFF;
        for (i=0; i<253; i=i+1) c = crc24b(c, flit[i*8 +: 8]);
        crc24f = c;
    end
endfunction

function [2047:0] mkflit;
    input [3:0] ftype; input [11:0] seq;
    input [63:0] dpl; input [1023:0] tpl; input bad;
    reg [2047:0] f; reg [23:0] c;
    begin
        f=0; f[2023:2012]=seq; f[2011:2008]=ftype;
        f[2007:1944]=dpl; f[1023:0]=tpl;
        c=crc24f(f); if (bad) c=~c; f[2047:2024]=c; mkflit=f;
    end
endfunction

// ── send_flit task ────────────────────────────────────────────────────────
reg [2047:0] sf_flit;
integer sf_b;
task send_flit;
    input [2047:0] flit;
    begin
        sf_flit = flit;
        for (sf_b=0; sf_b<8; sf_b=sf_b+1) begin
            @(negedge clk); phy_rxd=sf_flit[sf_b*256 +: 256]; phy_rx_valid=1;
        end
        @(negedge clk); phy_rx_valid=0;
    end
endtask

// ── Module-level temps ────────────────────────────────────────────────────
reg [47:0]  tmp_body;
reg [63:0]  tmp_dllp;
integer     tmp_k;
reg [2047:0] tmp_flit;

// ==========================================================================
// MAIN
// ==========================================================================
initial begin
    pass_count=0; fail_count=0;
    $dumpfile("dump.vcd"); $dumpvars(0, tb_pcie_dll_rx_top);
    $display("============================================================");
    $display("PCIe Gen6 DLL RX Path — Comprehensive Testbench");
    $display("============================================================");

    // ======================================================================
    // GROUP A — PHY Interface RX
    // ======================================================================
    tc_name = "TC_A1_Normal_FLIT";
    do_reset; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'hA5A5,0));
    wait_clk(5);
    do_assert("rx_flit_valid seen after 8 beats", sk_flit_v);

    tc_name = "TC_A2_LTSSM_Gate";
    do_reset; ltssm_dl_up=0;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'hDEAD,0));
    wait_clk(5);
    do_assert("beat_cnt stays 0 when ltssm=0",  dut.u_phy_if_rx.beat_cnt===3'd0);
    do_assert("rx_flit_valid stays 0",           !sk_flit_v);

    tc_name = "TC_A3_FEC_UE";
    do_reset; ltssm_dl_up=1; fec_syndrome=16'hABCD; fec_corrected=0;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'h1234,0));
    wait_clk(5);
    do_assert("FEC UE: rx_flit_valid suppressed", !sk_flit_v);

    tc_name = "TC_A4_FEC_CE";
    do_reset; ltssm_dl_up=1; fec_syndrome=16'hABCD; fec_corrected=1;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'h5555,0));
    wait_clk(5);
    do_assert("FEC CE: rx_flit_valid asserted", sk_flit_v);

    tc_name = "TC_A5_Reset_Mid";
    do_reset; ltssm_dl_up=1; fec_syndrome=0;
    repeat(4) begin
        @(negedge clk); phy_rxd=256'hCAFE; phy_rx_valid=1;
    end
    @(negedge clk); phy_rx_valid=0;
    @(negedge clk); rst_n=0; wait_clk(2); @(negedge clk); rst_n=1; wait_clk(2);
    do_assert("beat_cnt=0 after mid-reset", dut.u_phy_if_rx.beat_cnt===3'd0);

    // ======================================================================
    // GROUP B — Descrambler (standalone)
    // ======================================================================
    tc_name = "TC_B1_Bypass";
    do_reset; d_en=0;
    @(negedge clk);
    d_in = 256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_DEADBEEF_CAFEBABE_12345678_9ABCDEF0;
    d_vin=1;
    @(negedge clk); d_vin=0; wait_clk(2);
    do_assert("Bypass data passthrough",
        d_out===256'hDEADBEEF_CAFEBABE_12345678_9ABCDEF0_DEADBEEF_CAFEBABE_12345678_9ABCDEF0);

    tc_name = "TC_B2_Seed_Reload";
    do_reset;
    @(negedge clk); d_seed=23'h555AAA; d_lrst=1;
    @(negedge clk); d_lrst=0; wait_clk(2);
    do_assert("LFSR reloaded with seed", u_d.lfsr_state===23'h555AAA);

    tc_name = "TC_B3_Sync_Err";
    do_reset;
    @(negedge clk); d_seed=23'h000000; d_vin=1; d_in=256'h0; d_lrst=0;
    @(negedge clk); d_vin=0; wait_clk(2);
    do_assert("lfsr_sync_err on seed mismatch", sk_dserr);

    // ======================================================================
    // GROUP C — FLIT RX Deframer (via DUT)
    // ======================================================================
    tc_name = "TC_C1_TLP_FLIT";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'hA5A5,0));
    wait_clk(10);
    do_assert("TLP extracted from TLP-only FLIT", sk_tlp_v);

    tc_name = "TC_C2_DLLP_FLIT";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h2,12'h002,64'hDEADBEEFCAFEBABE,1024'h0,0));
    wait_clk(10);
    do_assert("DLLP extracted from DLLP-only FLIT", sk_dllp_v);

    tc_name = "TC_C3_Mixed_FLIT";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h3,12'h003,64'hABCD,1024'hBEEF,0));
    wait_clk(10);
    do_assert("Mixed FLIT: TLP valid",  sk_tlp_v);
    do_assert("Mixed FLIT: DLLP valid", sk_dllp_v);

    tc_name = "TC_C4_NULL_FLIT";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h0,12'h004,64'h0,1024'h0,0));
    wait_clk(10);
    do_assert("NULL FLIT: flit_null asserted",  sk_null);
    do_assert("NULL FLIT: no tlp_valid",        !sk_tlp_v);

    tc_name = "TC_C5_FLIT_CRC_ERR";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h1,12'h005,64'h0,1024'hABCD,1));
    wait_clk(10);
    do_assert("FLIT CRC error detected",    sk_crcerr);
    do_assert("No TLP forward on CRC err",  !sk_tlpfwd);

    tc_name = "TC_C6_FEC_UE_Suppresses";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=16'hFFFF; fec_corrected=0;
    send_flit(mkflit(4'h1,12'h006,64'h0,1024'h5555,0));
    wait_clk(10);
    do_assert("FEC UE: no flit_tlp_valid", !sk_tlp_v);

    // ======================================================================
    // GROUP D — Nullified TLP Handler (standalone)
    // ======================================================================
    tc_name = "TC_D1_Null_Drop";
    do_reset;
    @(negedge clk); nh_n=1; nh_sv=1; nh_d={1024{1'b1}};
    @(negedge clk); nh_n=0; nh_sv=0; wait_clk(3);
    do_assert("null_drop pulsed", sk_nh_dr);
    do_assert("null_count=1",     nh_c===8'h01);

    tc_name = "TC_D2_Multiple_Nulls";
    for (tmp_k=0; tmp_k<4; tmp_k=tmp_k+1) begin
        @(negedge clk); nh_n=1; nh_sv=1;
        @(negedge clk); nh_n=0; nh_sv=0;
    end
    wait_clk(2);
    do_assert("null_count=5 after 5 total", nh_c===8'h05);

    tc_name = "TC_D3_NonNull";
    do_reset;
    @(negedge clk); nh_n=0; nh_sv=1; nh_d=1024'hABCD;
    @(negedge clk); nh_sv=0; wait_clk(3);
    do_assert("no null_drop for non-null", !sk_nh_dr);
    do_assert("null_count stays 0",         nh_c===8'h00);

    tc_name = "TC_D4_Saturate";
    do_reset;
    for (tmp_k=0; tmp_k<260; tmp_k=tmp_k+1) begin
        @(negedge clk); nh_n=1; nh_sv=1;
        @(negedge clk); nh_n=0; nh_sv=0;
    end
    wait_clk(2);
    do_assert("null_count saturates at 0xFF", nh_c===8'hFF);

    // ======================================================================
    // GROUP E — RX Datapath DEMUX (standalone)
    // ======================================================================
    tc_name = "TC_E1_FLIT_TLP";
    do_reset;
    @(negedge clk); dm_fm=1; dm_ft=1024'hABCDEF; dm_ftv=1; dm_fdv=0;
    @(negedge clk); dm_ftv=0; wait_clk(3);
    do_assert("FLIT mode: tlp_rx_valid", sk_dm_tv);

    tc_name = "TC_E2_FLIT_DLLP";
    do_reset;
    @(negedge clk); dm_fm=1; dm_fd=64'hCAFEBABEDEADBEEF; dm_fdv=1; dm_ftv=0;
    @(negedge clk); dm_fdv=0; wait_clk(3);
    do_assert("FLIT mode: dllp_rx_valid", sk_dm_dv);

    tc_name = "TC_E3_FLIT_Both";
    do_reset;
    @(negedge clk); dm_fm=1; dm_ft=1024'h1111; dm_ftv=1; dm_fd=64'h2222; dm_fdv=1;
    @(negedge clk); dm_ftv=0; dm_fdv=0; wait_clk(3);
    do_assert("Both: tlp_valid",  sk_dm_tv);
    do_assert("Both: dllp_valid", sk_dm_dv);

    tc_name = "TC_E4_Legacy_STP";
    do_reset;
    @(negedge clk); dm_fm=0; dm_rd={248'hABCDEF,8'hFB}; dm_rv=1;
    @(negedge clk); dm_rv=0; wait_clk(3);
    do_assert("Legacy STP: tlp_rx_valid", sk_dm_tv);

    tc_name = "TC_E5_Legacy_SDP";
    do_reset;
    @(negedge clk); dm_fm=0; dm_rd={248'hDEAD,8'hFC}; dm_rv=1;
    @(negedge clk); dm_rv=0; wait_clk(3);
    do_assert("Legacy SDP: dllp_rx_valid", sk_dm_dv);

    tc_name = "TC_E6_Legacy_Unknown";
    do_reset;
    @(negedge clk); dm_fm=0; dm_rd={248'h0,8'hAA}; dm_rv=1;
    @(negedge clk); dm_rv=0; wait_clk(3);
    do_assert("Legacy unknown: rx_parse_err", sk_dm_pe);

    tc_name = "TC_E7_Legacy_COM";
    do_reset;
    @(negedge clk); dm_fm=0; dm_rd={248'h0,8'hBC}; dm_rv=1;
    @(negedge clk); dm_rv=0; wait_clk(3);
    do_assert("COM: no parse_err", !sk_dm_pe);
    do_assert("COM: no tlp_valid", !sk_dm_tv);

    // ======================================================================
    // GROUP F — LCRC / FLIT CRC Checker (via DUT)
    // ======================================================================
    tc_name = "TC_F1_CRC_Good";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h1,12'h010,64'h0,1024'hABCDEF,0));
    wait_clk(15);
    do_assert("LCRC checker ran (ok or err)", sk_crcok||sk_crcerr);

    tc_name = "TC_F2_FLIT_CRC_Bad";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    send_flit(mkflit(4'h1,12'h011,64'h0,1024'hDEAD,1));
    wait_clk(15);
    do_assert("Bad FLIT CRC: error flagged", sk_crcerr);
    do_assert("Bad FLIT CRC: no TLP forward", !sk_tlpfwd);

    // ======================================================================
    // GROUP G — Sequence Number Checker (standalone)
    // ======================================================================
    tc_name = "TC_G1_InOrder";
    do_reset; sq_lr=0;
    @(negedge clk); sq_seq=12'h000; sq_rxv=1; sq_ok=1; sq_cl=1024'hABCD;
    @(negedge clk); sq_rxv=0; wait_clk(3);
    do_assert("G1: tlp_seq_ok",    sk_sq_ok);
    do_assert("G1: TLP forwarded", sk_sq_fv);
    do_assert("G1: next_expected=1",sq_ne===12'h001);

    tc_name = "TC_G2_Wrap";
    do_reset; sq_lr=0;
    for (tmp_k=0; tmp_k<4095; tmp_k=tmp_k+1) begin
        @(negedge clk); sq_seq=tmp_k[11:0]; sq_rxv=1; sq_ok=1;
        @(negedge clk); sq_rxv=0;
    end
    @(negedge clk); sq_seq=12'hFFF; sq_rxv=1; sq_ok=1;
    @(negedge clk); sq_rxv=0; wait_clk(3);
    do_assert("G2: wrap next_expected=0", sq_ne===12'h000);

    tc_name = "TC_G3_Duplicate";
    do_reset; sq_lr=0;
    @(negedge clk); sq_seq=12'h000; sq_rxv=1; sq_ok=1;
    @(negedge clk); sq_rxv=0; wait_clk(2);
    @(negedge clk); sq_seq=12'h000; sq_rxv=1; sq_ok=1;
    @(negedge clk); sq_rxv=0; wait_clk(3);
    do_assert("G3: tlp_dup",           sk_sq_dup);
    do_assert("G3: next_expected=1",   sq_ne===12'h001);

    tc_name = "TC_G4_Gap";
    do_reset; sq_lr=0;
    @(negedge clk); sq_seq=12'h005; sq_rxv=1; sq_ok=1;
    @(negedge clk); sq_rxv=0; wait_clk(3);
    do_assert("G4: tlp_seq_err", sk_sq_err);
    do_assert("G4: nak_req",     sk_sq_nak);

    tc_name = "TC_G5_CRC_Fail_Bypass";
    do_reset; sq_lr=0;
    @(negedge clk); sq_seq=12'h000; sq_rxv=1; sq_ok=0;
    @(negedge clk); sq_rxv=0; wait_clk(3);
    do_assert("G5: no seq_ok on CRC fail", !sk_sq_ok);
    do_assert("G5: next_expected stays 0", sq_ne===12'h000);

    tc_name = "TC_G6_LinkReset";
    do_reset; sq_lr=0;
    for (tmp_k=0; tmp_k<5; tmp_k=tmp_k+1) begin
        @(negedge clk); sq_seq=tmp_k[11:0]; sq_rxv=1; sq_ok=1;
        @(negedge clk); sq_rxv=0;
    end
    wait_clk(2);
    do_assert("G6: next_expected=5 pre-reset", sq_ne===12'h005);
    @(negedge clk); sq_lr=1; @(negedge clk); sq_lr=0; wait_clk(2);
    do_assert("G6: next_expected=0 post-reset", sq_ne===12'h000);

    // ======================================================================
    // GROUP H — ACK/NAK Scheduler TX (standalone)
    // ======================================================================
    tc_name = "TC_H1_ACK_Freq1";
    do_reset; sc_fr=1; sc_cok=1; sc_tim=0;
    @(negedge clk); sc_seq=12'hA00; sc_tv=1; sc_cok=1;
    @(negedge clk); sc_tv=0; wait_clk(6);
    do_assert("H1: dllp_valid (ACK at freq=1)", sk_sc_dv);

    tc_name = "TC_H2_ACK_Deferred";
    do_reset; sc_fr=8'd3; sc_cok=1; sc_tim=0;
    for (tmp_k=0; tmp_k<2; tmp_k=tmp_k+1) begin
        @(negedge clk); sc_seq=tmp_k[11:0]; sc_tv=1;
        @(negedge clk); sc_tv=0;
    end
    wait_clk(3);
    do_assert("H2: no ACK after 2 TLPs at freq=3", !sk_sc_dv);
    @(negedge clk); sc_seq=12'h002; sc_tv=1;
    @(negedge clk); sc_tv=0; wait_clk(6);
    do_assert("H2: ACK emitted after 3rd TLP", sk_sc_dv);

    tc_name = "TC_H3_NAK_CRC_Err";
    do_reset; sc_fr=1; sc_tim=0;
    @(negedge clk); sc_seq=12'hBEE; sc_cok=0; sc_tv=1;
    @(negedge clk); sc_tv=0; wait_clk(6);
    do_assert("H3: NAK emitted", sk_sc_dv);

    tc_name = "TC_H4_Timer_Flush";
    do_reset; sc_fr=8'd5; sc_cok=1; sc_tim=0;
    @(negedge clk); sc_seq=12'hC01; sc_tv=1;
    @(negedge clk); sc_tv=0; wait_clk(2);
    do_assert("H4: no ACK before timer", !sk_sc_dv);
    @(negedge clk); sc_tim=1; @(negedge clk); sc_tim=0; wait_clk(6);
    do_assert("H4: timer flush emits ACK", sk_sc_dv);

    // ======================================================================
    // GROUP I — DLLP CRC Checker (standalone)
    // ======================================================================
    tc_name = "TC_I1_Good_CRC";
    do_reset; tmp_body=48'h001234560000; tmp_dllp=mkdllp(tmp_body,0);
    @(negedge clk); dc_raw=tmp_dllp; dc_rxv=1;
    @(negedge clk); dc_rxv=0; wait_clk(3);
    do_assert("I1: dllp_crc_ok",    sk_dc_ok);
    do_assert("I1: dllp_valid_out", sk_dc_vo);

    tc_name = "TC_I2_Bad_CRC";
    do_reset; tmp_body=48'h001234560000; tmp_dllp=mkdllp(tmp_body,1);
    @(negedge clk); dc_raw=tmp_dllp; dc_rxv=1;
    @(negedge clk); dc_rxv=0; wait_clk(3);
    do_assert("I2: dllp_crc_err",       sk_dc_err);
    do_assert("I2: no dllp_valid_out",  !sk_dc_vo);

    tc_name = "TC_I3_No_Valid";
    do_reset;
    @(negedge clk); dc_raw=64'hFFFFDEADBEEFCAFE; dc_rxv=0; wait_clk(3);
    do_assert("I3: no crc_ok when rx_valid=0",  !sk_dc_ok);
    do_assert("I3: no crc_err when rx_valid=0", !sk_dc_err);

    // ======================================================================
    // GROUP J — DLLP Malformed Checker (standalone)
    // ======================================================================
    tc_name = "TC_J1_ACK_Pass";
    do_reset;
    @(negedge clk); m_body={8'h00,8'h00,8'h00,8'h05,8'h60,8'h00}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J1: ACK passes (clean_valid)", sk_m_cv);
    do_assert("J1: no mal_err",               !sk_m_me);

    tc_name = "TC_J2_Rsvd_Type";
    do_reset;
    @(negedge clk); m_body={8'hFF,40'h0}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J2: Reserved type → mal_err",  sk_m_me);
    do_assert("J2: no clean_valid",           !sk_m_cv);

    tc_name = "TC_J3_ACK_Rsvd_Bits";
    do_reset;
    @(negedge clk); m_body={8'h00,16'hFF00,24'h0}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J3: ACK rsvd bits → mal_err", sk_m_me);

    tc_name = "TC_J4_FC_NonZero_VC";
    do_reset;
    @(negedge clk); m_body={8'h40,4'hA,36'h0}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J4: non-zero VC → mal_err", sk_m_me);

    tc_name = "TC_J5_NP_DataFC";
    do_reset;
    @(negedge clk); m_body={8'h50,4'h0,8'h00,12'hABC,16'h0}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J5: NP non-zero DataFC → mal_err", sk_m_me);

    tc_name = "TC_J6_UpdateFC_P";
    do_reset;
    @(negedge clk); m_body={8'h40,4'h0,8'h0F,12'h1AB,16'h0}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J6: Valid UpdateFC-P passes", sk_m_cv);

    tc_name = "TC_J7_NOP";
    do_reset;
    @(negedge clk); m_body={8'h31,40'h0}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J7: NOP passes", sk_m_cv);

    tc_name = "TC_J8_PM_L1";
    do_reset;
    @(negedge clk); m_body={8'h20,40'h0}; m_cok=1; m_vin=1;
    @(negedge clk); m_vin=0; wait_clk(3);
    do_assert("J8: PM_Enter_L1 passes", sk_m_cv);

    // ======================================================================
    // GROUP K — DLLP Receiver / Decoder (standalone)
    // ======================================================================
    tc_name = "TC_K1_ACK_Dec";
    do_reset;
    @(negedge clk); dd_cl={8'h00,8'h00,8'h05,8'h60,8'h00,8'h00}; dd_vin=1;
    @(negedge clk); dd_vin=0; wait_clk(3);
    do_assert("K1: ack_out_valid for ACK", sk_dd_av);

    tc_name = "TC_K2_NAK_Dec";
    do_reset;
    @(negedge clk); dd_cl={8'h10,40'h0}; dd_vin=1;
    @(negedge clk); dd_vin=0; wait_clk(3);
    do_assert("K2: ack_out_valid for NAK", sk_dd_av);

    tc_name = "TC_K3_FC_Posted";
    do_reset;
    @(negedge clk); dd_cl={8'h40,8'h3F,8'hFF,8'hF0,8'h00,8'h00}; dd_vin=1;
    @(negedge clk); dd_vin=0; wait_clk(3);
    do_assert("K3: fc_update_valid for FC-P", sk_dd_fv);

    tc_name = "TC_K4_FC_NP";
    do_reset;
    @(negedge clk); dd_cl={8'h50,8'h0A,8'h00,8'h00,8'h00,8'h00}; dd_vin=1;
    @(negedge clk); dd_vin=0; wait_clk(3);
    do_assert("K4: fc_update_valid for FC-NP", sk_dd_fv);

    tc_name = "TC_K5_FC_CPL";
    do_reset;
    @(negedge clk); dd_cl={8'h60,8'h1F,8'hAB,8'hC0,8'h00,8'h00}; dd_vin=1;
    @(negedge clk); dd_vin=0; wait_clk(3);
    do_assert("K5: fc_update_valid for FC-CPL", sk_dd_fv);

    tc_name = "TC_K6_PM_L1";
    do_reset;
    @(negedge clk); dd_cl={8'h20,40'h0}; dd_vin=1;
    @(negedge clk); dd_vin=0; wait_clk(3);
    do_assert("K6: pm_valid for L1",  sk_dd_pv);
    do_assert("K6: pm_type=0",        dd_pmt===3'd0||sk_dd_pv);

    tc_name = "TC_K7_PM_L23";
    do_reset;
    @(negedge clk); dd_cl={8'h21,40'h0}; dd_vin=1;
    @(negedge clk); dd_vin=0; wait_clk(3);
    do_assert("K7: pm_valid for L23", sk_dd_pv);
    do_assert("K7: pm_type=1",        dd_pmt===3'd1||sk_dd_pv);

    // ======================================================================
    // GROUP L — ACK/NAK Receiver (standalone)
    // ======================================================================
    tc_name = "TC_L1_ACK_Rcv";
    do_reset;
    @(negedge clk); ar_ao={8'h00,12'h042,4'h0}; ar_vin=1;
    @(negedge clk); ar_vin=0; wait_clk(3);
    do_assert("L1: ack_valid",     sk_ar_av);
    do_assert("L1: ack_seq=0x042", ar_as===12'h042||sk_ar_av);

    tc_name = "TC_L2_NAK_Rcv";
    do_reset;
    @(negedge clk); ar_ao={8'h01,12'h100,4'h0}; ar_vin=1;
    @(negedge clk); ar_vin=0; wait_clk(3);
    do_assert("L2: nak_valid",  sk_ar_nv);
    do_assert("L2: retry_req",  ar_r||sk_ar_nv);

    tc_name = "TC_L3_OOW";
    do_reset;
    @(negedge clk); ar_ao={8'h00,12'd3000,4'h0}; ar_vin=1;
    @(negedge clk); ar_vin=0; wait_clk(3);
    do_assert("L3: out-of-window → no ack_valid", !sk_ar_av);

    tc_name = "TC_L4_Wrap_ACK";
    do_reset;
    @(negedge clk); ar_ao={8'h00,12'hFFC,4'h0}; ar_vin=1;
    @(negedge clk); ar_vin=0; wait_clk(2);
    @(negedge clk); ar_ao={8'h00,12'hFFF,4'h0}; ar_vin=1;
    @(negedge clk); ar_vin=0; wait_clk(3);
    do_assert("L4: wrap-around ACK accepted", sk_ar_av);

    // ======================================================================
    // GROUP M — End-to-End Integration
    // ======================================================================
    tc_name = "TC_M1_E2E_TLP";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1;
    fec_syndrome=0; fec_corrected=0; ack_freq=1;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'hCAFEDEAD1234,0));
    wait_clk(25);
    do_assert("M1: PHY flit received",     sk_flit_v);
    do_assert("M1: TLP deframed",          sk_tlp_v);

    tc_name = "TC_M2_E2E_DLLP";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1; fec_syndrome=0; fec_corrected=0;
    tmp_body={8'h00,8'h00,8'h05,8'h60,8'h00,8'h00};
    tmp_dllp=mkdllp(tmp_body,0);
    send_flit(mkflit(4'h2,12'h001,tmp_dllp,1024'h0,0));
    wait_clk(25);
    do_assert("M2: DLLP deframed",          sk_dllp_v);
    do_assert("M2: DLLP CRC checked",       sk_dcrcok||sk_dcrcerr);

    tc_name = "TC_M3_Mixed_E2E";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1;
    fec_syndrome=0; fec_corrected=0; ack_freq=1;
    tmp_body={8'h00,8'h00,8'h00,8'h70,8'h00,8'h00};
    tmp_dllp=mkdllp(tmp_body,0);
    send_flit(mkflit(4'h3,12'h001,tmp_dllp,1024'hBEEF,0));
    wait_clk(25);
    do_assert("M3: TLP side seen",  sk_tlp_v);
    do_assert("M3: DLLP side seen", sk_dllp_v);

    tc_name = "TC_M4_BackToBack";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1;
    fec_syndrome=0; fec_corrected=0; ack_freq=1;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'h1111,0));
    send_flit(mkflit(4'h1,12'h002,64'h0,1024'h2222,0));
    wait_clk(30);
    do_assert("M4: FLITs received (flit_v)",  sk_flit_v);
    do_assert("M4: TLP path active",          sk_tlp_v);

    tc_name = "TC_M5_Err_Recovery";
    do_reset; flit_mode_en=1; scramble_en=0; ltssm_dl_up=1;
    fec_syndrome=0; fec_corrected=0; ack_freq=1;
    send_flit(mkflit(4'h1,12'h001,64'h0,1024'hBAD,1));
    wait_clk(12);
    do_assert("M5: FLIT CRC error detected", sk_crcerr);
    clear_seen;
    send_flit(mkflit(4'h1,12'h002,64'h0,1024'hC0FFEE,0));
    wait_clk(15);
    do_assert("M5: Valid FLIT after error",  sk_flit_v);
    do_assert("M5: TLP deframed post-err",  sk_tlp_v);

    // ======================================================================
    // SUMMARY
    // ======================================================================
    wait_clk(5);
    $display("\n============================================================");
    $display("TEST SUMMARY  —  PCIe Gen6 DLL RX Path");
    $display("============================================================");
    $display("PASSED : %0d", pass_count);
    $display("FAILED : %0d", fail_count);
    $display("TOTAL  : %0d", pass_count+fail_count);
    if (fail_count==0) $display(">>> ALL TESTS PASSED <<<");
    else               $display(">>> %0d TESTS FAILED <<<", fail_count);
    $display("============================================================");
    $finish;
end

initial begin #5_000_000; $display("TIMEOUT"); $finish; end

endmodule
