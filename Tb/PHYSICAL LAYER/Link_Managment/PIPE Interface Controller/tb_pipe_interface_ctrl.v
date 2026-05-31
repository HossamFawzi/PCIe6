// =============================================================================
// Testbench : tb_pipe_interface_ctrl
// Module    : pipe_interface_ctrl
//
// Tests:
//   1. Reset defaults
//   2. Power-down mapping for key LTSSM states
//   3. pipe_txelecidle assertion / de-assertion
//   4. pipe_txdetectrx one-cycle pulse in Detect.Active
//   5. pipe_txcompliance in Polling.Compliance
//   6. pclkchangeack handshake in Recovery.Speed
//   7. pipe_width tracks pipe_rate
// =============================================================================

`timescale 1ns/1ps

module tb_pipe_interface_ctrl;

    // ?? DUT ports ?????????????????????????????????????????????????????????????
    reg        clk;
    reg        rst_n;
    reg        pipe_phystatus;
    reg        pipe_rxvalid;
    reg [2:0]  pipe_rxstatus;
    reg [5:0]  ltssm_state;
    reg [1:0]  power_down_req;

    wire [1:0] pipe_powerdown;
    wire [3:0] pipe_rate;
    wire       pipe_txdetectrx;
    wire       pipe_txelecidle;
    wire       pipe_txcompliance;
    wire       pipe_pclkchangeack;
    wire [1:0] pipe_width;

    // ?? Instantiate DUT ??????????????????????????????????????????????????????
    pipe_interface_ctrl DUT (
        .clk               (clk),
        .rst_n             (rst_n),
        .pipe_phystatus    (pipe_phystatus),
        .pipe_rxvalid      (pipe_rxvalid),
        .pipe_rxstatus     (pipe_rxstatus),
        .ltssm_state       (ltssm_state),
        .power_down_req    (power_down_req),
        .pipe_powerdown    (pipe_powerdown),
        .pipe_rate         (pipe_rate),
        .pipe_txdetectrx   (pipe_txdetectrx),
        .pipe_txelecidle   (pipe_txelecidle),
        .pipe_txcompliance (pipe_txcompliance),
        .pipe_pclkchangeack(pipe_pclkchangeack),
        .pipe_width        (pipe_width)
    );

    // ?? Clock: 250 MHz ????????????????????????????????????????????????????????
    initial clk = 0;
    always  #2 clk = ~clk;

    // ?? LTSSM state constants (mirror DUT localparams) ????????????????????????
    localparam LTSSM_DETECT_QUIET    = 6'h00;
    localparam LTSSM_DETECT_ACTIVE   = 6'h01;
    localparam LTSSM_POLLING_ACTIVE  = 6'h02;
    localparam LTSSM_POLLING_COMPL   = 6'h03;
    localparam LTSSM_POLLING_CONFIG  = 6'h04;
    localparam LTSSM_L0              = 6'h10;
    localparam LTSSM_L0S_TX          = 6'h11;
    localparam LTSSM_L1_IDLE         = 6'h14;
    localparam LTSSM_L2_IDLE         = 6'h15;
    localparam LTSSM_RECOVERY_SPEED  = 6'h23;
    localparam LTSSM_DISABLED        = 6'h31;

    localparam PIPE_P0  = 2'b00;
    localparam PIPE_P0S = 2'b01;
    localparam PIPE_P1  = 2'b10;
    localparam PIPE_P2  = 2'b11;

    localparam WIDTH_16 = 2'b01;
    localparam WIDTH_32 = 2'b10;

    // ?? Helpers ???????????????????????????????????????????????????????????????
    integer pass_count;
    integer fail_count;

    task wait_clks;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    task check;
        input [63:0] got;
        input [63:0] expected;
        input [127:0] label;
        begin
            if (got === expected) begin
                $display("  PASS  %-44s  got=%b", label, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-44s  got=%b  expected=%b",
                         label, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // Main stimulus
    // =========================================================================
    initial begin
        pass_count     = 0;
        fail_count     = 0;
        rst_n          = 0;
        pipe_phystatus = 0;
        pipe_rxvalid   = 0;
        pipe_rxstatus  = 3'b000;
        ltssm_state    = LTSSM_DETECT_QUIET;
        power_down_req = 2'b00;

        $display("\n=== pipe_interface_ctrl Testbench ===\n");

        // ?? TEST 1: Reset defaults ?????????????????????????????????????????
        $display("--- Test 1: Reset Defaults ---");
        wait_clks(5);
        @(posedge clk);
        check(pipe_txelecidle,   1, "pipe_txelecidle = 1 in reset");
        check(pipe_txdetectrx,   0, "pipe_txdetectrx = 0 in reset");
        check(pipe_txcompliance, 0, "pipe_txcompliance = 0 in reset");
        check(pipe_pclkchangeack,0, "pipe_pclkchangeack = 0 in reset");
        check(pipe_width,        WIDTH_16, "pipe_width = 16 in reset");

        // ?? Release reset ?????????????????????????????????????????????????
        rst_n = 1;
        wait_clks(2);

        // ?? TEST 2: Power-down mapping ????????????????????????????????????
        $display("\n--- Test 2: Power-Down Mapping ---");

        ltssm_state = LTSSM_L0;
        wait_clks(2);
        check(pipe_powerdown, PIPE_P0, "L0 ? PIPE_P0");

        ltssm_state = LTSSM_DETECT_ACTIVE;
        wait_clks(2);
        check(pipe_powerdown, PIPE_P0S, "Detect.Active ? PIPE_P0S");

        ltssm_state = LTSSM_L0S_TX;
        wait_clks(2);
        check(pipe_powerdown, PIPE_P0S, "L0s.TX ? PIPE_P0S");

        ltssm_state = LTSSM_L1_IDLE;
        wait_clks(2);
        check(pipe_powerdown, PIPE_P1, "L1.Idle ? PIPE_P1");

        ltssm_state = LTSSM_L2_IDLE;
        wait_clks(2);
        check(pipe_powerdown, PIPE_P2, "L2.Idle ? PIPE_P2");

        ltssm_state = LTSSM_DISABLED;
        wait_clks(2);
        check(pipe_powerdown, PIPE_P2, "Disabled ? PIPE_P2");

        // ?? TEST 3: TX Electrical Idle ????????????????????????????????????
        $display("\n--- Test 3: pipe_txelecidle ---");

        ltssm_state = LTSSM_L0;
        wait_clks(2);
        check(pipe_txelecidle, 0, "L0 ? txelecidle = 0");

        ltssm_state = LTSSM_POLLING_ACTIVE;
        wait_clks(2);
        check(pipe_txelecidle, 0, "Polling.Active ? txelecidle = 0");

        ltssm_state = LTSSM_L1_IDLE;
        wait_clks(2);
        check(pipe_txelecidle, 1, "L1.Idle ? txelecidle = 1");

        ltssm_state = LTSSM_L2_IDLE;
        wait_clks(2);
        check(pipe_txelecidle, 1, "L2.Idle ? txelecidle = 1");

        ltssm_state = LTSSM_DETECT_QUIET;
        wait_clks(2);
        check(pipe_txelecidle, 1, "Detect.Quiet ? txelecidle = 1");

        // ?? TEST 4: TX Detect Receiver (one-cycle pulse) ??????????????????
        $display("\n--- Test 4: pipe_txdetectrx one-cycle pulse ---");
        ltssm_state = LTSSM_DETECT_QUIET;
        wait_clks(3);

        // Enter Detect.Active ? expect a single-cycle pulse
        ltssm_state = LTSSM_DETECT_ACTIVE;
        @(posedge clk); // first cycle: pulse asserted
        #1; // sample just after posedge
        check(pipe_txdetectrx, 1, "txdetectrx HIGH on 1st cycle in Detect.Active");
        @(posedge clk); // second cycle: pulse should have dropped
        #1;
        check(pipe_txdetectrx, 0, "txdetectrx LOW on 2nd cycle in Detect.Active");

        // Return to Detect.Quiet, re-enter ? pulse should re-fire
        ltssm_state = LTSSM_DETECT_QUIET;
        wait_clks(2);
        ltssm_state = LTSSM_DETECT_ACTIVE;
        @(posedge clk);
        #1;
        check(pipe_txdetectrx, 1, "txdetectrx re-fires on second Detect.Active entry");

        // ?? TEST 5: TX Compliance ?????????????????????????????????????????
        $display("\n--- Test 5: pipe_txcompliance ---");
        ltssm_state = LTSSM_L0;
        wait_clks(2);
        check(pipe_txcompliance, 0, "txcompliance = 0 in L0");

        ltssm_state = LTSSM_POLLING_COMPL;
        wait_clks(2);
        check(pipe_txcompliance, 1, "txcompliance = 1 in Polling.Compliance");

        ltssm_state = LTSSM_L0;
        wait_clks(2);
        check(pipe_txcompliance, 0, "txcompliance = 0 back in L0");

        // ?? TEST 6: PCLK Change Acknowledge ??????????????????????????????
        $display("\n--- Test 6: pipe_pclkchangeack handshake ---");
        ltssm_state    = LTSSM_RECOVERY_SPEED;
        pipe_phystatus = 0;
        wait_clks(3);
        check(pipe_pclkchangeack, 0, "no ack before phystatus rises");

        // PHY asserts phystatus (rising edge) during Recovery.Speed
        pipe_phystatus = 1;
        @(posedge clk);
        #1;
        // ack should appear on the cycle after phystatus is detected
        @(posedge clk);
        #1;
        check(pipe_pclkchangeack, 1, "pclkchangeack = 1 after phystatus rise");
        pipe_phystatus = 0;
        @(posedge clk);
        #1;
        check(pipe_pclkchangeack, 0, "pclkchangeack = 0 (one-cycle pulse)");

        // ?? TEST 7: No ack outside Recovery.Speed ?????????????????????????
        $display("\n--- Test 7: No pclkchangeack outside Recovery.Speed ---");
        ltssm_state    = LTSSM_L0;
        pipe_phystatus = 0;
        wait_clks(2);
        pipe_phystatus = 1;
        wait_clks(3);
        check(pipe_pclkchangeack, 0, "no ack in L0 even with phystatus");
        pipe_phystatus = 0;

        // ?? TEST 8: pipe_width tracks pipe_rate ??????????????????????????
        // NOTE: pipe_rate is internal and can only be updated during
        // Recovery.Speed in the DUT. We verify the width matches
        // the reset-time pipe_rate (Gen1 ? 16-bit).
        $display("\n--- Test 8: pipe_width ---");
        ltssm_state = LTSSM_L0;
        wait_clks(2);
        // After reset, pipe_rate = GEN1 (0001), so width should be 16-bit
        check(pipe_width, WIDTH_16, "pipe_width = 16-bit for Gen1 rate");

        // ?? Summary ??????????????????????????????????????????????????????
        $display("\n=== SUMMARY: %0d passed, %0d failed ===\n",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED\n");
        else
            $display("SOME TESTS FAILED\n");

        $finish;
    end

    // ?? Watchdog ??????????????????????????????????????????????????????????????
    initial begin
        #50_000;
        $display("TIMEOUT");
        $finish;
    end

    // ?? Waveform dump ?????????????????????????????????????????????????????????
    initial begin
        $dumpfile("pipe_interface_ctrl.vcd");
        $dumpvars(0, tb_pipe_interface_ctrl);
    end

endmodule