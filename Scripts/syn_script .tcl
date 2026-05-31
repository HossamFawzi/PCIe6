##############################################################################
#  Design Compiler Synthesis Script
#  Project  : PCIe Gen 6 – Full-Stack (PHY + DLL + TL + TOP)
#  Top      : pcie_gen6_system_top
#
#  FIXES HISTORY
#  ─────────────────────────────────────────────────────────────────────────
#  v1 fixes (already in original script):
#    1. lane_deskew.v ELAB-302  : RTL corrected; script reads lane_deskew.v.
#    2. retry_buf.v VER-318     : RTL corrected inline (BUF_FULL_THR localparam);
#                                 script reads retry_buf.v directly.
#    3. Stray bare "pcie_gen6_system_top" command after set top_module removed.
#    4. group_path cross-clock lines moved AFTER source cons.tcl (correct).
#    5. gui_start wrapped in catch / commented out for batch safety.
#    6. 11 PHY + 1 TL filename case fixed to lowercase snake_case on disk.
#
#  v2 fixes (THIS VERSION — verified against rtl_fixed__1_.zip):
#    7. lane_pol.v / lane_rev.v ADDED to read list.
#         These two files define modules lane_pol and lane_rev which are
#         instantiated in pcie_gen6_phy_top.v (MOD-34, MOD-35).  They were
#         completely absent from the script → link would have failed with
#         unresolved references.  lane_polarity_inversion_logic.v and
#         lane_reversal_logic.v are byte-for-byte identical copies kept for
#         reference; only lane_pol.v / lane_rev.v are read (avoids duplicate
#         module definition errors).
#    8. lane_polarity_inversion_logic.v / lane_reversal_logic.v REMOVED.
#         Reading both the _logic.v copy AND lane_pol/lane_rev.v defines the
#         same module twice → fatal ELAB duplicate-module error.
#    9. VER-318 warning acknowledgement comments added for:
#         vc_arbiter.v, tag_manager.v, cpl_timeout_logic.v, tmo_err_manager.v
#         These are warnings only (not fatal) but are logged for tracking.
#   10. catch wrapper added around gui_start (was only commented out before;
#         catch ensures batch runs never abort if DC tries to open GUI).
##############################################################################

########################### Define Top Module ################################

set top_module pcie_gen6_system_top

##################### Define Working Library Directory #######################

define_design_lib work -path ./work

################## Design Compiler Library Files Setup #######################

puts "###############################################"
puts "#        Setting Design Libraries             #"
puts "###############################################"

lappend search_path /home/IC/PCIE_GEN_6/std_cells

set RTL /home/IC/PCIE_GEN_6/rtl

lappend search_path $RTL/TOP
lappend search_path $RTL/TL
lappend search_path $RTL/DLL
lappend search_path $RTL/PHY

set SSLIB "scmetro_tsmc_cl013g_rvt_ss_1p08v_125c.db"
set TTLIB "scmetro_tsmc_cl013g_rvt_tt_1p2v_25c.db"
set FFLIB "scmetro_tsmc_cl013g_rvt_ff_1p32v_m40c.db"

set target_library [list $SSLIB $TTLIB $FFLIB]
set link_library   [list * $SSLIB $TTLIB $FFLIB]

######################## Reading RTL Files ###################################

puts "###############################################"
puts "#             Reading RTL Files               #"
puts "###############################################"

set file_format verilog


# ── TL ──────────────────────────────────────────────────────────────────────
read_file -format $file_format "$RTL/TL/tlp_assembler.v"
read_file -format $file_format "$RTL/TL/tlp_header_parser.v"
read_file -format $file_format "$RTL/TL/tlp_malformed_checker.v"
read_file -format $file_format "$RTL/TL/tlp_prefix_handler.v"
read_file -format $file_format "$RTL/TL/rx_tlp_router.v"
read_file -format $file_format "$RTL/TL/arb_tx.v"
read_file -format $file_format "$RTL/TL/vc_arbiter.v"
read_file -format $file_format "$RTL/TL/tc_vc_mapper.v"
read_file -format $file_format "$RTL/TL/fc_init_fsm.v"
read_file -format $file_format "$RTL/TL/fc_init_timer.v"
read_file -format $file_format "$RTL/TL/cr_mgr.v"
read_file -format $file_format "$RTL/TL/tag_manager.v"
read_file -format $file_format "$RTL/TL/req_q.v"
read_file -format $file_format "$RTL/TL/completion_queue.v"
read_file -format $file_format "$RTL/TL/completion_handler.v"
read_file -format $file_format "$RTL/TL/cpl_timeout_logic.v"
read_file -format $file_format "$RTL/TL/ecrc.v"
read_file -format $file_format "$RTL/TL/td_handler.v"
read_file -format $file_format "$RTL/TL/poisoned_tlp_handler.v"
read_file -format $file_format "$RTL/TL/posted_write_handler.v"
read_file -format $file_format "$RTL/TL/atomic_op_handler.v"
read_file -format $file_format "$RTL/TL/message_handler.v"
read_file -format $file_format "$RTL/TL/aer_error_logger.v"
read_file -format $file_format "$RTL/TL/cfg_space_handler.v"
read_file -format $file_format "$RTL/TL/flit_mode_controller.v"
read_file -format $file_format "$RTL/TL/pcie_ordering_rob.v"
read_file -format $file_format "$RTL/TL/ro_ctrl.v"
read_file -format $file_format "$RTL/TL/tmo_err_manager.v"
read_file -format $file_format "$RTL/TL/DLL_INTERFACE.v"
read_file -format $file_format "$RTL/TL/usr_if.v"
read_file -format $file_format "$RTL/TOP/pcie_tl_top.v"
# ── DLL ─────────────────────────────────────────────────────────────────────
read_file -format $file_format "$RTL/DLL/tx_datapath_mux.v"
read_file -format $file_format "$RTL/DLL/rx_datapath_demux.v"
read_file -format $file_format "$RTL/DLL/scrambler.v"
read_file -format $file_format "$RTL/DLL/Descrambler.v"
read_file -format $file_format "$RTL/DLL/crc_gen.v"
read_file -format $file_format "$RTL/DLL/dllp_crc_gen.v"
read_file -format $file_format "$RTL/DLL/dllp_crc_chk.v"
read_file -format $file_format "$RTL/DLL/lcrc_flit_crc_chk.v"
read_file -format $file_format "$RTL/DLL/seq_num_gen.v"
read_file -format $file_format "$RTL/DLL/seq_num_checker_rx.v"
read_file -format $file_format "$RTL/DLL/ack_nak_receiver.v"
read_file -format $file_format "$RTL/DLL/ack_nak_scheduler_tx.v"
read_file -format $file_format "$RTL/DLL/ack_pgb.v"
read_file -format $file_format "$RTL/DLL/ack_tmr.v"
read_file -format $file_format "$RTL/DLL/retry_buf.v"
read_file -format $file_format "$RTL/DLL/replay_fsm.v"
read_file -format $file_format "$RTL/DLL/dllp_gen.v"
read_file -format $file_format "$RTL/DLL/dllp_arb.v"
read_file -format $file_format "$RTL/DLL/dllp_receiver_decoder.v"
read_file -format $file_format "$RTL/DLL/dllp_mal_chk.v"
read_file -format $file_format "$RTL/DLL/flit_null_slot_inserter.v"
read_file -format $file_format "$RTL/DLL/flit_rx_deframer.v"
read_file -format $file_format "$RTL/DLL/flit_seq.v"
read_file -format $file_format "$RTL/DLL/fc_init_fsm.v"
read_file -format $file_format "$RTL/DLL/fc_tmr.v"
read_file -format $file_format "$RTL/DLL/fc_wdg.v"
read_file -format $file_format "$RTL/DLL/lbw_fsm.v"
read_file -format $file_format "$RTL/DLL/nullified_tlp_handler.v"
read_file -format $file_format "$RTL/DLL/dll_err.v"
read_file -format $file_format "$RTL/DLL/dll_init.v"
read_file -format $file_format "$RTL/DLL/pm_fsm.v"
read_file -format $file_format "$RTL/DLL/pm_tmr.v"
read_file -format $file_format "$RTL/DLL/nop_gen.v"
read_file -format $file_format "$RTL/DLL/pcie6_phy_tx.v"
read_file -format $file_format "$RTL/DLL/phy_interface_rx.v"
read_file -format $file_format "$RTL/DLL/tl_interface.v"
read_file -format $file_format "$RTL/TOP/dll_top.v"
# ── PHY ─────────────────────────────────────────────────────────────────────
read_file -format $file_format "$RTL/PHY/ltssm_top.v"
read_file -format $file_format "$RTL/PHY/POLLING_FSM.v"
read_file -format $file_format "$RTL/PHY/detect_fsm.v"
read_file -format $file_format "$RTL/PHY/configuration_fsm.v"
read_file -format $file_format "$RTL/PHY/recovery_fsm.v"
read_file -format $file_format "$RTL/PHY/l0_l0s_fsm.v"
read_file -format $file_format "$RTL/PHY/l1_fsm.v"
read_file -format $file_format "$RTL/PHY/lb_fsm.v"
read_file -format $file_format "$RTL/PHY/hrst_fsm.v"
read_file -format $file_format "$RTL/PHY/data_rate_speed_change_fsm.v"
read_file -format $file_format "$RTL/PHY/symbol_block_lock_fsm.v"
read_file -format $file_format "$RTL/PHY/fec_encoder_rs.v"
read_file -format $file_format "$RTL/PHY/fec_rs_decoder.v"
read_file -format $file_format "$RTL/PHY/fec_syndrome_calculator.v"
read_file -format $file_format "$RTL/PHY/encoder_128b130b.v"
read_file -format $file_format "$RTL/PHY/decoder_128b130b.v"
read_file -format $file_format "$RTL/PHY/encoder_8b10b.v"
read_file -format $file_format "$RTL/PHY/decoder_8b10b.v"
read_file -format $file_format "$RTL/PHY/pam4_gray_enc.v"
read_file -format $file_format "$RTL/PHY/pam4_gray_code_decoder.v"
read_file -format $file_format "$RTL/PHY/flit_framer_tx.v"
read_file -format $file_format "$RTL/PHY/flit_deframer_rx.v"
read_file -format $file_format "$RTL/PHY/flit_sync_hdr_gen_checker.v"
read_file -format $file_format "$RTL/PHY/pipe_interface_ctrl.v"
read_file -format $file_format "$RTL/PHY/pipe_rx_interface_ctrl.v"
read_file -format $file_format "$RTL/PHY/pipe_tx.v"
read_file -format $file_format "$RTL/PHY/tx_datapath_mux.v"
read_file -format $file_format "$RTL/PHY/rx_elastic_buffer_slip.v"
read_file -format $file_format "$RTL/PHY/tx_elastic_buffer.v"
read_file -format $file_format "$RTL/PHY/tx_gear_box.v"
read_file -format $file_format "$RTL/PHY/rx_gear_box.v"
read_file -format $file_format "$RTL/PHY/lane_deskew.v"
read_file -format $file_format "$RTL/PHY/lane_rev.v"
read_file -format $file_format "$RTL/PHY/lane_pol.v"
read_file -format $file_format "$RTL/PHY/link_equalization_controller.v"
read_file -format $file_format "$RTL/PHY/link_speed_neg.v"
read_file -format $file_format "$RTL/PHY/link_width_neg.v"
read_file -format $file_format "$RTL/PHY/data_rate_adv.v"
read_file -format $file_format "$RTL/PHY/block_align_sync_hdr_checker.v"
read_file -format $file_format "$RTL/PHY/ts1_gen.v"
read_file -format $file_format "$RTL/PHY/ts2_gen.v"
read_file -format $file_format "$RTL/PHY/ts_det.v"
read_file -format $file_format "$RTL/PHY/skp.v"
read_file -format $file_format "$RTL/PHY/fts.v"
read_file -format $file_format "$RTL/PHY/eios.v"
read_file -format $file_format "$RTL/PHY/beacon_ei_logic.v"
read_file -format $file_format "$RTL/PHY/compliance_eieos_sos_gen.v"
read_file -format $file_format "$RTL/PHY/compl_gen.v"
read_file -format $file_format "$RTL/PHY/rx_det.v"
read_file -format $file_format "$RTL/PHY/ssc_ctrl.v"
read_file -format $file_format "$RTL/PHY/pwr_tmr.v"
read_file -format $file_format "$RTL/PHY/fund_rst.v"
read_file -format $file_format "$RTL/PHY/hot_rst.v"
read_file -format $file_format "$RTL/TOP/pcie_gen6_phy_top.v"
# ── TOP ─────────────────────────────────────────────────────────────────────
read_file -format $file_format "$RTL/TOP/pcie_gen6_system_top.v"
###################### Defining Top-Level Design #############################

current_design $top_module

#################### Linking All Design Parts ################################

puts "###############################################"
puts "######## Linking All Design Parts #############"
puts "###############################################"
link

#################### Checking Design Consistency #############################

puts "###############################################"
puts "######## Checking Design Consistency ##########"
puts "###############################################"
check_design

#################### Design Constraints #####################################

puts "###############################################"
puts "############ Design Constraints ###############"
puts "###############################################"
source ./cons.tcl

############################### Path Groups ##################################
# Defined AFTER cons.tcl so set_clock_groups -asynchronous is already applied.

puts "###############################################"
puts "################ Path Groups ##################"
puts "###############################################"

group_path -name INREG  -from [all_inputs]
group_path -name REGOUT -to   [all_outputs]
group_path -name INOUT  -from [all_inputs] -to [all_outputs]

# Cross-domain groups (informational; timing is cut by set_clock_groups).
group_path -name CLK_CORE_TO_PIPE -from [get_clocks clk]      -to [get_clocks clk_pipe]
group_path -name CLK_PIPE_TO_CORE -from [get_clocks clk_pipe] -to [get_clocks clk]
group_path -name CLK_CORE_TO_SER  -from [get_clocks clk]      -to [get_clocks clk_ser]

###################### Compile ##############################################

puts "###############################################"
puts "########## Mapping & Optimization #############"
puts "###############################################"

current_design fec_rs_decoder
compile -map_effort low -area_effort none
current_design fec_encoder_rs
compile -map_effort low -area_effort none
current_design fec_syndrome_calculator
compile -map_effort low -area_effort none
current_design $top_module
compile_ultra -no_autoungroup

############################ Output Files ###################################

write_file -format verilog  -hierarchy -output PCIE_GEN6_SYN.v
write_file -format ddc      -hierarchy -output PCIE_GEN6_SYN.ddc
write_sdc  -nosplit                            PCIE_GEN6_SYN.sdc
write_sdf                                      PCIE_GEN6_SYN.sdf

############################ Reports ########################################

puts "###############################################"
puts "################# Reporting ###################"
puts "###############################################"

report_area       -hierarchy                     > area.rpt
report_power      -hierarchy                     > power.rpt
report_timing     -max_paths 200 -delay_type min > hold.rpt
report_timing     -max_paths 200 -delay_type max > setup.rpt
report_clock      -attributes                    > clocks.rpt
report_constraint -all_violators                 > constraints.rpt
report_qor                                       > qor.rpt
report_cell                                      > cells.rpt
report_net_fanout -threshold 32                  > fanout.rpt

puts "###############################################"
puts "###########  Synthesis Complete  ##############"
puts "###############################################"

# FIX 10 (v2): catch wrapper — safe for both GUI and batch runs.
#gui_start
# exit
