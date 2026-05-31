`timescale 1ns/1ps
module tb_ack_pgb;
    reg clk,rst_n; reg [11:0] ack_pending_seq; reg ack_pending,nop_send_req;
    reg [15:0] ack_lat_limit;
    wire [11:0] ack_piggyback_seq; wire ack_piggyback_valid,ack_sent;
    integer pass_count=0,fail_count=0;

    ack_pgb dut(.clk(clk),.rst_n(rst_n),.ack_pending_seq(ack_pending_seq),
        .ack_pending(ack_pending),.nop_send_req(nop_send_req),.ack_lat_limit(ack_lat_limit),
        .ack_piggyback_seq(ack_piggyback_seq),.ack_piggyback_valid(ack_piggyback_valid),.ack_sent(ack_sent));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk12; input [11:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=%0d",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%0d got=%0d",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;ack_pending_seq=0;ack_pending=0;nop_send_req=0;ack_lat_limit=10;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    initial begin
        $display("=== TB: ack_pgb ===");

        $display("[TC1] Reset clears outputs");
        rst; @(posedge clk); #1;
        chk1(0,ack_piggyback_valid,"ack_piggyback_valid=0 after reset");
        chk1(0,ack_sent,"ack_sent=0 after reset");

        $display("[TC2] No pending -> no piggyback");
        rst; ack_pending=0;
        nop_send_req=1; @(posedge clk); #1; nop_send_req=0;
        chk1(0,ack_piggyback_valid,"no piggyback when no pending");

        $display("[TC3] nop_send_req triggers piggyback");
        rst;
        ack_pending_seq=12'hABC; ack_pending=1; nop_send_req=1;
        @(posedge clk); #1;
        chk1(1,ack_piggyback_valid,"ack_piggyback_valid=1 on nop_req");
        chk1(1,ack_sent,"ack_sent=1 on nop_req");
        nop_send_req=0;

        $display("[TC4] ack_piggyback_seq == ack_pending_seq");
        rst;
        ack_pending_seq=12'h5A5; ack_pending=1; nop_send_req=1;
        @(posedge clk); #1;
        chk12(12'h5A5,ack_piggyback_seq,"ack_piggyback_seq=0x5A5");
        nop_send_req=0;

        $display("[TC5] Latency limit triggers piggyback");
        rst; ack_lat_limit=16'd5;
        ack_pending_seq=12'h100; ack_pending=1;
        repeat(7)@(posedge clk); #1;
        chk1(1,ack_piggyback_valid,"piggyback at lat_limit");
        chk1(1,ack_sent,"ack_sent at lat_limit");

        $display("[TC6] ack_sent clears after pending removed");
        rst; ack_lat_limit=16'd3;
        ack_pending=1; ack_pending_seq=12'd10;
        repeat(5)@(posedge clk); #1;
        ack_pending=0; @(posedge clk); #1; @(posedge clk); #1;
        chk1(0,ack_sent,"ack_sent=0 after pending cleared");

        $display("[TC7] Sequence updates on consecutive piggybacks");
        rst;
        ack_pending_seq=12'd7; ack_pending=1; nop_send_req=1;
        @(posedge clk); #1;
        chk12(12'd7,ack_piggyback_seq,"first piggyback seq=7");

        nop_send_req=0; @(posedge clk); #1;
        ack_pending_seq=12'd8; nop_send_req=1;
        @(posedge clk); #1;
        chk12(12'd8,ack_piggyback_seq,"second piggyback seq=8");
        nop_send_req=0;

        $display("[TC8] ack_piggyback_valid clears with no pending");
        rst;
        ack_pending=1; ack_pending_seq=12'd5; nop_send_req=1;
        @(posedge clk); #1;
        nop_send_req=0; ack_pending=0;
        @(posedge clk); #1; @(posedge clk); #1;
        chk1(0,ack_piggyback_valid,"ack_piggyback_valid=0 after clear");

        $display("=== ack_pgb: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
