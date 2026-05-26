`timescale 1ns/1ps
module tb_ack_tmr;
    reg        clk, rst_n, tlp_rx_valid, ack_sent;
    reg [15:0] ack_lat_limit, replay_limit;
    wire       ack_timer_exp, replay_timer_exp;
    wire [1:0] replay_num;
    integer pass_count = 0, fail_count = 0;

    ack_tmr dut(.clk(clk),.rst_n(rst_n),.tlp_rx_valid(tlp_rx_valid),.ack_sent(ack_sent),
        .ack_lat_limit(ack_lat_limit),.replay_limit(replay_limit),
        .ack_timer_exp(ack_timer_exp),.replay_timer_exp(replay_timer_exp),.replay_num(replay_num));

    initial clk=0; always #5 clk=~clk;

    task chk; input [63:0] exp,got; input [127:0] n;
        begin if(exp===got) begin $display("  PASS | %s",n); pass_count=pass_count+1; end
        else begin $display("  FAIL | %s | exp=%0d got=%0d",n,exp,got); fail_count=fail_count+1; end end
    endtask

    task rst; begin rst_n=0;tlp_rx_valid=0;ack_sent=0;ack_lat_limit=10;replay_limit=20;
        repeat(2)@(posedge clk); rst_n=1; #1; end endtask

    integer i;
    initial begin
        $display("=== TB: ack_tmr ===");

        // TC1: Reset
        $display("[TC1] Reset clears outputs");
        rst; @(posedge clk); #1;
        chk(0,ack_timer_exp,"ack_timer_exp=0 after reset");
        chk(0,replay_timer_exp,"replay_timer_exp=0 after reset");
        chk(0,replay_num,"replay_num=0 after reset");

        // TC2: No TLP - timers silent
        $display("[TC2] No TLP - timers silent");
        rst; for(i=0;i<30;i=i+1)@(posedge clk); #1;
        chk(0,ack_timer_exp,"ack_timer_exp stays 0");
        chk(0,replay_timer_exp,"replay_timer_exp stays 0");

        // TC3: ACK latency timer fires
        $display("[TC3] ACK latency timer fires");
        rst; ack_lat_limit=5; replay_limit=50;
        tlp_rx_valid=1; @(posedge clk); #1; tlp_rx_valid=0;
        repeat(7)@(posedge clk); #1;
        chk(1,ack_timer_exp,"ack_timer_exp fires at limit");

        // TC4: ack_sent clears timer
        $display("[TC4] ack_sent clears timer");
        rst; ack_lat_limit=5; replay_limit=50;
        tlp_rx_valid=1; @(posedge clk); #1; tlp_rx_valid=0;
        repeat(3)@(posedge clk); #1;
        ack_sent=1; @(posedge clk); #1; ack_sent=0;
        repeat(5)@(posedge clk); #1;
        chk(0,ack_timer_exp,"ack_timer_exp cleared after ack_sent");

        // TC5: Replay timer fires
        $display("[TC5] Replay timer fires");
        rst; ack_lat_limit=200; replay_limit=8;
        tlp_rx_valid=1; @(posedge clk); #1; tlp_rx_valid=0;
        repeat(11)@(posedge clk); #1;
        chk(1,replay_timer_exp,"replay_timer_exp fires at limit");

        // TC6: replay_num increments
        $display("[TC6] replay_num increments");
        rst; ack_lat_limit=200; replay_limit=4;
        tlp_rx_valid=1; @(posedge clk); #1; tlp_rx_valid=0;
        repeat(7)@(posedge clk); #1;
        if(replay_num>=1)begin $display("  PASS | replay_num >= 1 | got=%0d",replay_num);pass_count=pass_count+1;end
        else begin $display("  FAIL | replay_num < 1 | got=%0d",replay_num);fail_count=fail_count+1;end

        // TC7: replay_num saturates at 3
        $display("[TC7] replay_num saturates at 3");
        rst; ack_lat_limit=200; replay_limit=2;
        tlp_rx_valid=1; @(posedge clk); #1; tlp_rx_valid=0;
        repeat(50)@(posedge clk); #1;
        chk(3,replay_num,"replay_num saturates at 3");

        // TC8: ack_sent resets replay_num - key fix: wait extra cycle after ack_sent
        $display("[TC8] ack_sent resets replay_num");
        rst; ack_lat_limit=200; replay_limit=2;
        tlp_rx_valid=1; @(posedge clk); #1; tlp_rx_valid=0;
        repeat(10)@(posedge clk); #1;
        // replay_timer_exp is high; now send ack
        ack_sent=1; @(posedge clk); #1; ack_sent=0;
        // Need extra cycle: RTL clears replay_timer_exp when ack_sent, and replay_num clears next cycle
        @(posedge clk); #1;
        chk(0,replay_num,"replay_num=0 after ack_sent");

        $display("=== ack_tmr: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #20000 begin $display("TIMEOUT");$finish;end
endmodule
