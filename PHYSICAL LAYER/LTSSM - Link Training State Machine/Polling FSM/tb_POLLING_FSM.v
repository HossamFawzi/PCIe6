// =============================================================================
// File        : TEST.v
// Module      : tb_polling_fsm
// Description : Exhaustive self-checking Verilog-2001 testbench for
//               polling_fsm (PCIe Gen6 LTSSM Polling State Machine).
//
// Test Cases:
//   TC0 : Power-on reset — all outputs idle
//   TC1 : Ideal path  (TS1 RX lock -> Polling.Config TS2 exchange -> success)
//   TC2 : Timeout in Polling.Active (no lock achieved)
//   TC3 : Polarity Inversion recovery (inverted TS1 -> rx_polarity -> success)
//   TC4 : Partial lane failure (rx_valid drops mid TS2 run, recovers)
//   TC5 : Asynchronous reset mid-state
//   TC6 : No lanes detected — FSM stays in IDLE
//   TC7 : Compliance mode entry and exit
//   TC8 : Polling.Config timeout
//
// Parameters POLL_ACTIVE_TIMEOUT / POLL_CONFIG_TIMEOUT overridden to
// 50 / 100 cycles for instant simulation.
// Self-checking via check() task; prints *** ALL TESTS PASSED *** on success.
// Waveform dumped to waveform.vcd.
// =============================================================================

`timescale 1ns / 1ps

module tb_polling_fsm;

    // =========================================================================
    // Scaled parameters
    // =========================================================================
    localparam POLL_ACTIVE_TIMEOUT = 50;
    localparam POLL_CONFIG_TIMEOUT = 100;
    localparam TS2_REQUIRED_COUNT  = 8;
    localparam TS1_TX_COUNT        = 4;

    // =========================================================================
    // DUT ports
    // =========================================================================
    reg         clk;
    reg         rst_n;
    reg         polling_req;
    reg  [15:0] lanes_detected;
    reg         rx_valid;
    reg         rx_datak;
    reg  [31:0] rx_data;
    reg         rx_elec_idle;
    reg         compliance_req;

    wire        tx_elec_idle;
    wire        send_ts1;
    wire        send_ts2;
    wire        enter_compliance;
    wire        rx_polarity;
    wire        polling_done;
    wire        polling_success;
    wire        polling_timeout;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    polling_fsm #(
        .POLL_ACTIVE_TIMEOUT (POLL_ACTIVE_TIMEOUT),
        .POLL_CONFIG_TIMEOUT (POLL_CONFIG_TIMEOUT),
        .TS2_REQUIRED_COUNT  (TS2_REQUIRED_COUNT),
        .TS1_TX_COUNT        (TS1_TX_COUNT)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .polling_req     (polling_req),
        .lanes_detected  (lanes_detected),
        .rx_valid        (rx_valid),
        .rx_datak        (rx_datak),
        .rx_data         (rx_data),
        .rx_elec_idle    (rx_elec_idle),
        .compliance_req  (compliance_req),
        .tx_elec_idle    (tx_elec_idle),
        .send_ts1        (send_ts1),
        .send_ts2        (send_ts2),
        .enter_compliance(enter_compliance),
        .rx_polarity     (rx_polarity),
        .polling_done    (polling_done),
        .polling_success (polling_success),
        .polling_timeout (polling_timeout)
    );

    // =========================================================================
    // Clock: 250 MHz, 4 ns period
    // =========================================================================
    initial clk = 1'b0;
    always  #2 clk = ~clk;

    // =========================================================================
    // Pass / Fail counters
    // =========================================================================
    integer pass_cnt;
    integer fail_cnt;
    integer test_num;

    // =========================================================================
    // check() task
    // =========================================================================
    task check;
        input [239:0] label;
        input         actual;
        input         expected;
        begin
            if (actual === expected) begin
                $display("[PASS] TC%0d %s  got=%b exp=%b",
                         test_num, label, actual, expected);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] TC%0d %s  got=%b exp=%b  <<< MISMATCH",
                         test_num, label, actual, expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================================
    // do_reset
    // =========================================================================
    task do_reset;
        begin
            rst_n          <= 1'b0;
            polling_req    <= 1'b0;
            lanes_detected <= 16'h0000;
            rx_valid       <= 1'b0;
            rx_datak       <= 1'b0;
            rx_data        <= 32'h0;
            rx_elec_idle   <= 1'b1;
            compliance_req <= 1'b0;
            repeat(4) @(posedge clk); #1;
            rst_n <= 1'b1;
            @(posedge clk); #1;
        end
    endtask

    // =========================================================================
    // Atomic cycle drivers
    // =========================================================================
    task drive_ts1_com;
        begin
            rx_valid     <= 1'b1;
            rx_datak     <= 1'b1;
            rx_data      <= {24'h0, 8'hBC};
            rx_elec_idle <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task drive_ts1_ident;
        begin
            rx_valid     <= 1'b1;
            rx_datak     <= 1'b0;
            rx_data      <= {24'h0, 8'h4A};
            rx_elec_idle <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task drive_ts2_ident;
        begin
            rx_valid     <= 1'b1;
            rx_datak     <= 1'b0;
            rx_data      <= {24'h0, 8'hB5};
            rx_elec_idle <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task drive_inv_ts1_com;
        begin
            rx_valid     <= 1'b1;
            rx_datak     <= 1'b1;
            rx_data      <= {24'h0, 8'h43};
            rx_elec_idle <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task drive_idle_rx;
        begin
            rx_valid     <= 1'b0;
            rx_datak     <= 1'b0;
            rx_data      <= 32'h0;
            rx_elec_idle <= 1'b1;
            @(posedge clk); #1;
        end
    endtask

    task drive_junk_rx;
        // valid, non-K, non-TS symbol — breaks a TS2 run
        begin
            rx_valid     <= 1'b1;
            rx_datak     <= 1'b0;
            rx_data      <= {24'h0, 8'hDE};
            rx_elec_idle <= 1'b0;
            @(posedge clk); #1;
        end
    endtask

    // =========================================================================
    // pump_ts1_lock: N pairs of COM+IDENT
    // =========================================================================
    task pump_ts1_lock;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                drive_ts1_com;
                drive_ts1_ident;
            end
        end
    endtask

    // =========================================================================
    // pump_ts2: N consecutive TS2 IDENT cycles
    // =========================================================================
    task pump_ts2;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                drive_ts2_ident;
        end
    endtask

    // =========================================================================
    // wait_for_polling_done: block until polling_done or max_cycles exhausted
    // =========================================================================
    task wait_for_polling_done;
        input integer max_cycles;
        integer cyc;
        begin
            cyc = 0;
            while (!polling_done && cyc < max_cycles) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
            end
            if (cyc >= max_cycles)
                $display("[WARN] TC%0d wait_for_polling_done: no pulse in %0d cycles",
                         test_num, max_cycles);
        end
    endtask

    // =========================================================================
    // do_full_ts2_phase: drive TS2 to completion, then wait for done pulse
    // =========================================================================
    task do_full_ts2_phase;
        begin
            pump_ts2(TS2_REQUIRED_COUNT + 2);
            drive_idle_rx;
            // DUT now counts TS2 TX internally for TS2_REQUIRED_COUNT cycles
            wait_for_polling_done(POLL_CONFIG_TIMEOUT + 20);
        end
    endtask

    // =========================================================================
    // MAIN TEST BODY
    // =========================================================================
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_polling_fsm);

        pass_cnt = 0;
        fail_cnt = 0;
        test_num = 0;

        $display("================================================================");
        $display("  PCIe Gen6 polling_fsm Exhaustive Testbench");
        $display("  POLL_ACTIVE_TIMEOUT=%0d  POLL_CONFIG_TIMEOUT=%0d cycles",
                 POLL_ACTIVE_TIMEOUT, POLL_CONFIG_TIMEOUT);
        $display("================================================================");

        // =====================================================================
        // TC0: POWER-ON RESET
        // =====================================================================
        test_num = 0;
        $display("\n--- TC0: Power-on Reset ---");

        rst_n          = 1'b0;
        polling_req    = 1'b0;
        lanes_detected = 16'h0000;
        rx_valid       = 1'b0;
        rx_datak       = 1'b0;
        rx_data        = 32'h0;
        rx_elec_idle   = 1'b1;
        compliance_req = 1'b0;

        repeat(4) @(posedge clk); #1;

        check("tx_elec_idle=1            ", tx_elec_idle,    1'b1);
        check("send_ts1=0                ", send_ts1,        1'b0);
        check("send_ts2=0                ", send_ts2,        1'b0);
        check("polling_done=0            ", polling_done,    1'b0);
        check("polling_success=0         ", polling_success, 1'b0);
        check("polling_timeout=0         ", polling_timeout, 1'b0);
        check("rx_polarity=0             ", rx_polarity,     1'b0);
        check("enter_compliance=0        ", enter_compliance,1'b0);

        // =====================================================================
        // TC1: IDEAL PATH
        // =====================================================================
        test_num = 1;
        $display("\n--- TC1: Ideal Path (TS1 lock -> TS2 exchange -> success) ---");

        do_reset;

        lanes_detected <= 16'h00FF;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        // Pipeline: req seen at posedge → next_state=PA → state=PA at next posedge
        @(posedge clk); #1;
        check("PA: tx_elec_idle=0        ", tx_elec_idle, 1'b0);
        check("PA: send_ts1=1            ", send_ts1,     1'b1);
        check("PA: send_ts2=0            ", send_ts2,     1'b0);

        // Achieve lock + satisfy TS1_TX_COUNT (TS1_TX_COUNT+8 = 12 pairs)
        pump_ts1_lock(TS1_TX_COUNT + 8);

        // 3 pipeline cycles for NSL→state→output to propagate
        repeat(3) @(posedge clk); #1;

        check("PC: ts1 or ts2 active     ", (send_ts1 | send_ts2), 1'b1);
        check("PC: tx_elec_idle=0        ", tx_elec_idle,          1'b0);

        // TS2 exchange — drives TS2, waits for polling_done pulse
        do_full_ts2_phase;

        // We are NOW at the cycle polling_done is high
        check("TC1: polling_success=1    ", polling_success, 1'b1);
        check("TC1: polling_done=1       ", polling_done,    1'b1);
        check("TC1: polling_timeout=0    ", polling_timeout, 1'b0);
        check("TC1: tx_elec_idle=1       ", tx_elec_idle,   1'b1);

        // One-cycle pulse — must clear next cycle
        @(posedge clk); #1;
        check("TC1: done clears (pulse)  ", polling_done,   1'b0);

        // =====================================================================
        // TC2: TIMEOUT IN POLLING.ACTIVE
        // =====================================================================
        test_num = 2;
        $display("\n--- TC2: Timeout in Polling.Active (no training symbols) ---");

        do_reset;

        lanes_detected <= 16'h000F;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        // Drive nothing — wait for active timeout
        wait_for_polling_done(POLL_ACTIVE_TIMEOUT + 15);

        check("TC2: polling_timeout=1    ", polling_timeout, 1'b1);
        check("TC2: polling_done=1       ", polling_done,    1'b1);
        check("TC2: polling_success=0    ", polling_success, 1'b0);

        @(posedge clk); #1;
        check("TC2: idle after tmout     ", tx_elec_idle,   1'b1);
        check("TC2: done clears          ", polling_done,   1'b0);

        // =====================================================================
        // TC3: POLARITY INVERSION RECOVERY
        // =====================================================================
        test_num = 3;
        $display("\n--- TC3: Polarity Inversion Recovery ---");

        do_reset;

        lanes_detected <= 16'h00FF;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        // Settle into Polling.Active
        repeat(3) @(posedge clk); #1;

        // Fire one inverted COM — triggers ST_POLARITY_CHECK transition
        drive_inv_ts1_com;

        // NSL fires on the posedge that saw the inverted COM.
        // State register updates one cycle later, output register one more.
        @(posedge clk); #1;
        check("TC3: rx_polarity=1        ", rx_polarity, 1'b1);
        check("TC3: send_ts1=1 in PC     ", send_ts1,    1'b1);

        // Pump normal TS1 (PIPE_CTRL has corrected polarity externally)
        pump_ts1_lock(TS1_TX_COUNT + 8);
        repeat(3) @(posedge clk); #1;

        check("TC3: entered PC           ", tx_elec_idle, 1'b0);

        do_full_ts2_phase;

        check("TC3: polling_success=1    ", polling_success, 1'b1);
        check("TC3: polling_done=1       ", polling_done,    1'b1);
        check("TC3: polling_timeout=0    ", polling_timeout, 1'b0);

        // =====================================================================
        // TC4: PARTIAL LANE FAILURE — TS2 run broken, re-accumulates
        // =====================================================================
        test_num = 4;
        $display("\n--- TC4: Partial Lane Failure (TS2 run broken, recovers) ---");

        do_reset;

        lanes_detected <= 16'h00FF;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        // Achieve lock and enter Polling.Config
        pump_ts1_lock(TS1_TX_COUNT + 8);
        repeat(3) @(posedge clk); #1;

        // Partial TS2 run: 4 symbols (need 8)
        pump_ts2(4);

        // Break the run with a non-TS2 valid symbol → ts2_rx_cnt resets to 0
        drive_junk_rx;

        // Lane back online — drive full 8+2 consecutive TS2
        pump_ts2(TS2_REQUIRED_COUNT + 2);
        drive_idle_rx;

        wait_for_polling_done(POLL_CONFIG_TIMEOUT + 20);

        check("TC4: polling_done=1       ", polling_done,    1'b1);
        check("TC4: polling_success=1    ", polling_success, 1'b1);
        check("TC4: polling_timeout=0    ", polling_timeout, 1'b0);

        // =====================================================================
        // TC5: ASYNCHRONOUS RESET MID-STATE
        // =====================================================================
        test_num = 5;
        $display("\n--- TC5: Asynchronous Reset Mid-State ---");

        do_reset;

        lanes_detected <= 16'hFFFF;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        repeat(10) @(posedge clk); #1;

        check("TC5 pre-rst: send_ts1=1   ", send_ts1,     1'b1);
        check("TC5 pre-rst: tx_idle=0    ", tx_elec_idle, 1'b0);

        // Assert reset between clock edges
        #1 rst_n = 1'b0;

        @(posedge clk); #1;
        check("TC5 rst: tx_elec_idle=1   ", tx_elec_idle,    1'b1);
        check("TC5 rst: send_ts1=0       ", send_ts1,        1'b0);
        check("TC5 rst: send_ts2=0       ", send_ts2,        1'b0);
        check("TC5 rst: polling_done=0   ", polling_done,    1'b0);
        check("TC5 rst: polling_success=0", polling_success, 1'b0);
        check("TC5 rst: polling_timeout=0", polling_timeout, 1'b0);
        check("TC5 rst: rx_polarity=0    ", rx_polarity,     1'b0);
        check("TC5 rst: enter_comp=0     ", enter_compliance,1'b0);

        // Release reset and verify clean restart
        rst_n <= 1'b1;
        @(posedge clk); #1;
        lanes_detected <= 16'hFFFF;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;
        @(posedge clk); #1;
        check("TC5 restart: send_ts1=1   ", send_ts1, 1'b1);

        // =====================================================================
        // TC6: NO LANES DETECTED
        // =====================================================================
        test_num = 6;
        $display("\n--- TC6: No Lanes Detected (lanes_detected=0) ---");

        do_reset;

        lanes_detected <= 16'h0000;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        repeat(8) @(posedge clk); #1;
        check("TC6: tx_elec_idle=1       ", tx_elec_idle, 1'b1);
        check("TC6: send_ts1=0           ", send_ts1,     1'b0);
        check("TC6: send_ts2=0           ", send_ts2,     1'b0);
        check("TC6: polling_done=0       ", polling_done, 1'b0);

        // =====================================================================
        // TC7: COMPLIANCE MODE ENTRY AND EXIT
        // =====================================================================
        test_num = 7;
        $display("\n--- TC7: Compliance Mode Entry and Exit ---");

        do_reset;

        lanes_detected <= 16'h00FF;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        repeat(4) @(posedge clk); #1;

        // Assert compliance
        compliance_req <= 1'b1;
        // 1 cycle: NSL sees compliance_req, next_state=ST_COMPLIANCE
        // 2 cycle: state=ST_COMPLIANCE, output register captures enter_compliance=1
        @(posedge clk); #1;
        @(posedge clk); #1;

        check("TC7: enter_compliance=1   ", enter_compliance, 1'b1);
        check("TC7: send_ts1=0           ", send_ts1,         1'b0);
        check("TC7: send_ts2=0           ", send_ts2,         1'b0);
        check("TC7: tx_elec_idle=0       ", tx_elec_idle,     1'b0);

        // Deassert compliance — return to Polling.Active
        compliance_req <= 1'b0;
        repeat(3) @(posedge clk); #1;

        check("TC7: enter_comp=0 (exit)  ", enter_compliance, 1'b0);
        check("TC7: send_ts1=1 (PA back) ", send_ts1,         1'b1);

        // =====================================================================
        // TC8: POLLING.CONFIG TIMEOUT
        // =====================================================================
        test_num = 8;
        $display("\n--- TC8: Polling.Config Timeout (TS2 never received) ---");

        do_reset;

        lanes_detected <= 16'h000F;
        polling_req    <= 1'b1;
        @(posedge clk); #1;
        polling_req    <= 1'b0;

        // Achieve lock, enter Polling.Config
        pump_ts1_lock(TS1_TX_COUNT + 8);
        repeat(3) @(posedge clk); #1;

        // Drive nothing (idle RX) — wait for config timeout
        drive_idle_rx;
        wait_for_polling_done(POLL_CONFIG_TIMEOUT + 30);

        check("TC8: polling_timeout=1    ", polling_timeout, 1'b1);
        check("TC8: polling_done=1       ", polling_done,    1'b1);
        check("TC8: polling_success=0    ", polling_success, 1'b0);

        @(posedge clk); #1;
        check("TC8: tx_elec_idle=1 idle  ", tx_elec_idle,   1'b1);

        // =====================================================================
        // SUMMARY
        // =====================================================================
        $display("\n================================================================");
        $display("  FINAL RESULTS");
        $display("  PASSED : %0d", pass_cnt);
        $display("  FAILED : %0d", fail_cnt);
        $display("================================================================");

        if (fail_cnt == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** %0d TEST(S) FAILED — REVIEW OUTPUT ABOVE ***", fail_cnt);

        $finish;
    end

    // =========================================================================
    // Global watchdog — 500 000 cycles
    // =========================================================================
    initial begin
        #(500_000 * 4);
        $display("[ERROR] Global watchdog expired — simulation hung");
        $finish;
    end

endmodule
