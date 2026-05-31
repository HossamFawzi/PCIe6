####################################################################################
# Constraints
# Project  : PCIe Gen 6 – Full-Stack (PHY + DLL + TL + TOP)
# Top      : pcie_gen6_system_top
# Std      : PCIe Base Specification 6.0
# Tool     : Synopsys Design Compiler (dc_shell)
# Library  : TSMC CL013G RVT (SS/TT/FF corners)
#
# Clock Architecture (3 domains):
#   clk       – Core logic clock  (250 MHz  →  4.0 ns period)
#   clk_pipe  – PIPE interface    (500 MHz  →  2.0 ns period)
#   clk_ser   – Serialiser/PAM4  (2000 MHz →  0.5 ns period)
#   ssc_ref_clk – SSC reference  (100  MHz → 10.0 ns period)
#
# Sections:
#   0.  DC Variables
#   1.  Master Clock Definitions
#   2.  Generated Clock Definitions  (none – all clocks are board-supplied)
#   3.  Preserve Clock & Reset Networks
#   4.  Clock Relationships (domain crossings)
#   5.  Input / Output Delays
#   6.  Driving Cells
#   7.  Output Loads
#   8.  Operating Conditions (OCV corners)
#   9.  Wire-Load Model
#
# Changes vs previous version:
#   - Section numbering corrected (was inconsistent 0/1/2/3/4/5/6/7/8/9)
#   - set_clock_groups now includes -name for DC traceability
#   - set_false_path added for async reset ports (rst_n / perst_n → all_registers)
#   - set_max_transition added per clock domain (guards SI on high-speed nets)
#   - set_max_fanout added (32 for core/pipe, 16 for ser)
#   - Output load for wide buses increased to 3.0 pF (512-bit FLIT buses)
#   - Wire-load comment updated: wl50 upgrade trigger clarified
####################################################################################

           #########################################################
                  #### Section 0 : DC Variables ####
           #########################################################

# Prevent assign statements in the netlist; insert buffers on constants/feedthroughs
set_fix_multiple_port_nets -all -buffer_constants -feedthroughs

####################################################################################
           #########################################################
                  #### Section 1 : Master Clock Definitions ####
           #########################################################
####################################################################################

# ---------------------------------------------------------------------------
# CLK – Core logic clock  (250 MHz → 4.0 ns)
#   Drives: all RTL registers across PHY/DLL/TL layers
# ---------------------------------------------------------------------------
set CLK_NAME          clk
set CLK_PER           4.0
set CLK_SETUP_SKEW    0.10
set CLK_HOLD_SKEW     0.05
set CLK_LAT           0.0
set CLK_RISE          0.05
set CLK_FALL          0.05

create_clock -name $CLK_NAME \
             -period $CLK_PER \
             -waveform "0 [expr {$CLK_PER / 2.0}]" \
             [get_ports clk]

set_clock_uncertainty -setup $CLK_SETUP_SKEW [get_clocks $CLK_NAME]
set_clock_uncertainty -hold  $CLK_HOLD_SKEW  [get_clocks $CLK_NAME]
set_clock_transition  -rise  $CLK_RISE        [get_clocks $CLK_NAME]
set_clock_transition  -fall  $CLK_FALL        [get_clocks $CLK_NAME]
set_clock_latency     $CLK_LAT               [get_clocks $CLK_NAME]

# ---------------------------------------------------------------------------
# CLK_PIPE – PIPE PHY interface clock  (500 MHz → 2.0 ns)
#   Drives: pipe_interface_ctrl, pipe_rx_interface_ctrl, pipe_tx,
#           tx/rx_gear_box, rx_elastic_buffer_slip, tx_elastic_buffer
# ---------------------------------------------------------------------------
set CLK_PIPE_NAME         clk_pipe
set CLK_PIPE_PER          2.0
set CLK_PIPE_SETUP_SKEW   0.08
set CLK_PIPE_HOLD_SKEW    0.04
set CLK_PIPE_LAT          0.0
set CLK_PIPE_RISE         0.04
set CLK_PIPE_FALL         0.04

create_clock -name $CLK_PIPE_NAME \
             -period $CLK_PIPE_PER \
             -waveform "0 [expr {$CLK_PIPE_PER / 2.0}]" \
             [get_ports clk_pipe]

set_clock_uncertainty -setup $CLK_PIPE_SETUP_SKEW [get_clocks $CLK_PIPE_NAME]
set_clock_uncertainty -hold  $CLK_PIPE_HOLD_SKEW  [get_clocks $CLK_PIPE_NAME]
set_clock_transition  -rise  $CLK_PIPE_RISE        [get_clocks $CLK_PIPE_NAME]
set_clock_transition  -fall  $CLK_PIPE_FALL        [get_clocks $CLK_PIPE_NAME]
set_clock_latency     $CLK_PIPE_LAT               [get_clocks $CLK_PIPE_NAME]

# ---------------------------------------------------------------------------
# CLK_SER – High-speed serialiser / PAM4 clock  (2000 MHz → 0.5 ns)
#   Drives: fec_encoder_rs, fec_rs_decoder, encoder/decoder_128b130b,
#           pam4_gray_enc, pam4_gray_code_decoder, fec_syndrome_calculator
#   NOTE:  Only combinational cones are clocked by clk_ser in this RTL
#          style.  If PAM4/FEC cells contain flip-flops on this clock,
#          tighten CLK_SER_SETUP_SKEW to ≤ 0.03 ns.
# ---------------------------------------------------------------------------
set CLK_SER_NAME         clk_ser
set CLK_SER_PER          0.5
set CLK_SER_SETUP_SKEW   0.05
set CLK_SER_HOLD_SKEW    0.02
set CLK_SER_LAT          0.0
set CLK_SER_RISE         0.02
set CLK_SER_FALL         0.02

create_clock -name $CLK_SER_NAME \
             -period $CLK_SER_PER \
             -waveform "0 [expr {$CLK_SER_PER / 2.0}]" \
             [get_ports clk_ser]

set_clock_uncertainty -setup $CLK_SER_SETUP_SKEW [get_clocks $CLK_SER_NAME]
set_clock_uncertainty -hold  $CLK_SER_HOLD_SKEW  [get_clocks $CLK_SER_NAME]
set_clock_transition  -rise  $CLK_SER_RISE        [get_clocks $CLK_SER_NAME]
set_clock_transition  -fall  $CLK_SER_FALL        [get_clocks $CLK_SER_NAME]
set_clock_latency     $CLK_SER_LAT               [get_clocks $CLK_SER_NAME]

# ---------------------------------------------------------------------------
# SSC reference clock  (100 MHz → 10.0 ns)
#   Used by ssc_ctrl only; mark ideal so DC does not try to propagate it.
# ---------------------------------------------------------------------------
set CLK_SSC_NAME         ssc_ref_clk
set CLK_SSC_PER          10.0

create_clock -name $CLK_SSC_NAME \
             -period $CLK_SSC_PER \
             -waveform "0 [expr {$CLK_SSC_PER / 2.0}]" \
             [get_ports ssc_ref_clk]

set_ideal_network [get_ports ssc_ref_clk]

####################################################################################
           #########################################################
           #### Section 2 : Generated Clock Definitions ####
           #########################################################
####################################################################################
# All clocks are externally supplied; no generated clocks required.
# If a PLL/DLL is added inside the boundary, add create_generated_clock here.

####################################################################################
           #########################################################
           #### Section 3 : Preserve Clock & Reset Networks ####
           #########################################################
####################################################################################

# Do not touch clock and reset networks – driven by CTS tool post-synthesis
set_dont_touch_network [get_ports {clk clk_pipe clk_ser ssc_ref_clk}]
set_dont_touch_network [get_ports {rst_n perst_n}]

# Resets are asynchronous to all register clocks; cut timing arcs to avoid
# false setup/hold violations on the reset release path.
set_false_path -from [get_ports {rst_n perst_n}] -to [all_registers]

####################################################################################
           #########################################################
                  #### Section 4 : Clock Relationships ####
           #########################################################
####################################################################################

# All four clocks are asynchronous to each other (independent board/PLL sources).
# CDC paths are handled by synchronisers in the RTL; tell DC not to analyse them.
set_clock_groups -name async_domains -asynchronous \
    -group [get_clocks $CLK_NAME]      \
    -group [get_clocks $CLK_PIPE_NAME] \
    -group [get_clocks $CLK_SER_NAME]  \
    -group [get_clocks $CLK_SSC_NAME]


####################################################################################
           #########################################################
             #### Section 4b : Transition & Fanout Constraints ####
           #########################################################
####################################################################################

# ── set_max_transition ────────────────────────────────────────────────────────
# Guards Signal Integrity (SI) on high-speed nets.
# Rule: max_transition ≤ 10 % of the clock period for each domain.
# clk      (4.0 ns)  → 0.40 ns ; clk_pipe (2.0 ns) → 0.20 ns
# clk_ser  (0.5 ns)  → 0.05 ns ; ssc      (10  ns)  → 1.00 ns
set_max_transition 0.40 [get_clocks $CLK_NAME]
set_max_transition 0.20 [get_clocks $CLK_PIPE_NAME]
set_max_transition 0.05 [get_clocks $CLK_SER_NAME]
set_max_transition 1.00 [get_clocks $CLK_SSC_NAME]

# ── set_max_fanout ────────────────────────────────────────────────────────────
# Limits the number of loads on any net.  High-speed clocks use tighter limits.
# Values: 32 for core/pipe (per header comment), 16 for ser.
# Apply to the current_design so DC buffers any net that exceeds the limit.
set_max_fanout 32 [get_clocks $CLK_NAME]
set_max_fanout 32 [get_clocks $CLK_PIPE_NAME]
set_max_fanout 16 [get_clocks $CLK_SER_NAME]

####################################################################################
           #########################################################
             #### Section 5 : Input / Output Delays ####
           #########################################################
#
#   Convention: 30 % of the relevant clock period for both input and output delays.
#   Ports driven/sampled by clk_pipe use CLK_PIPE_PER.
#   Control/config/status ports use CLK_PER (core clock).
####################################################################################

# ── Input delays (30 % of period) ────────────────────────────────────────────
set in_dly_core [expr {0.3 * $CLK_PER}]        ;# 1.2 ns
set in_dly_pipe [expr {0.3 * $CLK_PIPE_PER}]   ;# 0.6 ns

# ── Output delays (30 % of period) ───────────────────────────────────────────
set out_dly_core [expr {0.3 * $CLK_PER}]       ;# 1.2 ns
set out_dly_pipe [expr {0.3 * $CLK_PIPE_PER}]  ;# 0.6 ns

# ─── INPUTS : System control (clk domain) ────────────────────────────────────
# NOTE: rst_n and perst_n also have set_dont_touch_network (Section 3).
# set_input_delay is still valid here: DC uses it for timing-arc analysis
# even when buffer insertion is suppressed.  Both constraints are intentional.
set_input_delay $in_dly_core -clock $CLK_NAME [get_ports {
    rst_n
    perst_n
    power_good
    clk_valid
}]

# ─── INPUTS : PIPE RX interface (clk_pipe domain) ────────────────────────────
set_input_delay $in_dly_pipe -clock $CLK_PIPE_NAME [get_ports {
    pipe_rxd
    pipe_rxdatak
    pipe_rx_valid
    pipe_rx_status
    pipe_rx_elec_idle
    pipe_phystatus
}]

# ─── INPUTS : User-logic / TL interface (clk domain) ─────────────────────────
set_input_delay $in_dly_core -clock $CLK_NAME [get_ports {
    req_type
    req_addr
    req_len
    req_data
    req_valid
    req_attr
    req_tc
    req_first_be
    req_last_be
}]

# ─── INPUTS : Config space (clk domain) ──────────────────────────────────────
set_input_delay $in_dly_core -clock $CLK_NAME [get_ports {
    tlp_cfg_in
    tlp_cfg_valid
    cfg_addr
    cfg_wr_data
    cfg_wr_en
}]

# ─── INPUTS : VC Arbiter (clk domain) ────────────────────────────────────────
set_input_delay $in_dly_core -clock $CLK_NAME [get_ports {
    vc0_req
    vc1_req
    vc2_req
    vc3_req
    vc_arb_scheme
    vc_weight
}]

# ─── INPUTS : Power Management & Control (clk domain) ────────────────────────
set_input_delay $in_dly_core -clock $CLK_NAME [get_ports {
    pm_req
    hot_reset_req_sw
    disable_req_sw
    compliance_req
    l0s_entry_limit
    l1_entry_limit
}]

# ─── INPUTS : SSC Control (ssc_ref_clk domain) ───────────────────────────────
set_input_delay 1.0 -clock $CLK_SSC_NAME [get_ports {
    ssc_profile
    ssc_en
}]

# ─── INPUTS : Device & Link Configuration (clk domain) ───────────────────────
set_input_delay $in_dly_core -clock $CLK_NAME [get_ports {
    local_speed_cap
    local_width_cap
    local_lane_id
}]

# ─── INPUTS : DLL Configuration (clk domain) ─────────────────────────────────
set_input_delay $in_dly_core -clock $CLK_NAME [get_ports {
    lfsr_seed
    scramble_en
    ack_freq
    ack_lat_limit
    replay_limit
    fc_timer_limit
    fc_watchdog_limit
    l0s_limit
    l1_limit
    pm_req_sw
}]

# ─── OUTPUTS : PIPE TX interface (clk_pipe domain) ───────────────────────────
set_output_delay $out_dly_pipe -clock $CLK_PIPE_NAME [get_ports {
    pipe_txd_o
    pipe_txdatak_o
    pipe_tx_elec_idle_o
    pipe_tx_compliance_o
    pipe_tx_swing_o
    pipe_powerdown_o
    pipe_rate_o
    pipe_txdetectrx_o
    pipe_pclkchangeack_o
    pipe_width_o
}]

# ─── OUTPUTS : User-logic / TL interface (clk domain) ────────────────────────
set_output_delay $out_dly_core -clock $CLK_NAME [get_ports {
    req_ready
    usr_cpl_data
    usr_cpl_valid
    usr_cpl_status
    usr_cpl_tag
    usr_mwr_data
    usr_mwr_valid
    usr_mwr_addr
}]

# ─── OUTPUTS : Config Space (clk domain) ─────────────────────────────────────
set_output_delay $out_dly_core -clock $CLK_NAME [get_ports {
    cfg_rd_data
    cfg_rd_valid
}]

# ─── OUTPUTS : VC Arbiter (clk domain) ───────────────────────────────────────
set_output_delay $out_dly_core -clock $CLK_NAME [get_ports {
    vc_grant
    vc_grant_id
    vc_arb_valid
}]

# ─── OUTPUTS : AER / Error Status (clk domain) ───────────────────────────────
set_output_delay $out_dly_core -clock $CLK_NAME [get_ports {
    aer_status
    aer_int
    err_msg_tlp
    err_msg_valid
}]

# ─── OUTPUTS : Status & Debug (clk domain) ───────────────────────────────────
set_output_delay $out_dly_core -clock $CLK_NAME [get_ports {
    ltssm_state_o
    link_speed_o
    link_width_o
    rst_done_o
    fec_err_count_o
    ssc_active_o
    dll_up_o
    dll_error_o
    link_state_o
    fc_init_done_o
    ordering_ok_o
    tag_exhausted_o
    outstanding_count_o
}]

####################################################################################
           #########################################################
                  #### Section 6 : Driving Cells ####
           #########################################################
####################################################################################

# All data/control inputs modelled as driven by BUFX2M (SS worst-case corner)

# PIPE RX – high-speed data bus (clk_pipe domain)
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX4M -pin Y \
    [get_ports {pipe_rxd pipe_rxdatak}]

set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {pipe_rx_valid pipe_rx_status pipe_rx_elec_idle pipe_phystatus}]

# User-logic request bus
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX4M -pin Y \
    [get_ports {req_data req_addr}]

set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {req_type req_len req_valid req_attr req_tc req_first_be req_last_be}]

# Config space
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {tlp_cfg_in tlp_cfg_valid cfg_addr cfg_wr_data cfg_wr_en}]

# VC arbiter & PM inputs
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {vc0_req vc1_req vc2_req vc3_req vc_arb_scheme vc_weight}]

set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {pm_req hot_reset_req_sw disable_req_sw compliance_req
                l0s_entry_limit l1_entry_limit}]

# SSC
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {ssc_profile ssc_en}]

# Device/link config
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {local_speed_cap local_width_cap local_lane_id}]

# DLL config
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {lfsr_seed scramble_en ack_freq ack_lat_limit replay_limit
                fc_timer_limit fc_watchdog_limit l0s_limit l1_limit pm_req_sw}]

# Resets & control
set_driving_cell \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c \
    -lib_cell BUFX2M -pin Y \
    [get_ports {rst_n perst_n power_good clk_valid}]

####################################################################################
           #########################################################
                  #### Section 7 : Output Loads ####
           #########################################################
####################################################################################

# Wide buses (512-bit FLIT / 256-bit data) driven off-chip → heavier load model
# FIX: increased to 3.0 pF to better model PCB+connector load on 512-bit FLIT bus
set_load 3.0 [get_ports {
    pipe_txd_o
    usr_cpl_data
    usr_mwr_data
    err_msg_tlp
}]

# Narrow status/control outputs
set_load 0.5 [get_ports {
    pipe_txdatak_o
    pipe_tx_elec_idle_o
    pipe_tx_compliance_o
    pipe_tx_swing_o
    pipe_powerdown_o
    pipe_rate_o
    pipe_txdetectrx_o
    pipe_pclkchangeack_o
    pipe_width_o
    req_ready
    usr_cpl_valid
    usr_cpl_status
    usr_cpl_tag
    usr_mwr_valid
    usr_mwr_addr
    cfg_rd_data
    cfg_rd_valid
    vc_grant
    vc_grant_id
    vc_arb_valid
    aer_status
    aer_int
    err_msg_valid
    ltssm_state_o
    link_speed_o
    link_width_o
    rst_done_o
    fec_err_count_o
    ssc_active_o
    dll_up_o
    dll_error_o
    link_state_o
    fc_init_done_o
    ordering_ok_o
    tag_exhausted_o
    outstanding_count_o
}]

####################################################################################
           #########################################################
                  #### Section 8 : Operating Conditions ####
           #########################################################
####################################################################################

# Max (setup) analysis  → Slow-Slow  corner  (SS 1.08 V, 125 °C)
# Min (hold)  analysis  → Fast-Fast  corner  (FF 1.32 V, -40 °C)
set_operating_conditions \
    -min_library "scmetro_tsmc_cl013g_rvt_ff_1p32v_m40c" \
    -min         "scmetro_tsmc_cl013g_rvt_ff_1p32v_m40c" \
    -max_library "scmetro_tsmc_cl013g_rvt_ss_1p08v_125c" \
    -max         "scmetro_tsmc_cl013g_rvt_ss_1p08v_125c"

####################################################################################
           #########################################################
                  #### Section 9 : Wire-Load Model ####
           #########################################################
####################################################################################

# tsmc13_wl30 is appropriate for the projected die area of a multi-layer PCIe IP.
# Upgrade to wl50 if post-route wire-length reports show > 20 % underestimation
# on nets with fanout > 8 (typical trigger for a larger PCIe full-stack die).
set_wire_load_model \
    -name    tsmc13_wl30 \
    -library scmetro_tsmc_cl013g_rvt_ss_1p08v_125c

####################################################################################
#  End of cons.tcl
####################################################################################
