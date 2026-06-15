# =============================================================================
# run.do  —  PCIe Gen 6.0 Simulation Script (ModelSim / Questa)
# =============================================================================
# Usage (from Questa GUI  →  Transcript):
#   do run.do
#
# Or from command line (GUI stays open):
#   vsim -do run.do
#
# After simulation completes the GUI remains open.
# Coverage reports are written to:
#   coverage_summary.txt        — plain-text summary
#   coverage_report/index.html  — interactive HTML report (Questa only)
#
# Throughput benchmark output appears in the transcript under GROUP K.
# =============================================================================

# ── 1. Setup ─────────────────────────────────────────────────────────────────
quietly set DESIGN_DIR [file dirname [info script]]

# Work library — rebuild every run for a clean slate
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# ── 2. Compile RTL source files (Verilog-2001) ───────────────────────────────
set rtl_files {
    ack_nak_receiver.v
    ack_nak_scheduler_tx.v
    ack_pgb.v
    ack_tmr.v
    aer_error_logger.v
    arb_tx.v
    atomic_op_handler.v
    beacon_ei_logic.v
    block_align_sync_hdr_checker.v
    cfg_space_handler.v
    compl_gen.v
    completion_handler.v
    completion_queue.v
    compliance_eieos_sos_gen.v
    configuration_fsm.v
    cpl_timeout_logic.v
    cr_mgr.v
    crc_gen.v
    data_rate_adv.v
    data_rate_speed_change_fsm.v
    decoder_128b130b.v
    decoder_8b10b.v
    Descrambler.v
    detect_fsm.v
    dll_err.v
    dll_init.v
    DLL_INTERFACE.v
    dll_top.v
    dllp_arb.v
    dllp_crc_chk.v
    dllp_crc_gen.v
    dllp_gen.v
    dllp_mal_chk.v
    dllp_receiver_decoder.v
    ecrc.v
    eios.v
    encoder_128b130b.v
    encoder_8b10b.v
    fc_init_fsm.v
    fc_init_fsm_tl.v
    fc_init_timer.v
    fc_tmr.v
    fc_wdg.v
    fec_encoder_rs.v
    fec_rs_decoder.v
    fec_syndrome_calculator.v
    flit_deframer_rx.v
    flit_framer_tx.v
    flit_mode_controller.v
    flit_null_slot_inserter.v
    flit_rx_deframer.v
    flit_seq.v
    flit_sync_hdr_gen_checker.v
    fts.v
    fund_rst.v
    hot_rst.v
    hrst_fsm.v
    l0_l0s_fsm.v
    l1_fsm.v
    lane_deskew.v
    lane_pol.v
    lane_polarity_inversion_logic.v
    lane_rev.v
    lane_reversal_logic.v
    lb_fsm.v
    lbw_fsm.v
    lcrc_flit_crc_chk.v
    link_equalization_controller.v
    link_speed_neg.v
    link_width_neg.v
    ltssm_top.v
    message_handler.v
    nop_gen.v
    nullified_tlp_handler.v
    pam4_gray_code_decoder.v
    pam4_gray_enc.v
    pcie6_phy_tx.v
    pcie_gen6_phy_top.v
    pcie_gen6_system_top.v
    pcie_ordering_rob.v
    pcie_tl_top.v
    phy_interface_rx.v
    pipe_interface_ctrl.v
    pipe_rx_interface_ctrl.v
    pipe_tx.v
    pm_fsm.v
    pm_tmr.v
    poisoned_tlp_handler.v
    posted_write_handler.v
    pwr_tmr.v
    recovery_fsm.v
    replay_fsm.v
    req_q.v
    retry_buf.v
    ro_ctrl.v
    rx_datapath_demux.v
    rx_det.v
    rx_elastic_buffer_slip.v
    rx_gear_box.v
    rx_tlp_router.v
    scrambler.v
    seq_num_checker_rx.v
    seq_num_gen.v
    skp.v
    ssc_ctrl.v
    symbol_block_lock_fsm.v
    tag_manager.v
    tc_vc_mapper.v
    td_handler.v
    tl_interface.v
    tlp_assembler.v
    tlp_header_parser.v
    tlp_malformed_checker.v
    tlp_prefix_handler.v
    tmo_err_manager.v
    ts1_gen.v
    ts2_gen.v
    ts_det.v
    tx_datapath_mux.v
    tx_datapath_mux_dll.v
    tx_elastic_buffer.v
    tx_gear_box.v
    usr_if.v
    vc_arbiter.v
    {tb_pcie_gen6_system_top_fixed (2).v}
    POLLING_FSM.v
}

echo "=== Compiling RTL source files ==="
foreach f $rtl_files {
    set fpath [file join $DESIGN_DIR $f]
    if {[file exists $fpath]} {
        vlog +define+SIMULATION -work work "$fpath"
    } else {
        echo "WARNING: Source file not found: $fpath"
    }
}

# ── 3. Compile SystemVerilog testbench ───────────────────────────────────────
echo "=== Compiling SystemVerilog testbench ==="
vlog -sv +define+SIMULATION -work work \
    [file join $DESIGN_DIR "tb_pcie_gen6_sv.sv"]

# ── 4. Simulate with coverage ────────────────────────────────────────────────
echo "=== Starting simulation ==="

vsim -t 1ps          \
     -coverage        \
     +cover=bcesf     \
     -cvgperinstance  \
     +define+SIMULATION \
     work.tb_pcie_gen6_sv

# ── 5. Run to completion ──────────────────────────────────────────────────────
run -all

# ── 6. Coverage reports ───────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  COVERAGE SUMMARY"
echo "============================================================"

# Plain-text detailed report to transcript
coverage report -cvg -details

# Plain-text report saved to file
coverage report -cvg -details -output [file join $DESIGN_DIR coverage_summary.txt]
echo "  Text report  : coverage_summary.txt"

# HTML report (Questa 2019+ native command)
quietly set html_dir [file join $DESIGN_DIR coverage_report]
if {[catch {
    coverage report -cvg -details -html -output $html_dir
} err]} {
    # Fallback: use vcover for older Questa versions
    quietly set ucdb_file [file join $DESIGN_DIR sim_coverage.ucdb]
    coverage save $ucdb_file
    if {[catch {
        vcover report -html -output $html_dir $ucdb_file
    } err2]} {
        echo "  WARNING: HTML report generation failed: $err2"
        echo "  Text report available at: coverage_summary.txt"
    } else {
        echo "  HTML report  : coverage_report/index.html"
    }
} else {
    echo "  HTML report  : coverage_report/index.html"
}

echo "============================================================"
echo "  Simulation complete — QuestaSim remains open."
echo "  To re-run:  do run.do"
echo "  To exit:    quit"
echo "============================================================"

# NOTE: No 'quit' here — the GUI stays open so you can:
#   • Browse waveforms  (wave window)
#   • Explore coverage  (coverage browser)
#   • Re-run tests      (do run.do)
