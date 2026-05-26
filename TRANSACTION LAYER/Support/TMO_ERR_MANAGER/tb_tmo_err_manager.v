// =============================================================
//  TESTBENCH : tb_tmo_err_manager
//  DUT       : tmo_err_manager
//  TESTS:
//    T1 — Allocate tag, return before timeout → no error
//    T2 — Allocate tag, let it expire → timeout fires
//    T3 — Multiple tags: one returns OK, one times out
//    T4 — cpl_timeout_err sticks after timeout
//    T5 — New tag alloc right after timeout of previous
// =============================================================
`timescale 1ns/1ps

module tb_tmo_err_manager;

    reg         clk = 0;
    always #5 clk = ~clk;

    reg         rst_n;
    reg  [9:0]  tag_start;
    reg         tag_start_valid;
    reg         tag_return_valid;
    reg  [9:0]  tag_returned;
    reg  [15:0] timeout_limit;

    wire [9:0]  timeout_tag;
    wire        timeout_valid;
    wire        cpl_timeout_err;
    wire [3:0]  err_to_aer;

    tmo_err_manager #(.MAX_TAGS(16)) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .tag_start        (tag_start),
        .tag_start_valid  (tag_start_valid),
        .tag_return_valid (tag_return_valid),
        .tag_returned     (tag_returned),
        .timeout_limit    (timeout_limit),
        .timeout_tag      (timeout_tag),
        .timeout_valid    (timeout_valid),
        .cpl_timeout_err  (cpl_timeout_err),
        .err_to_aer       (err_to_aer)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task check(input got, input exp, input [127:0] name);
        if (got === exp) begin
            $display("  PASS  %0s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL  %0s  got=%0b exp=%0b", name, got, exp);
            fail_count = fail_count + 1;
        end
    endtask

    task check_val(input [9:0] got, input [9:0] exp, input [127:0] name);
        if (got === exp) begin
            $display("  PASS  %0s = %0d", name, got);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL  %0s  got=%0d exp=%0d", name, got, exp);
            fail_count = fail_count + 1;
        end
    endtask

    task do_reset;
        begin
            rst_n            = 0;
            tag_start        = 10'h0;
            tag_start_valid  = 0;
            tag_return_valid = 0;
            tag_returned     = 10'h0;
            timeout_limit    = 16'd10;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task alloc_tag(input [9:0] t);
        begin
            @(negedge clk);
            tag_start       = t;
            tag_start_valid = 1;
            @(negedge clk);
            tag_start_valid = 0;
        end
    endtask

    task return_tag(input [9:0] t);
        begin
            @(negedge clk);
            tag_returned     = t;
            tag_return_valid = 1;
            @(negedge clk);
            tag_return_valid = 0;
        end
    endtask

    initial begin
        $display("=== tmo_err_manager Testbench ===");

        // --------------------------------------------------
        // T1: Allocate tag 3, return before timeout → no error
        // --------------------------------------------------
        $display("\n[T1] Tag 3 returned before timeout");
        do_reset;
        timeout_limit = 16'd20;
        alloc_tag(10'd3);
        repeat(5) @(posedge clk);
        return_tag(10'd3);
        repeat(5) @(posedge clk);
        check(timeout_valid,   1'b0, "no timeout_valid");
        check(cpl_timeout_err, 1'b0, "no cpl_timeout_err");

        // --------------------------------------------------
        // T2: Allocate tag 5, let it expire (limit=8 cycles)
        // --------------------------------------------------
        $display("\n[T2] Tag 5 expires → timeout fires");
        do_reset;
        timeout_limit = 16'd8;
        alloc_tag(10'd5);
        // Wait until timeout fires (up to 20 cycles)
        begin : wait_tmo
            integer cyc;
            for (cyc = 0; cyc < 20; cyc = cyc + 1) begin
                @(posedge clk);
                if (timeout_valid) disable wait_tmo;
            end
        end
        check(timeout_valid, 1'b1, "timeout_valid fired");
        check_val(timeout_tag, 10'd5, "timeout_tag=5");
        check(cpl_timeout_err, 1'b1, "cpl_timeout_err sticky");
        check(err_to_aer[0], 1'b1, "err_to_aer[0]=1");

        // --------------------------------------------------
        // T3: Tag 2 returns OK, tag 7 times out
        // --------------------------------------------------
        $display("\n[T3] Tag 2 OK, tag 7 times out");
        do_reset;
        timeout_limit = 16'd10;
        alloc_tag(10'd2);
        alloc_tag(10'd7);
        repeat(3) @(posedge clk);
        return_tag(10'd2);   // Tag 2 completes early
        begin : wait_tmo3
            integer cyc;
            for (cyc = 0; cyc < 20; cyc = cyc + 1) begin
                @(posedge clk);
                if (timeout_valid) disable wait_tmo3;
            end
        end
        check(timeout_valid, 1'b1, "timeout_valid for tag 7");
        check_val(timeout_tag, 10'd7, "timeout_tag=7 (not 2)");

        // --------------------------------------------------
        // T4: cpl_timeout_err stays sticky
        // --------------------------------------------------
        $display("\n[T4] cpl_timeout_err remains sticky");
        repeat(5) @(posedge clk);
        check(cpl_timeout_err, 1'b1, "sticky after timeout");

        // --------------------------------------------------
        // T5: Re-alloc same tag after timeout
        // --------------------------------------------------
        $display("\n[T5] Re-alloc tag 7 after its timeout");
        alloc_tag(10'd7);
        repeat(3) @(posedge clk);
        return_tag(10'd7);
        repeat(3) @(posedge clk);
        // The timeout_valid should NOT fire again
        check(timeout_valid, 1'b0, "no spurious timeout after re-alloc");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                  $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
