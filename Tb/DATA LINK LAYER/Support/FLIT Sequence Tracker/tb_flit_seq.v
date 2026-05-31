`timescale 1ns/1ps
module tb_flit_seq;
    reg clk,rst_n; reg [11:0] flit_tx_seq,flit_rx_seq,ack_seq,nak_seq; reg link_reset;
    wire [11:0] oldest_unacked_seq; wire seq_window_full,seq_wrap_det,seq_err;
    integer pass_count=0,fail_count=0;

    flit_seq dut(.clk(clk),.rst_n(rst_n),.flit_tx_seq(flit_tx_seq),.flit_rx_seq(flit_rx_seq),
        .ack_seq(ack_seq),.nak_seq(nak_seq),.link_reset(link_reset),
        .oldest_unacked_seq(oldest_unacked_seq),.seq_window_full(seq_window_full),
        .seq_wrap_det(seq_wrap_det),.seq_err(seq_err));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk12; input [11:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=%0d",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%0d got=%0d",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;flit_tx_seq=0;flit_rx_seq=0;ack_seq=0;nak_seq=0;link_reset=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    initial begin
        $display("=== TB: flit_seq ===");

        $display("[TC1] Reset clears state");
        rst; @(posedge clk); #1;
        chk12(12'd0,oldest_unacked_seq,"oldest_unacked=0 after reset");
        chk1(0,seq_window_full,"seq_window_full=0 after reset");
        chk1(0,seq_wrap_det,"seq_wrap_det=0 after reset");

        $display("[TC2] link_reset clears tracker");
        rst;
        flit_tx_seq=12'd100; ack_seq=12'd50;
        @(posedge clk); #1; @(posedge clk); #1;

        link_reset=1; ack_seq=12'd0; flit_tx_seq=12'd0;
        @(posedge clk); #1; link_reset=0;
        @(posedge clk); #1;
        chk12(12'd0,oldest_unacked_seq,"oldest_unacked=0 after link_reset");

        $display("[TC3] ACK advances oldest_unacked_seq");
        rst;
        flit_tx_seq=12'd10; ack_seq=12'd5;
        @(posedge clk); #1; @(posedge clk); #1;
        chk12(12'd6,oldest_unacked_seq,"oldest_unacked=ack+1=6");

        $display("[TC4] Sequential ACKs advance tracker");
        rst;
        flit_tx_seq=12'd20; ack_seq=12'd10;
        @(posedge clk); #1; @(posedge clk); #1;
        ack_seq=12'd15; @(posedge clk); #1; @(posedge clk); #1;
        chk12(12'd16,oldest_unacked_seq,"oldest_unacked=16 after ack=15");

        $display("[TC5] seq_window_full at 2048 outstanding");
        rst;
        ack_seq=12'd0; flit_tx_seq=12'd2048;
        @(posedge clk); #1; @(posedge clk); #1;
        chk1(1,seq_window_full,"seq_window_full=1 at 2048");

        $display("[TC6] seq_window_full=0 below threshold");
        rst;
        ack_seq=12'd0; flit_tx_seq=12'd100;
        @(posedge clk); #1; @(posedge clk); #1;
        chk1(0,seq_window_full,"seq_window_full=0 at 100");

        $display("[TC7] Window clears as ACKs arrive");
        rst;
        ack_seq=12'd0; flit_tx_seq=12'd2048;
        @(posedge clk); #1; @(posedge clk); #1;
        chk1(1,seq_window_full,"window full first");
        ack_seq=12'd2000; @(posedge clk); #1; @(posedge clk); #1;
        chk1(0,seq_window_full,"window cleared after ACK catchup");

        $display("[TC8] seq_wrap_det on rollover");
        rst;
        flit_tx_seq=12'd4095; @(posedge clk); #1;
        flit_tx_seq=12'd0;    @(posedge clk); #1;
        chk1(1,seq_wrap_det,"seq_wrap_det=1 on 4095->0 rollover");

        $display("=== flit_seq: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
