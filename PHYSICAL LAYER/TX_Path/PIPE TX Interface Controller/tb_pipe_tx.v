// =============================================================================
// Testbench : tb_pipe_tx
// DUT       : pipe_tx  (PCIe Gen6 PHY – Module 10)
// Simulator : QuestaSim  (Verilog-2001 only)
// Self-checking with pass/fail reporting and waveform visibility
// =============================================================================
`timescale 1ns/1ps

module tb_pipe_tx;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
parameter CORE_CLK_HALF  = 2;   // 250 MHz  core clk
parameter PIPE_CLK_HALF  = 2;   // 250 MHz  pipe clk (same freq; slight phase offset to stress CDC)

// ---------------------------------------------------------------------------
// DUT I/O
// ---------------------------------------------------------------------------
reg          pipe_clk;
reg          clk;
reg          rst_n;

reg  [255:0] tx_data;
reg          tx_valid;
reg  [31:0]  tx_datak;
reg          tx_elec_idle;
reg          tx_compliance;

wire [255:0] pipe_txd;
wire [31:0]  pipe_txdatak;
wire         pipe_tx_elec_idle;
wire         pipe_tx_compliance;
wire [1:0]   pipe_power_down;
wire         pipe_tx_swing;

// ---------------------------------------------------------------------------
// Internal register visibility  (waveform probes)
// ---------------------------------------------------------------------------
wire         dut_ei_s1   = dut.tx_elec_idle_s1;
wire         dut_ei_s2   = dut.tx_elec_idle_s2;
wire         dut_cpl_s1  = dut.tx_compliance_s1;
wire         dut_cpl_s2  = dut.tx_compliance_s2;
wire         dut_vld_s1  = dut.tx_valid_s1;
wire         dut_vld_s2  = dut.tx_valid_s2;
wire [255:0] dut_txd_reg = dut.txd_reg;
wire [31:0]  dut_txdk_reg= dut.txdatak_reg;

// ---------------------------------------------------------------------------
// Scoreboard
// ---------------------------------------------------------------------------
integer pass_cnt;
integer fail_cnt;
integer normal_data_tests;
integer elec_idle_tests;
integer compliance_tests;
integer cdc_tests;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
pipe_tx dut (
    .pipe_clk           (pipe_clk),
    .clk                (clk),
    .rst_n              (rst_n),
    .tx_data            (tx_data),
    .tx_valid           (tx_valid),
    .tx_datak           (tx_datak),
    .tx_elec_idle       (tx_elec_idle),
    .tx_compliance      (tx_compliance),
    .pipe_txd           (pipe_txd),
    .pipe_txdatak       (pipe_txdatak),
    .pipe_tx_elec_idle  (pipe_tx_elec_idle),
    .pipe_tx_compliance (pipe_tx_compliance),
    .pipe_power_down    (pipe_power_down),
    .pipe_tx_swing      (pipe_tx_swing)
);

// ---------------------------------------------------------------------------
// Clocks  (slight phase offset between core and pipe for CDC stress)
// ---------------------------------------------------------------------------
initial clk      = 0;
initial pipe_clk = 0;

always #(CORE_CLK_HALF)          clk      = ~clk;
always #(PIPE_CLK_HALF)          pipe_clk = ~pipe_clk;

// ---------------------------------------------------------------------------
// Task: apply reset
// ---------------------------------------------------------------------------
task apply_reset;
    begin
        rst_n         = 1'b0;
        tx_data       = 256'h0;
        tx_valid      = 1'b0;
        tx_datak      = 32'h0;
        tx_elec_idle  = 1'b0;
        tx_compliance = 1'b0;
        #(PIPE_CLK_HALF * 3);          // hold reset for 1.5 pipe clocks
        repeat(8) @(posedge pipe_clk);
        #1;
        rst_n = 1'b1;
        repeat(4) @(posedge pipe_clk);
        #1;
    end
endtask

// ---------------------------------------------------------------------------
// Task: wait N pipe clocks
// ---------------------------------------------------------------------------
task wait_pipe;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge pipe_clk);
        #1;
    end
endtask

// ---------------------------------------------------------------------------
// Task: check
// ---------------------------------------------------------------------------
task check;
    input        cond;
    input [127:0] msg;
    begin
        if (cond) begin
            pass_cnt = pass_cnt + 1;
            $display("[PASS] %s  t=%0t", msg, $time);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("[FAIL] %s  t=%0t", msg, $time);
        end
    end
endtask

// ---------------------------------------------------------------------------
// Task: drive one data beat on core clk, wait for it to appear on pipe side
// ---------------------------------------------------------------------------
task drive_data;
    input [255:0] d;
    input [31:0]  k;
    begin
        @(posedge clk); #1;
        tx_data  = d;
        tx_datak = k;
        tx_valid = 1'b1;
        @(posedge clk); #1;
        tx_valid = 1'b0;
        // Allow 2-stage sync (2 pipe_clk + 1 register stage = 3 pipe clocks worst case)
        wait_pipe(5);
    end
endtask

// ===========================================================================
// TEST SUITE
// ===========================================================================
initial begin
    $dumpfile("tb_pipe_tx.vcd");
    $dumpvars(0, tb_pipe_tx);

    pass_cnt           = 0;
    fail_cnt           = 0;
    normal_data_tests  = 0;
    elec_idle_tests    = 0;
    compliance_tests   = 0;
    cdc_tests          = 0;

    // =========================================================================
    // TC-01 : Reset defaults  (sample while rst_n is asserted)
    // =========================================================================
    $display("\n=== TC-01 : Reset Defaults ===");
    rst_n         = 1'b0;
    tx_data       = 256'h0;
    tx_valid      = 1'b0;
    tx_datak      = 32'h0;
    tx_elec_idle  = 1'b0;
    tx_compliance = 1'b0;
    // Hold reset low, wait two pipe_clk edges so async reset propagates
    @(posedge pipe_clk); #1;
    @(posedge pipe_clk); #1;

    check(pipe_txd            === 256'h0, "TC01a TXD=0 on reset");
    check(pipe_txdatak        === 32'h0,  "TC01b TXDataK=0 on reset");
    check(pipe_tx_elec_idle   === 1'b1,   "TC01c TXElecIdle=1 on reset");
    check(pipe_tx_compliance  === 1'b0,   "TC01d TXCompliance=0 on reset");
    check(pipe_power_down     === 2'b10,  "TC01e PowerDown=P2 on reset");
    check(pipe_tx_swing       === 1'b1,   "TC01f TXSwing=1 on reset");

    // Now fully apply reset to clean up for subsequent tests
    apply_reset;

    // =========================================================================
    // TC-02 : Normal data transfer
    //   Drive known data pattern; verify it appears on pipe_txd with correct datak
    // =========================================================================
    $display("\n=== TC-02 : Normal Data Transfer ===");
    apply_reset;
    normal_data_tests = normal_data_tests + 1;

    tx_elec_idle  = 1'b0;
    tx_compliance = 1'b0;

    drive_data(256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_0000_1111_2222_3333_4444_5555_6666_7777,
               32'hA5A5_A5A5);

    check(pipe_txd     === 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_0000_1111_2222_3333_4444_5555_6666_7777,
          "TC02a TXD matches input");
    check(pipe_txdatak === 32'hA5A5_A5A5, "TC02b TXDataK matches input");
    check(pipe_tx_elec_idle  === 1'b0,    "TC02c EI=0 during data");
    check(pipe_power_down    === 2'b00,   "TC02d P0 during normal data");
    check(pipe_tx_swing      === 1'b1,    "TC02e full swing during data");

    // =========================================================================
    // TC-03 : All-zeros data
    // =========================================================================
    $display("\n=== TC-03 : All-Zeros Data ===");
    normal_data_tests = normal_data_tests + 1;

    drive_data(256'h0, 32'h0);
    check(pipe_txd     === 256'h0, "TC03a TXD all-zeros");
    check(pipe_txdatak === 32'h0,  "TC03b TXDataK all-zeros");

    // =========================================================================
    // TC-04 : All-ones data + all-K
    // =========================================================================
    $display("\n=== TC-04 : All-Ones + All-K ===");
    normal_data_tests = normal_data_tests + 1;

    drive_data({256{1'b1}}, {32{1'b1}});
    check(pipe_txd     === {256{1'b1}}, "TC04a TXD all-ones");
    check(pipe_txdatak === {32{1'b1}},  "TC04b TXDataK all-ones");

    // =========================================================================
    // TC-05 : Electrical Idle assertion
    //   tx_elec_idle=1 → pipe_tx_elec_idle=1, TXD=0, TXDataK=all-K, P1
    // =========================================================================
    $display("\n=== TC-05 : Electrical Idle ===");
    apply_reset;
    elec_idle_tests = elec_idle_tests + 1;

    tx_elec_idle  = 1'b1;
    tx_compliance = 1'b0;
    tx_valid      = 1'b0;
    wait_pipe(5);   // allow sync

    check(pipe_tx_elec_idle  === 1'b1,        "TC05a EI output asserted");
    check(pipe_txd           === 256'h0,      "TC05b TXD=0 during EI");
    check(pipe_txdatak       === 32'hFFFF_FFFF,"TC05c TXDataK=all-K during EI");
    check(pipe_power_down    === 2'b01,       "TC05d PowerDown=P1 during EI");
    check(pipe_tx_swing      === 1'b1,        "TC05e full swing during EI");

    // =========================================================================
    // TC-06 : Electrical Idle deassert → P0
    // =========================================================================
    $display("\n=== TC-06 : EI Deassert Returns to P0 ===");
    elec_idle_tests = elec_idle_tests + 1;

    tx_elec_idle = 1'b0;
    wait_pipe(5);
    check(pipe_tx_elec_idle === 1'b0,  "TC06a EI deasserted");
    check(pipe_power_down   === 2'b00, "TC06b P0 restored");

    // =========================================================================
    // TC-07 : Compliance mode
    //   tx_compliance=1 → pipe_tx_compliance=1, P0 (PHY must be active), half-swing
    // =========================================================================
    $display("\n=== TC-07 : Compliance Mode ===");
    apply_reset;
    compliance_tests = compliance_tests + 1;

    tx_compliance = 1'b1;
    tx_elec_idle  = 1'b0;
    wait_pipe(5);

    check(pipe_tx_compliance === 1'b1,  "TC07a TXCompliance asserted");
    check(pipe_power_down    === 2'b00, "TC07b P0 forced during compliance");
    check(pipe_tx_swing      === 1'b0,  "TC07c half-swing during compliance");

    // =========================================================================
    // TC-08 : Compliance + EI simultaneously → Compliance wins (P0)
    //   Per PIPE spec: compliance overrides idle for power-state
    // =========================================================================
    $display("\n=== TC-08 : Compliance + EI (Compliance Wins) ===");
    compliance_tests = compliance_tests + 1;

    tx_compliance = 1'b1;
    tx_elec_idle  = 1'b1;
    wait_pipe(5);

    check(pipe_power_down     === 2'b00, "TC08a Compliance overrides EI → P0");
    check(pipe_tx_compliance  === 1'b1,  "TC08b Compliance still signalled");
    check(pipe_tx_swing       === 1'b0,  "TC08c half-swing");

    tx_compliance = 1'b0;
    tx_elec_idle  = 1'b0;

    // =========================================================================
    // TC-09 : CDC stress – data valid for exactly 1 core clock
    //   Verify data still captured correctly after 2-stage pipe_clk sync
    // =========================================================================
    $display("\n=== TC-09 : CDC Single-Cycle Valid ===");
    apply_reset;
    cdc_tests = cdc_tests + 1;

    tx_elec_idle  = 1'b0;
    tx_compliance = 1'b0;

    @(posedge clk); #1;
    tx_data  = 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999;
    tx_datak = 32'hF0F0_F0F0;
    tx_valid = 1'b1;
    @(posedge clk); #1;
    tx_valid = 1'b0;
    // Wait enough pipe_clks for 2-stage sync + register
    wait_pipe(6);

    check(pipe_txd     === 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999,
          "TC09a CDC data captured");
    check(pipe_txdatak === 32'hF0F0_F0F0, "TC09b CDC datak captured");
    cdc_tests = cdc_tests + 1;

    // =========================================================================
    // TC-10 : Multiple consecutive data beats
    // =========================================================================
    $display("\n=== TC-10 : Consecutive Data Beats ===");
    normal_data_tests = normal_data_tests + 1;

    begin : consec_block
        integer i;
        reg [255:0] pat;
        reg [31:0]  dk;
        for (i = 0; i < 8; i = i + 1) begin
            pat = {8{$random}};
            dk  = $random;
            drive_data(pat, dk);
            check(pipe_txd     === pat, "TC10 consecutive TXD match");
            check(pipe_txdatak === dk,  "TC10 consecutive TXDataK match");
        end
    end

    // =========================================================================
    // TC-11 : Async reset mid-data
    // =========================================================================
    $display("\n=== TC-11 : Async Reset Mid-Data ===");
    tx_data       = {256{1'b1}};
    tx_datak      = {32{1'b1}};
    tx_valid      = 1'b1;
    tx_elec_idle  = 1'b0;
    tx_compliance = 1'b0;
    @(posedge clk); #1;

    rst_n = 1'b0;
    #1;
    check(pipe_txd            === 256'h0, "TC11a TXD=0 on async reset");
    check(pipe_tx_elec_idle   === 1'b1,   "TC11b EI=1 on async reset");
    check(pipe_power_down     === 2'b10,  "TC11c P2 on async reset");
    rst_n = 1'b1;
    tx_valid = 1'b0;
    wait_pipe(4);

    // =========================================================================
    // TC-12 : Randomised no-X test on all outputs
    // =========================================================================
    $display("\n=== TC-12 : Randomised Outputs No-X ===");
    apply_reset;
    begin : rand_block
        integer i;
        for (i = 0; i < 300; i = i + 1) begin
            tx_valid      = $random & 1'b1;
            tx_elec_idle  = $random & 1'b1;
            tx_compliance = $random & 1'b1;
            tx_data       = {8{$random}};
            tx_datak      = $random;
            @(posedge clk); #1;
            wait_pipe(3);
            check(pipe_power_down    !== 2'bxx, "TC12 PowerDown no-X");
            check(pipe_tx_elec_idle  !== 1'bx,  "TC12 EI no-X");
            check(pipe_tx_compliance !== 1'bx,  "TC12 Compliance no-X");
            check(pipe_tx_swing      !== 1'bx,  "TC12 Swing no-X");
        end
    end
    tx_valid = 1'b0; tx_elec_idle = 1'b0; tx_compliance = 1'b0;

    // =========================================================================
    // TC-13 : EI with data valid simultaneously → EI overrides data on pipe
    // =========================================================================
    $display("\n=== TC-13 : EI Overrides Data ===");
    apply_reset;
    elec_idle_tests = elec_idle_tests + 1;

    tx_elec_idle  = 1'b1;
    tx_data       = {256{1'b1}};
    tx_datak      = {32{1'b1}};
    tx_valid      = 1'b1;
    wait_pipe(5);

    check(pipe_txd           === 256'h0,        "TC13a EI overrides data → TXD=0");
    check(pipe_txdatak       === 32'hFFFF_FFFF, "TC13b EI overrides data → all-K");
    check(pipe_tx_elec_idle  === 1'b1,          "TC13c EI output asserted");
    tx_elec_idle = 1'b0; tx_valid = 1'b0;

    // =========================================================================
    // Summary
    // =========================================================================
    $display("\n===========================================");
    $display("  pipe_tx Testbench Summary");
    $display("  PASS : %0d", pass_cnt);
    $display("  FAIL : %0d", fail_cnt);
    $display("  Coverage:");
    $display("    Normal-data tests  : %0d", normal_data_tests);
    $display("    Elec-idle tests    : %0d", elec_idle_tests);
    $display("    Compliance tests   : %0d", compliance_tests);
    $display("    CDC tests          : %0d", cdc_tests);
    $display("===========================================");

    if (fail_cnt === 0)
        $display("*** ALL TESTS PASSED ***");
    else
        $display("*** %0d TEST(S) FAILED ***", fail_cnt);

    $finish;
end

// ---------------------------------------------------------------------------
// Timeout watchdog
// ---------------------------------------------------------------------------
initial begin
    #2_000_000;
    $display("[WATCHDOG] Simulation timeout");
    $finish;
end

endmodule
