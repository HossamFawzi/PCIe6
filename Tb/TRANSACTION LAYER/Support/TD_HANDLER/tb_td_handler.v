
`timescale 1ns/1ps
module tb_td_handler;

    reg          clk = 0;
    always #5 clk = ~clk;

    reg          rst_n;
    reg [1183:0] tlp_tx;
    reg          tlp_tx_valid;
    reg          tlp_td_bit;
    reg [31:0]   ecrc_val;
    reg          ecrc_en;

    wire [1215:0] tlp_with_digest;
    wire          digest_valid;
    wire          td_strip_ok;
    wire          td_err;

    td_handler dut (
        .clk(clk),.rst_n(rst_n),
        .tlp_tx(tlp_tx),.tlp_tx_valid(tlp_tx_valid),
        .tlp_td_bit(tlp_td_bit),.ecrc_val(ecrc_val),.ecrc_en(ecrc_en),
        .tlp_with_digest(tlp_with_digest),.digest_valid(digest_valid),
        .td_strip_ok(td_strip_ok),.td_err(td_err)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task chk1(input got, input exp, input [127:0] name);
        if (got===exp) begin
            $display("  PASS  %0s", name); pass_count=pass_count+1;
        end else begin
            $display("  FAIL  %0s got=%0b exp=%0b", name, got, exp);
            fail_count=fail_count+1;
        end
    endtask

    task chk32(input [31:0] got, input [31:0] exp, input [127:0] name);
        if (got===exp) begin
            $display("  PASS  %0s=0x%08h", name, got); pass_count=pass_count+1;
        end else begin
            $display("  FAIL  %0s got=0x%08h exp=0x%08h", name, got, exp);
            fail_count=fail_count+1;
        end
    endtask

    task do_reset;
        begin
            rst_n=0; tlp_tx=0; tlp_tx_valid=0;
            tlp_td_bit=0; ecrc_val=0; ecrc_en=0;
            repeat(4) @(posedge clk); rst_n=1; @(posedge clk);
        end
    endtask

    task apply(input [1183:0] tlp, input td, input [31:0] ecrc, input en);
        begin
            @(negedge clk);
            tlp_tx=tlp; tlp_tx_valid=1; tlp_td_bit=td; ecrc_val=ecrc; ecrc_en=en;
            @(posedge clk); #1;
            tlp_tx_valid=0;
        end
    endtask

    initial begin
        $display("=== td_handler Testbench ===");

        $display("\n[T1] TX: ecrc_en=1 td_bit=1 → ECRC appended");
        do_reset;
        apply(1184'hABCD_1234, 1, 32'hDEAD_BEEF, 1);
        chk1(digest_valid, 1'b1, "digest_valid=1");
        chk32(tlp_with_digest[31:0], 32'hDEAD_BEEF, "ECRC at [31:0]");

        $display("\n[T2] TX: no ECRC pass-through");
        do_reset;
        apply(1184'hCAFE_F00D, 0, 32'h0, 0);
        chk1(digest_valid, 1'b1, "digest_valid passthrough");
        chk1(td_err,       1'b0, "no td_err");

        $display("\n[T3] RX strip: ECRC match → td_strip_ok");
        do_reset;
        begin : T3_BLK
            reg [1183:0] rx_tlp;
            rx_tlp        = 1184'h0;
            rx_tlp[31:0]  = 32'h1234_5678;
            rx_tlp[1183:32]= 1152'hAA;
            apply(rx_tlp, 1, 32'h1234_5678, 0);
        end
        chk1(td_strip_ok, 1'b1, "td_strip_ok=1");
        chk1(td_err,      1'b0, "no td_err");

        $display("\n[T4] RX strip: ECRC mismatch → td_err");
        do_reset;
        begin : T4_BLK
            reg [1183:0] rx_tlp2;
            rx_tlp2        = 1184'h0;
            rx_tlp2[31:0]  = 32'hDEAD_BEEF;
            apply(rx_tlp2, 1, 32'hBAAD_F00D, 0);
        end
        chk1(td_err,      1'b1, "td_err=1 mismatch");
        chk1(td_strip_ok, 1'b0, "no strip_ok");

        $display("\n[T5] Idle → no outputs");
        do_reset;
        repeat(3) @(posedge clk); #1;
        chk1(digest_valid, 1'b0, "digest_valid=0");
        chk1(td_err,       1'b0, "td_err=0");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count==0) $display("ALL TESTS PASSED");
        else               $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
