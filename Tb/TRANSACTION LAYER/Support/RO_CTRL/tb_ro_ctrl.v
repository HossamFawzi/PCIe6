
`timescale 1ns/1ps

module tb_ro_ctrl;

    reg        clk = 0;
    always #5 clk = ~clk;

    reg        rst_n;
    reg        req_attr_ro;
    reg [3:0]  req_type;
    reg [2:0]  req_tc;
    reg        ro_en;
    reg        ordering_stall;

    wire       ro_bypass_ok;
    wire       ordering_override;
    wire       ro_err;

    ro_ctrl dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .req_attr_ro     (req_attr_ro),
        .req_type        (req_type),
        .req_tc          (req_tc),
        .ro_en           (ro_en),
        .ordering_stall  (ordering_stall),
        .ro_bypass_ok    (ro_bypass_ok),
        .ordering_override(ordering_override),
        .ro_err          (ro_err)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task chk1;
        input       got;
        input       exp;
        input [127:0] name;
        begin
            if (got === exp) begin
                $display("  PASS  %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %0s  got=%0b exp=%0b", name, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task do_reset;
        begin
            rst_n          = 0;
            req_attr_ro    = 0;
            req_type       = 4'h0;
            req_tc         = 3'h0;
            ro_en          = 0;
            ordering_stall = 0;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task apply;
        input       attr_ro;
        input [3:0] rtype;
        input       en;
        input       stall;
        begin
            @(negedge clk);
            req_attr_ro    = attr_ro;
            req_type       = rtype;
            ro_en          = en;
            ordering_stall = stall;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        $display("=== ro_ctrl Testbench ===");

        $display("\n[T1] MWr + RO=1 + ro_en=1");
        do_reset;
        apply(1, 4'b0000, 1, 0);
        chk1(ro_bypass_ok,     1'b1, "ro_bypass_ok=1");
        chk1(ro_err,           1'b0, "no ro_err");
        chk1(ordering_override,1'b0, "ordering_override=0");

        $display("\n[T2] MWr + RO=1 + ro_en=0");
        do_reset;
        apply(1, 4'b0000, 0, 0);
        chk1(ro_err,       1'b1, "ro_err=1");
        chk1(ro_bypass_ok, 1'b0, "no bypass");

        $display("\n[T3] MRd + RO=1 + ro_en=1");
        do_reset;
        apply(1, 4'b0001, 1, 0);
        chk1(ro_bypass_ok, 1'b1, "ro_bypass_ok=1 MRd");
        chk1(ro_err,       1'b0, "no error");

        $display("\n[T4] Cpl + RO=1 -> ro_err");
        do_reset;
        apply(1, 4'b1010, 1, 0);
        chk1(ro_err,       1'b1, "ro_err=1 Cpl");
        chk1(ro_bypass_ok, 1'b0, "no bypass Cpl");

        $display("\n[T5] MWr + RO=0");
        do_reset;
        apply(0, 4'b0000, 1, 0);
        chk1(ro_bypass_ok, 1'b0, "no bypass RO=0");
        chk1(ro_err,       1'b0, "no error");

        $display("\n[T6] RO=1 + ordering_stall=1");
        do_reset;
        apply(1, 4'b0000, 1, 1);
        chk1(ro_bypass_ok,     1'b1, "ro_bypass_ok=1");
        chk1(ordering_override,1'b1, "ordering_override=1");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                  $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
