
`timescale 1ns/1ps
module tb_fc_init_timer;

    reg        clk = 0;
    always #5 clk = ~clk;

    reg        rst_n;
    reg        fc_init_start;
    reg        fc_init_done;
    reg [15:0] fc_init_timeout_val;

    wire       fc_init_timeout;
    wire       fc_init_retry_req;
    wire       fc_init_err;

    fc_init_timer dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .fc_init_start      (fc_init_start),
        .fc_init_done       (fc_init_done),
        .fc_init_timeout_val(fc_init_timeout_val),
        .fc_init_timeout    (fc_init_timeout),
        .fc_init_retry_req  (fc_init_retry_req),
        .fc_init_err        (fc_init_err)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task chk1(input got, input exp, input [127:0] name);
        if (got===exp) begin
            $display("  PASS  %0s", name); pass_count=pass_count+1;
        end else begin
            $display("  FAIL  %0s  got=%0b exp=%0b", name, got, exp);
            fail_count=fail_count+1;
        end
    endtask

    task do_reset;
        begin
            rst_n=0; fc_init_start=0; fc_init_done=0;
            fc_init_timeout_val=16'd10;
            repeat(4) @(posedge clk); rst_n=1; @(posedge clk);
        end
    endtask

    task pulse_start;
        begin
            @(negedge clk); fc_init_start=1;
            @(posedge clk); #1; fc_init_start=0;
        end
    endtask

    task pulse_done;
        begin
            @(negedge clk); fc_init_done=1;
            @(posedge clk); #1; fc_init_done=0;
        end
    endtask

    integer found;
    integer kk;

    initial begin
        $display("=== fc_init_timer Testbench ===");

        $display("\n[T1] Start then done before timeout");
        do_reset;
        fc_init_timeout_val = 16'd20;
        pulse_start;
        repeat(5) @(posedge clk);
        pulse_done;
        repeat(5) @(posedge clk); #1;
        chk1(fc_init_timeout, 1'b0, "no timeout");
        chk1(fc_init_err,     1'b0, "no err");

        $display("\n[T2] One timeout → retry requested");
        do_reset;
        fc_init_timeout_val = 16'd8;
        pulse_start;
        found=0;
        for (kk=0; kk<20; kk=kk+1) begin
            @(posedge clk); #1;
            if (fc_init_timeout) begin found=1; kk=20; end
        end
        chk1(found[0], 1'b1, "fc_init_timeout fired");
        found=0;
        for (kk=0; kk<5; kk=kk+1) begin
            @(posedge clk); #1;
            if (fc_init_retry_req) begin found=1; kk=5; end
        end
        chk1(found[0], 1'b1, "fc_init_retry_req");
        pulse_done;
        repeat(3) @(posedge clk); #1;
        chk1(fc_init_err, 1'b0, "no permanent err after 1 retry");

        $display("\n[T3] 3 timeouts in a row → fc_init_err");
        do_reset;
        fc_init_timeout_val = 16'd5;
        pulse_start;
        repeat(100) @(posedge clk); #1;
        chk1(fc_init_err, 1'b1, "fc_init_err after 3 retries");

        $display("\n[T4] Immediate done");
        do_reset;
        fc_init_timeout_val = 16'd20;
        @(negedge clk); fc_init_start=1; fc_init_done=1;
        @(posedge clk); #1;
        fc_init_start=0; fc_init_done=0;
        repeat(3) @(posedge clk); #1;
        chk1(fc_init_timeout, 1'b0, "no timeout");
        chk1(fc_init_err,     1'b0, "no err");

        $display("\n[T5] fc_init_err clears on rst_n");
        do_reset;
        fc_init_timeout_val = 16'd5;
        pulse_start;
        repeat(100) @(posedge clk);
        chk1(fc_init_err, 1'b1, "err set before reset");
        rst_n=0; repeat(2) @(posedge clk);
        rst_n=1; @(posedge clk); #1;
        chk1(fc_init_err, 1'b0, "err cleared after reset");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count==0) $display("ALL TESTS PASSED");
        else               $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
