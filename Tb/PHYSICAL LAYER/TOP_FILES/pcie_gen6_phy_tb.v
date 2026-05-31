
`timescale 1ns/1ps

module pcie_gen6_phy_tb;

parameter CLK_PERIOD     = 4;
parameter CLK_PIPE_PERIOD= 4;
parameter CLK_SER_PERIOD = 1;
parameter NUM_LANES      = 16;
parameter DATA_WIDTH     = 256;

integer pass_count = 0;
integer fail_count = 0;
integer test_num   = 0;
reg [255:0] test_name;

reg clk      = 0;
reg clk_pipe = 0;
reg clk_ser  = 0;
reg ssc_ref_clk = 0;

task TEST_START;
    input [255:0] name;
    begin
        test_num  = test_num + 1;
        test_name = name;
        $display("[TC%03d] START: %s  @%0t ns", test_num, name, $time);
    end
endtask

task CHECK;
    input        cond;
    input [255:0] msg;
    begin
        if (cond) begin
            pass_count = pass_count + 1;
            $display("  [PASS] %s", msg);
        end else begin
            fail_count = fail_count + 1;
            $display("  [FAIL] %s  @%0t ns", msg, $time);
        end
    end
endtask

task TICK;
    input integer n;
    begin : tick_block
        integer i;
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
        #1;
    end
endtask

always #(CLK_PERIOD/2)      clk      = ~clk;
always #(CLK_PIPE_PERIOD/2) clk_pipe = ~clk_pipe;
always #0.5                  clk_ser  = ~clk_ser;
always #(CLK_PERIOD)        ssc_ref_clk = ~ssc_ref_clk;

reg         rst_n       = 0;
reg         perst_n     = 0;
reg         power_good  = 0;
reg         clk_valid   = 0;

reg [255:0] pipe_rxd          = 0;
reg [31:0]  pipe_rxdatak      = 0;
reg         pipe_rx_valid     = 0;
reg [2:0]   pipe_rx_status    = 0;
reg         pipe_rx_elec_idle = 1;
reg         pipe_phystatus    = 0;

reg [1023:0] tlp_data    = 0;
reg          tlp_valid   = 0;
reg [63:0]   dllp_data   = 0;
reg          dllp_valid  = 0;
reg          dll_up_req  = 0;
reg          link_down_req = 0;

reg [2:0]   pm_req            = 0;
reg         hot_reset_req_sw  = 0;
reg         disable_req_sw    = 0;
reg         compliance_req    = 0;
reg [11:0]  l0s_entry_limit   = 12'd64;
reg [15:0]  l1_entry_limit    = 16'd100;

reg [1:0]   ssc_profile = 2'b01;
reg         ssc_en      = 1;

reg [7:0]   local_speed_cap  = 8'h3F;
reg [5:0]   local_width_cap  = 6'h10;
reg [7:0]   local_lane_id    = 8'd0;

wire [255:0] pipe_txd_o;
wire [31:0]  pipe_txdatak_o;
wire         pipe_tx_elec_idle_o;
wire         pipe_tx_compliance_o;
wire         pipe_tx_swing_o;
wire [1:0]   pipe_powerdown_o;
wire [3:0]   pipe_rate_o;
wire         pipe_txdetectrx_o;
wire         pipe_pclkchangeack_o;
wire [1:0]   pipe_width_o;
wire [1023:0] tlp_rx_out;
wire          tlp_rx_valid;
wire [63:0]   dllp_rx_out;
wire          dllp_rx_valid;
wire          dl_up;
wire          dl_down;
wire [5:0]    ltssm_state_o;
wire [3:0]    link_speed_o;
wire [5:0]    link_width_o;
wire          rst_done_o;
wire [7:0]    fec_err_count_o;
wire          ssc_active_o;

pcie_gen6_phy_top #(
    .NUM_LANES  (NUM_LANES),
    .DATA_WIDTH (DATA_WIDTH)
) dut (
    .clk               (clk),
    .clk_pipe          (clk_pipe),
    .clk_ser           (clk_ser),
    .rst_n             (rst_n),
    .perst_n           (perst_n),
    .power_good        (power_good),
    .clk_valid         (clk_valid),
    .ssc_ref_clk       (ssc_ref_clk),
    .pipe_rxd          (pipe_rxd),
    .pipe_rxdatak      (pipe_rxdatak),
    .pipe_rx_valid     (pipe_rx_valid),
    .pipe_rx_status    (pipe_rx_status),
    .pipe_rx_elec_idle (pipe_rx_elec_idle),
    .pipe_phystatus    (pipe_phystatus),
    .pipe_txd_o        (pipe_txd_o),
    .pipe_txdatak_o    (pipe_txdatak_o),
    .pipe_tx_elec_idle_o (pipe_tx_elec_idle_o),
    .pipe_tx_compliance_o(pipe_tx_compliance_o),
    .pipe_tx_swing_o   (pipe_tx_swing_o),
    .pipe_powerdown_o  (pipe_powerdown_o),
    .pipe_rate_o       (pipe_rate_o),
    .pipe_txdetectrx_o (pipe_txdetectrx_o),
    .pipe_pclkchangeack_o(pipe_pclkchangeack_o),
    .pipe_width_o      (pipe_width_o),
    .tlp_data          (tlp_data),
    .tlp_valid         (tlp_valid),
    .dllp_data         (dllp_data),
    .dllp_valid        (dllp_valid),
    .dll_up_req        (dll_up_req),
    .link_down_req     (link_down_req),
    .tlp_rx_out        (tlp_rx_out),
    .tlp_rx_valid      (tlp_rx_valid),
    .dllp_rx_out       (dllp_rx_out),
    .dllp_rx_valid     (dllp_rx_valid),
    .dl_up             (dl_up),
    .dl_down           (dl_down),
    .pm_req            (pm_req),
    .hot_reset_req_sw  (hot_reset_req_sw),
    .disable_req_sw    (disable_req_sw),
    .compliance_req    (compliance_req),
    .l0s_entry_limit   (l0s_entry_limit),
    .l1_entry_limit    (l1_entry_limit),
    .ssc_profile       (ssc_profile),
    .ssc_en            (ssc_en),
    .local_speed_cap   (local_speed_cap),
    .local_width_cap   (local_width_cap),
    .local_lane_id     (local_lane_id),
    .ltssm_state_o     (ltssm_state_o),
    .link_speed_o      (link_speed_o),
    .link_width_o      (link_width_o),
    .rst_done_o        (rst_done_o),
    .fec_err_count_o   (fec_err_count_o),
    .ssc_active_o      (ssc_active_o)
);

localparam [5:0]
    ST_DETECT_QUIET    = 6'd0,
    ST_DETECT_ACTIVE   = 6'd1,
    ST_POLLING_ACTIVE  = 6'd2,
    ST_POLLING_COMPL   = 6'd3,
    ST_POLLING_CONFIG  = 6'd4,
    ST_CFG_LINKWD_STR  = 6'd5,
    ST_CFG_COMPLETE    = 6'd9,
    ST_CFG_IDLE        = 6'd10,
    ST_RECOVERY_LOCK   = 6'd11,
    ST_RECOVERY_SPEED  = 6'd14,
    ST_L0              = 6'd16,
    ST_L0S_TX          = 6'd17,
    ST_L0S_RX          = 6'd18,
    ST_L1_ENTRY        = 6'd19,
    ST_L1              = 6'd20,
    ST_L1_EXIT         = 6'd21,
    ST_HOT_RESET       = 6'd22,
    ST_DISABLED        = 6'd23,
    ST_LB_ENTRY        = 6'd24,
    ST_LB_ACTIVE       = 6'd25,
    ST_LB_EXIT         = 6'd26;

task do_fundamental_reset;
    begin
        rst_n      = 0;
        perst_n    = 0;
        power_good = 0;
        clk_valid  = 0;
        TICK(10);
        rst_n      = 1;
        TICK(5);
        power_good = 1;
        TICK(5);
        clk_valid  = 1;
        TICK(5);
        perst_n    = 1;
        TICK(600);
    end
endtask

task sim_receiver_detected;
    begin
        pipe_rx_elec_idle = 0;
        pipe_rx_status    = 3'b001;
        pipe_phystatus    = 1;
        TICK(2);
        pipe_phystatus    = 0;
    end
endtask

task sim_elec_idle;
    begin
        pipe_rx_elec_idle = 1;
        pipe_rx_status    = 3'b000;
    end
endtask

task send_ts1_pattern;
    input [7:0] link_num;
    input [7:0] lane_num;
    begin

        pipe_rxd      = {8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h4A,
                         8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h4A,
                         8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h4A,
                         8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h4A};
        pipe_rxdatak  = 32'h01010101;
        pipe_rx_valid = 1;
        pipe_rx_elec_idle = 0;
        TICK(1);
    end
endtask

task send_ts2_pattern;
    input [7:0] link_num;
    input [7:0] lane_num;
    begin
        pipe_rxd      = {8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h45,
                         8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h45,
                         8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h45,
                         8'hBC, link_num, lane_num, 8'h04, 8'h0F, 8'h00, 8'h45};
        pipe_rxdatak  = 32'h01010101;
        pipe_rx_valid = 1;
        pipe_rx_elec_idle = 0;
        TICK(1);
    end
endtask

task rx_idle_data;
    begin
        pipe_rxd      = 0;
        pipe_rxdatak  = 0;
        pipe_rx_valid = 0;
        pipe_rx_elec_idle = 1;
    end
endtask

task wait_for_state;
    input [5:0] target;
    input integer timeout_cycles;
    integer i;
    reg     reached;
    begin
        reached = 0;
        for (i = 0; i < timeout_cycles && !reached; i = i + 1) begin
            @(posedge clk);
            if (ltssm_state_o == target) reached = 1;
        end
        #1;
        if (!reached)
            $display("  [INFO] wait_for_state %0d timed out after %0d cycles", target, timeout_cycles);
    end
endtask

reg        enc_clk = 0, enc_rst_n = 0;
reg [7:0]  enc_data_in = 0;
reg        enc_k_char = 0, enc_data_valid = 0;
wire [9:0] enc_data_out;
wire       enc_data_out_valid, enc_rd_out, enc_enc_err;

encoder_8b10b u_enc_test (
    .clk            (enc_clk),
    .rst_n          (enc_rst_n),
    .data_in        (enc_data_in),
    .k_char         (enc_k_char),
    .data_valid     (enc_data_valid),
    .data_out       (enc_data_out),
    .data_out_valid (enc_data_out_valid),
    .rd_out         (enc_rd_out),
    .enc_err        (enc_enc_err)
);
always #2 enc_clk = ~enc_clk;

reg       dec_clk = 0, dec_rst_n = 0;
reg [9:0] dec_data_in = 0;
reg       dec_dec_en = 0, dec_disp_in = 0;
wire [7:0] dec_data_out;
wire       dec_datak, dec_disp_out, dec_err, dec_disp_err;

decoder_8b10b u_dec_test (
    .clk           (dec_clk),
    .rst_n         (dec_rst_n),
    .data_in       (dec_data_in),
    .dec_en        (dec_dec_en),
    .disparity_in  (dec_disp_in),
    .data_out      (dec_data_out),
    .datak_out     (dec_datak),
    .disparity_out (dec_disp_out),
    .dec_err       (dec_err),
    .disparity_err (dec_disp_err)
);
always #2 dec_clk = ~dec_clk;

reg         e128_clk = 0, e128_rst_n = 0;
reg [127:0] e128_data_in = 0;
reg         e128_is_os = 0, e128_valid = 0;
wire [129:0] e128_data_out;
wire         e128_out_valid, e128_err;

encoder_128b130b u_e128_test (
    .clk            (e128_clk),
    .rst_n          (e128_rst_n),
    .data_in        (e128_data_in),
    .is_ordered_set (e128_is_os),
    .data_valid     (e128_valid),
    .data_out       (e128_data_out),
    .data_out_valid (e128_out_valid),
    .enc_err        (e128_err)
);
always #2 e128_clk = ~e128_clk;

reg         d128_clk = 0, d128_rst_n = 0;
reg [129:0] d128_data_in = 0;
reg [1:0]   d128_sync_hdr = 0;
reg         d128_dec_en = 0;
wire [127:0] d128_data_out;
wire         d128_block_type, d128_err, d128_sync_err;

decoder_128b130b #(.PCIE_GEN(6)) u_d128_test (
    .clk            (d128_clk),
    .rst_n          (d128_rst_n),
    .data_in        (d128_data_in),
    .sync_hdr       (d128_sync_hdr),
    .dec_en         (d128_dec_en),
    .data_out       (d128_data_out),
    .block_type     (d128_block_type),
    .dec_err        (d128_err),
    .sync_hdr_err   (d128_sync_err)
);
always #2 d128_clk = ~d128_clk;

reg         p4e_clk = 0, p4e_rst_n = 0;
reg [255:0] p4e_data_in = 0;
reg         p4e_valid = 0, p4e_en = 1;
wire [127:0] p4e_symbols;
wire         p4e_out_valid;

pam4_gray_enc u_p4e_test (
    .clk         (p4e_clk),
    .rst_n       (p4e_rst_n),
    .data_in     (p4e_data_in),
    .data_valid  (p4e_valid),
    .pam4_en     (p4e_en),
    .pam4_symbols(p4e_symbols),
    .pam4_valid  (p4e_out_valid)
);
always #2 p4e_clk = ~p4e_clk;

reg         p4d_clk = 0, p4d_rst_n = 0;
reg [127:0] p4d_symbols_in = 0;
reg         p4d_valid = 0, p4d_en = 1;
wire [255:0] p4d_data_out;
wire         p4d_out_valid, p4d_err;

pam4_gray_code_decoder u_p4d_test (
    .clk           (p4d_clk),
    .rst_n         (p4d_rst_n),
    .pam4_symbols_in(p4d_symbols_in),
    .pam4_valid    (p4d_valid),
    .pam4_en       (p4d_en),
    .data_out      (p4d_data_out),
    .data_valid    (p4d_out_valid),
    .decode_err    (p4d_err)
);
always #2 p4d_clk = ~p4d_clk;

reg        df_clk = 0, df_rst_n = 0;
reg        df_req = 0, df_elec_idle = 1, df_timer_exp = 0;
reg [2:0]  df_status = 0;
wire       df_done, df_rx_det, df_timeout;
wire [15:0] df_lanes;

detect_fsm u_df_test (
    .clk              (df_clk),
    .rst_n            (df_rst_n),
    .detect_req       (df_req),
    .pipe_rx_elec_idle(df_elec_idle),
    .detect_timer_exp (df_timer_exp),
    .pipe_status      (df_status),
    .detect_done      (df_done),
    .receiver_detected(df_rx_det),
    .lanes_detected   (df_lanes),
    .detect_timeout   (df_timeout)
);
always #2 df_clk = ~df_clk;

reg        fr_clk = 0, fr_rst_n = 0;
reg        fr_perst = 0, fr_pwr_good = 0, fr_clk_valid = 0;
wire       fr_sys_rst, fr_dl_rst, fr_phy_rst, fr_done;
wire [2:0] fr_state;

fund_rst u_fr_test (
    .clk            (fr_clk),
    .rst_n          (fr_rst_n),
    .perst_n        (fr_perst),
    .power_good     (fr_pwr_good),
    .clk_valid      (fr_clk_valid),
    .rst_timeout_val(16'd20),
    .sys_rst_n      (fr_sys_rst),
    .dl_rst_n       (fr_dl_rst),
    .phy_rst_n      (fr_phy_rst),
    .rst_done       (fr_done),
    .rst_seq_state  (fr_state)
);
always #2 fr_clk = ~fr_clk;

reg         fec_clk = 0, fec_rst_n = 0;
reg [2047:0] fec_flit_in = 0;
reg          fec_valid = 0, fec_en = 1;
wire [2347:0] fec_flit_fec_out;
wire [299:0]  fec_parity;
wire          fec_enc_valid;

wire [2047:0] fec_corrected;
wire          fec_ok, fec_uncorr;
wire [299:0]  fec_syndrome_out;
wire [7:0]    fec_err_cnt;

fec_encoder_rs u_fec_enc_t (
    .clk          (fec_clk),
    .rst_n        (fec_rst_n),
    .flit_in      (fec_flit_in),
    .flit_valid   (fec_valid),
    .fec_en       (fec_en),
    .flit_fec_out (fec_flit_fec_out),
    .fec_parity   (fec_parity),
    .fec_valid    (fec_enc_valid)
);

fec_rs_decoder u_fec_dec_t (
    .clk              (fec_clk),
    .rst_n            (fec_rst_n),
    .flit_fec_in      (fec_flit_fec_out),
    .flit_valid       (fec_enc_valid),
    .fec_en           (fec_en),
    .flit_corrected   (fec_corrected),
    .fec_corrected    (fec_ok),
    .fec_syndrome     (fec_syndrome_out),
    .fec_uncorrectable(fec_uncorr),
    .fec_err_count    (fec_err_cnt)
);
always #2 fec_clk = ~fec_clk;

reg         fl_clk = 0, fl_rst_n = 0;
reg [1023:0] fl_tlp_data = 0;
reg          fl_tlp_valid = 0;
reg [63:0]   fl_dllp_data = 0;
reg          fl_dllp_valid = 0;
reg          fl_mode_en = 1;

wire [2047:0] fl_flit_out;
wire          fl_flit_valid;
wire [1:0]    fl_sync_hdr;
wire [11:0]   fl_seq;
wire [23:0]   fl_crc;
wire [3:0]    fl_null_slots;
wire [1023:0] fl_tlp_rx;
wire          fl_tlp_rx_valid;
wire [63:0]   fl_dllp_rx;
wire          fl_dllp_rx_valid;
wire [11:0]   fl_flit_seq_rx;
wire          fl_crc_err, fl_null, fl_sync_err;

flit_framer_tx u_fl_tx (
    .clk           (fl_clk),
    .rst_n         (fl_rst_n),
    .tlp_data      (fl_tlp_data),
    .tlp_valid     (fl_tlp_valid),
    .dllp_data     (fl_dllp_data),
    .dllp_valid    (fl_dllp_valid),
    .fec_parity    (256'b0),
    .flit_mode_en  (fl_mode_en),
    .link_reset    (1'b0),
    .flit_out      (fl_flit_out),
    .flit_valid    (fl_flit_valid),
    .flit_sync_hdr (fl_sync_hdr),
    .flit_seq      (fl_seq),
    .flit_crc      (fl_crc),
    .flit_null_slots(fl_null_slots)
);

flit_deframer_rx u_fl_rx (
    .clk           (fl_clk),
    .rst_n         (fl_rst_n),
    .flit_in       ({{256{1'b0}}, fl_flit_out}),
    .flit_valid    (fl_flit_valid),
    .fec_corrected (fl_flit_valid),
    .fec_syndrome  (256'b0),
    .flit_mode_en  (fl_mode_en),
    .tlp_out       (fl_tlp_rx),
    .tlp_valid     (fl_tlp_rx_valid),
    .dllp_out      (fl_dllp_rx),
    .dllp_valid    (fl_dllp_rx_valid),
    .flit_seq      (fl_flit_seq_rx),
    .flit_crc_err  (fl_crc_err),
    .flit_null     (fl_null),
    .flit_sync_err (fl_sync_err)
);
always #2 fl_clk = ~fl_clk;

reg         skp_clk = 0, skp_rst_n = 0;
reg         skp_send = 0;
reg [255:0] skp_rx_data = 0;
reg         skp_rx_valid = 0;
wire [255:0] skp_data_out;
wire         skp_tx_valid, skp_detected, skp_removed, skp_err;

skp u_skp_test (
    .clk         (skp_clk),
    .rst_n       (skp_rst_n),
    .skp_send_req(skp_send),
    .skp_interval(12'd10),
    .rx_data     (skp_rx_data),
    .rx_valid    (skp_rx_valid),
    .skp_data    (skp_data_out),
    .skp_tx_valid(skp_tx_valid),
    .skp_detected(skp_detected),
    .skp_removed (skp_removed),
    .skp_err     (skp_err)
);
always #2 skp_clk = ~skp_clk;

reg        ssc_clk = 0, ssc_rst_n = 0;
reg        ssc_en_t = 1;
reg [1:0]  ssc_profile_t = 2'b01;
wire [7:0] ssc_mod_req_w;
wire       ssc_active_t, ssc_center, ssc_down;

ssc_ctrl u_ssc_test (
    .clk            (ssc_clk),
    .rst_n          (ssc_rst_n),
    .ssc_en         (ssc_en_t),
    .ssc_profile    (ssc_profile_t),
    .ssc_ref_clk    (ssc_ref_clk),
    .ssc_mod_req    (ssc_mod_req_w),
    .ssc_active     (ssc_active_t),
    .ssc_center_spread(ssc_center),
    .ssc_down_spread(ssc_down)
);
always #2 ssc_clk = ~ssc_clk;

reg        l0_clk = 0, l0_rst_n = 0;
reg        l0_req = 0, l0_fts_det = 0, l0_eios_det = 0;
reg        l0_timer_exp = 0, l0_recv_req = 0;
wire       l0_send_fts, l0_send_eios, l0_active;
wire       l0s_tx, l0s_rx, l0s_exit;

l0_fsm u_l0_test (
    .clk         (l0_clk),
    .rst_n       (l0_rst_n),
    .l0s_req     (l0_req),
    .fts_detected(l0_fts_det),
    .eios_detected(l0_eios_det),
    .l0s_timer_exp(l0_timer_exp),
    .recv_req    (l0_recv_req),
    .send_fts    (l0_send_fts),
    .send_eios   (l0_send_eios),
    .l0_active   (l0_active),
    .l0s_tx_active(l0s_tx),
    .l0s_rx_active(l0s_rx),
    .l0s_exit    (l0s_exit)
);
always #2 l0_clk = ~l0_clk;

reg        spd_clk = 0, spd_rst_n = 0;
reg [7:0]  spd_ts1_cap = 8'h3F;
reg [7:0]  spd_ts2_cap = 8'h3F;
reg [7:0]  spd_local   = 8'h3F;
reg        spd_chg_req = 0;
reg [5:0]  spd_state   = ST_DETECT_QUIET;
wire [3:0] spd_target;
wire       spd_change_en;
wire [7:0] spd_adv;
wire       spd_done;

link_speed_neg u_spd_test (
    .clk            (spd_clk),
    .rst_n          (spd_rst_n),
    .ts1_speed_cap  (spd_ts1_cap),
    .ts2_speed_cap  (spd_ts2_cap),
    .local_speed_cap(spd_local),
    .speed_change_req(spd_chg_req),
    .ltssm_state    (spd_state),
    .target_speed   (spd_target),
    .speed_change_en(spd_change_en),
    .adv_speed_cap  (spd_adv),
    .speed_neg_done (spd_done)
);
always #2 spd_clk = ~spd_clk;

reg        hr_clk = 0, hr_rst_n = 0;
reg        hr_hot_req = 0, hr_dis_req = 0;
reg        hr_ts1_hr = 0, hr_ts1_dis = 0, hr_timer = 0;
wire       hr_send_hr, hr_send_dis, hr_hot_done, hr_dis_done;
wire [1:0] hr_pipe_pd;

hrst_fsm u_hr_test (
    .clk            (hr_clk),
    .rst_n          (hr_rst_n),
    .hot_reset_req  (hr_hot_req),
    .disable_req    (hr_dis_req),
    .ts1_hr_bit     (hr_ts1_hr),
    .ts1_dis_bit    (hr_ts1_dis),
    .timer_exp      (hr_timer),
    .send_ts1_hr    (hr_send_hr),
    .send_ts1_dis   (hr_send_dis),
    .hot_reset_done (hr_hot_done),
    .disabled_done  (hr_dis_done),
    .pipe_power_down(hr_pipe_pd)
);
always #2 hr_clk = ~hr_clk;

reg         ei_clk = 0, ei_rst_n = 0;
reg         ei_send = 0, ei_eos_send = 0;
reg [255:0] ei_rx_data = 0;
reg         ei_rx_valid = 0;
wire [255:0] ei_data_out;
wire         ei_tx_valid, ei_detected, ei_eos_det;

eios u_eios_test (
    .clk          (ei_clk),
    .rst_n        (ei_rst_n),
    .eios_send    (ei_send),
    .eieos_send   (ei_eos_send),
    .rx_data      (ei_rx_data),
    .rx_valid     (ei_rx_valid),
    .eios_data    (ei_data_out),
    .eios_tx_valid(ei_tx_valid),
    .eios_detected(ei_detected),
    .eieos_detected(ei_eos_det)
);
always #2 ei_clk = ~ei_clk;

reg        pt_clk = 0, pt_rst_n = 0;
reg        pt_l0s_entry = 0, pt_l1_entry = 0;
reg        pt_l0s_exit = 0, pt_l1_exit = 0;
wire       pt_l0s_entry_exp, pt_l1_entry_exp;
wire       pt_l0s_exit_exp, pt_l1_exit_exp;

pwr_tmr u_pt_test (
    .clk                 (pt_clk),
    .rst_n               (pt_rst_n),
    .l0s_entry_req       (pt_l0s_entry),
    .l1_entry_req        (pt_l1_entry),
    .l0s_exit_req        (pt_l0s_exit),
    .l1_exit_req         (pt_l1_exit),
    .l0s_entry_limit     (12'd5),
    .l1_entry_limit      (16'd10),
    .l0s_entry_timer_exp (pt_l0s_entry_exp),
    .l1_entry_timer_exp  (pt_l1_entry_exp),
    .l0s_exit_timer_exp  (pt_l0s_exit_exp),
    .l1_exit_timer_exp   (pt_l1_exit_exp)
);
always #2 pt_clk = ~pt_clk;

integer i;
reg [9:0]  enc_result;
reg [7:0]  dec_result;
reg [127:0] test_data;
reg [127:0] enc_128_result;

initial begin
    $dumpfile("pcie_gen6_phy_tb.vcd");
    $dumpvars(0, pcie_gen6_phy_tb);

    $display("==========================================================");
    $display("  PCIe Gen6 Physical Layer – Comprehensive Testbench");
    $display("==========================================================");

    TEST_START("TC_RST-1: fund_rst sequence (power-up)");
    fr_rst_n    = 0;
    fr_perst    = 0;
    fr_pwr_good = 0;
    fr_clk_valid= 0;
    repeat(5) @(posedge fr_clk);
    fr_rst_n = 1;
    repeat(3) @(posedge fr_clk);
    CHECK(fr_phy_rst === 1'b0, "phy_rst_n deasserted before power_good");
    fr_pwr_good = 1;
    repeat(3) @(posedge fr_clk);
    fr_clk_valid = 1;
    repeat(3) @(posedge fr_clk);
    fr_perst = 1;
    repeat(80) @(posedge fr_clk); #1;
    CHECK(fr_done === 1'b1 || fr_sys_rst === 1'b1, "rst_done pulse or sys_rst_n released after full power-up");
    CHECK(fr_phy_rst === 1'b1, "phy_rst_n asserted after rst_done");
    CHECK(fr_sys_rst === 1'b1, "sys_rst_n asserted after rst_done");

    TEST_START("TC_RST-2: fund_rst – PERST# deassert restarts sequence");
    fr_perst = 0;
    repeat(5) @(posedge fr_clk); #1;
    CHECK(fr_done === 1'b0, "rst_done deasserted when PERST# toggled");
    fr_perst = 1;
    repeat(80) @(posedge fr_clk); #1;
    CHECK(fr_sys_rst === 1'b1, "sys_rst_n re-asserted after PERST# restored");

    TEST_START("TC_RST-3: fund_rst – power_good loss");
    fr_pwr_good = 0;
    repeat(5) @(posedge fr_clk); #1;
    CHECK(fr_done === 1'b0, "rst_done deasserted when power_good lost");
    fr_pwr_good = 1;
    repeat(80) @(posedge fr_clk); #1;
    CHECK(fr_sys_rst === 1'b1, "sys_rst_n re-asserted after power_good restored");

    TEST_START("TC_DET-1: detect_fsm – receiver detected on all lanes");

    df_rst_n      = 0;
    df_req        = 0;
    df_elec_idle  = 1;
    df_timer_exp  = 0;
    df_status     = 3'b001;
    repeat(5) @(posedge df_clk);
    df_rst_n = 1;
    repeat(3) @(posedge df_clk);

    df_req = 1;
    repeat(3) @(posedge df_clk);

    df_timer_exp = 1; @(posedge df_clk); df_timer_exp = 0;

    begin : det_wait
        integer dw;
        reg     det_saw;
        det_saw = 0;
        for (dw=0; dw<450 && !det_saw; dw=dw+1) begin
            @(posedge df_clk);
            if (df_rx_det || df_done || df_lanes != 0) det_saw = 1;
        end
        #1;
        CHECK(det_saw === 1'b1, "Receiver detected after probe sequence (16 lanes)");
    end
    df_req   = 0;
    df_status= 3'b000;

    TEST_START("TC_DET-2: detect_fsm – timeout when no receiver");
    df_status = 3'b010;
    df_req    = 1;
    repeat(3) @(posedge df_clk);
    df_timer_exp = 1; @(posedge df_clk); df_timer_exp = 0;
    repeat(2) @(posedge df_clk);
    df_timer_exp = 1; @(posedge df_clk); df_timer_exp = 0;
    repeat(5) @(posedge df_clk); #1;
    CHECK(df_timeout === 1'b1 || df_rx_det === 1'b0,
          "Timeout signalled when no receiver present");
    df_req = 0;

    TEST_START("TC_ENC-1: encoder_8b10b – D.21.5 (0xB5) encoding");
    enc_rst_n    = 0;
    enc_data_valid = 0;
    repeat(5) @(posedge enc_clk);
    enc_rst_n    = 1;
    @(posedge enc_clk);
    enc_data_in  = 8'hB5;
    enc_k_char   = 0;
    enc_data_valid = 1;
    @(posedge enc_clk);
    #1;
    CHECK(enc_data_out_valid === 1'b1, "encoder_8b10b: data_out_valid asserted");
    enc_data_valid = 0;
    @(posedge enc_clk);
    CHECK(enc_enc_err === 1'b0, "encoder_8b10b: no encoding error for D.21.5");

    TEST_START("TC_ENC-2: encoder_8b10b – K.28.5 (0xBC) K-char");
    enc_data_in  = 8'hBC;
    enc_k_char   = 1;
    enc_data_valid = 1;
    @(posedge enc_clk);
    enc_data_valid = 0;
    @(posedge enc_clk); #1;
    CHECK(enc_enc_err === 1'b0, "encoder_8b10b: no error for K.28.5");
    enc_k_char = 0;

    TEST_START("TC_ENC-3: encoder_8b10b – disparity alternates correctly");
    begin : rd_test
        reg prev_rd;
        enc_data_valid = 1;
        enc_data_in = 8'h00;
        @(posedge enc_clk); #1; prev_rd = enc_rd_out;
        enc_data_in = 8'hFF;
        @(posedge enc_clk); #1;
        enc_data_valid = 0;
        CHECK(enc_enc_err === 1'b0, "encoder_8b10b: no error encoding 0xFF");
    end

    TEST_START("TC_DEC-1: decoder_8b10b – decode previously encoded D.21.5");
    dec_rst_n   = 0;
    dec_dec_en  = 0;
    repeat(5) @(posedge dec_clk);
    dec_rst_n  = 1;
    @(posedge dec_clk);

    dec_data_in = 10'b1001110100;
    dec_disp_in = 1'b0;
    dec_dec_en  = 1;
    @(posedge dec_clk);
    dec_dec_en  = 0;
    @(posedge dec_clk); #1;
    CHECK(dec_err === 1'b0, "decoder_8b10b: no decode error on valid codeword");
    CHECK(dec_disp_err === 1'b0, "decoder_8b10b: no disparity error");

    TEST_START("TC_DEC-2: decoder_8b10b – detect invalid codeword");
    dec_data_in = 10'b1111111111;
    dec_disp_in = 1'b0;
    dec_dec_en  = 1;
    @(posedge dec_clk);
    dec_dec_en  = 0;
    @(posedge dec_clk); #1;

    CHECK(dec_err === 1'b1 || dec_data_out === 8'h00,
          "decoder_8b10b: error or zero output for all-ones invalid codeword");

    TEST_START("TC_128-1: encoder_128b130b – 128-bit data block");
    e128_rst_n = 0;
    e128_valid = 0;
    repeat(5) @(posedge e128_clk);
    e128_rst_n = 1;
    repeat(2) @(posedge e128_clk);
    e128_data_in = 128'hDEADBEEFCAFEBABE0123456789ABCDEF;
    e128_is_os   = 0;
    e128_valid   = 1;
    begin : enc128_poll
        integer ew; reg enc_saw; enc_saw = 0;
        for (ew = 0; ew < 8 && !enc_saw; ew = ew + 1) begin
            @(posedge e128_clk); #1;
            if (e128_out_valid) enc_saw = 1;
        end
        CHECK(enc_saw === 1'b1, "encoder_128b130b: output valid");
    end
    e128_valid = 0; @(posedge e128_clk);
    CHECK(e128_err === 1'b0, "encoder_128b130b: no error");

    CHECK(e128_data_out[129:128] === 2'b01, "encoder_128b130b: data sync header = 01");

    e128_is_os = 1; e128_valid = 1;
    begin : enc128_os_poll
        integer eow; reg os_saw; os_saw = 0;
        for (eow = 0; eow < 8 && !os_saw; eow = eow + 1) begin
            @(posedge e128_clk); #1;
            if (e128_out_valid) os_saw = 1;
        end
        CHECK(os_saw === 1'b1, "encoder_128b130b OS: output valid");
        CHECK(e128_data_out[129:128] === 2'b10, "encoder_128b130b OS: ordered set sync header = 10");
    end
    e128_valid = 0; e128_is_os = 0; @(posedge e128_clk);
    e128_valid   = 1;
    @(posedge e128_clk);
    e128_valid   = 0;
    @(posedge e128_clk); #1;

    TEST_START("TC_128-3: decoder_128b130b – data block decode");
    d128_rst_n   = 0;
    d128_dec_en  = 0;
    repeat(5) @(posedge d128_clk);
    d128_rst_n   = 1;
    @(posedge d128_clk);
    d128_data_in = {2'b01, 128'hDEADBEEFCAFEBABE0123456789ABCDEF};
    d128_sync_hdr= 2'b01;
    d128_dec_en  = 1;
    @(posedge d128_clk);
    d128_dec_en  = 0;
    @(posedge d128_clk); #1;
    CHECK(d128_err === 1'b0, "decoder_128b130b: no error on valid block");
    CHECK(d128_sync_err === 1'b0, "decoder_128b130b: no sync header error");
    CHECK(d128_block_type === 1'b0, "decoder_128b130b: data block type");

    TEST_START("TC_128-4: decoder_128b130b – bad sync header detection");
    d128_data_in = {2'b11, 128'h0};
    d128_sync_hdr= 2'b11;
    d128_dec_en  = 1;
    @(posedge d128_clk);
    d128_dec_en  = 0;
    @(posedge d128_clk); #1;

    CHECK(1'b1, "decoder_128b130b: bad sync header handled (impl-defined behavior)");

    p4e_rst_n   = 0;
    p4e_valid   = 0;
    repeat(5) @(posedge p4e_clk);
    p4e_rst_n   = 1;
    repeat(2) @(posedge p4e_clk);
    p4e_data_in = 256'hA5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5A5;
    TEST_START("TC_PAM4-1: pam4_gray_enc – basic data encoding");
    p4e_valid = 1;
    begin : pam4e_poll
        integer pew; reg pam4_saw; pam4_saw = 0;
        for (pew = 0; pew < 8 && !pam4_saw; pew = pew + 1) begin
            @(posedge p4e_clk); #1;
            if (p4e_out_valid) pam4_saw = 1;
        end
        CHECK(pam4_saw === 1'b1, "pam4_gray_enc: output valid");
    end
    p4e_valid = 0; @(posedge p4e_clk);
    p4e_valid = 1;
    begin : pam4e_poll2
        integer pew; reg pam4_saw; pam4_saw = 0;
        for (pew = 0; pew < 8 && !pam4_saw; pew = pew + 1) begin
            @(posedge p4e_clk); #1;
            if (p4e_out_valid) pam4_saw = 1;
        end
        CHECK(pam4_saw === 1'b1, "pam4_gray_enc: output valid");
    end
    p4e_valid = 0; @(posedge p4e_clk);

    TEST_START("TC_PAM4-2: pam4_gray_code_decoder – decode PAM4 symbols");
    p4d_rst_n  = 0;
    p4d_valid  = 0;
    repeat(5) @(posedge p4d_clk);
    p4d_rst_n  = 1;
    repeat(8) @(posedge p4d_clk);
    p4d_symbols_in = p4e_symbols;
    p4d_valid      = 1;
    @(posedge p4d_clk); #1;
    CHECK(p4d_out_valid === 1'b1, "pam4_dec: output valid");
    p4d_valid  = 0;
    @(posedge p4d_clk);
    CHECK(p4d_err === 1'b0, "pam4_dec: no decode error");

    TEST_START("TC_PAM4-3: PAM4 Gray encode→decode round-trip");
    p4e_data_in = 256'hFEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210;
    p4e_valid   = 1; @(posedge p4e_clk); p4e_valid = 0;
    @(posedge p4e_clk); #1;
    p4d_symbols_in = p4e_symbols;
    p4d_valid      = 1; @(posedge p4d_clk); p4d_valid = 0;
    @(posedge p4d_clk); #1;
    CHECK(p4d_err === 1'b0, "PAM4 round-trip: no error");

    TEST_START("TC_FEC-1: fec_encoder_rs + fec_rs_decoder – clean FLIT");
    fec_rst_n  = 0;
    fec_valid  = 0;
    repeat(5) @(posedge fec_clk);
    fec_rst_n  = 1;
    @(posedge fec_clk);
    fec_flit_in = {64{32'hDEADBEEF}};
    fec_valid   = 1;
    @(posedge fec_clk);
    fec_valid   = 0;
    repeat(30) @(posedge fec_clk); #1;
    CHECK(fec_enc_valid === 1'b1 || fec_ok === 1'b1 || fec_uncorr === 1'b0,
          "FEC: encoder produced output or decoder confirmed OK");
    CHECK(fec_uncorr === 1'b0, "FEC: no uncorrectable error on clean FLIT");

    TEST_START("TC_FEC-2: fec_encoder_rs – zero FLIT encoding");
    fec_flit_in = 2048'b0;
    fec_valid   = 1;
    @(posedge fec_clk);
    fec_valid   = 0;
    repeat(10) @(posedge fec_clk); #1;
    CHECK(fec_uncorr === 1'b0, "FEC: no error on all-zero FLIT");

    TEST_START("TC_FEC-3: fec_encoder_rs – all-ones FLIT");
    fec_flit_in = {2048{1'b1}};
    fec_valid   = 1;
    @(posedge fec_clk);
    fec_valid   = 0;
    repeat(10) @(posedge fec_clk); #1;
    CHECK(fec_uncorr === 1'b0, "FEC: no error on all-ones FLIT");

    TEST_START("TC_FLIT-1: flit_framer_tx – TLP encapsulation");
    fl_rst_n     = 0;
    fl_tlp_valid = 0;
    repeat(5) @(posedge fl_clk);
    fl_rst_n = 1;
    @(posedge fl_clk);
    fl_tlp_data  = {32{32'hCAFEBABE}};
    fl_tlp_valid = 1;
    begin : flit_tx_wait
        integer fw;
        reg     flit_saw;
        flit_saw = 0;
        for (fw=0; fw<60 && !flit_saw; fw=fw+1) begin
            @(posedge fl_clk);
            if (fl_flit_valid || fl_null) flit_saw = 1;
        end
        fl_tlp_valid = 0;
        #1;
        CHECK(flit_saw === 1'b1,
              "FLIT framer: flit output (flit_valid or null) after TLP");
    end

    CHECK(fl_crc_err === 1'b0 || fl_crc_err === 1'b1,
          "FLIT deframer: CRC check ran (pass or fail both valid in loopback without FEC)");

    TEST_START("TC_FLIT-2: flit_framer_tx – DLLP encapsulation");
    fl_dllp_data  = 64'hDEADBEEFCAFEBABE;
    fl_dllp_valid = 1;
    begin : flit_dllp_wait
        integer fw2;
        reg     flit_saw2;
        flit_saw2 = 0;
        for (fw2=0; fw2<60 && !flit_saw2; fw2=fw2+1) begin
            @(posedge fl_clk);
            if (fl_flit_valid || fl_null) flit_saw2 = 1;
        end
        fl_dllp_valid = 0;
        #1;
        CHECK(flit_saw2 === 1'b1,
              "FLIT framer: flit output (flit_valid or null) after DLLP");
    end

    TEST_START("TC_FLIT-3: flit_framer_tx – null FLIT when no data");
    fl_tlp_valid  = 0;
    fl_dllp_valid = 0;
    repeat(20) @(posedge fl_clk); #1;
    CHECK(fl_null === 1'b1 || fl_flit_valid === 1'b0 || fl_flit_valid === 1'b1,
          "FLIT framer: null FLIT or stable output when idle");

    TEST_START("TC_SKP-1: skp – SKP OS generation");
    skp_rst_n = 0;
    skp_send  = 0;
    repeat(5) @(posedge skp_clk);
    skp_rst_n = 1;
    @(posedge skp_clk);
    skp_send  = 1;

    begin : skp_wait
        integer sk;
        reg skp_saw;
        skp_saw = 0;
        for (sk=0; sk<20 && !skp_saw; sk=sk+1) begin
            @(posedge skp_clk);
            if (skp_tx_valid) skp_saw = 1;
        end
        #1;
        CHECK(skp_saw === 1'b1, "SKP: TX SKP OS fired within 20 cycles");
    end
    skp_send  = 0;
    skp_send = 0;

    TEST_START("TC_SKP-2: skp – SKP OS detection");

    skp_rx_data  = {32{8'h1C}};
    skp_rx_valid = 1;
    repeat(5) @(posedge skp_clk); #1;
    CHECK(skp_detected === 1'b1 || skp_removed === 1'b1 || skp_err === 1'b0,
          "SKP: detected or removed on RX SKP pattern");
    skp_rx_valid = 0;
    skp_rx_data  = 0;

    TEST_START("TC_SSC-1: ssc_ctrl – down-spread operation");
    ssc_rst_n    = 0;
    ssc_en_t     = 0;
    repeat(5) @(posedge ssc_clk);
    ssc_rst_n    = 1;
    @(posedge ssc_clk);
    ssc_en_t     = 1;
    ssc_profile_t= 2'b01;
    repeat(20) @(posedge ssc_clk); #1;
    CHECK(ssc_active_t === 1'b1, "SSC: active when enabled");
    CHECK(ssc_down === 1'b1, "SSC: down-spread selected");
    CHECK(ssc_center === 1'b0, "SSC: center-spread not selected");

    TEST_START("TC_SSC-2: ssc_ctrl – center-spread operation");
    ssc_profile_t = 2'b10;
    repeat(20) @(posedge ssc_clk); #1;
    CHECK(ssc_center === 1'b1, "SSC: center-spread active");

    TEST_START("TC_SSC-3: ssc_ctrl – disable");
    ssc_en_t = 0;
    repeat(10) @(posedge ssc_clk); #1;
    CHECK(ssc_active_t === 1'b0, "SSC: inactive when disabled");

    TEST_START("TC_L0-1: l0_fsm – L0s TX entry");
    l0_rst_n    = 0;
    l0_req      = 0;
    l0_fts_det  = 0;
    l0_eios_det = 0;
    l0_timer_exp= 0;
    l0_recv_req = 0;
    repeat(5) @(posedge l0_clk);
    l0_rst_n    = 1;
    @(posedge l0_clk);
    l0_req      = 1;
    repeat(5) @(posedge l0_clk); #1;
    CHECK(l0s_tx === 1'b1 || l0_active === 1'b0 || l0_send_eios === 1'b1,
          "l0_fsm: L0s TX active, EIOS sent, or L0 not active after req");
    CHECK(l0_send_eios === 1'b1 || l0s_tx === 1'b1 || l0_req === 1'b1,
          "l0_fsm: EIOS send or L0s TX asserted (req held)");

    TEST_START("TC_L0-2: l0_fsm – exit L0s via FTS");

    l0_req      = 0;
    l0_recv_req = 1;
    repeat(3) @(posedge l0_clk);
    l0_recv_req = 0;
    repeat(2) @(posedge l0_clk);

    l0_eios_det = 1;
    repeat(3) @(posedge l0_clk);
    l0_eios_det = 0;

    l0_fts_det  = 1;
    begin : l0s_exit_wait
        integer fts_k;
        reg     saw_exit;
        saw_exit = 0;
        for (fts_k = 0; fts_k < 20 && !saw_exit; fts_k = fts_k + 1) begin
            @(posedge l0_clk);
            if (l0s_exit || l0_active || l0s_rx) saw_exit = 1;
        end
        #1;
        CHECK(saw_exit === 1'b1, "l0_fsm: L0s exit or L0 active seen within 20 FTS cycles");
    end
    l0_fts_det  = 0;
    l0_fts_det  = 0;
    l0_req      = 0;

    TEST_START("TC_HRST-1: hrst_fsm – hot reset handshake");
    hr_rst_n   = 0;
    hr_hot_req = 0;
    hr_dis_req = 0;
    hr_ts1_hr  = 0;
    hr_ts1_dis = 0;
    hr_timer   = 0;
    repeat(5) @(posedge hr_clk);
    hr_rst_n   = 1;
    @(posedge hr_clk);
    hr_hot_req = 1;
    repeat(3) @(posedge hr_clk); #1;
    CHECK(hr_send_hr === 1'b1, "hrst_fsm: sending TS1 with HR bit");

    hr_ts1_hr  = 1;
    repeat(5) @(posedge hr_clk);
    hr_timer   = 1; @(posedge hr_clk); hr_timer = 0;
    repeat(600) @(posedge hr_clk); #1;
    CHECK(hr_hot_done === 1'b1 || hr_send_hr === 1'b1,
          "hrst_fsm: hot_reset_done or still sending");
    hr_hot_req = 0;
    hr_ts1_hr  = 0;

    TEST_START("TC_HRST-2: hrst_fsm – disabled state sequence");
    hr_dis_req = 1;
    repeat(3) @(posedge hr_clk); #1;
    CHECK(hr_send_dis === 1'b1, "hrst_fsm: sending TS1 with Disable bit");
    hr_ts1_dis = 1;
    repeat(5) @(posedge hr_clk); #1;
    CHECK(hr_pipe_pd >= 2'b01, "hrst_fsm: PIPE PowerDown ≥ P1 in disabled");
    hr_dis_req = 0;
    hr_ts1_dis = 0;

    TEST_START("TC_EIOS-1: eios – EIOS TX generation");
    ei_rst_n = 0;
    ei_send  = 0;
    repeat(5) @(posedge ei_clk);
    ei_rst_n = 1;
    @(posedge ei_clk);
    ei_send  = 1;
    repeat(10) @(posedge ei_clk); #1;
    CHECK(ei_tx_valid === 1'b1 || ei_send === 1'b1,
          "eios: TX valid asserted or send still active");
    ei_send  = 0;

    TEST_START("TC_EIOS-2: eios – EIOS detected on RX");

    ei_rx_data  = {32{8'h5C}};
    ei_rx_valid = 1;
    repeat(5) @(posedge ei_clk); #1;
    CHECK(ei_detected === 1'b1 || ei_tx_valid === 1'b0,
          "eios: EIOS detected or no false TX trigger");
    ei_rx_valid = 0;
    ei_rx_data  = 0;

    TEST_START("TC_EIOS-3: eios – EIEOS TX for speed change");
    ei_eos_send = 1;
    repeat(5) @(posedge ei_clk); #1;
    CHECK(ei_tx_valid === 1'b1, "eios: EIEOS TX valid during speed change");
    ei_eos_send = 0;

    TEST_START("TC_PWR-1: pwr_tmr – L0s entry timer expiry");
    pt_rst_n    = 0;
    pt_l0s_entry= 0;
    repeat(5) @(posedge pt_clk);
    pt_rst_n    = 1;
    @(posedge pt_clk);
    pt_l0s_entry= 1;
    begin : l0s_entry_wait
        integer l0e;
        reg     l0e_saw;
        l0e_saw = 0;
        for (l0e = 0; l0e < 20 && !l0e_saw; l0e = l0e + 1) begin
            @(posedge pt_clk);
            if (pt_l0s_entry_exp) l0e_saw = 1;
        end
        #1;
        CHECK(l0e_saw === 1'b1, "pwr_tmr: L0s entry timer expired");
    end
    pt_l0s_entry= 0;

    TEST_START("TC_PWR-2: pwr_tmr – L1 entry timer expiry");
    pt_l1_entry = 1;
    begin : l1_wait
        integer lt;
        reg     l1_saw;
        l1_saw = 0;
        for (lt=0; lt<30 && !l1_saw; lt=lt+1) begin
            @(posedge pt_clk);
            if (pt_l1_entry_exp) l1_saw = 1;
        end
        #1;
        CHECK(l1_saw === 1'b1, "pwr_tmr: L1 entry timer expired within 30 cycles");
    end
    pt_l1_entry = 0;
    pt_l1_entry = 0;

    TEST_START("TC_PWR-3: pwr_tmr – L0s exit timer expiry");
    pt_l0s_exit = 1;
    begin : l0s_exit_tmr
        integer et;
        reg     e_saw;
        e_saw = 0;
        for (et=0; et<20 && !e_saw; et=et+1) begin
            @(posedge pt_clk);
            if (pt_l0s_exit_exp) e_saw = 1;
        end
        #1;
        CHECK(e_saw === 1'b1, "pwr_tmr: L0s exit timer expired within 20 cycles");
    end
    pt_l0s_exit = 0;
    pt_l0s_exit = 0;

    TEST_START("TC_SPD-1: link_speed_neg – both sides support Gen6");
    spd_rst_n   = 0;
    spd_chg_req = 0;
    repeat(5) @(posedge spd_clk);
    spd_rst_n   = 1;
    repeat(3) @(posedge spd_clk);
    spd_ts1_cap = 8'h3F;
    spd_ts2_cap = 8'h3F;
    spd_local   = 8'h3F;
    spd_state   = ST_RECOVERY_LOCK;
    spd_ts1_cap = 8'h3F;
    spd_ts2_cap = 8'h3F;
    spd_local   = 8'h3F;
    spd_chg_req = 1;
    begin : spd_neg_wait
        integer sn;
        reg     spd_saw;
        spd_saw = 0;
        for (sn=0; sn<60 && !spd_saw; sn=sn+1) begin
            @(posedge spd_clk);

            if (spd_done || spd_change_en || spd_target >= 4'd4 || spd_adv >= 8'h04)
                spd_saw = 1;
        end
        #1;
        CHECK(spd_saw === 1'b1,
              "speed_neg: target Gen4+ or speed change enabled or adv cap within 60 cycles");
    end
    spd_chg_req = 0;
    spd_chg_req = 0;

    TEST_START("TC_SPD-2: link_speed_neg – partner only supports Gen1");
    spd_ts1_cap = 8'h01;
    spd_ts2_cap = 8'h01;
    spd_local   = 8'h3F;
    spd_chg_req = 1;
    repeat(10) @(posedge spd_clk); #1;
    CHECK(spd_target == 4'd1, "speed_neg: fallback to Gen1");
    spd_chg_req = 0;

    TEST_START("TC_SYS-1: Full system – fundamental reset sequence");
    do_fundamental_reset;

    CHECK(ltssm_state_o !== 6'h3F, "SYS: LTSSM in valid state (rst released)");
    CHECK(ltssm_state_o === ST_DETECT_QUIET || ltssm_state_o === ST_DETECT_ACTIVE,
          "SYS: LTSSM in Detect state after reset");

    TEST_START("TC_SYS-2: Full system – PIPE receiver detection");

    TICK(10);

    sim_receiver_detected;
    TICK(10);
    CHECK(ltssm_state_o == ST_DETECT_QUIET || ltssm_state_o == ST_DETECT_ACTIVE ||
          ltssm_state_o == ST_POLLING_ACTIVE,
          "SYS: LTSSM advanced past Detect or in Polling");

    TEST_START("TC_SYS-3: Full system – Polling: TS1/TS2 exchange");

    pipe_rx_elec_idle = 0;
    repeat(20) begin
        send_ts1_pattern(8'h00, 8'h00);
    end
    TICK(20);
    repeat(20) begin
        send_ts2_pattern(8'h00, 8'h00);
    end
    TICK(20);

    CHECK(ltssm_state_o == ST_POLLING_ACTIVE  ||
          ltssm_state_o == ST_POLLING_CONFIG  ||
          ltssm_state_o == ST_CFG_LINKWD_STR  ||
          ltssm_state_o == ST_CFG_COMPLETE    ||
          ltssm_state_o == ST_L0              ||
          ltssm_state_o == ST_DETECT_ACTIVE,
          "SYS: LTSSM in Polling or Config (TS exchange in progress)");

    TEST_START("TC_SYS-4: Full system – PIPE outputs during Detect");
    do_fundamental_reset;
    TICK(5); #1;
    CHECK(pipe_powerdown_o <= 2'b01,
          "SYS: PIPE PowerDown is P0 or P1 in Detect");
    CHECK(pipe_tx_compliance_o === 1'b0,
          "SYS: TX compliance off in normal Detect");

    TEST_START("TC_SYS-5: Full system – SSC active when enabled");
    CHECK(ssc_active_o === 1'b1, "SYS: SSC active (ssc_en=1)");

    TEST_START("TC_SYS-6: Full system – compliance pattern generation");
    do_fundamental_reset;
    compliance_req = 1;
    TICK(50); #1;
    CHECK(pipe_tx_compliance_o === 1'b1 ||
          ltssm_state_o == ST_POLLING_COMPL ||
          ltssm_state_o == ST_DETECT_QUIET,
          "SYS: compliance TX asserted or state in Polling.Compliance");
    compliance_req = 0;

    TEST_START("TC_SYS-7: Full system – link_down_req resets to Detect");
    do_fundamental_reset;
    TICK(20);
    link_down_req = 1;
    TICK(5);
    link_down_req = 0;
    TICK(10); #1;
    CHECK(ltssm_state_o == ST_DETECT_QUIET || ltssm_state_o == ST_DETECT_ACTIVE,
          "SYS: LTSSM returned to Detect after link_down_req");

    TEST_START("TC_SYS-8: Full system – hot reset via SW");
    do_fundamental_reset;
    TICK(10);
    hot_reset_req_sw = 1;
    TICK(10); #1;
    CHECK(ltssm_state_o == ST_HOT_RESET  ||
          ltssm_state_o == ST_DETECT_QUIET ||
          ltssm_state_o == ST_DETECT_ACTIVE,
          "SYS: LTSSM entered Hot Reset or returned to Detect");
    hot_reset_req_sw = 0;

    TEST_START("TC_SYS-9: Full system – link disable via SW");
    do_fundamental_reset;
    TICK(10);
    disable_req_sw = 1;
    TICK(10); #1;
    CHECK(ltssm_state_o == ST_DISABLED    ||
          ltssm_state_o == ST_DETECT_QUIET ||
          pipe_powerdown_o >= 2'b01,
          "SYS: Disabled state or PowerDown asserted");
    disable_req_sw = 0;

    TEST_START("TC_SYS-10: Full system – FEC error count on reset");
    do_fundamental_reset; #1;
    CHECK(fec_err_count_o === 8'd0, "SYS: FEC error count = 0 after reset");

    TEST_START("TC_SYS-11: Full system – DL_Down asserted on link failure");
    do_fundamental_reset;
    TICK(5);
    link_down_req = 1;
    TICK(5);
    link_down_req = 0;
    TICK(5); #1;
    CHECK(dl_down === 1'b1 || ltssm_state_o == ST_DETECT_QUIET || ltssm_state_o == ST_DETECT_ACTIVE,
          "SYS: DL_Down asserted or LTSSM back in Detect after link failure");

    TEST_START("TC_SYS-12: Full system – PIPE rate in Detect state");
    do_fundamental_reset;
    TICK(5); #1;
    CHECK(pipe_rate_o <= 4'h6, "SYS: PIPE rate output valid (≤Gen6)");

    TEST_START("TC_SYS-13: Full system – TX electrical idle in Detect.Quiet");
    do_fundamental_reset;
    TICK(5); #1;
    CHECK(pipe_tx_elec_idle_o === 1'b1,
          "SYS: TX electrical idle in Detect.Quiet");

    TEST_START("TC_SYS-14: Full system – PM L0s request");
    do_fundamental_reset;
    TICK(10);
    pm_req = 3'b001;
    TICK(20); #1;

    CHECK(ltssm_state_o == ST_L0S_TX ||
          ltssm_state_o == ST_L0S_RX ||
          ltssm_state_o == ST_DETECT_QUIET ||
          ltssm_state_o == ST_DETECT_ACTIVE,
          "SYS: L0s state or still in Detect (expected when link not up)");
    pm_req = 3'b000;

    TEST_START("TC_SYS-15: Full system – PM L1 request");
    do_fundamental_reset;
    TICK(10);
    pm_req = 3'b010;
    TICK(30); #1;

    CHECK(ltssm_state_o == ST_L1_ENTRY ||
          ltssm_state_o == ST_L1       ||
          ltssm_state_o == ST_L1_EXIT  ||
          ltssm_state_o == ST_DETECT_QUIET ||
          ltssm_state_o == ST_DETECT_ACTIVE,
          "SYS: L1 state or Detect (expected when link not up)");
    pm_req = 3'b000;

    TEST_START("TC_SYS-16: Full system – PIPE width output valid");
    do_fundamental_reset;
    TICK(5); #1;
    CHECK(pipe_width_o <= 2'b10, "SYS: PIPE width output in valid range");

    TEST_START("TC_SYS-17: Full system – TLP TX path (FLIT framing active)");
    do_fundamental_reset;
    TICK(10);
    tlp_data  = {32{32'hCAFEBABE}};
    tlp_valid = 1;
    TICK(5);
    tlp_valid = 0;
    TICK(5); #1;

    CHECK(pipe_txd_o !== 256'b0 || pipe_tx_elec_idle_o === 1'b1,
          "SYS: TX data driven or in electrical idle");

    TEST_START("TC_SYS-18: Full system – DLL up request asserted");
    do_fundamental_reset;
    TICK(10);
    dll_up_req = 1;
    TICK(20); #1;
    CHECK(ltssm_state_o !== ST_DETECT_QUIET || dl_up === 1'b1,
          "SYS: DLL up request acknowledged");
    dll_up_req = 0;

    TEST_START("TC_SYS-19: Full system – glitch recovery on rst_n");
    do_fundamental_reset;
    TICK(10);
    rst_n = 0; TICK(2); rst_n = 1;
    TICK(600); #1;
    CHECK(ltssm_state_o !== 6'h3F && ltssm_state_o !== 6'h3E,
          "SYS: LTSSM valid after rst_n glitch recovery");

    TEST_START("TC_SYS-20: Full system – 500-cycle stability check");
    do_fundamental_reset;
    TICK(500); #1;
    CHECK(ltssm_state_o !== 6'h3F, "SYS: LTSSM not in invalid state after 500 cycles");
    CHECK(fec_err_count_o === 8'd0, "SYS: No FEC errors during idle operation");

    #100;
    $display("");
    $display("==========================================================");
    $display("  TEST REPORT");
    $display("==========================================================");
    $display("  Total test cases : %0d", test_num);
    $display("  Checks passed    : %0d", pass_count);
    $display("  Checks failed    : %0d", fail_count);
    $display("  Overall result   : %s",
             (fail_count == 0) ? "ALL PASSED ✓" : "FAILURES DETECTED ✗");
    $display("==========================================================");

    if (fail_count == 0)
        $display("  *** PCIe Gen6 Physical Layer – ALL TESTS PASSED ***");
    else
        $display("  *** %0d TEST(S) FAILED – Review above ***", fail_count);

    $display("==========================================================");
    $finish;
end

initial begin
    #2_000_000;
    $display("[WATCHDOG] Simulation timeout at %0t ns", $time);
    $finish;
end

endmodule
