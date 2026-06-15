###############################################################################
#            Formality — DLL  (RTL  vs  Synthesized Netlist)
#            Modeled on the UART_TX formality flow.
###############################################################################

##======================= Standard-cell libraries (.db) =====================##
set SSLIB "/home/IC/PCIE_GEN_6/std_cells/scmetro_tsmc_cl013g_rvt_ss_1p08v_125c.db"
set TTLIB "/home/IC/PCIE_GEN_6/std_cells/scmetro_tsmc_cl013g_rvt_tt_1p2v_25c.db"
set FFLIB "/home/IC/PCIE_GEN_6/std_cells/scmetro_tsmc_cl013g_rvt_ff_1p32v_m40c.db"

##============================ RTL source files =============================##
set RTL "/home/IC/PCIE_GEN_6/rtl"

set RTL_FILES [list \
  "$RTL/DLL/tx_datapath_mux.v"        "$RTL/DLL/rx_datapath_demux.v" \
  "$RTL/DLL/scrambler.v"              "$RTL/DLL/Descrambler.v" \
  "$RTL/DLL/crc_gen.v"               "$RTL/DLL/dllp_crc_gen.v" \
  "$RTL/DLL/dllp_crc_chk.v"          "$RTL/DLL/lcrc_flit_crc_chk.v" \
  "$RTL/DLL/seq_num_gen.v"           "$RTL/DLL/seq_num_checker_rx.v" \
  "$RTL/DLL/ack_nak_receiver.v"      "$RTL/DLL/ack_nak_scheduler_tx.v" \
  "$RTL/DLL/ack_pgb.v"               "$RTL/DLL/ack_tmr.v" \
  "$RTL/DLL/retry_buf.v"             "$RTL/DLL/replay_fsm.v" \
  "$RTL/DLL/dllp_gen.v"              "$RTL/DLL/dllp_arb.v" \
  "$RTL/DLL/dllp_receiver_decoder.v" "$RTL/DLL/dllp_mal_chk.v" \
  "$RTL/DLL/flit_null_slot_inserter.v" "$RTL/DLL/flit_rx_deframer.v" \
  "$RTL/DLL/flit_seq.v"              "$RTL/DLL/fc_init_fsm.v" \
  "$RTL/DLL/fc_tmr.v"                "$RTL/DLL/fc_wdg.v" \
  "$RTL/DLL/lbw_fsm.v"               "$RTL/DLL/nullified_tlp_handler.v" \
  "$RTL/DLL/dll_err.v"               "$RTL/DLL/dll_init.v" \
  "$RTL/DLL/pm_fsm.v"                "$RTL/DLL/pm_tmr.v" \
  "$RTL/DLL/nop_gen.v"               "$RTL/DLL/pcie6_phy_tx.v" \
  "$RTL/DLL/phy_interface_rx.v"      "$RTL/DLL/tl_interface.v" \
  "$RTL/TOP/dll_top.v" ]

##============================== Guidance ===================================##
# Enable Synopsys auto-setup (valid var name has NO leading underscore).
set_app_var synopsys_auto_setup true

# SVF written by Design Compiler. MUST be loaded so Formality understands DC's
# optimizations (compile_ultra retiming / register opt). Load it BEFORE reading
# the designs. Ensure synthesis ran with:  set_svf <this same path>
set_svf "/home/IC/PCIE_GEN_6/syn/DLL_SYN.svf"

##======================= Reference container (RTL) ========================##
read_verilog -container ref -libname WORK -05 $RTL_FILES
read_db -container ref [list $SSLIB $TTLIB $FFLIB]
set_reference_design ref:/WORK/dll_top
set_top dll_top

##==================== Implementation container (Netlist) ==================##
read_verilog -container impl -libname WORK -netlist "/home/IC/PCIE_GEN_6/syn/DLL_SYN.v"
read_db -container impl [list $SSLIB $TTLIB $FFLIB]
set_implementation_design impl:/WORK/dll_top
set_top dll_top

##============================ Match & Verify ==============================##
match

set successful [verify]

##============================== Reports ===================================##
report_status            > rpt/DLL_FM_status.rpt
report_verify            > rpt/DLL_FM_verify.rpt
report_unmatched_points  > rpt/DLL_FM_unmatched.rpt
report_failing_points    > rpt/DLL_FM_failing_points.rpt

if {$successful} {
    puts "############################################################"
    puts "#   FORMAL VERIFICATION PASSED — RTL matches Netlist        #"
    puts "############################################################"
} else {
    puts "############################################################"
    puts "#   FORMAL VERIFICATION FAILED — see rpt/ for details       #"
    puts "############################################################"
}
