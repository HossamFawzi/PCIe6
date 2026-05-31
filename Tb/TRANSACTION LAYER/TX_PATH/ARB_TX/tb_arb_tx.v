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

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass = 0, fail = 0, test_id = 0;

    reg ordering_ok_d;

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

    initial begin
        $display("==== TB arb_tx START ====");
        reset_dut();

        req_p = 576'hAAAA;
        req_p_valid = 1;
        credit_grant_p = 1;
        ordering_ok = 1;

        @(posedge clk); #1;
        check(arb_tlp_valid && arb_type==0 && arb_tlp==req_p);

        req_p_valid = 0;
        req_np = 576'hBBBB;
        req_np_valid = 1;
        credit_grant_np = 1;

        @(posedge clk); #1;
        check(arb_tlp_valid && arb_type==1 && arb_tlp==req_np);

        credit_grant_np = 0;

        @(posedge clk); #1;
        check(!arb_tlp_valid);

        req_p_valid = 1;
        credit_grant_p = 1;
        ordering_ok = 0;

        @(posedge clk); #1;
        check(!arb_tlp_valid);

        ordering_ok = 1;
        req_p_valid = 1;
        req_np_valid = 1;
        credit_grant_p = 1;
        credit_grant_np = 1;

        @(posedge clk); #1;
        check(arb_tlp_valid);

        @(posedge clk); #1;
        check(arb_tlp_valid);

        repeat(5) begin
            req_p_valid  = {$random} % 2;
            req_np_valid = {$random} % 2;
            credit_grant_p  = 1;
            credit_grant_np = 1;
            ordering_ok = 1;

            @(posedge clk); #1;
            if (req_p_valid || req_np_valid)
                check(arb_tlp_valid);
        end

        req_p_valid = 1;
        credit_grant_p = 1;
        ordering_ok = 1;

        @(posedge clk);
        rst_n = 0;

        @(posedge clk); #1;
        check(!arb_tlp_valid);

        rst_n = 1;

        repeat(10) begin
            req_p_valid  = {$random} % 2;
            req_np_valid = {$random} % 2;
            credit_grant_p  = {$random} % 2;
            credit_grant_np = {$random} % 2;
            ordering_ok = {$random} % 2;

            ordering_ok_d = ordering_ok;

            @(posedge clk); #1;

            if (arb_tlp_valid) begin
                check(ordering_ok_d &&
                     ((req_p_valid && credit_grant_p) ||
                      (req_np_valid && credit_grant_np)));
            end
        end

        #20;
        $display("==== RESULTS ====");
        $display("PASS=%0d FAIL=%0d", pass, fail);
        $finish;
    end

endmodule