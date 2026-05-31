// =============================================================
//  TESTBENCH : tb_cpl_timeout_logic
//  DUT       : cpl_timeout_logic
//  TESTS:
//    T1 — Alloc tag 1, complete before timeout → no fire
//    T2 — Alloc tag 2, let it expire → timeout_fired + abort
//    T3 — err_to_aer code = 0xE on timeout
//    T4 — 3 tags alloc; tag 1 & 3 complete OK, tag 2 times out
//    T5 — Re-alloc tag after prior timeout → works correctly
// =============================================================
`timescale 1ns/1ps

module tb_cpl_timeout_logic;

    reg         clk = 0;
    always #5 clk = ~clk;

    reg         rst_n;
    reg  [9:0]  tag_alloc;
    reg         tag_alloc_valid;
    reg  [9:0]  tag_return;
    reg         tag_return_valid;
    reg  [19:0] cpl_timeout_val;

    wire [9:0]  timeout_tag;
    wire        timeout_fired;
    wire        cpl_abort_req;
    wire [3:0]  err_to_aer;

    cpl_timeout_logic #(.MAX_TAGS(16)) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .tag_alloc        (tag_alloc),
        .tag_alloc_valid  (tag_alloc_valid),
        .tag_return       (tag_return),
        .tag_return_valid (tag_return_valid),
        .cpl_timeout_val  (cpl_timeout_val),
        .timeout_tag      (timeout_tag),
        .timeout_fired    (timeout_fired),
        .cpl_abort_req    (cpl_abort_req),
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

    task check_tag(input [9:0] got, input [9:0] exp, input [127:0] name);
        if (got === exp) begin
            $display("  PASS  %0s=%0d", name, got);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL  %0s  got=%0d exp=%0d", name, got, exp);
            fail_count = fail_count + 1;
        end
    endtask

    task do_reset;
        begin
            rst_n             = 0;
            tag_alloc         = 10'h0;
            tag_alloc_valid   = 0;
            tag_return        = 10'h0;
            tag_return_valid  = 0;
            cpl_timeout_val   = 20'd10;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task alloc(input [9:0] t);
        begin
            @(negedge clk);
            tag_alloc       = t;
            tag_alloc_valid = 1;
            @(negedge clk);
            tag_alloc_valid = 0;
        end
    endtask

    task ret(input [9:0] t);
        begin
            @(negedge clk);
            tag_return       = t;
            tag_return_valid = 1;
            @(negedge clk);
            tag_return_valid = 0;
        end
    endtask

    // Wait for timeout_fired or give up after N cycles
    task wait_for_timeout(input integer max_cyc, output got_it);
        integer k;
        begin
            got_it = 0;
            for (k = 0; k < max_cyc; k = k + 1) begin
                @(posedge clk);
                if (timeout_fired) begin
                    got_it = 1;
                    k = max_cyc; // break
                end
            end
        end
    endtask

    reg got;

    initial begin
        $display("=== cpl_timeout_logic Testbench ===");

        // --------------------------------------------------
        // T1: Tag 1 completes before timeout → no fire
        // --------------------------------------------------
        $display("\n[T1] Tag 1 completes before timeout");
        do_reset;
        cpl_timeout_val = 20'd20;
        alloc(10'd1);
        repeat(5) @(posedge clk);
        ret(10'd1);
        repeat(5) @(posedge clk);
        check(timeout_fired, 1'b0, "no timeout_fired");
        check(cpl_abort_req, 1'b0, "no abort");

        // --------------------------------------------------
        // T2: Tag 2 expires → timeout_fired + abort
        // --------------------------------------------------
        $display("\n[T2] Tag 2 expires → timeout_fired");
        do_reset;
        cpl_timeout_val = 20'd8;
        alloc(10'd2);
        wait_for_timeout(25, got);
        check(got,           1'b1, "timeout_fired detected");
        check(cpl_abort_req, 1'b1, "cpl_abort_req set");

        // --------------------------------------------------
        // T3: err_to_aer = 0xE on timeout
        // --------------------------------------------------
        $display("\n[T3] err_to_aer code on timeout");
        // (timeout still firing from T2 same edge)
        do_reset;
        cpl_timeout_val = 20'd8;
        alloc(10'd3);
        wait_for_timeout(25, got);
        if (got) begin
            if (err_to_aer === 4'hE) begin
                $display("  PASS  err_to_aer=0xE");
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  err_to_aer=0x%0h (exp 0xE)", err_to_aer);
                fail_count = fail_count + 1;
            end
        end

        // --------------------------------------------------
        // T4: Tags 4,5,6 alloc; 4 & 6 complete, 5 times out
        // --------------------------------------------------
        $display("\n[T4] Tag 5 times out while 4 & 6 OK");
        do_reset;
        cpl_timeout_val = 20'd12;
        alloc(10'd4);
        alloc(10'd5);
        alloc(10'd6);
        repeat(4) @(posedge clk);
        ret(10'd4);
        ret(10'd6);
        wait_for_timeout(25, got);
        check(got, 1'b1, "timeout fired for remaining tag");
        check_tag(timeout_tag, 10'd5, "timeout_tag=5");

        // --------------------------------------------------
        // T5: Re-alloc same tag after its timeout
        // --------------------------------------------------
        $display("\n[T5] Re-alloc tag 5 after timeout");
        cpl_timeout_val = 20'd15;
        alloc(10'd5);
        repeat(5) @(posedge clk);
        ret(10'd5);
        repeat(5) @(posedge clk);
        check(timeout_fired, 1'b0, "no spurious timeout");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                  $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
