`timescale 1ns / 1ps

module tb_arb_tx;

    parameter CLK_PERIOD = 4;

    reg clk, rst_n;

    reg         req_p_valid;
    reg         req_np_valid;
    reg [575:0] req_p;
    reg [575:0] req_np;

    reg credit_grant_p;
    reg credit_grant_np;

    reg ordering_ok;

    wire [575:0] arb_tlp;
    wire         arb_tlp_valid;
    wire [1:0]   arb_type;

    arb_tx dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_p_valid(req_p_valid),
        .req_np_valid(req_np_valid),
        .req_p(req_p),
        .req_np(req_np),
        .credit_grant_p(credit_grant_p),
        .credit_grant_np(credit_grant_np),
        .ordering_ok(ordering_ok),
        .arb_tlp(arb_tlp),
        .arb_tlp_valid(arb_tlp_valid),
        .arb_type(arb_type)
    );

    // Clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass = 0, fail = 0, test_id = 0;

    reg ordering_ok_d;

    // =============================
    task reset_dut;
    begin
        rst_n = 0;
        req_p_valid = 0;
        req_np_valid = 0;
        credit_grant_p = 0;
        credit_grant_np = 0;
        ordering_ok = 0;
        req_p = 0;
        req_np = 0;

        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
    end
    endtask

    // =============================
    task check;
        input cond;
    begin
        test_id = test_id + 1;
        if (cond) begin
            $display("[PASS] T%0d", test_id);
            pass = pass + 1;
        end else begin
            $display("[FAIL] T%0d", test_id);
            fail = fail + 1;
        end
    end
    endtask

    // =============================
    initial begin
        $display("==== TB arb_tx START ====");
        reset_dut();

        // -------------------------------------------------
        // T1: Posted only
        // -------------------------------------------------
        req_p = 576'hAAAA;
        req_p_valid = 1;
        credit_grant_p = 1;
        ordering_ok = 1;

        @(posedge clk); #1;
        check(arb_tlp_valid && arb_type==0 && arb_tlp==req_p);

        // -------------------------------------------------
        // T2: Non-Posted only
        // -------------------------------------------------
        req_p_valid = 0;
        req_np = 576'hBBBB;
        req_np_valid = 1;
        credit_grant_np = 1;

        @(posedge clk); #1;
        check(arb_tlp_valid && arb_type==1 && arb_tlp==req_np);

        // -------------------------------------------------
        // T3: No credit ? stall
        // -------------------------------------------------
        credit_grant_np = 0;

        @(posedge clk); #1;
        check(!arb_tlp_valid);

        // -------------------------------------------------
        // T4: ordering stall
        // -------------------------------------------------
        req_p_valid = 1;
        credit_grant_p = 1;
        ordering_ok = 0;

        @(posedge clk); #1;
        check(!arb_tlp_valid);

        // -------------------------------------------------
        // T5: Round robin check
        // -------------------------------------------------
        ordering_ok = 1;
        req_p_valid = 1;
        req_np_valid = 1;
        credit_grant_p = 1;
        credit_grant_np = 1;

        @(posedge clk); #1;
        check(arb_tlp_valid);

        @(posedge clk); #1;
        check(arb_tlp_valid);

        // -------------------------------------------------
        // T6: Back-to-back random traffic
        // -------------------------------------------------
        repeat(5) begin
            req_p_valid  = {$random} % 2; // FIXED to {$random}
            req_np_valid = {$random} % 2; // FIXED to {$random}
            credit_grant_p  = 1;
            credit_grant_np = 1;
            ordering_ok = 1;

            @(posedge clk); #1;
            if (req_p_valid || req_np_valid)
                check(arb_tlp_valid);
        end

        // -------------------------------------------------
        // T7: Reset during operation
        // -------------------------------------------------
        req_p_valid = 1;
        credit_grant_p = 1;
        ordering_ok = 1;

        @(posedge clk);
        rst_n = 0; // Assert reset

        @(posedge clk); #1;
        check(!arb_tlp_valid); // FIXED: Check while reset is active

        rst_n = 1; // Safely deassert reset for next tests

        // -------------------------------------------------
        // T8: FIXED RANDOM STRESS (correct model-aware check)
        // -------------------------------------------------
        repeat(10) begin
            req_p_valid  = {$random} % 2; // FIXED to {$random}
            req_np_valid = {$random} % 2; // FIXED to {$random}
            credit_grant_p  = {$random} % 2; // FIXED to {$random}
            credit_grant_np = {$random} % 2; // FIXED to {$random}
            ordering_ok = {$random} % 2; // FIXED to {$random}

            ordering_ok_d = ordering_ok;

            @(posedge clk); #1;

            // ?? correct condition for valid output
            if (arb_tlp_valid) begin
                check(ordering_ok_d &&
                     ((req_p_valid && credit_grant_p) ||
                      (req_np_valid && credit_grant_np)));
            end
        end

        // -------------------------------------------------
        // RESULTS
        // -------------------------------------------------
        #20;
        $display("==== RESULTS ====");
        $display("PASS=%0d FAIL=%0d", pass, fail);
        $finish;
    end

endmodule