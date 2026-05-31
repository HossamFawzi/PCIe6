
`timescale 1ns/1ps

module tb_tc_vc_mapper;

    reg        clk = 0;
    always #5 clk = ~clk;

    reg        rst_n;
    reg [2:0]  tlp_tc;
    reg        tlp_valid;
    reg [23:0] vc_map_cfg;
    reg [7:0]  vc_arb_cfg;

    wire [2:0] vc_id;
    wire       vc_map_valid;
    wire       vc_map_err;

    tc_vc_mapper dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .tlp_tc     (tlp_tc),
        .tlp_valid  (tlp_valid),
        .vc_map_cfg (vc_map_cfg),
        .vc_arb_cfg (vc_arb_cfg),
        .vc_id      (vc_id),
        .vc_map_valid(vc_map_valid),
        .vc_map_err (vc_map_err)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task check(input [3:0] got, input [3:0] exp, input [127:0] name);
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
            rst_n       = 0;
            tlp_tc      = 3'h0;
            tlp_valid   = 0;

            vc_map_cfg  = 24'h000000;
            vc_arb_cfg  = 8'h00;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task send_tlp(input [2:0] tc);
        begin
            @(negedge clk);
            tlp_tc    = tc;
            tlp_valid = 1;
            @(posedge clk); #1;
            tlp_valid = 0;
        end
    endtask

    function [23:0] set_tc_vc;
        input [23:0] cfg;
        input [2:0]  tc;
        input [2:0]  vc;
        begin
            set_tc_vc = cfg;
            set_tc_vc[3*tc +: 3] = vc;
        end
    endfunction

    initial begin
        $display("=== tc_vc_mapper Testbench ===");

        $display("\n[T1] All TC→VC0 by default, TC3");
        do_reset;
        vc_map_cfg = 24'h000000;
        send_tlp(3'd3);
        check(vc_id,        3'd0, "vc_id=0");
        check(vc_map_valid, 1'b1, "vc_map_valid=1");
        check(vc_map_err,   1'b0, "no error");

        $display("\n[T2] TC1→VC1, TC2→VC2");
        do_reset;
        vc_map_cfg = 24'h000000;
        vc_map_cfg = set_tc_vc(vc_map_cfg, 3'd1, 3'd1);
        vc_map_cfg = set_tc_vc(vc_map_cfg, 3'd2, 3'd2);

        send_tlp(3'd1);
        check(vc_id, 3'd1, "TC1→VC1");
        check(vc_map_err, 1'b0, "no err TC1");

        send_tlp(3'd2);
        check(vc_id, 3'd2, "TC2→VC2");
        check(vc_map_err, 1'b0, "no err TC2");

        $display("\n[T3] TC7→VC3 (valid)");
        do_reset;
        vc_map_cfg = set_tc_vc(24'h000000, 3'd7, 3'd3);
        send_tlp(3'd7);
        check(vc_id,      3'd3, "TC7→VC3");
        check(vc_map_err, 1'b0, "no error for VC3");

        $display("\n[T4] TC5→VC7 triggers vc_map_err");
        do_reset;
        vc_map_cfg = set_tc_vc(24'h000000, 3'd5, 3'd7);
        send_tlp(3'd5);
        check(vc_map_err, 1'b1, "vc_map_err=1 for VC7");

        $display("\n[T5] tlp_valid=0 → vc_map_valid=0");
        do_reset;
        @(posedge clk);
        tlp_tc    = 3'd2;
        tlp_valid = 0;
        @(posedge clk); @(posedge clk);
        check(vc_map_valid, 1'b0, "vc_map_valid=0 when idle");

        $display("\n[T6] Back-to-back TC0→TC1→TC2→TC3");
        do_reset;
        vc_map_cfg = 24'h000000;
        vc_map_cfg = set_tc_vc(vc_map_cfg, 3'd0, 3'd0);
        vc_map_cfg = set_tc_vc(vc_map_cfg, 3'd1, 3'd1);
        vc_map_cfg = set_tc_vc(vc_map_cfg, 3'd2, 3'd2);
        vc_map_cfg = set_tc_vc(vc_map_cfg, 3'd3, 3'd3);
        send_tlp(3'd0); check(vc_id, 3'd0, "TC0→VC0");
        send_tlp(3'd1); check(vc_id, 3'd1, "TC1→VC1");
        send_tlp(3'd2); check(vc_id, 3'd2, "TC2→VC2");
        send_tlp(3'd3); check(vc_id, 3'd3, "TC3→VC3");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                  $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
