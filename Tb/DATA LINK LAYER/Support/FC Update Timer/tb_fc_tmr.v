
`timescale 1ns/1ps
module tb_fc_tmr;

    reg        clk, rst_n;
    reg        fc_update_sent, dll_active;
    reg [15:0] fc_timer_limit;
    wire       fc_update_req, fc_timer_exp;

    integer pass_count = 0;
    integer fail_count = 0;

    fc_tmr dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .fc_update_sent(fc_update_sent),
        .fc_timer_limit(fc_timer_limit),
        .dll_active    (dll_active),
        .fc_update_req (fc_update_req),
        .fc_timer_exp  (fc_timer_exp)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check(input exp, input got, input [127:0] name);
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
        rst_n = 0; fc_update_sent = 0; dll_active = 0; fc_timer_limit = 16'd10;
        repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
      end
    endtask

    integer i;
    initial begin
        $display("=== TB: fc_tmr ===");

        $display("[TC1] After reset outputs = 0");
        apply_reset;
        @(posedge clk);
        check(0, fc_update_req, "fc_update_req=0 after reset");
        check(0, fc_timer_exp,  "fc_timer_exp=0 after reset");

        $display("[TC2] dll_active=0 suppresses timer");
        apply_reset;
        dll_active = 0; fc_timer_limit = 16'd3;
        repeat(10) @(posedge clk);
        check(0, fc_timer_exp, "fc_timer_exp stays 0 when dll_active=0");

        $display("[TC3] Timer fires at fc_timer_limit");
        apply_reset;
        dll_active = 1; fc_timer_limit = 16'd5;
        repeat(7) @(posedge clk);
        check(1, fc_timer_exp,  "fc_timer_exp=1 at limit");
        check(1, fc_update_req, "fc_update_req=1 at limit");

        $display("[TC4] fc_update_sent resets counter");
        apply_reset;
        dll_active = 1; fc_timer_limit = 16'd8;
        repeat(4) @(posedge clk);
        fc_update_sent = 1; @(posedge clk); fc_update_sent = 0;

        repeat(4) @(posedge clk);
        check(0, fc_timer_exp, "fc_timer_exp=0 after fc_update_sent reset");

        $display("[TC5] Timer re-arms after fc_update_sent");
        apply_reset;
        dll_active = 1; fc_timer_limit = 16'd4;

        repeat(6) @(posedge clk);
        check(1, fc_timer_exp, "first expiry fires");

        fc_update_sent = 1; @(posedge clk); fc_update_sent = 0;

        repeat(6) @(posedge clk);
        check(1, fc_timer_exp, "second expiry fires after re-arm");

        $display("[TC6] fc_update_req == fc_timer_exp");
        apply_reset;
        dll_active = 1; fc_timer_limit = 16'd3;
        repeat(5) @(posedge clk);
        if (fc_update_req === fc_timer_exp) begin
            $display("  PASS | fc_update_req == fc_timer_exp");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL | fc_update_req != fc_timer_exp");
            fail_count = fail_count + 1;
        end

        $display("=== fc_tmr: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #3000 begin $display("TIMEOUT"); $finish; end
endmodule
