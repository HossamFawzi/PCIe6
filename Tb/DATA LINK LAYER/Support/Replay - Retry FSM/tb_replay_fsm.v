`timescale 1ns/1ps
module tb_replay_fsm;
    reg clk,rst_n,nak_valid,replay_timer_exp;
    reg [11:0] nak_seq; reg [1:0] replay_num; reg [11:0] buf_occ;
    wire retry_req; wire [11:0] retry_seq_start;
    wire dll_link_down,replay_rollover_err;
    integer pass_count=0,fail_count=0;

    replay_fsm dut(.clk(clk),.rst_n(rst_n),.nak_valid(nak_valid),
        .replay_timer_exp(replay_timer_exp),.nak_seq(nak_seq),.replay_num(replay_num),
        .buf_occ(buf_occ),.retry_req(retry_req),.retry_seq_start(retry_seq_start),
        .dll_link_down(dll_link_down),.replay_rollover_err(replay_rollover_err));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;nak_valid=0;replay_timer_exp=0;nak_seq=0;replay_num=0;buf_occ=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    initial begin
        $display("=== TB: replay_fsm ===");

        $display("[TC1] Reset clears outputs");
        rst; @(posedge clk); #1;
        chk1(0,retry_req,"retry_req=0");
        chk1(0,dll_link_down,"dll_link_down=0");
        chk1(0,replay_rollover_err,"replay_rollover_err=0");

        $display("[TC2] NAK triggers retry_req");
        rst; replay_num=2'd0; nak_seq=12'hABC;

        nak_valid=1; @(posedge clk); #1; nak_valid=0;
        chk1(1,retry_req,"retry_req=1 on NAK");

        $display("[TC3] retry_seq_start follows nak_seq");
        rst; replay_num=2'd0; nak_seq=12'h123;
        nak_valid=1; @(posedge clk); #1; nak_valid=0;
        if(retry_seq_start===12'h123)begin $display("  PASS | retry_seq_start=0x123");pass_count=pass_count+1;end
        else begin $display("  FAIL | retry_seq_start exp=0x123 got=0x%h",retry_seq_start);fail_count=fail_count+1;end

        $display("[TC4] retry_req auto-clears");
        rst; replay_num=2'd0;
        nak_valid=1; @(posedge clk); #1; nak_valid=0;
        @(posedge clk); #1;
        chk1(0,retry_req,"retry_req=0 after one cycle");

        $display("[TC5] replay_timer_exp triggers retry_req");
        rst; replay_num=2'd1;
        replay_timer_exp=1; @(posedge clk); #1; replay_timer_exp=0;
        chk1(1,retry_req,"retry_req=1 on replay_timer_exp");

        $display("[TC6] replay_num=3 causes dll_link_down");
        rst; replay_num=2'd3;
        nak_valid=1; @(posedge clk); #1; nak_valid=0;
        @(posedge clk); #1;
        chk1(1,dll_link_down,"dll_link_down=1 at replay_num=3");
        chk1(1,replay_rollover_err,"replay_rollover_err=1 at replay_num=3");

        $display("[TC7] replay_num=2 -> no link_down");
        rst; replay_num=2'd2;
        nak_valid=1; @(posedge clk); #1; nak_valid=0;
        repeat(3)@(posedge clk); #1;
        chk1(0,dll_link_down,"dll_link_down=0 when replay_num=2");

        $display("[TC8] Idle: no retry");
        rst; replay_num=2'd0;
        repeat(10)@(posedge clk); #1;
        chk1(0,retry_req,"retry_req=0 when idle");

        $display("=== replay_fsm: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
