
`timescale 1ns/1ps
module tb_pm_tmr;

    reg        clk, rst_n;
    reg        l0s_entry_req, l1_entry_req;
    reg        l0s_exit_req, l1_exit_req;
    reg [15:0] l0s_limit, l1_limit;
    wire       l0s_timer_exp, l1_timer_exp, pm_timeout_err;

    integer pass_count = 0;
    integer fail_count = 0;

    pm_tmr dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .l0s_entry_req(l0s_entry_req),
        .l1_entry_req (l1_entry_req),
        .l0s_exit_req (l0s_exit_req),
        .l1_exit_req  (l1_exit_req),
        .l0s_limit    (l0s_limit),
        .l1_limit     (l1_limit),
        .l0s_timer_exp(l0s_timer_exp),
        .l1_timer_exp (l1_timer_exp),
        .pm_timeout_err(pm_timeout_err)
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
        l0s_entry_req = 0; l1_entry_req = 0;
        l0s_exit_req = 0;  l1_exit_req = 0;
        l0s_limit = 16'd8; l1_limit = 16'd12;
        repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
      end
    endtask

    initial begin
        $display("=== TB: pm_tmr ===");

        $display("[TC1] Reset: no timer expiry");
        apply_reset; @(posedge clk);
        check1(0, l0s_timer_exp,  "l0s_timer_exp=0 after reset");
        check1(0, l1_timer_exp,   "l1_timer_exp=0 after reset");
        check1(0, pm_timeout_err, "pm_timeout_err=0 after reset");

        $display("[TC2] No entry_req -> timer silent");
        apply_reset;
        l0s_limit = 16'd4; l1_limit = 16'd4;
        repeat(10) @(posedge clk);
        check1(0, l0s_timer_exp, "l0s_timer_exp=0 without entry_req");
        check1(0, l1_timer_exp,  "l1_timer_exp=0 without entry_req");

        $display("[TC3] L0s timer fires at l0s_limit");
        apply_reset;
        l0s_limit = 16'd5;
        l0s_entry_req = 1; @(posedge clk); l0s_entry_req = 0;
        repeat(7) @(posedge clk);
        check1(1, l0s_timer_exp, "l0s_timer_exp=1 at limit");

        $display("[TC4] L1 timer fires at l1_limit");
        apply_reset;
        l1_limit = 16'd6;
        l1_entry_req = 1; @(posedge clk); l1_entry_req = 0;
        repeat(9) @(posedge clk);
        check1(1, l1_timer_exp, "l1_timer_exp=1 at limit");

        $display("[TC5] l0s_exit_req resets L0s timer");
        apply_reset;
        l0s_limit = 16'd6;
        l0s_entry_req = 1; @(posedge clk); l0s_entry_req = 0;
        repeat(3) @(posedge clk);
        l0s_exit_req = 1; @(posedge clk); l0s_exit_req = 0;
        repeat(4) @(posedge clk);
        check1(0, l0s_timer_exp, "l0s_timer_exp=0 after exit_req reset");

        $display("[TC6] l1_exit_req resets L1 timer");
        apply_reset;
        l1_limit = 16'd6;
        l1_entry_req = 1; @(posedge clk); l1_entry_req = 0;
        repeat(3) @(posedge clk);
        l1_exit_req = 1; @(posedge clk); l1_exit_req = 0;
        repeat(4) @(posedge clk);
        check1(0, l1_timer_exp, "l1_timer_exp=0 after l1_exit_req reset");

        $display("[TC7] L0s and L1 timers are independent");
        apply_reset;
        l0s_limit = 16'd5; l1_limit = 16'd10;
        l0s_entry_req = 1; l1_entry_req = 1;
        @(posedge clk); l0s_entry_req = 0; l1_entry_req = 0;
        repeat(7) @(posedge clk);
        check1(1, l0s_timer_exp, "L0s fired at 5 cycles");
        check1(0, l1_timer_exp,  "L1 not fired at 7 cycles (limit=10)");

        $display("[TC8] pm_timeout_err on simultaneous expiry");
        apply_reset;
        l0s_limit = 16'd5; l1_limit = 16'd5;
        l0s_entry_req = 1; l1_entry_req = 1;
        @(posedge clk); l0s_entry_req = 0; l1_entry_req = 0;
        repeat(8) @(posedge clk);
        check1(1, pm_timeout_err, "pm_timeout_err=1 on simultaneous expiry");

        $display("=== pm_tmr: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #3000 begin $display("TIMEOUT"); $finish; end
endmodule
