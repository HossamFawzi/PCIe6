// =============================================================================
// Testbench: fc_wdg — Flow Control Watchdog  🔴 MUST
// Tests: reset, no-pending no-fire, credits arriving resets counter,
//        deadlock detection at limit, dll_inactive suppresses watchdog,
//        all three credit types independently release watchdog
// =============================================================================
`timescale 1ns/1ps
module tb_fc_wdg;

    reg        clk, rst_n;
    reg        credit_grant_p, credit_grant_np, credit_grant_cpl;
    reg        tlp_pending;
    reg [15:0] fc_watchdog_limit;
    reg        dll_active;
    wire       fc_deadlock_det, fc_watchdog_err, fc_recovery_req;

    integer pass_count = 0;
    integer fail_count = 0;

    fc_wdg dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .credit_grant_p   (credit_grant_p),
        .credit_grant_np  (credit_grant_np),
        .credit_grant_cpl (credit_grant_cpl),
        .tlp_pending      (tlp_pending),
        .fc_watchdog_limit(fc_watchdog_limit),
        .dll_active       (dll_active),
        .fc_deadlock_det  (fc_deadlock_det),
        .fc_watchdog_err  (fc_watchdog_err),
        .fc_recovery_req  (fc_recovery_req)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check1(input exp, input got, input [127:0] name);
        if (exp === got) begin
            $display("  PASS | %s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL | %s | exp=%b got=%b", name, exp, got);
            fail_count = fail_count + 1;
        end
    endtask

    task apply_reset;
      begin
        rst_n = 0;
        credit_grant_p = 0; credit_grant_np = 0; credit_grant_cpl = 0;
        tlp_pending = 0; fc_watchdog_limit = 16'd8; dll_active = 0;
        repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
      end
    endtask

    initial begin
        $display("=== TB: fc_wdg ===");

        // TC1: Reset -> all outputs 0
        $display("[TC1] Reset clears outputs");
        apply_reset; @(posedge clk);
        check1(0, fc_deadlock_det, "fc_deadlock_det=0");
        check1(0, fc_watchdog_err, "fc_watchdog_err=0");
        check1(0, fc_recovery_req, "fc_recovery_req=0");

        // TC2: tlp_pending=0 -> no watchdog even without credits
        $display("[TC2] No TLP pending -> no deadlock");
        apply_reset;
        dll_active = 1; tlp_pending = 0; fc_watchdog_limit = 16'd3;
        repeat(10) @(posedge clk);
        check1(0, fc_deadlock_det, "fc_deadlock_det=0 when no tlp_pending");

        // TC3: dll_active=0 -> watchdog suppressed
        $display("[TC3] dll_active=0 suppresses watchdog");
        apply_reset;
        dll_active = 0; tlp_pending = 1; fc_watchdog_limit = 16'd3;
        repeat(10) @(posedge clk);
        check1(0, fc_deadlock_det, "fc_deadlock_det=0 when dll_inactive");

        // TC4: Deadlock detected at fc_watchdog_limit
        $display("[TC4] Deadlock detected at limit");
        apply_reset;
        dll_active = 1; tlp_pending = 1; fc_watchdog_limit = 16'd5;
        repeat(8) @(posedge clk);
        check1(1, fc_deadlock_det, "fc_deadlock_det=1 at limit");
        check1(1, fc_watchdog_err, "fc_watchdog_err=1 at limit");
        check1(1, fc_recovery_req, "fc_recovery_req=1 at limit");

        // TC5: credit_grant_p resets counter -> no deadlock
        $display("[TC5] credit_grant_p prevents deadlock");
        apply_reset;
        dll_active = 1; tlp_pending = 1; fc_watchdog_limit = 16'd5;
        repeat(3) @(posedge clk);
        credit_grant_p = 1; @(posedge clk); credit_grant_p = 0;
        repeat(3) @(posedge clk);
        check1(0, fc_deadlock_det, "no deadlock when p credit arrives");

        // TC6: credit_grant_np resets counter -> no deadlock
        $display("[TC6] credit_grant_np prevents deadlock");
        apply_reset;
        dll_active = 1; tlp_pending = 1; fc_watchdog_limit = 16'd5;
        repeat(3) @(posedge clk);
        credit_grant_np = 1; @(posedge clk); credit_grant_np = 0;
        repeat(3) @(posedge clk);
        check1(0, fc_deadlock_det, "no deadlock when np credit arrives");

        // TC7: credit_grant_cpl resets counter -> no deadlock
        $display("[TC7] credit_grant_cpl prevents deadlock");
        apply_reset;
        dll_active = 1; tlp_pending = 1; fc_watchdog_limit = 16'd5;
        repeat(3) @(posedge clk);
        credit_grant_cpl = 1; @(posedge clk); credit_grant_cpl = 0;
        repeat(3) @(posedge clk);
        check1(0, fc_deadlock_det, "no deadlock when cpl credit arrives");

        // TC8: tlp_pending de-asserts -> counter resets, deadlock clears
        $display("[TC8] tlp_pending de-asserts -> deadlock clears");
        apply_reset;
        dll_active = 1; tlp_pending = 1; fc_watchdog_limit = 16'd4;
        repeat(6) @(posedge clk); // trigger deadlock
        check1(1, fc_deadlock_det, "deadlock detected first");
        tlp_pending = 0; @(posedge clk); @(posedge clk);
        check1(0, fc_deadlock_det, "deadlock cleared when no tlp_pending");

        $display("=== fc_wdg: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #3000 begin $display("TIMEOUT"); $finish; end
endmodule
