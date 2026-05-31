// =============================================================================
// File    : pcie_gen6_system_top.v
// Project : PCIe Gen6 ? Full-Stack System Top
// Purpose : Integrates the three layer tops into a single chip-level wrapper:
//              ? pcie_gen6_phy_top  ? Physical Layer (53 modules)
//              ? dll_top            ? Data Link Layer (36 modules)
//              ? pcie_tl_top        ? Transaction Layer (28 modules)
//
// ?????????????????????????????????????????????????????????????????
// ?                    pcie_gen6_system_top                       ?
// ?                                                               ?
// ?  ????????????     ????????????     ????????????????????????  ?
// ?  ? pcie_tl  ??????? dll_top  ??????? pcie_gen6_phy_top    ?  ?
// ?  ? _top     ???????          ???????                      ?  ?
// ?  ????????????     ????????????     ????????????????????????  ?
// ?       ?                                        ?              ?
// ?  User-Logic I/F                        PIPE / SerDes          ?
// ?????????????????????????????????????????????????????????????????
//
// KNOWN DUPLICATE MODULE ISSUES FOUND (documented here, must be resolved
// before simulation by renaming one instance in its source file):
//
//   1. tx_datapath_mux ? exists in BOTH:
//        ALL_PYHSICAL_LAYER_MODULES/tx_datapath_mux.v  (PHY MUX)
//        all_DATA LINK MODULES/tx_datapath_mux.v       (DLL MUX)
//      FIX: Rename the DLL version to dll_tx_datapath_mux in its source.
//
//   2. fc_init_fsm ? exists in BOTH:
//        all_DATA LINK MODULES/fc_init_fsm.v    (DLL FC init)
//        all_TRANSACTION MODULES/fc_init_fsm.v  (TL FC init)
//      FIX: Rename the TL version to tl_fc_init_fsm in its source, AND
//           update the reference inside pcie_tl_top.v to match.
//
//   3. Descrambler (capital D) ? DLL module name does not follow the
//      lowercase convention; this causes case-sensitive tool errors on Linux.
//      FIX: Rename module to "descrambler" in Descrambler.v and update
//           the instantiation in dll_top.v.
//
// Standard  : PCIe Base Specification 6.0
// Language  : Verilog-2001 (no SystemVerilog)
// Version   : v22 — SYNTHESIS-CLEAN
//   Fixes applied vs v18:
//   [SYNTH-1] aer_error_logger.v   : Removed 'initial' block; aer_mask now reset in always
//   [SYNTH-2] tlp_prefix_handler.v : $display wrapped in `ifdef SIMULATION
//   [SYNTH-3] nullified_tlp_handler.v : $display wrapped in `ifdef SIMULATION
//   [SYNTH-4] AER display storm    : aer_error_logger now prints only on status change
//   [SYNTH-5] PHY filenames        : All 11 files with spaces renamed to underscore format
//   [SYNTH-6] TL filename          : "Completion Handler.v" -> completion_handler.v
//   NOTE: Duplicate module renames (dll_tx_datapath_mux, tl_fc_init_fsm, descrambler)
//         were already applied in v18 and remain correct.
// =============================================================================
`timescale 1ns/1ps

module pcie_gen6_system_top #(
    parameter NUM_LANES  = 16,
    parameter DATA_WIDTH = 256,
    // FIX-STUB-4: propagated from pcie_gen6_phy_top — set 1 for bring-up without FEC
    parameter BYPASS_FEC  = 0,
    // FIX-SYS-3: Set SIM_BYPASS=1 ONLY in simulation to allow direct PIPE inject.
    // In real hardware this MUST be 0 so FEC+FLIT deframer pipeline is active.
    parameter SIM_BYPASS = 0
)(
    // ?? System Clocks & Resets ???????????????????????????????????????????????
    input  wire        clk,           // Core clock (e.g. 250 MHz)
    input  wire        clk_pipe,      // PIPE interface clock from PHY macro
    input  wire        clk_ser,       // High-speed serialiser clock
    input  wire        rst_n,         // Active-low async system reset
    input  wire        perst_n,       // PCIe PERST# (fundamental reset)
    input  wire        power_good,    // Power rail stable
    input  wire        clk_valid,     // Reference clock valid
    input  wire        ssc_ref_clk,   // SSC reference clock

    // ?? PIPE PHY Interface ? RX ??????????????????????????????????????????????
    input  wire [255:0] pipe_rxd,
    input  wire [31:0]  pipe_rxdatak,
    input  wire         pipe_rx_valid,
    input  wire [2:0]   pipe_rx_status,
    input  wire         pipe_rx_elec_idle,
    input  wire         pipe_phystatus,

    // ?? PIPE PHY Interface ? TX ??????????????????????????????????????????????
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

    // ?? User-Logic Interface (TL ? Application) ??????????????????????????????
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

    // ?? Config Space ?????????????????????????????????????????????????????????
    input  wire [255:0] tlp_cfg_in,
    input  wire         tlp_cfg_valid,
    input  wire [11:0]  cfg_addr,
    input  wire [31:0]  cfg_wr_data,
    input  wire         cfg_wr_en,
    output wire [31:0]  cfg_rd_data,
    output wire         cfg_rd_valid,

    // ?? VC Arbiter ???????????????????????????????????????????????????????????
    input  wire         vc0_req,
    input  wire         vc1_req,
    input  wire         vc2_req,
    input  wire         vc3_req,
    input  wire [1:0]   vc_arb_scheme,
    input  wire [31:0]  vc_weight,
    output wire [3:0]   vc_grant,
    output wire [2:0]   vc_grant_id,
    output wire         vc_arb_valid,

    // ?? Power Management ?????????????????????????????????????????????????????
    input  wire [2:0]   pm_req,
    input  wire         hot_reset_req_sw,
    input  wire         disable_req_sw,
    input  wire         compliance_req,
    input  wire [11:0]  l0s_entry_limit,
    input  wire [15:0]  l1_entry_limit,

    // ?? SSC Control ??????????????????????????????????????????????????????????
    input  wire [1:0]   ssc_profile,
    input  wire         ssc_en,

    // ?? Device Configuration ?????????????????????????????????????????????????
    input  wire [7:0]   local_speed_cap,
    input  wire [5:0]   local_width_cap,
    input  wire [7:0]   local_lane_id,

    // ?? DLL Configuration ????????????????????????????????????????????????????
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

    // ?? AER / Error Status ???????????????????????????????????????????????????
    output wire [31:0]  aer_status,
    output wire         aer_int,
    output wire [255:0] err_msg_tlp,
    output wire         err_msg_valid,

    // ?? Status / Debug ???????????????????????????????????????????????????????
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

// =============================================================================
// [A]  INTER-LAYER WIRES
// =============================================================================

// ?? A1: PHY ? DLL (RX path: PHY ? DLL) ??????????????????????????????????????
// PHY outputs the recovered FLIT TLP/DLLP on tlp_rx_out / dllp_rx_out.
// DLL takes these on phy_rxd / phy_rx_valid (simplified 256-bit beat).
// We route tlp_rx_out[255:0] as the phy_rxd beat (first 256 bits of the 1024-bit TLP bus).
wire [1023:0] phy_tlp_rx_w;
wire          phy_tlp_rx_valid_w;
// FIX-SYS-1: Wire from DLL RX path (seq_checker output) to TL RX input.
// dll_tlp_to_tl_w carries the CRC-checked, sequence-checked TLP payload
// that the DLL receives from the link partner. This is the correct source
// for the TL RX pipeline (HDR_PARSE ? MAL_CHK ? RX_RTR ? handlers).
wire [1023:0] dll_rx_to_tl_w;
wire          dll_rx_to_tl_valid_w;
wire [63:0]   phy_dllp_rx_w;
wire          phy_dllp_rx_valid_w;
wire          phy_dl_up_w;
wire          phy_dl_down_w;

// DLL phy_rxd is 256-bit beat; map lower 256b of the 1024-bit PHY TLP bus.
// FIX-SYS-3 (FIXED): PHY bypass is now gated by SIM_BYPASS parameter.
// SIM_BYPASS=1 (simulation only): allows direct PIPE inject to DLL,
//              bypassing FEC+FLIT deframer — needed for TB inject_tlp().
// SIM_BYPASS=0 (default / all real hardware): RX data always flows through
//              the full PHY pipeline (FEC decoder -> FLIT deframer -> DLL).
wire [255:0]  dll_phy_rxd_w      = (SIM_BYPASS && pipe_rx_valid)
                                    ? pipe_rxd
                                    : phy_tlp_rx_w[255:0];
wire          dll_phy_rx_valid_w = (SIM_BYPASS && pipe_rx_valid)
                                    ? pipe_rx_valid
                                    : (phy_tlp_rx_valid_w | phy_dllp_rx_valid_w);

// ?? A2: PHY ? DLL (TX path: DLL ? PHY) ??????????????????????????????????????
wire [255:0]  dll_phy_txd_w;
wire          dll_phy_tx_valid_w;
wire          dll_phy_tx_elec_idle_w;
wire          dll_phy_tx_compliance_w;

// ?? A3: PHY status signals to DLL ????????????????????????????????????????????
// fec_syndrome[15:0] from fec_err_count_o (stub; full syndrome bus would come
// from pcie_gen6_phy_top's internal fec_syndrome wire ? not yet exposed).
// FIX-STUB-1: driven from pcie_gen6_phy_top fec_syndrome_o / fec_corrected_o outputs
wire [15:0]   dll_fec_syndrome_w;   // assigned after u_phy_top instantiation
wire          dll_fec_corrected_w;  // assigned after u_phy_top instantiation

// ?? A4: DLL ? TL ?????????????????????????????????????????????????????????????
// TL ? DLL (TX)
wire [2047:0] tl_flit_to_dll_w;
wire          tl_flit_to_dll_valid_w;
wire          tl_dll_ready_w;

// DLL ? TL (RX)
wire [1023:0] dll_tlp_to_tl_w;
wire          dll_tlp_to_tl_valid_w;

// DLL status ? TL
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

// TL control outputs not consumed internally (stubs)
// FIX-SYS-2: Generate a ONE-SHOT cr_update pulse when dll_up_to_tl first asserts.
// TL fc_init_fsm.initfc_rx_valid must be a pulse, not a level, so it doesn't
// repeatedly trigger the rx_type case and confuse all_ifc1 detection.
reg   dll_up_prev_r;
always @(posedge clk or negedge rst_n)
    if (!rst_n) dll_up_prev_r <= 1'b0;
    else        dll_up_prev_r <= dll_up_to_tl_w;
wire dll_up_rise = dll_up_to_tl_w & ~dll_up_prev_r;  // rising edge of dll_up_to_tl

// FIX-STUB-3: UpdateFC credit values driven from dll_top RX decoder outputs.
// Declarations must precede cr_update_w which references them.
wire [7:0]    fc_update_ph_w;    // assigned from dll_top.fc_update_ph_rx_o
wire [11:0]   fc_update_pd_w;    // assigned from dll_top.fc_update_pd_rx_o
wire [7:0]    fc_update_nph_w;   // assigned from dll_top.fc_update_nph_rx_o
wire [7:0]    fc_update_cplh_w;  // assigned from dll_top.fc_update_cplh_rx_o
wire [11:0]   fc_update_cpld_w;  // assigned from dll_top.fc_update_cpld_rx_o
wire          fc_update_valid_w; // assigned from dll_top.fc_update_valid_rx_o

// cr_update_w layout matches pcie_tl_top cr_update decompose:
//   [71:64]=ph [63:56]=pd [55:48]=nph [47:40]=npd [39:32]=cplh [31:24]=cpld [23:0]=unused
wire [71:0]   cr_update_w = {fc_update_ph_w,
                              fc_update_pd_w[7:0],
                              fc_update_nph_w,
                              8'd0,          // NPD: infinite credits (no NPD UpdateFC)
                              fc_update_cplh_w,
                              fc_update_cpld_w[7:0],
                              8'd0};
wire          cr_update_valid_w = fc_update_valid_w | dll_up_rise;  // UpdateFC or link-up pulse
wire          dll_ack_w         = dll_up_to_tl_w;  // ACK = link active
wire          dll_nak_w         = 1'b0;

// ?? A5: PHY ? DLL LTSSM signals ??????????????????????????????????????????????
wire [5:0]    phy_ltssm_state_w;
wire [3:0]    phy_link_speed_w;
wire [5:0]    phy_link_width_w;

// ?? A6: DLL ? PHY (link_down_req / dll_up_req) ???????????????????????????????
wire          dll_link_down_req_w  = replay_rollover_err_w | dll_error_w;
wire          phy_dll_up_req_w     = dll_up_to_tl_w;

// ?? A7: PHY TX data (TLP from TL passed through DLL to PHY) ??????????????????
// PHY receives TLP data directly from the TL's flit_to_dll bus (FLIT framed).
// tlp_data port on phy_top receives the first 1024b slice.
wire [1023:0] phy_tlp_data_w    = tl_flit_to_dll_w[1023:0];
wire          phy_tlp_valid_w   = tl_flit_to_dll_valid_w;
// DLLP port: DLL generates DLLPs; stub as zero (DLL handles internally).
// FIX-STUB-2: DLL DLLP arbiter output now feeds PHY flit_framer_tx for Gen6 co-packing
// These are driven from dll_top outputs after u_dll_top instantiation
wire [63:0]   phy_dllp_data_w;   // assigned from dll_top.dllp_arb_out_o
wire          phy_dllp_valid_w;  // assigned from dll_top.dllp_arb_valid_o

// =============================================================================
// [B]  PHYSICAL LAYER INSTANTIATION
// =============================================================================

pcie_gen6_phy_top #(
    .NUM_LANES  (NUM_LANES),
    .DATA_WIDTH (DATA_WIDTH),
    .BYPASS_FEC (BYPASS_FEC)   // FIX-STUB-4
) u_phy_top (
    // Clocks & Resets
    .clk                    (clk),
    .clk_pipe               (clk_pipe),
    .clk_ser                (clk_ser),
    .rst_n                  (rst_n),
    .perst_n                (perst_n),
    .power_good             (power_good),
    .clk_valid              (clk_valid),
    .ssc_ref_clk            (ssc_ref_clk),

    // PIPE RX
    .pipe_rxd               (pipe_rxd),
    .pipe_rxdatak           (pipe_rxdatak),
    .pipe_rx_valid          (pipe_rx_valid),
    .pipe_rx_status         (pipe_rx_status),
    .pipe_rx_elec_idle      (pipe_rx_elec_idle),
    .pipe_phystatus         (pipe_phystatus),

    // PIPE TX
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

    // DLL/TL TX input (TLP from TL, DLLP from DLL ? stubs)
    .tlp_data               (phy_tlp_data_w),
    .tlp_valid              (phy_tlp_valid_w),
    .dllp_data              (phy_dllp_data_w),
    .dllp_valid             (phy_dllp_valid_w),
    .dll_up_req             (phy_dll_up_req_w),
    .link_down_req          (dll_link_down_req_w),

    // RX outputs ? DLL
    .tlp_rx_out             (phy_tlp_rx_w),
    .tlp_rx_valid           (phy_tlp_rx_valid_w),
    .dllp_rx_out            (phy_dllp_rx_w),
    .dllp_rx_valid          (phy_dllp_rx_valid_w),
    .dl_up                  (phy_dl_up_w),
    .dl_down                (phy_dl_down_w),

    // Power Management
    .pm_req                 (pm_req),
    .hot_reset_req_sw       (hot_reset_req_sw),
    .disable_req_sw         (disable_req_sw),
    .compliance_req         (compliance_req),
    .l0s_entry_limit        (l0s_entry_limit),
    .l1_entry_limit         (l1_entry_limit),

    // SSC
    .ssc_profile            (ssc_profile),
    .ssc_en                 (ssc_en),

    // Device Config
    .local_speed_cap        (local_speed_cap),
    .local_width_cap        (local_width_cap),
    .local_lane_id          (local_lane_id),

    // Status/Debug
    .ltssm_state_o          (phy_ltssm_state_w),
    .link_speed_o           (phy_link_speed_w),
    .link_width_o           (phy_link_width_w),
    .rst_done_o             (rst_done_o),
    .fec_err_count_o        (fec_err_count_o),
    .ssc_active_o           (ssc_active_o),
    // FIX-STUB-1: connect FEC syndrome outputs
    .fec_syndrome_o         (dll_fec_syndrome_w),
    .fec_corrected_o        (dll_fec_corrected_w)
);

// =============================================================================
// [C]  DATA LINK LAYER INSTANTIATION
// =============================================================================

dll_top u_dll_top (
    .clk                    (clk),
    .rst_n                  (rst_n),

    // PHY RX interface
    .phy_rxd                (dll_phy_rxd_w),
    .phy_rx_valid           (dll_phy_rx_valid_w),
    .phy_rx_status          (pipe_rx_status),
    .fec_syndrome           (dll_fec_syndrome_w),
    .fec_corrected          (dll_fec_corrected_w),

    // PHY TX interface
    .phy_txd                (dll_phy_txd_w),
    .phy_tx_valid           (dll_phy_tx_valid_w),
    .phy_tx_elec_idle       (dll_phy_tx_elec_idle_w),
    .phy_tx_compliance      (dll_phy_tx_compliance_w),

    // TL interface (TX: TL ? DLL)
    .tlp_from_tl            (1024'b0),                  // FIX-SYS-1: TX from TL not connected here (goes via flit path)
    .tlp_from_tl_valid      (1'b0),
    .flit_from_tl           (tl_flit_to_dll_w),
    .flit_from_tl_valid     (tl_flit_to_dll_valid_w),
    .fc_update_ph           (fc_update_ph_w),
    .fc_update_valid        (fc_update_valid_w),

    // TL interface (RX: DLL ? TL)
    .tlp_to_tl              (dll_rx_to_tl_w),          // FIX-SYS-1: RX TLPs from link partner
    .tlp_to_tl_valid        (dll_rx_to_tl_valid_w),

    // LTSSM interface (from PHY)
    .ltssm_dl_up            (phy_dl_up_w),
    .ltssm_dl_down          (phy_dl_down_w),
    .ltssm_speed            (phy_link_speed_w),
    .ltssm_width            (phy_link_width_w),

    // PHY TX control
    .tx_elec_idle_req       (1'b0),
    .tx_compliance_req      (compliance_req),

    // Mode & Config
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

    // Status outputs
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
    // FIX-STUB-2: DLLP arbiter outputs for PHY flit co-packing
    .dllp_arb_out_o         (phy_dllp_data_w),
    .dllp_arb_valid_o       (phy_dllp_valid_w),
    // FIX-STUB-3: UpdateFC RX values for TL credit manager
    .fc_update_ph_rx_o      (fc_update_ph_w),
    .fc_update_pd_rx_o      (fc_update_pd_w),
    .fc_update_nph_rx_o     (fc_update_nph_w),
    .fc_update_cplh_rx_o    (fc_update_cplh_w),
    .fc_update_cpld_rx_o    (fc_update_cpld_w),
    .fc_update_valid_rx_o   (fc_update_valid_w)
);

// =============================================================================
// [D]  TRANSACTION LAYER INSTANTIATION
// =============================================================================

pcie_tl_top u_tl_top (
    .clk                    (clk),
    .rst_n                  (rst_n),

    // User Logic Interface
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

    // DLL Boundary
    .dll_ack                (dll_ack_w),
    .dll_nak                (dll_nak_w),
    .dll_up                 (dll_up_to_tl_w),
    .dll_err_to_aer         (dll_err_to_aer_w),  // FIX-AER: DLL errors → TL AER logger
    .dll_err_valid          (dll_err_valid_w),   // FIX-AER: pulse gate
    .cr_update              (cr_update_w),
    .cr_update_valid        (cr_update_valid_w),
    // FIX-SYS-1: Direct DLL RX TLP path to TL (bypasses DLL_IF cr_update hack)
    .dll_tlp_rx_direct      (dll_rx_to_tl_w),
    .dll_tlp_rx_direct_valid(dll_rx_to_tl_valid_w),

    .flit_to_dll            (tl_flit_to_dll_w),
    .flit_to_dll_valid      (tl_flit_to_dll_valid_w),
    .dll_ready              (tl_dll_ready_w),

    // Config Space
    .tlp_cfg_in             (tlp_cfg_in),
    .tlp_cfg_valid          (tlp_cfg_valid),
    .cfg_addr               (cfg_addr),
    .cfg_wr_data            (cfg_wr_data),
    .cfg_wr_en              (cfg_wr_en),
    .cfg_rd_data            (cfg_rd_data),
    .cfg_rd_valid           (cfg_rd_valid),

    // AER / Error Status
    .aer_status             (aer_status),
    .aer_int                (aer_int),
    .err_msg_tlp            (err_msg_tlp),
    .err_msg_valid          (err_msg_valid),

    // VC Arbiter
    .vc0_req                (vc0_req),
    .vc1_req                (vc1_req),
    .vc2_req                (vc2_req),
    .vc3_req                (vc3_req),
    .vc_arb_scheme          (vc_arb_scheme),
    .vc_weight              (vc_weight),
    .vc_grant               (vc_grant),
    .vc_grant_id            (vc_grant_id),
    .vc_arb_valid           (vc_arb_valid),

    // Debug / Status
    .fc_init_done_out       (fc_init_done_o),
    .ordering_ok_out        (ordering_ok_o),
    .tag_exhausted_out      (tag_exhausted_o),
    .outstanding_count_out  (outstanding_count_o)
);

// =============================================================================
// [E]  TOP-LEVEL OUTPUT ASSIGNMENTS
// =============================================================================
assign ltssm_state_o = phy_ltssm_state_w;
assign link_speed_o  = phy_link_speed_w;
assign link_width_o  = phy_link_width_w;
assign dll_up_o      = dll_up_to_tl_w;
assign dll_error_o   = dll_error_w;
assign link_state_o  = link_state_w;

endmodule
// =============================================================================
// End of pcie_gen6_system_top.v
// =============================================================================
