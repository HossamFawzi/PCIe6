
`timescale 1ns/1ps

module pcie_gen6_system_top #(
    parameter NUM_LANES  = 16,
    parameter DATA_WIDTH = 256,

    parameter BYPASS_FEC  = 0,

    parameter SIM_BYPASS = 0
)(

    input  wire        clk,
    input  wire        clk_pipe,
    input  wire        clk_ser,
    input  wire        rst_n,
    input  wire        perst_n,
    input  wire        power_good,
    input  wire        clk_valid,
    input  wire        ssc_ref_clk,

    input  wire [255:0] pipe_rxd,
    input  wire [31:0]  pipe_rxdatak,
    input  wire         pipe_rx_valid,
    input  wire [2:0]   pipe_rx_status,
    input  wire         pipe_rx_elec_idle,
    input  wire         pipe_phystatus,

    output wire [255:0] pipe_txd_o,
    output wire [31:0]  pipe_txdatak_o,
    output wire         pipe_tx_elec_idle_o,
    output wire         pipe_tx_compliance_o,
    output wire         pipe_tx_swing_o,
    output wire [1:0]   pipe_powerdown_o,
    output wire [3:0]   pipe_rate_o,
    output wire         pipe_txdetectrx_o,
    output wire         pipe_pclkchangeack_o,
    output wire [1:0]   pipe_width_o,

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

    output wire [511:0] usr_cpl_data,
    output wire         usr_cpl_valid,
    output wire [2:0]   usr_cpl_status,
    output wire [9:0]   usr_cpl_tag,
    output wire [511:0] usr_mwr_data,
    output wire         usr_mwr_valid,
    output wire [63:0]  usr_mwr_addr,

    input  wire [255:0] tlp_cfg_in,
    input  wire         tlp_cfg_valid,
    input  wire [11:0]  cfg_addr,
    input  wire [31:0]  cfg_wr_data,
    input  wire         cfg_wr_en,
    output wire [31:0]  cfg_rd_data,
    output wire         cfg_rd_valid,

    input  wire         vc0_req,
    input  wire         vc1_req,
    input  wire         vc2_req,
    input  wire         vc3_req,
    input  wire [1:0]   vc_arb_scheme,
    input  wire [31:0]  vc_weight,
    output wire [3:0]   vc_grant,
    output wire [2:0]   vc_grant_id,
    output wire         vc_arb_valid,

    input  wire [2:0]   pm_req,
    input  wire         hot_reset_req_sw,
    input  wire         disable_req_sw,
    input  wire         compliance_req,
    input  wire [11:0]  l0s_entry_limit,
    input  wire [15:0]  l1_entry_limit,

    input  wire [1:0]   ssc_profile,
    input  wire         ssc_en,

    input  wire [7:0]   local_speed_cap,
    input  wire [5:0]   local_width_cap,
    input  wire [7:0]   local_lane_id,

    input  wire [22:0]  lfsr_seed,
    input  wire         scramble_en,
    input  wire [7:0]   ack_freq,
    input  wire [15:0]  ack_lat_limit,
    input  wire [15:0]  replay_limit,
    input  wire [15:0]  fc_timer_limit,
    input  wire [15:0]  fc_watchdog_limit,
    input  wire [15:0]  l0s_limit,
    input  wire [15:0]  l1_limit,
    input  wire [2:0]   pm_req_sw,

    output wire [31:0]  aer_status,
    output wire         aer_int,
    output wire [255:0] err_msg_tlp,
    output wire         err_msg_valid,

    output wire [5:0]   ltssm_state_o,
    output wire [3:0]   link_speed_o,
    output wire [5:0]   link_width_o,
    output wire         rst_done_o,
    output wire [7:0]   fec_err_count_o,
    output wire         ssc_active_o,
    output wire         dll_up_o,
    output wire         dll_error_o,
    output wire [2:0]   link_state_o,
    output wire         fc_init_done_o,
    output wire         ordering_ok_o,
    output wire         tag_exhausted_o,
    output wire [9:0]   outstanding_count_o
);

wire [1023:0] phy_tlp_rx_w;
wire          phy_tlp_rx_valid_w;

wire [1023:0] dll_rx_to_tl_w;
wire          dll_rx_to_tl_valid_w;
wire [63:0]   phy_dllp_rx_w;
wire          phy_dllp_rx_valid_w;
wire          phy_dl_up_w;
wire          phy_dl_down_w;

wire [255:0]  dll_phy_rxd_w      = (SIM_BYPASS && pipe_rx_valid)
                                    ? pipe_rxd
                                    : phy_tlp_rx_w[255:0];
wire          dll_phy_rx_valid_w = (SIM_BYPASS && pipe_rx_valid)
                                    ? pipe_rx_valid
                                    : (phy_tlp_rx_valid_w | phy_dllp_rx_valid_w);

wire [255:0]  dll_phy_txd_w;
wire          dll_phy_tx_valid_w;
wire          dll_phy_tx_elec_idle_w;
wire          dll_phy_tx_compliance_w;

wire [15:0]   dll_fec_syndrome_w;
wire          dll_fec_corrected_w;

wire [2047:0] tl_flit_to_dll_w;
wire          tl_flit_to_dll_valid_w;
wire          tl_dll_ready_w;

wire [1023:0] dll_tlp_to_tl_w;
wire          dll_tlp_to_tl_valid_w;

wire          dll_up_to_tl_w;
wire          dll_active_w;
wire          dll_error_w;
wire [5:0]    dll_err_to_aer_w;
wire          dll_err_valid_w;
wire [3:0]    dll_err_type_w;
wire [1:0]    dll_err_severity_w;
wire [2:0]    link_state_w;
wire          fc_deadlock_det_w;
wire          replay_rollover_err_w;

reg   dll_up_prev_r;
always @(posedge clk or negedge rst_n)
    if (!rst_n) dll_up_prev_r <= 1'b0;
    else        dll_up_prev_r <= dll_up_to_tl_w;
wire dll_up_rise = dll_up_to_tl_w & ~dll_up_prev_r;

wire [7:0]    fc_update_ph_w;
wire [11:0]   fc_update_pd_w;
wire [7:0]    fc_update_nph_w;
wire [7:0]    fc_update_cplh_w;
wire [11:0]   fc_update_cpld_w;
wire          fc_update_valid_w;

wire [71:0]   cr_update_w = {fc_update_ph_w,
                              fc_update_pd_w[7:0],
                              fc_update_nph_w,
                              8'd0,
                              fc_update_cplh_w,
                              fc_update_cpld_w[7:0],
                              8'd0};
wire          cr_update_valid_w = fc_update_valid_w | dll_up_rise;
wire          dll_ack_w         = dll_up_to_tl_w;
wire          dll_nak_w         = 1'b0;

wire [5:0]    phy_ltssm_state_w;
wire [3:0]    phy_link_speed_w;
wire [5:0]    phy_link_width_w;

wire          dll_link_down_req_w  = replay_rollover_err_w | dll_error_w;
wire          phy_dll_up_req_w     = dll_up_to_tl_w;

wire [1023:0] phy_tlp_data_w    = tl_flit_to_dll_w[1023:0];
wire          phy_tlp_valid_w   = tl_flit_to_dll_valid_w;

wire [63:0]   phy_dllp_data_w;
wire          phy_dllp_valid_w;

pcie_gen6_phy_top #(
    .NUM_LANES  (NUM_LANES),
    .DATA_WIDTH (DATA_WIDTH),
    .BYPASS_FEC (BYPASS_FEC)
) u_phy_top (

    .clk                    (clk),
    .clk_pipe               (clk_pipe),
    .clk_ser                (clk_ser),
    .rst_n                  (rst_n),
    .perst_n                (perst_n),
    .power_good             (power_good),
    .clk_valid              (clk_valid),
    .ssc_ref_clk            (ssc_ref_clk),

    .pipe_rxd               (pipe_rxd),
    .pipe_rxdatak           (pipe_rxdatak),
    .pipe_rx_valid          (pipe_rx_valid),
    .pipe_rx_status         (pipe_rx_status),
    .pipe_rx_elec_idle      (pipe_rx_elec_idle),
    .pipe_phystatus         (pipe_phystatus),

    .pipe_txd_o             (pipe_txd_o),
    .pipe_txdatak_o         (pipe_txdatak_o),
    .pipe_tx_elec_idle_o    (pipe_tx_elec_idle_o),
    .pipe_tx_compliance_o   (pipe_tx_compliance_o),
    .pipe_tx_swing_o        (pipe_tx_swing_o),
    .pipe_powerdown_o       (pipe_powerdown_o),
    .pipe_rate_o            (pipe_rate_o),
    .pipe_txdetectrx_o      (pipe_txdetectrx_o),
    .pipe_pclkchangeack_o   (pipe_pclkchangeack_o),
    .pipe_width_o           (pipe_width_o),

    .tlp_data               (phy_tlp_data_w),
    .tlp_valid              (phy_tlp_valid_w),
    .dllp_data              (phy_dllp_data_w),
    .dllp_valid             (phy_dllp_valid_w),
    .dll_up_req             (phy_dll_up_req_w),
    .link_down_req          (dll_link_down_req_w),

    .tlp_rx_out             (phy_tlp_rx_w),
    .tlp_rx_valid           (phy_tlp_rx_valid_w),
    .dllp_rx_out            (phy_dllp_rx_w),
    .dllp_rx_valid          (phy_dllp_rx_valid_w),
    .dl_up                  (phy_dl_up_w),
    .dl_down                (phy_dl_down_w),

    .pm_req                 (pm_req),
    .hot_reset_req_sw       (hot_reset_req_sw),
    .disable_req_sw         (disable_req_sw),
    .compliance_req         (compliance_req),
    .l0s_entry_limit        (l0s_entry_limit),
    .l1_entry_limit         (l1_entry_limit),

    .ssc_profile            (ssc_profile),
    .ssc_en                 (ssc_en),

    .local_speed_cap        (local_speed_cap),
    .local_width_cap        (local_width_cap),
    .local_lane_id          (local_lane_id),

    .ltssm_state_o          (phy_ltssm_state_w),
    .link_speed_o           (phy_link_speed_w),
    .link_width_o           (phy_link_width_w),
    .rst_done_o             (rst_done_o),
    .fec_err_count_o        (fec_err_count_o),
    .ssc_active_o           (ssc_active_o),

    .fec_syndrome_o         (dll_fec_syndrome_w),
    .fec_corrected_o        (dll_fec_corrected_w)
);

dll_top u_dll_top (
    .clk                    (clk),
    .rst_n                  (rst_n),

    .phy_rxd                (dll_phy_rxd_w),
    .phy_rx_valid           (dll_phy_rx_valid_w),
    .phy_rx_status          (pipe_rx_status),
    .fec_syndrome           (dll_fec_syndrome_w),
    .fec_corrected          (dll_fec_corrected_w),

    .phy_txd                (dll_phy_txd_w),
    .phy_tx_valid           (dll_phy_tx_valid_w),
    .phy_tx_elec_idle       (dll_phy_tx_elec_idle_w),
    .phy_tx_compliance      (dll_phy_tx_compliance_w),

    .tlp_from_tl            (1024'b0),
    .tlp_from_tl_valid      (1'b0),
    .flit_from_tl           (tl_flit_to_dll_w),
    .flit_from_tl_valid     (tl_flit_to_dll_valid_w),
    .fc_update_ph           (fc_update_ph_w),
    .fc_update_valid        (fc_update_valid_w),

    .tlp_to_tl              (dll_rx_to_tl_w),
    .tlp_to_tl_valid        (dll_rx_to_tl_valid_w),

    .ltssm_dl_up            (phy_dl_up_w),
    .ltssm_dl_down          (phy_dl_down_w),
    .ltssm_speed            (phy_link_speed_w),
    .ltssm_width            (phy_link_width_w),

    .tx_elec_idle_req       (1'b0),
    .tx_compliance_req      (compliance_req),

    .flit_mode_en           (phy_link_speed_w == 4'd6),
    .lfsr_seed              (lfsr_seed),
    .scramble_en            (scramble_en),
    .ack_freq               (ack_freq),
    .ack_lat_limit          (ack_lat_limit),
    .replay_limit           (replay_limit),
    .fc_timer_limit         (fc_timer_limit),
    .fc_watchdog_limit      (fc_watchdog_limit),
    .l0s_limit              (l0s_limit),
    .l1_limit               (l1_limit),
    .pm_req_sw              (pm_req_sw),

    .dll_up_to_tl           (dll_up_to_tl_w),
    .dll_active             (dll_active_w),
    .dll_error              (dll_error_w),
    .dll_err_to_aer         (dll_err_to_aer_w),
    .dll_err_valid          (dll_err_valid_w),
    .dll_err_type           (dll_err_type_w),
    .dll_err_severity       (dll_err_severity_w),
    .link_state             (link_state_w),
    .fc_deadlock_det        (fc_deadlock_det_w),
    .replay_rollover_err    (replay_rollover_err_w),

    .dllp_arb_out_o         (phy_dllp_data_w),
    .dllp_arb_valid_o       (phy_dllp_valid_w),

    .fc_update_ph_rx_o      (fc_update_ph_w),
    .fc_update_pd_rx_o      (fc_update_pd_w),
    .fc_update_nph_rx_o     (fc_update_nph_w),
    .fc_update_cplh_rx_o    (fc_update_cplh_w),
    .fc_update_cpld_rx_o    (fc_update_cpld_w),
    .fc_update_valid_rx_o   (fc_update_valid_w)
);

pcie_tl_top u_tl_top (
    .clk                    (clk),
    .rst_n                  (rst_n),

    .req_type               (req_type),
    .req_addr               (req_addr),
    .req_len                (req_len),
    .req_data               (req_data),
    .req_valid              (req_valid),
    .req_attr               (req_attr),
    .req_tc                 (req_tc),
    .req_first_be           (req_first_be),
    .req_last_be            (req_last_be),
    .req_ready              (req_ready),

    .usr_cpl_data           (usr_cpl_data),
    .usr_cpl_valid          (usr_cpl_valid),
    .usr_cpl_status         (usr_cpl_status),
    .usr_cpl_tag            (usr_cpl_tag),
    .usr_mwr_data           (usr_mwr_data),
    .usr_mwr_valid          (usr_mwr_valid),
    .usr_mwr_addr           (usr_mwr_addr),

    .dll_ack                (dll_ack_w),
    .dll_nak                (dll_nak_w),
    .dll_up                 (dll_up_to_tl_w),
    .dll_err_to_aer         (dll_err_to_aer_w),
    .dll_err_valid          (dll_err_valid_w),
    .cr_update              (cr_update_w),
    .cr_update_valid        (cr_update_valid_w),

    .dll_tlp_rx_direct      (dll_rx_to_tl_w),
    .dll_tlp_rx_direct_valid(dll_rx_to_tl_valid_w),

    .flit_to_dll            (tl_flit_to_dll_w),
    .flit_to_dll_valid      (tl_flit_to_dll_valid_w),
    .dll_ready              (tl_dll_ready_w),

    .tlp_cfg_in             (tlp_cfg_in),
    .tlp_cfg_valid          (tlp_cfg_valid),
    .cfg_addr               (cfg_addr),
    .cfg_wr_data            (cfg_wr_data),
    .cfg_wr_en              (cfg_wr_en),
    .cfg_rd_data            (cfg_rd_data),
    .cfg_rd_valid           (cfg_rd_valid),

    .aer_status             (aer_status),
    .aer_int                (aer_int),
    .err_msg_tlp            (err_msg_tlp),
    .err_msg_valid          (err_msg_valid),

    .vc0_req                (vc0_req),
    .vc1_req                (vc1_req),
    .vc2_req                (vc2_req),
    .vc3_req                (vc3_req),
    .vc_arb_scheme          (vc_arb_scheme),
    .vc_weight              (vc_weight),
    .vc_grant               (vc_grant),
    .vc_grant_id            (vc_grant_id),
    .vc_arb_valid           (vc_arb_valid),

    .fc_init_done_out       (fc_init_done_o),
    .ordering_ok_out        (ordering_ok_o),
    .tag_exhausted_out      (tag_exhausted_o),
    .outstanding_count_out  (outstanding_count_o)
);

assign ltssm_state_o = phy_ltssm_state_w;
assign link_speed_o  = phy_link_speed_w;
assign link_width_o  = phy_link_width_w;
assign dll_up_o      = dll_up_to_tl_w;
assign dll_error_o   = dll_error_w;
assign link_state_o  = link_state_w;

endmodule
