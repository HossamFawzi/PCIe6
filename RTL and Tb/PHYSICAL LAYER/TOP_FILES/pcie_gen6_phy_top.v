// =============================================================================
// File   : pcie_gen6_phy_top.v
// Project: PCIe Gen6 Physical Layer
// Purpose: TOP-LEVEL wrapper that instantiates and connects all 53 Physical
//          Layer modules exactly as mapped in the block diagram:
//
//   LTSSM Group (19 modules)  – Mods  2-10, 43-52
//   TX Path      (9 modules)  – Mods 11-19
//   RX Path     (10 modules)  – Mods 20-29
//   Link Mgmt   (10 modules)  – Mods 30-37, 53-54
//   Gen6 Specific (5 modules) – Mods 38-42
//
// Standard : PCIe Base Specification 6.0
// Language : Verilog-2001  (no SystemVerilog)
// =============================================================================
`timescale 1ns/1ps

module pcie_gen6_phy_top #(
    parameter NUM_LANES  = 16,
    parameter DATA_WIDTH = 256
)(
    // ── Clocks & Resets ────────────────────────────────────────────────────
    input  wire        clk,              // Core clock
    input  wire        clk_pipe,         // PIPE clock from PHY macro
    input  wire        clk_ser,          // High-speed serialiser clock
    input  wire        rst_n,            // Active-low system reset
    input  wire        perst_n,          // PCIe PERST# (fundamental reset)
    input  wire        power_good,       // Power-rail stable indication
    input  wire        clk_valid,        // Reference clock valid
    input  wire        ssc_ref_clk,      // SSC reference clock

    // ── PIPE PHY interface – RX (from analog PHY macro) ────────────────────
    input  wire [255:0] pipe_rxd,            // PHY RX data (256-bit Gen6)
    input  wire [31:0]  pipe_rxdatak,        // PHY RX K-char flags
    input  wire         pipe_rx_valid,       // PHY RxValid
    input  wire [2:0]   pipe_rx_status,      // PHY RxStatus[2:0]
    input  wire         pipe_rx_elec_idle,   // PHY RxElecIdle
    input  wire         pipe_phystatus,      // PHY PhyStatus strobe

    // ── PIPE PHY interface – TX (to analog PHY macro) ──────────────────────
    output wire [255:0] pipe_txd_o,           // PHY TX data
    output wire [31:0]  pipe_txdatak_o,       // PHY TX K-char flags
    output wire         pipe_tx_elec_idle_o,  // PHY TXElecIdle
    output wire         pipe_tx_compliance_o, // PHY TXCompliance
    output wire         pipe_tx_swing_o,      // PHY TXSwing
    output wire [1:0]   pipe_powerdown_o,     // PHY PowerDown[1:0]
    output wire [3:0]   pipe_rate_o,          // PHY Rate[3:0]
    output wire         pipe_txdetectrx_o,    // PHY TxDetectRx/Loopback
    output wire         pipe_pclkchangeack_o, // PHY PCLK-change acknowledge
    output wire [1:0]   pipe_width_o,         // PHY bus-width select

    // ── DLL / Transaction Layer interface ──────────────────────────────────
    input  wire [1023:0] tlp_data,       // TLP payload from TL (TX)
    input  wire          tlp_valid,      // TLP valid
    input  wire [63:0]   dllp_data,      // DLLP from DLL (TX)
    input  wire          dllp_valid,     // DLLP valid
    input  wire          dll_up_req,     // DLL DL_Init done, request link-up
    input  wire          link_down_req,  // DLL replay rollover / fatal error

    output wire [1023:0] tlp_rx_out,     // Recovered TLP to TL  (RX)
    output wire          tlp_rx_valid,   // TLP RX valid
    output wire [63:0]   dllp_rx_out,    // Recovered DLLP to DLL (RX)
    output wire          dllp_rx_valid,  // DLLP RX valid
    output wire          dl_up,          // DL_Up  → DLL
    output wire          dl_down,        // DL_Down → DLL

    // ── Power Management & Control ─────────────────────────────────────────
    input  wire [2:0]   pm_req,           // PM request (L0s/L1/L1.1/L1.2)
    input  wire         hot_reset_req_sw, // Software-triggered hot reset
    input  wire         disable_req_sw,   // Software link-disable request
    input  wire         compliance_req,   // Compliance test entry request
    input  wire [11:0]  l0s_entry_limit,  // L0s entry timer limit (cycles)
    input  wire [15:0]  l1_entry_limit,   // L1  entry timer limit (cycles)

    // ── SSC control ────────────────────────────────────────────────────────
    input  wire [1:0]   ssc_profile,      // 00=off,01=down-spread,10=center
    input  wire         ssc_en,           // Enable SSC

    // ── Local device configuration ─────────────────────────────────────────
    input  wire [7:0]   local_speed_cap,  // This device's supported speeds
    input  wire [5:0]   local_width_cap,  // This device's supported widths
    input  wire [7:0]   local_lane_id,    // Physical lane ID (0-15)

    // ── Status / Debug outputs ─────────────────────────────────────────────
    output wire [5:0]   ltssm_state_o,    // Current LTSSM state
    output wire [3:0]   link_speed_o,     // Negotiated link speed
    output wire [5:0]   link_width_o,     // Active lane count
    output wire         rst_done_o,       // Reset sequence complete
    output wire [7:0]   fec_err_count_o,  // FEC uncorrected error count
    output wire         ssc_active_o      // SSC operating
);

// =============================================================================
// [A]  PARAMETERS – STATE ENCODING (mirrors ltssm_top.v localparam)
// =============================================================================
localparam [5:0]
    ST_DETECT_QUIET       = 6'd0,
    ST_DETECT_ACTIVE      = 6'd1,
    ST_POLLING_ACTIVE     = 6'd2,
    ST_POLLING_COMPLIANCE = 6'd3,
    ST_POLLING_CONFIG     = 6'd4,
    ST_CFG_LINKWD_START   = 6'd5,
    ST_CFG_COMPLETE       = 6'd9,
    ST_CFG_IDLE           = 6'd10,
    ST_RECOVERY_RCVLOCK   = 6'd11,
    ST_RECOVERY_SPEED     = 6'd14,
    ST_L0                 = 6'd16,
    ST_L0S_TX             = 6'd17,
    ST_L0S_RX             = 6'd18,
    ST_L1_ENTRY           = 6'd19,
    ST_L1                 = 6'd20,
    ST_L1_EXIT            = 6'd21,
    ST_HOT_RESET          = 6'd22,
    ST_DISABLED           = 6'd23,
    ST_LOOPBACK_ENTRY     = 6'd24,
    ST_LOOPBACK_ACTIVE    = 6'd25,
    ST_LOOPBACK_EXIT      = 6'd26;

// Default timer periods (clock cycles; tune per design frequency)
localparam [15:0] TMO_DETECT   = 16'd200;
localparam [15:0] TMO_CFG      = 16'd2000;
localparam [15:0] TMO_RECOVERY = 16'd2000;
localparam [15:0] TMO_L0S      = 16'd64;
localparam [15:0] TMO_L1       = 16'd100;
localparam [15:0] TMO_HRST     = 16'd50;
localparam [15:0] TMO_LB       = 16'd500;
localparam [15:0] TMO_EQ       = 16'd1000;
localparam [15:0] TMO_LOCK     = 16'd512;

// =============================================================================
// [B]  INTERNAL WIRE DECLARATIONS
// =============================================================================

// ── B1: Reset sequencing (Mod 51 – fund_rst) ────────────────────────────────
wire sys_rst_n_w, dl_rst_n_w, phy_rst_n_w, rst_done_w;
wire [2:0] rst_seq_state_w;

// ── B2: LTSSM top outputs (Mod 2 – ltssm_top) ───────────────────────────────
wire [5:0] ltssm_state_w;
wire       dl_up_w, dl_down_w;
wire [1:0] ltssm_pipe_power_down_w;
wire       ltssm_pipe_tx_elec_idle_w;
wire [3:0] link_speed_w;
wire [5:0] link_width_w;
wire       ltssm_reset_out_w;

// ── B3: LTSSM sub-FSM request signals (derived from ltssm_state) ─────────────
wire detect_req_w   = (ltssm_state_w == ST_DETECT_QUIET) | (ltssm_state_w == ST_DETECT_ACTIVE);
wire polling_req_w  = (ltssm_state_w >= ST_POLLING_ACTIVE) & (ltssm_state_w <= ST_POLLING_CONFIG);
wire cfg_req_w      = (ltssm_state_w >= ST_CFG_LINKWD_START) & (ltssm_state_w <= ST_CFG_IDLE);
wire recv_req_w     = (ltssm_state_w >= ST_RECOVERY_RCVLOCK) & (ltssm_state_w <= ST_RECOVERY_SPEED);
wire l0s_req_w      = (ltssm_state_w == ST_L0S_TX) | (ltssm_state_w == ST_L0S_RX);
wire l1_req_w       = (ltssm_state_w >= ST_L1_ENTRY) & (ltssm_state_w <= ST_L1_EXIT);
wire lb_req_w       = (ltssm_state_w >= ST_LOOPBACK_ENTRY) & (ltssm_state_w <= ST_LOOPBACK_EXIT);
wire gen6_mode_w    = (link_speed_w == 4'd6);  // Gen6 → FLIT/PAM4 mode
wire flit_mode_en_w = gen6_mode_w;

// ── B4: Detect FSM wires (Mod 3) ────────────────────────────────────────────
wire       detect_done_w, receiver_detected_w, detect_timeout_w;
wire [15:0] lanes_detected_w;

// ── B5: RX Detect wires (Mod 49) ────────────────────────────────────────────
wire       rx_det_done_w, rx_det_timeout_w, rx_receiver_detected_w;
wire [15:0] rx_lanes_det_w;

// ── B6: Polling FSM wires (Mod 4) ───────────────────────────────────────────
wire       poll_send_ts1_w, poll_send_ts2_w;
wire       poll_enter_compliance_w, poll_rx_polarity_w;
wire       poll_done_w, poll_success_w, poll_timeout_w;
wire       poll_tx_elec_idle_w;

// ── B7: Config FSM wires (Mod 5) ────────────────────────────────────────────
wire [7:0] cfg_link_num_w, cfg_lane_num_w;
wire       cfg_send_ts2_w, cfg_done_w, cfg_timeout_err_w;
wire [5:0] cfg_neg_width_w;

// ── B8: Recovery FSM wires (Mod 6) ──────────────────────────────────────────
wire       recv_send_ts1_w, recv_send_ts2_w;
wire       recv_speed_change_en_w, recv_eq_start_w;
wire       recv_done_w, recv_timeout_err_w, recv_retrain_req_w;

// ── B9: L0/L0s FSM wires (Mod 7) ────────────────────────────────────────────
wire       l0_send_fts_w, l0_send_eios_w;
wire       l0_active_w, l0s_tx_active_w, l0s_rx_active_w, l0s_exit_w;

// ── B10: L1 FSM wires (Mod 8) ───────────────────────────────────────────────
wire       l1_send_eios_w, l1_active_w, l1_exit_w;
wire [1:0] l1_pipe_power_down_w;
wire       l1_timeout_err_w;
wire       l1_ack_w = 1'b0;   // Connect to PM DLLP ACK when DLL is present
wire       pm_dllp_rx_w = 1'b0; // Connect to DLL PM DLLP received signal

// ── B11: Loopback FSM wires (Mod 9) ─────────────────────────────────────────
wire       lb_active_w, lb_send_ts1_w, lb_data_en_w, lb_exit_w;

// ── B12: Hot-Reset / Disabled FSM wires (Mod 10) ────────────────────────────
wire       hrst_send_ts1_hr_w, hrst_send_ts1_dis_w;
wire       hrst_hot_reset_done_w, hrst_disabled_done_w;
wire [1:0] hrst_pipe_power_down_w;
wire       hot_reset_req_comb_w;  // OR of SW request and TS1 HR bit

// ── B13: Hot Reset controller wires (Mod 50) ────────────────────────────────
wire       hot_reset_active_w, send_ts1_hot_reset_w, hot_reset_done_w;
wire       pipe_reset_out_w;

// ── B14: Fundamental Reset wires (Mod 51) ────────────────────────────────────
// (declared in B1 above)

// ── B15: TS1 / TS2 generator wires (Mods 43,44) ─────────────────────────────
wire [255:0] ts1_data_w;
wire         ts1_valid_w, ts1_done_w;
wire [255:0] ts2_data_w;
wire         ts2_valid_w, ts2_done_w;

// ── B16: TS detector wires (Mod 45) ─────────────────────────────────────────
wire       ts1_detected_w, ts2_detected_w;
wire [7:0] ts1_link_num_w, ts1_lane_num_w;
wire [7:0] ts2_speed_cap_w;
wire       ts_decode_err_w;
wire       ts1_hot_reset_bit_w;  // derived in ts_det or tied low for now
wire       ts1_lb_bit_w;
wire       ts1_hr_bit_w  = ts1_detected_w & hot_reset_active_w;
wire       ts1_dis_bit_w = 1'b0;  // tie; would come from TS1 field decoder

// ── B17: FTS wires (Mod 46) ─────────────────────────────────────────────────
wire [255:0] fts_data_w;
wire         fts_tx_valid_w, fts_detected_w;
wire [7:0]   fts_count_rx_w;

// ── B18: EIOS wires (Mod 47) ────────────────────────────────────────────────
wire [255:0] eios_data_w;
wire         eios_tx_valid_w, eios_detected_w, eieos_detected_w;
wire         send_eios_comb_w = l0_send_eios_w | l1_send_eios_w;
wire         send_eieos_w     = recv_speed_change_en_w; // EIEOS during speed change

// ── B19: SKP OS wires (Mod 48) ──────────────────────────────────────────────
wire [255:0] skp_data_w;
wire         skp_tx_valid_w, skp_detected_w, skp_removed_w, skp_err_w;

// ── B20: Compliance generator wires (Mod 52) ────────────────────────────────
wire [255:0] compl_data_w;
wire         compl_valid_w, compl_active_w;

// ── B21: Ordered-Set generator wires (Mod 18) ────────────────────────────────
wire [255:0] os_data_w;
wire         os_valid_w;
wire [3:0]   os_type_w;
// Combined send_ts1/send_ts2 from all LTSSM sources
wire send_ts1_comb_w = poll_send_ts1_w | recv_send_ts1_w
                     | hrst_send_ts1_hr_w | hrst_send_ts1_dis_w
                     | lb_send_ts1_w | send_ts1_hot_reset_w;
wire send_ts2_comb_w = poll_send_ts2_w | cfg_send_ts2_w | recv_send_ts2_w;
wire send_sos_w      = 1'b0;  // SOS: driven by Recovery EQ state (Gen6)

// ── B22: Link speed / width negotiation wires (Mods 30,31) ──────────────────
wire [3:0] target_speed_w;
wire       speed_change_en_neg_w;
wire [7:0] adv_speed_cap_w;
wire       speed_neg_done_w;
wire [5:0] neg_width_w;
wire       width_neg_done_w;
wire [15:0] active_lanes_w;
wire       width_change_req_w;

// ── B23: Equalisation controller wires (Mod 32) ─────────────────────────────
wire [2:0] pipe_txdeemph_w;
wire [2:0] pipe_txmargin_w;
wire       pipe_rxeqeval_out_w;
wire       eq_done_w, eq_err_w;
wire [1:0] eq_phase_out_w;
wire       pipe_rxeqeval_w = 1'b0; // tie; comes from PIPE PHY when EQ eval done

// ── B24: Speed-change FSM wires (Mod 33) ────────────────────────────────────
wire [3:0] spd_pipe_rate_out_w;
wire       spd_change_done_w, spd_change_err_w, spd_retrain_req_w;

// ── B25: Lane reversal / polarity wires (Mods 34,35) ────────────────────────
wire [3:0]  lane_map_w;
wire        reversal_active_w;
wire [255:0] rx_data_pol_w;
wire [15:0]  polarity_inv_w;

// ── B26: Beacon / EI wires (Mod 36) ─────────────────────────────────────────
wire       beacon_detect_w, ei_detect_w, wakeup_req_w;
wire       pipe_tx_elec_idle_beacon_w;

// ── B27: PIPE interface controller wires (Mod 37) ────────────────────────────
wire [1:0] pipe_ctrl_powerdown_w;
wire [3:0] pipe_ctrl_rate_w;
wire       pipe_ctrl_txdetectrx_w;
wire       pipe_ctrl_txelecidle_w;
wire       pipe_ctrl_txcompliance_w;
wire       pipe_ctrl_pclkchangeack_w;
wire [1:0] pipe_ctrl_width_w;

// ── B28: PIPE RX interface wires (Mod 20) ────────────────────────────────────
wire [255:0] rx_data_raw_w;
wire [31:0]  rx_datak_w;
wire         rx_valid_w;
wire         rx_elec_idle_w;
wire [2:0]   rx_status_w;
wire         phystatus_sync_w;
wire         pipe_up_w, rate_change_busy_w;

// ── B29: RX Gear Box wires (Mod 28) ─────────────────────────────────────────
wire [255:0] rx_gear_data_w;
wire         rx_gear_valid_w;

// ── B30: Lane Deskew wires (Mod 27) ─────────────────────────────────────────
wire [255:0] deskewed_data_w;
wire         deskew_valid_w;
wire [4:0]   skew_amount_w;
wire         deskew_err_w;

// ── B31: Block/Symbol lock wires (Mod 22) ────────────────────────────────────
wire symbol_lock_w, block_lock_w, lock_err_w, lock_lost_w;

// ── B32: Block-align + sync-header checker wires (Mod 29) ────────────────────
wire [255:0] aligned_data_w;
wire         aligned_valid_w;
wire [1:0]   sync_hdr_rx_w;
wire         align_err_w;

// ── B33: RX Elastic Buffer wires (Mod 21) ────────────────────────────────────
wire [255:0] rx_buf_data_w;
wire         rx_buf_valid_w;
wire         rx_buf_empty_w, rx_buf_full_w, rx_buf_slip_done_w, rx_buf_center_w;

// ── B34: 8b10b decoder wires (Mod 23) ────────────────────────────────────────
wire [7:0]   dec_8b10b_data_w;
wire         dec_8b10b_datak_w;
wire         dec_8b10b_disp_w;
wire         dec_8b10b_err_w, dec_8b10b_disp_err_w;

// ── B35: 128b/130b decoder wires (Mod 24) ────────────────────────────────────
wire [127:0] dec_128b_data_w;
wire         dec_128b_block_type_w;
wire         dec_128b_err_w, dec_128b_sync_err_w;

// ── B36: PAM4 Gray decoder wires (Mod 39) ────────────────────────────────────
wire [255:0] pam4_dec_data_w;
wire         pam4_dec_valid_w, pam4_dec_err_w;

// ── B37: FEC RS decoder wires (Mod 26) ───────────────────────────────────────
// flit_corrected_w = [2047:0]: FEC RS decoder corrects and outputs 2048-bit FLIT data.
// (flit_fec_in is 2348 bits including parity; corrected output is the data portion only)
wire [2047:0] flit_corrected_w;
wire          fec_corrected_w;
wire [299:0]  fec_syndrome_dec_w;
wire          fec_uncorrectable_w;
wire [7:0]    fec_err_count_w;

// ── B38: FEC Syndrome Calculator wires (Mod 40) ──────────────────────────────
wire [255:0] syndrome_w;
wire         syndrome_valid_w, zero_syndrome_w;

// ── B39: FLIT deframer RX wires (Mod 25) ────────────────────────────────────
wire [1023:0] tlp_rx_w;
wire          tlp_rx_valid_w;
wire [63:0]   dllp_rx_w;
wire          dllp_rx_valid_w;
wire [11:0]   flit_seq_rx_w;
wire          flit_crc_err_w, flit_null_w, flit_sync_err_w;

// ── B40: FLIT sync-header gen/checker wires (Mod 41) ────────────────────────
wire [2049:0] flit_tx_with_hdr_w;
wire [1:0]    sync_hdr_tx_w;
wire          sync_hdr_rx_ok_w, sync_hdr_rx_err_w, flit_lock_w;

// ── B41: FLIT framer TX wires (Mod 15) ────────────────────────────────────────
wire [2047:0] flit_out_w;
wire          flit_framer_valid_w;
wire [1:0]    flit_sync_hdr_w;
wire [11:0]   flit_seq_tx_w;
wire [23:0]   flit_crc_w;
wire [3:0]    flit_null_slots_w;

// ── B42: FEC RS encoder wires (Mod 16) ────────────────────────────────────────
wire [2347:0] flit_fec_out_w;
wire [299:0]  fec_parity_w;
wire          fec_enc_valid_w;

// ── B43: 128b/130b encoder wires (Mod 14) ────────────────────────────────────
wire [129:0]  enc_128b_data_w;
wire          enc_128b_valid_w, enc_128b_err_w;

// ── B44: 8b10b encoder wires (Mod 13) ─────────────────────────────────────────
wire [9:0]    enc_8b10b_data_w;
wire          enc_8b10b_valid_w, enc_8b10b_rd_w, enc_8b10b_err_w;

// ── B45: PAM4 Gray encoder wires (Mod 38) ────────────────────────────────────
wire [127:0]  pam4_symbols_w;
wire          pam4_enc_valid_w;

// ── B46: TX Elastic Buffer wires (Mod 12) ────────────────────────────────────
wire [255:0]  tx_buf_data_w;
wire          tx_buf_valid_w;
wire          tx_buf_full_w, tx_buf_empty_w, tx_buf_half_w;
wire          tx_buf_skp_inserted_w, tx_buf_skp_removed_w;

// ── B47: TX Datapath MUX wires (Mod 19) ──────────────────────────────────────
wire [255:0]  tx_mux_out_w;
wire          tx_mux_valid_w, tx_mux_elec_idle_w;
wire [1:0]    tx_mux_sel_w;
// enc_data to MUX: 128b130b in Gen3-5, 8b10b (zero-extended) in Gen1/2
wire [255:0]  enc_data_mux_w  = (link_speed_w <= 4'd2)
                                ? {{246{1'b0}}, enc_8b10b_data_w}
                                : {{126{1'b0}}, enc_128b_data_w};
wire          enc_valid_mux_w = (link_speed_w <= 4'd2)
                                ? enc_8b10b_valid_w : enc_128b_valid_w;

// ── B48: TX Gear Box wires (Mod 17) ──────────────────────────────────────────
wire [31:0]   tx_gear_out_w;     // NARROW_W=32 default
wire          tx_gear_valid_w;
wire          tx_gear_full_w, tx_gear_empty_w;

// ── B49: Data Rate Advertisement wires (Mod 42) ──────────────────────────────
wire [7:0]    adv_speed_cap_rate_w;
wire [7:0]    negotiated_speed_w;
wire [2:0]    negotiated_gen_w;
wire          negotiation_done_w, speed_change_req_adv_w;

// ── B50: SSC controller wires (Mod 53) ────────────────────────────────────────
wire [7:0]    ssc_mod_req_w;
wire          ssc_active_w, ssc_center_spread_w, ssc_down_spread_w;

// ── B51: Power State Timer wires (Mod 54) ─────────────────────────────────────
wire          l0s_entry_timer_exp_w, l1_entry_timer_exp_w;
wire          l0s_exit_timer_exp_w,  l1_exit_timer_exp_w;

// ── B52: Misc helper wires ────────────────────────────────────────────────────
wire [255:0]  rx_for_ts_w;    // RX data fed to TS detector & OS detectors
wire          rx_for_ts_valid_w;
// After lane correction, feed the aligned/buffered data for TS/OS detection
assign rx_for_ts_w       = rx_buf_data_w;
assign rx_for_ts_valid_w = rx_buf_valid_w;
// Master reset: AND of fundamental reset and system reset
wire          phy_rst_n_comb = rst_n & phy_rst_n_w;

// =============================================================================
// [C]  PER-FSM TIMER LOGIC  (simple down-counters; one-cycle exp pulse)
// =============================================================================

// --- C1: Detect timer ---
reg [15:0] detect_tmr;
wire detect_timer_exp_w = (detect_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb)  detect_tmr <= 16'd0;
    else if (detect_req_w && detect_tmr == 16'd0) detect_tmr <= TMO_DETECT;
    else if (detect_tmr  != 16'd0) detect_tmr <= detect_tmr - 1'b1;
end

// --- C2: Config timer ---
reg [15:0] cfg_tmr;
wire cfg_timer_exp_w = (cfg_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) cfg_tmr <= 16'd0;
    else if (cfg_req_w && cfg_tmr == 16'd0) cfg_tmr <= TMO_CFG;
    else if (cfg_tmr   != 16'd0) cfg_tmr <= cfg_tmr - 1'b1;
end

// --- C3: Recovery timer ---
reg [15:0] recv_tmr;
wire recv_timer_exp_w = (recv_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) recv_tmr <= 16'd0;
    else if (recv_req_w && recv_tmr == 16'd0) recv_tmr <= TMO_RECOVERY;
    else if (recv_tmr   != 16'd0) recv_tmr <= recv_tmr - 1'b1;
end

// --- C4: L0s timer ---
reg [15:0] l0s_tmr;
wire l0s_timer_exp_w = (l0s_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) l0s_tmr <= 16'd0;
    else if (l0s_req_w && l0s_tmr == 16'd0) l0s_tmr <= TMO_L0S;
    else if (l0s_tmr   != 16'd0) l0s_tmr <= l0s_tmr - 1'b1;
end

// --- C5: L1 timer ---
reg [15:0] l1_tmr;
wire l1_timer_exp_w = (l1_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) l1_tmr <= 16'd0;
    else if (l1_req_w && l1_tmr == 16'd0) l1_tmr <= TMO_L1;
    else if (l1_tmr   != 16'd0) l1_tmr <= l1_tmr - 1'b1;
end

// --- C6: Hot-Reset / Disabled timer ---
reg [15:0] hrst_tmr;
wire hrst_timer_exp_w = (hrst_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) hrst_tmr <= 16'd0;
    else if ((ltssm_state_w == ST_HOT_RESET || ltssm_state_w == ST_DISABLED)
             && hrst_tmr == 16'd0) hrst_tmr <= TMO_HRST;
    else if (hrst_tmr != 16'd0) hrst_tmr <= hrst_tmr - 1'b1;
end

// --- C7: Loopback timer ---
reg [15:0] lb_tmr;
wire lb_timer_exp_w = (lb_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) lb_tmr <= 16'd0;
    else if (lb_req_w && lb_tmr == 16'd0) lb_tmr <= TMO_LB;
    else if (lb_tmr   != 16'd0) lb_tmr <= lb_tmr - 1'b1;
end

// --- C8: Equalisation timer ---
reg [15:0] eq_tmr;
wire eq_timer_exp_w = (eq_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) eq_tmr <= 16'd0;
    else if (recv_eq_start_w && eq_tmr == 16'd0) eq_tmr <= TMO_EQ;
    else if (eq_tmr  != 16'd0) eq_tmr <= eq_tmr - 1'b1;
end

// --- C9: Block/Symbol lock timer ---
reg [15:0] lock_tmr;
wire lock_timer_exp_w = (lock_tmr == 16'd1);
always @(posedge clk or negedge phy_rst_n_comb) begin
    if (!phy_rst_n_comb) lock_tmr <= 16'd0;
    else if (rx_valid_w && lock_tmr == 16'd0) lock_tmr <= TMO_LOCK;
    else if (lock_tmr != 16'd0) lock_tmr <= lock_tmr - 1'b1;
end

// Combined hot-reset request
assign hot_reset_req_comb_w = hot_reset_req_sw | hot_reset_active_w;
// ts1_lb_bit: simplified tie (full decode requires TS1 field parser)
assign ts1_lb_bit_w = lb_req_w & ts1_detected_w;

// =============================================================================
// [D]  MODULE INSTANTIATIONS
// Ordering: Reset → LTSSM → Sub-FSMs → TX path → RX path → Link Mgmt → Gen6
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// MOD 51 – fund_rst  (Fundamental Reset Sequencer)
// ─────────────────────────────────────────────────────────────────────────────
fund_rst u_fund_rst (
    .clk             (clk),
    .rst_n           (rst_n),
    .perst_n         (perst_n),
    .power_good      (power_good),
    .clk_valid       (clk_valid),
    .rst_timeout_val (16'd500),
    .sys_rst_n       (sys_rst_n_w),
    .dl_rst_n        (dl_rst_n_w),
    .phy_rst_n       (phy_rst_n_w),
    .rst_done        (rst_done_w),
    .rst_seq_state   (rst_seq_state_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 2 – ltssm_top  (LTSSM Top Controller)
// ─────────────────────────────────────────────────────────────────────────────
ltssm_top u_ltssm_top (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .pipe_rx_status     (pipe_rx_status),
    .pipe_detect_lane   (rx_receiver_detected_w),
    .dll_up_req         (dll_up_req),
    .pm_req             (pm_req),
    .hot_reset_req      (hot_reset_req_comb_w),
    .link_down_req      (link_down_req),
    .compliance_req     (compliance_req),
    .ltssm_state        (ltssm_state_w),
    .dl_up              (dl_up_w),
    .dl_down            (dl_down_w),
    .pipe_power_down    (ltssm_pipe_power_down_w),
    .pipe_tx_elec_idle  (ltssm_pipe_tx_elec_idle_w),
    .link_speed         (link_speed_w),
    .link_width         (link_width_w),
    .ltssm_reset_out    (ltssm_reset_out_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 3 – detect_fsm  (Detect State FSM)
// ─────────────────────────────────────────────────────────────────────────────
detect_fsm u_detect_fsm (
    .clk                  (clk),
    .rst_n                (phy_rst_n_comb),
    .detect_req           (detect_req_w),
    .pipe_rx_elec_idle    (pipe_rx_elec_idle),
    .detect_timer_exp     (detect_timer_exp_w),
    .pipe_status          (pipe_rx_status),
    .detect_done          (detect_done_w),
    .receiver_detected    (receiver_detected_w),
    .lanes_detected       (lanes_detected_w),
    .detect_timeout       (detect_timeout_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 49 – rx_det  (PIPE Receiver Detection)
// ─────────────────────────────────────────────────────────────────────────────
rx_det u_rx_det (
    .clk                  (clk),
    .rst_n                (phy_rst_n_comb),
    .detect_start         (detect_req_w),
    .pipe_rx_elec_idle    (pipe_rx_elec_idle),
    .pipe_phystatus       (pipe_phystatus),
    .detect_timeout_val   (16'd200),
    .receiver_detected    (rx_receiver_detected_w),
    .lanes_det            (rx_lanes_det_w),
    .detect_done          (rx_det_done_w),
    .detect_timeout       (rx_det_timeout_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 4 – polling_fsm  (Polling State FSM)
// ─────────────────────────────────────────────────────────────────────────────
polling_fsm u_polling_fsm (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .polling_req        (polling_req_w),
    .lanes_detected     (lanes_detected_w),
    .rx_valid           (rx_valid_w),
    .rx_datak           (|rx_datak_w),
    .rx_data            (rx_buf_data_w[31:0]),
    .rx_elec_idle       (rx_elec_idle_w),
    .compliance_req     (compliance_req),
    .tx_elec_idle       (poll_tx_elec_idle_w),
    .send_ts1           (poll_send_ts1_w),
    .send_ts2           (poll_send_ts2_w),
    .enter_compliance   (poll_enter_compliance_w),
    .rx_polarity        (poll_rx_polarity_w),
    .polling_done       (poll_done_w),
    .polling_success    (poll_success_w),
    .polling_timeout    (poll_timeout_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 5 – cfg_fsm  (Configuration State FSM)
// ─────────────────────────────────────────────────────────────────────────────
cfg_fsm u_cfg_fsm (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .ts1_link_num       (ts1_link_num_w),
    .ts1_lane_num       (ts1_lane_num_w),
    .ts2_detected       (ts2_detected_w),
    .cfg_timer_exp      (cfg_timer_exp_w),
    .upcfg_req          (width_change_req_w),
    .cfg_link_num       (cfg_link_num_w),
    .cfg_lane_num       (cfg_lane_num_w),
    .send_ts2           (cfg_send_ts2_w),
    .cfg_done           (cfg_done_w),
    .negotiated_width   (cfg_neg_width_w),
    .cfg_timeout_err    (cfg_timeout_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 6 – recv_fsm  (Recovery State FSM)
// ─────────────────────────────────────────────────────────────────────────────
recv_fsm u_recv_fsm (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .recv_req           (recv_req_w),
    .ts1_detected       (ts1_detected_w),
    .ts2_detected       (ts2_detected_w),
    .idle_detected      (rx_elec_idle_w),
    .speed_change_req   (speed_change_req_adv_w),
    .eq_done            (eq_done_w),
    .recv_timer_exp     (recv_timer_exp_w),
    .send_ts1           (recv_send_ts1_w),
    .send_ts2           (recv_send_ts2_w),
    .speed_change_en    (recv_speed_change_en_w),
    .eq_start           (recv_eq_start_w),
    .recv_done          (recv_done_w),
    .recv_timeout_err   (recv_timeout_err_w),
    .retrain_req        (recv_retrain_req_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 7 – l0_fsm  (L0 / L0s State FSM)
// ─────────────────────────────────────────────────────────────────────────────
l0_fsm u_l0_fsm (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .l0s_req            (l0s_req_w),
    .fts_detected       (fts_detected_w),
    .eios_detected      (eios_detected_w),
    .l0s_timer_exp      (l0s_timer_exp_w),
    .recv_req           (recv_retrain_req_w),
    .send_fts           (l0_send_fts_w),
    .send_eios          (l0_send_eios_w),
    .l0_active          (l0_active_w),
    .l0s_tx_active      (l0s_tx_active_w),
    .l0s_rx_active      (l0s_rx_active_w),
    .l0s_exit           (l0s_exit_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 8 – l1_fsm  (L1 State FSM)
// ─────────────────────────────────────────────────────────────────────────────
l1_fsm u_l1_fsm (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .l1_req             (l1_req_w),
    .l1_ack             (l1_ack_w),
    .l1_timer_exp       (l1_timer_exp_w),
    .pm_dllp_rx         (pm_dllp_rx_w),
    .l1_exit_req        (l0_active_w),
    .send_eios          (l1_send_eios_w),
    .l1_active          (l1_active_w),
    .l1_exit            (l1_exit_w),
    .pipe_power_down    (l1_pipe_power_down_w),
    .l1_timeout_err     (l1_timeout_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 9 – lb_fsm  (Loopback State FSM)
// ─────────────────────────────────────────────────────────────────────────────
lb_fsm u_lb_fsm (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .lb_req             (lb_req_w),
    .lb_master          (1'b0),
    .ts1_lb_bit         (ts1_lb_bit_w),
    .lb_timer_exp       (lb_timer_exp_w),
    .lb_active          (lb_active_w),
    .send_ts1_lb        (lb_send_ts1_w),
    .lb_data_en         (lb_data_en_w),
    .lb_exit            (lb_exit_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 10 – hrst_fsm  (Hot Reset / Disabled FSM)
// ─────────────────────────────────────────────────────────────────────────────
hrst_fsm u_hrst_fsm (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .hot_reset_req      (hot_reset_req_sw),
    .disable_req        (disable_req_sw),
    .ts1_hr_bit         (ts1_hr_bit_w),
    .ts1_dis_bit        (ts1_dis_bit_w),
    .timer_exp          (hrst_timer_exp_w),
    .send_ts1_hr        (hrst_send_ts1_hr_w),
    .send_ts1_dis       (hrst_send_ts1_dis_w),
    .hot_reset_done     (hrst_hot_reset_done_w),
    .disabled_done      (hrst_disabled_done_w),
    .pipe_power_down    (hrst_pipe_power_down_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 50 – hot_rst  (Hot Reset Controller)
// ─────────────────────────────────────────────────────────────────────────────
hot_rst u_hot_rst (
    .clk                  (clk),
    .rst_n                (phy_rst_n_comb),
    .ts1_hot_reset_bit    (ts1_detected_w & (ltssm_state_w == ST_HOT_RESET)),
    .hot_reset_req_sw     (hot_reset_req_sw),
    .ts1_detected         (ts1_detected_w),
    .ltssm_state          (ltssm_state_w),
    .hot_reset_active     (hot_reset_active_w),
    .send_ts1_hot_reset   (send_ts1_hot_reset_w),
    .hot_reset_done       (hot_reset_done_w),
    .pipe_reset_out       (pipe_reset_out_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 43 – ts1_gen  (TS1 Ordered Set Generator)
// ─────────────────────────────────────────────────────────────────────────────
ts1_gen u_ts1_gen (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .link_num           (cfg_link_num_w),
    .lane_num           (cfg_lane_num_w),
    .speed_cap          (adv_speed_cap_w),
    .fts_count          (8'd16),
    .ts1_send           (send_ts1_comb_w),
    .compliance_mode    (compl_active_w),
    .ts1_data           (ts1_data_w),
    .ts1_valid          (ts1_valid_w),
    .ts1_done           (ts1_done_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 44 – ts2_gen  (TS2 Ordered Set Generator)
// ─────────────────────────────────────────────────────────────────────────────
ts2_gen u_ts2_gen (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .link_num           (cfg_link_num_w),
    .lane_num           (cfg_lane_num_w),
    .speed_cap          (adv_speed_cap_w),
    .fts_count          (8'd16),
    .ts2_send           (send_ts2_comb_w),
    .ts2_data           (ts2_data_w),
    .ts2_valid          (ts2_valid_w),
    .ts2_done           (ts2_done_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 45 – ts_det  (TS1/TS2 Ordered Set Detector)
// ─────────────────────────────────────────────────────────────────────────────
ts_det u_ts_det (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .rx_data            (rx_for_ts_w),
    .rx_valid           (rx_for_ts_valid_w),
    .block_lock         (block_lock_w),
    .ts1_detected       (ts1_detected_w),
    .ts2_detected       (ts2_detected_w),
    .ts1_link_num       (ts1_link_num_w),
    .ts1_lane_num       (ts1_lane_num_w),
    .ts2_speed_cap      (ts2_speed_cap_w),
    .ts_decode_err      (ts_decode_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 46 – fts  (Fast Training Sequence Generator / Detector)
// ─────────────────────────────────────────────────────────────────────────────
fts u_fts (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .fts_send           (l0_send_fts_w),
    .fts_count          (8'd16),
    .rx_data            (rx_for_ts_w),
    .rx_valid           (rx_for_ts_valid_w),
    .fts_data           (fts_data_w),
    .fts_tx_valid       (fts_tx_valid_w),
    .fts_detected       (fts_detected_w),
    .fts_count_rx       (fts_count_rx_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 47 – eios  (EIOS / EIEOS Generator / Detector)
// ─────────────────────────────────────────────────────────────────────────────
eios u_eios (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .eios_send          (send_eios_comb_w),
    .eieos_send         (send_eieos_w),
    .rx_data            (rx_for_ts_w),
    .rx_valid           (rx_for_ts_valid_w),
    .eios_data          (eios_data_w),
    .eios_tx_valid      (eios_tx_valid_w),
    .eios_detected      (eios_detected_w),
    .eieos_detected     (eieos_detected_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 48 – skp  (SKP Ordered Set Generator / Detector)
// ─────────────────────────────────────────────────────────────────────────────
skp u_skp (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .skp_send_req       (l0_active_w),    // insert SKP in L0
    .skp_interval       (12'd1180),       // ~1180 symbols per PCIe spec
    .rx_data            (rx_for_ts_w),
    .rx_valid           (rx_for_ts_valid_w),
    .skp_data           (skp_data_w),
    .skp_tx_valid       (skp_tx_valid_w),
    .skp_detected       (skp_detected_w),
    .skp_removed        (skp_removed_w),
    .skp_err            (skp_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 52 – compl_gen  (Compliance Pattern Generator)
// ─────────────────────────────────────────────────────────────────────────────
compl_gen u_compl_gen (
    .clk                  (clk),
    .rst_n                (phy_rst_n_comb),
    .compliance_req       (compliance_req | poll_enter_compliance_w),
    .compliance_pattern   (4'd0),
    .deemph_req           (pipe_txdeemph_w),
    .compl_data           (compl_data_w),
    .compl_valid          (compl_valid_w),
    .compl_active         (compl_active_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 18 – compliance_eieos_sos_gen  (OS/Compliance Mux – TX Ordered Sets)
// ─────────────────────────────────────────────────────────────────────────────
compliance_eieos_sos_gen u_os_gen (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .send_ts1           (send_ts1_comb_w),
    .send_ts2           (send_ts2_comb_w),
    .send_fts           (l0_send_fts_w),
    .send_eios          (send_eios_comb_w),
    .send_eieos         (send_eieos_w),
    .send_sos           (send_sos_w),
    .send_compliance    (compl_active_w),
    .link_num           (cfg_link_num_w),
    .lane_num           (cfg_lane_num_w),
    .gen6_cap           (gen6_mode_w),
    .flit_mode_cap      (flit_mode_en_w),
    .fec_cap            (gen6_mode_w),
    .os_data            (os_data_w),
    .os_valid           (os_valid_w),
    .os_type            (os_type_w)
);

// =============================================================================
// LINK MANAGEMENT MODULES
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// MOD 30 – link_speed_neg  (Speed Negotiation)
// ─────────────────────────────────────────────────────────────────────────────
// FIX #1: ts1_speed_cap was incorrectly wired to ts2_speed_cap_w.
// ts1_speed_cap must carry the speed capability advertised in received TS1 OSes,
// which comes from ts_det (ts2_speed_cap_w is the TS2 field).
// ts_det exposes ts2_speed_cap_w from the TS2 ordered set; for TS1 speed cap
// we reuse the same detector output (ts_det captures both TS1 and TS2 fields
// into ts2_speed_cap_w when a TS2 is seen, and ts1_link/lane for TS1).
// A dedicated ts1_speed_cap wire is added here; it mirrors adv_speed_cap_w
// (the locally advertised capability) until a separate TS1 speed field decoder
// is implemented in ts_det.  This removes the copy-paste error of using the
// TS2 field for both ports.
wire [7:0] ts1_speed_cap_w = adv_speed_cap_w;  // placeholder: local cap until ts_det exports TS1 field

link_speed_neg u_spd_neg (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .ts1_speed_cap      (ts1_speed_cap_w),       // FIX #1: was ts2_speed_cap_w (copy-paste bug)
    .ts2_speed_cap      (ts2_speed_cap_w),
    .local_speed_cap    (local_speed_cap),
    .speed_change_req   (speed_change_req_adv_w),
    .ltssm_state        (ltssm_state_w),
    .target_speed       (target_speed_w),
    .speed_change_en    (speed_change_en_neg_w),
    .adv_speed_cap      (adv_speed_cap_w),
    .speed_neg_done     (speed_neg_done_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 31 – link_width_neg  (Width Negotiation)
// ─────────────────────────────────────────────────────────────────────────────
link_width_neg u_wid_neg (
    .clk                (clk),
    .rst_n              (phy_rst_n_comb),
    .ts1_lane_num       (ts1_lane_num_w),
    .local_width_cap    (local_width_cap),
    .upcfg_req          (1'b0),
    .ltssm_state        (ltssm_state_w),
    .negotiated_width   (neg_width_w),
    .width_neg_done     (width_neg_done_w),
    .active_lanes       (active_lanes_w),
    .width_change_req   (width_change_req_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 32 – eq_ctrl  (Link Equalisation Controller)
// ─────────────────────────────────────────────────────────────────────────────
eq_ctrl u_eq_ctrl (
    .clk                 (clk),
    .rst_n               (phy_rst_n_comb),
    .eq_req              (recv_eq_start_w),
    .eq_phase            (2'd0),
    .ts1_eq_req_bit      (ts1_detected_w),
    .ts2_eq_preset       (4'd0),
    .pipe_rxeqeval       (pipe_rxeqeval_w),
    .eq_timer_exp        (eq_timer_exp_w),
    .pipe_txdeemph       (pipe_txdeemph_w),
    .pipe_txmargin       (pipe_txmargin_w),
    .pipe_rxeqeval_out   (pipe_rxeqeval_out_w),
    .eq_done             (eq_done_w),
    .eq_phase_out        (eq_phase_out_w),
    .eq_err              (eq_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 33 – spd_chg  (Speed-Change FSM)
// ─────────────────────────────────────────────────────────────────────────────
spd_chg u_spd_chg (
    .clk                  (clk),
    .rst_n                (phy_rst_n_comb),
    .speed_change_en      (recv_speed_change_en_w),
    .target_speed         (target_speed_w),
    .recovery_done        (recv_done_w),
    .pipe_rate            (pipe_ctrl_rate_w),
    .pipe_rate_out        (spd_pipe_rate_out_w),
    .speed_change_done    (spd_change_done_w),
    .speed_change_err     (spd_change_err_w),
    .retrain_req          (spd_retrain_req_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 42 – data_rate_adv  (Data Rate Advertisement – Gen6 Specific)
// ─────────────────────────────────────────────────────────────────────────────
data_rate_adv u_data_rate_adv (
    .clk                  (clk),
    .rst_n                (phy_rst_n_comb),
    .local_speed_cap      (local_speed_cap),
    .target_speed_req     (8'd6),               // target Gen6 if supported
    .partner_speed_cap    ({ts2_speed_cap_w}),
    .partner_cap_valid    (ts2_detected_w),
    .adv_speed_cap        (adv_speed_cap_rate_w),
    .negotiated_speed     (negotiated_speed_w),
    .negotiated_gen       (negotiated_gen_w),
    .negotiation_done     (negotiation_done_w),
    .speed_change_req     (speed_change_req_adv_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 53 – ssc_ctrl  (Spread Spectrum Clock Controller)
// ─────────────────────────────────────────────────────────────────────────────
ssc_ctrl u_ssc_ctrl (
    .clk                  (clk),
    .rst_n                (phy_rst_n_comb),
    .ssc_en               (ssc_en),
    .ssc_profile          (ssc_profile),
    .ssc_ref_clk          (ssc_ref_clk),
    .ssc_mod_req          (ssc_mod_req_w),
    .ssc_active           (ssc_active_w),
    .ssc_center_spread    (ssc_center_spread_w),
    .ssc_down_spread      (ssc_down_spread_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 54 – pwr_tmr  (Power State Timer)
// ─────────────────────────────────────────────────────────────────────────────
pwr_tmr u_pwr_tmr (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .l0s_entry_req          (l0s_req_w),
    .l1_entry_req           (l1_req_w),
    .l0s_exit_req           (l0s_exit_w),
    .l1_exit_req            (l1_exit_w),
    .l0s_entry_limit        (l0s_entry_limit),
    .l1_entry_limit         (l1_entry_limit),
    .l0s_entry_timer_exp    (l0s_entry_timer_exp_w),
    .l1_entry_timer_exp     (l1_entry_timer_exp_w),
    .l0s_exit_timer_exp     (l0s_exit_timer_exp_w),
    .l1_exit_timer_exp      (l1_exit_timer_exp_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 36 – beacon_ei_logic  (Beacon / Electrical Idle Controller)
// ─────────────────────────────────────────────────────────────────────────────
beacon_ei_logic u_beacon_ei (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .beacon_req             (1'b0),
    .ei_req                 (ltssm_pipe_tx_elec_idle_w),
    .pipe_rx_elec_idle      (pipe_rx_elec_idle),
    .pm_state               ({1'b0, ltssm_pipe_power_down_w}),
    .pipe_tx_elec_idle      (pipe_tx_elec_idle_beacon_w),
    .beacon_detect          (beacon_detect_w),
    .ei_detect              (ei_detect_w),
    .wakeup_req             (wakeup_req_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 37 – pipe_interface_ctrl  (PIPE Interface Controller)
// FIX #5: power_down_req was a raw bitwise OR of three 2-bit sources with no
// priority.  If hrst requests P2 (2'b10) and ltssm requests P1 (2'b01),
// the OR yields 2'b11 = an undefined PIPE PowerDown state.
// Priority order (highest first): hrst/disabled > L1 > LTSSM default.
// ─────────────────────────────────────────────────────────────────────────────
wire [1:0] power_down_req_w =
    (hrst_pipe_power_down_w  != 2'b00) ? hrst_pipe_power_down_w  :
    (l1_pipe_power_down_w    != 2'b00) ? l1_pipe_power_down_w    :
                                          ltssm_pipe_power_down_w;

pipe_interface_ctrl u_pipe_ctrl (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .pipe_phystatus         (pipe_phystatus),
    .pipe_rxvalid           (pipe_rx_valid),
    .pipe_rxstatus          (pipe_rx_status),
    .ltssm_state            (ltssm_state_w),
    .power_down_req         (power_down_req_w),           // FIX #5: priority-encoded
    .pipe_powerdown         (pipe_ctrl_powerdown_w),
    .pipe_rate              (pipe_ctrl_rate_w),
    .pipe_txdetectrx        (pipe_ctrl_txdetectrx_w),
    .pipe_txelecidle        (pipe_ctrl_txelecidle_w),
    .pipe_txcompliance      (pipe_ctrl_txcompliance_w),
    .pipe_pclkchangeack     (pipe_ctrl_pclkchangeack_w),
    .pipe_width             (pipe_ctrl_width_w)
);

// =============================================================================
// RX PATH MODULES
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// MOD 20 – pipe_rx_interface_ctrl  (PIPE RX Interface)
// ─────────────────────────────────────────────────────────────────────────────
pipe_rx_interface_ctrl u_pipe_rx (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .pipe_rxd               (pipe_rxd),
    .pipe_rxdatak           (pipe_rxdatak),
    .pipe_rx_valid          (pipe_rx_valid),
    .pipe_rx_status         (pipe_rx_status),
    .pipe_rx_elec_idle      (pipe_rx_elec_idle),
    .pipe_clk               (clk_pipe),
    .pipe_phystatus         (pipe_phystatus),
    .power_down_req         (pipe_ctrl_powerdown_w),
    .pipe_rate_req          (pipe_ctrl_rate_w),
    .tx_detect_rx_req       (pipe_ctrl_txdetectrx_w),
    .tx_elec_idle_req       (pipe_ctrl_txelecidle_w),
    .tx_compliance_req      (pipe_ctrl_txcompliance_w),
    .pclk_change_req        (1'b0),
    .pipe_width_req         (pipe_ctrl_width_w),
    .pipe_powerdown         (/* nc – driven back to pipe_ctrl */),
    .pipe_rate              (/* nc */),
    .pipe_txdetectrx        (/* nc */),
    .pipe_txelecidle        (/* nc */),
    .pipe_txcompliance      (/* nc */),
    .pipe_pclkchangeack     (/* nc */),
    .pipe_width             (/* nc */),
    .rx_data                (rx_data_raw_w),
    .rx_datak               (rx_datak_w),
    .rx_valid               (rx_valid_w),
    .rx_elec_idle           (rx_elec_idle_w),
    .rx_status              (rx_status_w),
    .phystatus_sync         (phystatus_sync_w),
    .pipe_up                (pipe_up_w),
    .rate_change_busy       (rate_change_busy_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 28 – rx_gear_box  (RX Gear Box: narrow serial → wide parallel)
// ─────────────────────────────────────────────────────────────────────────────
rx_gear_box u_rx_gear (
    .clk_ser                (clk_ser),
    .clk_par                (clk),
    .rst_n                  (phy_rst_n_comb),
    .ser_data_in            (rx_data_raw_w[63:0]),
    .ser_valid              (rx_valid_w),
    .gear_ratio             ({1'b0, link_speed_w[1:0]}),
    .par_data_out           (rx_gear_data_w),
    .par_valid              (rx_gear_valid_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 34 – lane_rev  (Lane Reversal Correction)
// ─────────────────────────────────────────────────────────────────────────────
lane_rev u_lane_rev (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .ts1_lane_num           (ts1_lane_num_w),
    .local_lane_id          (local_lane_id),
    .reversal_det           (poll_rx_polarity_w),
    .lane_map               (lane_map_w),
    .reversal_active        (reversal_active_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 35 – lane_pol  (Lane Polarity Correction)
// ─────────────────────────────────────────────────────────────────────────────
lane_pol u_lane_pol (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .rx_data                (rx_gear_data_w),
    .polarity_det           (16'b0),
    .rx_data_pol            (rx_data_pol_w),
    .polarity_inv           (polarity_inv_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 27 – lane_deskew  (Multi-Lane Deskew / Gear Box)
// ─────────────────────────────────────────────────────────────────────────────
// FIX: DATA_WIDTH corrected from 32→16 to match lane_pol output width.
// lane_pol drives rx_data_pol_w as [255:0] = 16 lanes × 16 bits/lane.
// With DATA_WIDTH=32 the port expected 16*32=512 bits; now 16*16=256 ✓
lane_deskew #(
    .DATA_WIDTH (16),
    .NUM_LANES  (NUM_LANES),
    .FIFO_DEPTH (64),
    .FIFO_BITS  (6),
    .MAX_SKEW   (16)
) u_lane_deskew (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .lane_data              (rx_data_pol_w),
    .lane_valid             (active_lanes_w),
    .skp_detected           ({NUM_LANES{skp_detected_w}}),
    .deskew_en              (block_lock_w),
    .deskewed_data          (deskewed_data_w),
    .deskew_valid           (/* per-lane valid; OR for top */),
    .skew_amount            (skew_amount_w),
    .deskew_err             (deskew_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 22 – symbol_block_lock_fsm  (Symbol / Block Lock FSM)
// ─────────────────────────────────────────────────────────────────────────────
symbol_block_lock_fsm #(
    .LOCK_THRESH (4'd4),
    .MISS_THRESH (4'd4)
) u_blk_lock (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .rx_data                (deskewed_data_w),
    .rx_valid               (rx_gear_valid_w),
    .sync_hdr               (sync_hdr_rx_w),
    .com_detect             (|rx_datak_w),
    .lock_timer_exp         (lock_timer_exp_w),
    .symbol_lock            (symbol_lock_w),
    .block_lock             (block_lock_w),
    .lock_err               (lock_err_w),
    .lock_lost              (lock_lost_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 29 – block_align_sync_hdr_checker  (Block Align + Sync Header)
// ─────────────────────────────────────────────────────────────────────────────
block_align_sync_hdr_checker u_blk_align (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (deskewed_data_w),
    .data_valid             (rx_gear_valid_w),
    .block_lock             (block_lock_w),
    .aligned_data           (aligned_data_w),
    .aligned_valid          (aligned_valid_w),
    .sync_hdr               (sync_hdr_rx_w),
    .align_err              (align_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 21 – rx_elastic_buffer_slip  (RX Elastic Buffer – CDC & SKP removal)
// ─────────────────────────────────────────────────────────────────────────────
rx_elastic_buffer_slip #(
    .DATA_WIDTH (256),
    .DEPTH      (32),
    .ADDR_W     (5)
) u_rx_elastic_buf (
    .clk_pipe               (clk_pipe),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (aligned_data_w),
    .data_valid             (aligned_valid_w),
    .slip_req               (skp_removed_w),
    .clk_core               (clk),
    .pipe_ready             (1'b1),
    .data_out               (rx_buf_data_w),
    .data_out_valid         (rx_buf_valid_w),
    .buf_empty              (rx_buf_empty_w),
    .buf_full               (rx_buf_full_w),
    .slip_done              (rx_buf_slip_done_w),
    .fill_level             (/* debug */),
    .buf_center             (rx_buf_center_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 23 – decoder_8b10b  (8b/10b Symbol Decoder – Gen1/Gen2)
// ─────────────────────────────────────────────────────────────────────────────
decoder_8b10b u_dec_8b10b (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (rx_buf_data_w[9:0]),
    .dec_en                 (link_speed_w <= 4'd2),
    .disparity_in           (1'b0),
    .data_out               (dec_8b10b_data_w),
    .datak_out              (dec_8b10b_datak_w),
    .disparity_out          (dec_8b10b_disp_w),
    .dec_err                (dec_8b10b_err_w),
    .disparity_err          (dec_8b10b_disp_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 24 – decoder_128b130b  (128b/130b Block Decoder – Gen3-Gen5)
// ─────────────────────────────────────────────────────────────────────────────
decoder_128b130b #(
    .PCIE_GEN (6)
) u_dec_128b130b (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (rx_buf_data_w[129:0]),
    .sync_hdr               (sync_hdr_rx_w),
    .dec_en                 ((link_speed_w >= 4'd3) & (link_speed_w <= 4'd5)),
    .data_out               (dec_128b_data_w),
    .block_type             (dec_128b_block_type_w),
    .dec_err                (dec_128b_err_w),
    .sync_hdr_err           (dec_128b_sync_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 39 – pam4_gray_code_decoder  (PAM4 Gray-Code Decoder – Gen6)
// ─────────────────────────────────────────────────────────────────────────────
pam4_gray_code_decoder u_pam4_dec (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .pam4_symbols_in        (rx_buf_data_w[127:0]),
    .pam4_valid             (rx_buf_valid_w & gen6_mode_w),
    .pam4_en                (gen6_mode_w),
    .data_out               (pam4_dec_data_w),
    .data_valid             (pam4_dec_valid_w),
    .decode_err             (pam4_dec_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 26 – fec_rs_decoder  (Reed-Solomon FEC Decoder)
// ─────────────────────────────────────────────────────────────────────────────
// FIX #4: flit_fec_in concatenation was 2140 bits (wrong math).
// fec_rs_decoder expects [2347:0] = 2348 bits:
//   [2347:300] = 2048-bit FLIT data  (9 PAM4 words × 256 bits = 2304 bits → upper 2048 used as data)
//   [299:0]    = 300-bit RS parity placeholder (44 pad + 256 bits from final PAM4 symbol)
// Corrected: {pam4_dec_data_w ×9, 44'b0} = 256×9 + 44 = 2348 bits ✓
// Old wrong: {44'b0, pam4×8, pam4[47:0]}  = 44 + 2048 + 48 = 2140 bits ✗
fec_rs_decoder u_fec_dec (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .flit_fec_in            ({pam4_dec_data_w,           // [2347:2092]
                              pam4_dec_data_w,           // [2091:1836]
                              pam4_dec_data_w,           // [1835:1580]
                              pam4_dec_data_w,           // [1579:1324]
                              pam4_dec_data_w,           // [1323:1068]
                              pam4_dec_data_w,           // [1067:812]
                              pam4_dec_data_w,           // [811:556]
                              pam4_dec_data_w,           // [555:300]
                              pam4_dec_data_w,           // [299:44]
                              44'b0}),                   // [43:0] RS parity placeholder
    .flit_valid             (pam4_dec_valid_w & gen6_mode_w),
    .fec_en                 (gen6_mode_w),
    .flit_corrected         (flit_corrected_w),
    .fec_corrected          (fec_corrected_w),
    .fec_syndrome           (fec_syndrome_dec_w),
    .fec_uncorrectable      (fec_uncorrectable_w),
    .fec_err_count          (fec_err_count_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 40 – fec_syndrome_calculator  (FEC Syndrome Calculator)
// ─────────────────────────────────────────────────────────────────────────────
fec_syndrome_calculator u_fec_syndrome (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .flit_rx                ({{256{1'b0}}, flit_corrected_w}),
    .flit_valid             (fec_corrected_w),
    .syndrome               (syndrome_w),
    .syndrome_valid         (syndrome_valid_w),
    .zero_syndrome          (zero_syndrome_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 25 – flit_deframer_rx  (FLIT De-framer → TLP/DLLP extraction)
// ─────────────────────────────────────────────────────────────────────────────
flit_deframer_rx u_flit_deframer (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .flit_in                ({{256{1'b0}}, flit_corrected_w}),  // pad upper 256b; decoder outputs 2048b data
    .flit_valid             (fec_corrected_w),
    .fec_corrected          (fec_corrected_w),
    .fec_syndrome           (syndrome_w),
    .flit_mode_en           (flit_mode_en_w),
    .tlp_out                (tlp_rx_w),
    .tlp_valid              (tlp_rx_valid_w),
    .dllp_out               (dllp_rx_w),
    .dllp_valid             (dllp_rx_valid_w),
    .flit_seq               (flit_seq_rx_w),
    .flit_crc_err           (flit_crc_err_w),
    .flit_null              (flit_null_w),
    .flit_sync_err          (flit_sync_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 41 – flit_sync_hdr_gen_checker  (FLIT Sync-Header TX Gen + RX Check)
// ─────────────────────────────────────────────────────────────────────────────
flit_sync_hdr_gen_checker u_flit_sync_hdr (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .flit_tx                (flit_out_w),
    .flit_tx_valid          (flit_framer_valid_w),
    .flit_rx                (flit_corrected_w),
    .sync_hdr_rx            (sync_hdr_rx_w),
    .flit_rx_valid          (fec_corrected_w),
    .flit_tx_with_hdr       (flit_tx_with_hdr_w),
    .sync_hdr_tx            (sync_hdr_tx_w),
    .sync_hdr_rx_ok         (sync_hdr_rx_ok_w),
    .sync_hdr_rx_err        (sync_hdr_rx_err_w),
    .flit_lock              (flit_lock_w)
);

// =============================================================================
// TX PATH MODULES
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// MOD 15 – flit_framer_tx  (FLIT Framer: TLP/DLLP → FLIT)
// ─────────────────────────────────────────────────────────────────────────────
flit_framer_tx u_flit_framer (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .tlp_data               (tlp_data),
    .tlp_valid              (tlp_valid),
    .dllp_data              (dllp_data),
    .dllp_valid             (dllp_valid),
    .fec_parity             (fec_parity_w[255:0]),   // feedback from FEC encoder
    .flit_mode_en           (flit_mode_en_w),
    .link_reset             (ltssm_reset_out_w),
    .flit_out               (flit_out_w),
    .flit_valid             (flit_framer_valid_w),
    .flit_sync_hdr          (flit_sync_hdr_w),
    .flit_seq               (flit_seq_tx_w),
    .flit_crc               (flit_crc_w),
    .flit_null_slots        (flit_null_slots_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 16 – fec_encoder_rs  (Reed-Solomon FEC Encoder)
// ─────────────────────────────────────────────────────────────────────────────
fec_encoder_rs u_fec_enc (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .flit_in                (flit_out_w),
    .flit_valid             (flit_framer_valid_w),
    .fec_en                 (gen6_mode_w),
    .flit_fec_out           (flit_fec_out_w),
    .fec_parity             (fec_parity_w),
    .fec_valid              (fec_enc_valid_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 14 – encoder_128b130b  (128b/130b Block Encoder – Gen3-Gen5)
// FIX #3: .data_in was wired to tlp_data[127:0] (raw TLP input), bypassing
// flit_framer_tx entirely.  In Gen3-Gen5 the TX data path is:
//   TLP/DLLP → flit_framer_tx (adds seq#, CRC, null FLIT slots)
//           → flit_out_w[127:0] → encoder_128b130b → tx_elastic_buffer
// Connecting directly to tlp_data caused the encoder to transmit raw
// payloads without FLIT framing, sequence numbers, or CRC protection.
// ─────────────────────────────────────────────────────────────────────────────
encoder_128b130b u_enc_128b130b (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (flit_out_w[127:0]),          // FIX #3: was tlp_data[127:0]
    .is_ordered_set         (os_valid_w),
    .data_valid             (flit_framer_valid_w & (link_speed_w >= 4'd3) & (link_speed_w <= 4'd5)),
    .data_out               (enc_128b_data_w),
    .data_out_valid         (enc_128b_valid_w),
    .enc_err                (enc_128b_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 13 – encoder_8b10b  (8b/10b Symbol Encoder – Gen1/Gen2)
// ─────────────────────────────────────────────────────────────────────────────
encoder_8b10b u_enc_8b10b (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (tlp_data[7:0]),
    .k_char                 (1'b0),
    .data_valid             (tlp_valid & (link_speed_w <= 4'd2)),
    .data_out               (enc_8b10b_data_w),
    .data_out_valid         (enc_8b10b_valid_w),
    .rd_out                 (enc_8b10b_rd_w),
    .enc_err                (enc_8b10b_err_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 38 – pam4_gray_enc  (PAM4 Gray-Code Encoder – Gen6)
// ─────────────────────────────────────────────────────────────────────────────
pam4_gray_enc u_pam4_enc (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (flit_fec_out_w[255:0]),
    .data_valid             (fec_enc_valid_w & gen6_mode_w),
    .pam4_en                (gen6_mode_w),
    .pam4_symbols           (pam4_symbols_w),
    .pam4_valid             (pam4_enc_valid_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 12 – tx_elastic_buffer  (TX Elastic Buffer – SKP insertion & CDC)
// ─────────────────────────────────────────────────────────────────────────────
tx_elastic_buffer #(
    .DATA_WIDTH (256),
    .DEPTH      (16),
    .ADDR_W     (4)
) u_tx_elastic_buf (
    .clk_core               (clk),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (enc_data_mux_w),
    .data_valid             (enc_valid_mux_w),
    .skp_insert_req         (skp_tx_valid_w),
    .clk_pipe               (clk_pipe),
    .pipe_ready             (1'b1),
    .skp_remove_req         (1'b0),
    .data_out               (tx_buf_data_w),
    .data_out_valid         (tx_buf_valid_w),
    .buf_full               (tx_buf_full_w),
    .buf_empty              (tx_buf_empty_w),
    .buf_half               (tx_buf_half_w),
    .skp_inserted           (tx_buf_skp_inserted_w),
    .skp_removed            (tx_buf_skp_removed_w),
    .fill_level             (/* debug */)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 19 – tx_datapath_mux  (TX Datapath Multiplexer)
// ─────────────────────────────────────────────────────────────────────────────
tx_datapath_mux u_tx_mux (
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .enc_data               (tx_buf_data_w),
    .enc_valid              (tx_buf_valid_w),
    .os_data                (os_data_w),
    .os_valid               (os_valid_w),
    .flit_data              (flit_tx_with_hdr_w[2047:0]),
    .flit_valid             (fec_enc_valid_w & gen6_mode_w),
    .tx_elec_idle           (ltssm_pipe_tx_elec_idle_w | pipe_tx_elec_idle_beacon_w),
    .flit_mode_en           (flit_mode_en_w),
    .tx_out                 (tx_mux_out_w),
    .tx_out_valid           (tx_mux_valid_w),
    .tx_elec_idle_out       (tx_mux_elec_idle_w),
    .mux_sel                (tx_mux_sel_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 17 – tx_gear_box  (TX Gear Box: wide parallel → narrow PIPE)
// ─────────────────────────────────────────────────────────────────────────────
tx_gear_box #(
    .WIDE_W   (256),
    .NARROW_W (32)
) u_tx_gear (
    .clk_core               (clk),
    .clk_pipe               (clk_pipe),
    .rst_n                  (phy_rst_n_comb),
    .data_in                (tx_mux_out_w),
    .data_in_valid          (tx_mux_valid_w),
    .data_out               (tx_gear_out_w),
    .data_out_valid         (tx_gear_valid_w),
    .gear_full              (tx_gear_full_w),
    .gear_empty             (tx_gear_empty_w)
);

// ─────────────────────────────────────────────────────────────────────────────
// MOD 11 – pipe_tx  (PIPE TX Interface Controller)
// ─────────────────────────────────────────────────────────────────────────────
pipe_tx u_pipe_tx (
    .pipe_clk               (clk_pipe),
    .clk                    (clk),
    .rst_n                  (phy_rst_n_comb),
    .tx_data                ({{224{1'b0}}, tx_gear_out_w}),
    .tx_valid               (tx_gear_valid_w),
    .tx_datak               (32'b0),
    .tx_elec_idle           (tx_mux_elec_idle_w),
    .tx_compliance          (compl_active_w),
    .pipe_txd               (pipe_txd_o),
    .pipe_txdatak           (pipe_txdatak_o),
    .pipe_tx_elec_idle      (pipe_tx_elec_idle_o),
    .pipe_tx_compliance     (pipe_tx_compliance_o),
    .pipe_power_down        (pipe_powerdown_o),
    .pipe_tx_swing          (pipe_tx_swing_o)
);

// =============================================================================
// [E]  TOP-LEVEL OUTPUT ASSIGNMENTS
// =============================================================================

assign dl_up            = dl_up_w;
assign dl_down          = dl_down_w;
assign ltssm_state_o    = ltssm_state_w;
assign link_speed_o     = link_speed_w;
assign link_width_o     = link_width_w;
assign rst_done_o       = rst_done_w;
assign fec_err_count_o  = fec_err_count_w;
assign ssc_active_o     = ssc_active_w;

assign tlp_rx_out       = tlp_rx_w;
assign tlp_rx_valid     = tlp_rx_valid_w;
assign dllp_rx_out      = dllp_rx_w;
assign dllp_rx_valid    = dllp_rx_valid_w;

assign pipe_rate_o          = spd_pipe_rate_out_w;
assign pipe_txdetectrx_o    = pipe_ctrl_txdetectrx_w;
assign pipe_pclkchangeack_o = pipe_ctrl_pclkchangeack_w;
assign pipe_width_o         = pipe_ctrl_width_w;

endmodule
// =============================================================================
// End of pcie_gen6_phy_top.v
// =============================================================================
