# =============================================================================
# File    : run.do
# Purpose : Automation script for QuestaSim / ModelSim
# Metrics : Statement, Branch, Condition, Expression, FSM, Toggle, Covergroup
# =============================================================================

# 1. Change to the exact project directory
cd "E:/Study/term 10/PROJECT 2 GRADUATION/PCIE"

# 2. Clean up old simulation directories and files
if [file exists work] {
    vdel -all -lib work
}

# 3. Create a fresh design library
vlib work
vmap work work

# 4. Compile the RTL files FIRST
# This compiles all standard Verilog (.v) files in the directory so the optimizer can find the DUT.
vlog "E:/Study/term 10/PROJECT 2 GRADUATION/PCIE/*.v"

# If you have files in subfolders, you may need to add them specifically, like:
# vlog "E:/Study/term 10/PROJECT 2 GRADUATION/PCIE/PHY/*.v"
# vlog "E:/Study/term 10/PROJECT 2 GRADUATION/PCIE/DLL/*.v"
# vlog "E:/Study/term 10/PROJECT 2 GRADUATION/PCIE/TL/*.v"

# 5. Compile the SystemVerilog testbench with coverage
vlog -sv +cover=sbcefx -work work "E:/Study/term 10/PROJECT 2 GRADUATION/PCIE/tb_pcie_gen6_sv_top.sv"

# 6. Optimize the design for simulation with coverage retention
vopt tb_pcie_gen6_sv_top -o top_opt +acc -cover sbcefx

# 7. Load the simulation with the coverage engine enabled
vsim -c top_opt -coverage -voptargs="+acc"

# 8. Name the coverage test run
coverage attribute -name TESTNAME -value "pcie_gen6_full_test"

# 9. Run the simulation completely
run -all

# 10. Save all collected coverage metrics to a Unified Coverage Database (UCDB)
coverage save -onexit -assert -directive -cvg -code sbcefx graduation_project.ucdb

# 11. Generate a detailed command-line text summary
echo "====================================================================="
echo "                  SIMULATION COVERAGE SUMMARY                        "
echo "====================================================================="
coverage report -detail -code sbcefx -cvg

# 12. Generate a comprehensive, interactive HTML dashboard report
echo "Generating interactive HTML report..."
vcover report -html graduation_project.ucdb -htmldir coverage_html_report -verbose

echo "====================================================================="
echo "Run complete. Open 'coverage_html_report/index.html' to view dashboards."
echo "====================================================================="
q -f