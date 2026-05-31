`timescale 1ns/1ps
module tb_dll_init;
    reg clk,rst_n,ltssm_dl_up,ltssm_dl_down,fc_init_done,replay_rollover_err,dll_link_down;
    wire dll_up_to_tl,dll_reset_seq,dll_active,dll_error;
    integer pass_count=0,fail_count=0;

    dll_init dut(.clk(clk),.rst_n(rst_n),.ltssm_dl_up(ltssm_dl_up),.ltssm_dl_down(ltssm_dl_down),
        .fc_init_done(fc_init_done),.replay_rollover_err(replay_rollover_err),.dll_link_down(dll_link_down),
        .dll_up_to_tl(dll_up_to_tl),.dll_reset_seq(dll_reset_seq),.dll_active(dll_active),.dll_error(dll_error));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;ltssm_dl_up=0;ltssm_dl_down=0;fc_init_done=0;
        replay_rollover_err=0;dll_link_down=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask
    task to_active; begin
        ltssm_dl_up=1; @(posedge clk); #1; ltssm_dl_up=0;
        @(posedge clk); #1;
        fc_init_done=1; @(posedge clk); #1; fc_init_done=0;
        @(posedge clk); #1; end endtask

    initial begin
        $display("=== TB: dll_init ===");

        // TC1: Reset
        $display("[TC1] Reset state");
        rst; @(posedge clk); #1;
        chk1(0,dll_up_to_tl,"dll_up_to_tl=0");
        chk1(0,dll_active,"dll_active=0");
        chk1(0,dll_error,"dll_error=0");

        // TC2: dl_up -> dll_reset_seq pulse registered same clock
        $display("[TC2] ltssm_dl_up -> dll_reset_seq");
        rst;
        ltssm_dl_up=1; @(posedge clk); #1; ltssm_dl_up=0;
        // dll_reset_seq is registered ON the clock that sees dl_up=1
        chk1(1,dll_reset_seq,"dll_reset_seq=1 on INIT entry");

        // TC3: fc_init_done -> ACTIVE
        $display("[TC3] fc_init_done -> dll_active=1");
        rst; to_active;
        chk1(1,dll_active,"dll_active=1 in ACTIVE");
        chk1(1,dll_up_to_tl,"dll_up_to_tl=1 in ACTIVE");

        // TC4: dll_up_to_tl=0 in INIT
        $display("[TC4] dll_up_to_tl=0 in INIT");
        rst;
        ltssm_dl_up=1; @(posedge clk); #1; ltssm_dl_up=0;
        @(posedge clk); #1;
        chk1(0,dll_up_to_tl,"dll_up_to_tl=0 in INIT");

        // TC5: dl_down in ACTIVE -> ERROR
        $display("[TC5] dl_down in ACTIVE -> dll_error");
        rst; to_active;
        ltssm_dl_down=1; @(posedge clk); #1; ltssm_dl_down=0;
        @(posedge clk); #1;
        chk1(1,dll_error,"dll_error=1 after dl_down");
        chk1(0,dll_active,"dll_active=0 in ERROR");
        chk1(0,dll_up_to_tl,"dll_up_to_tl=0 in ERROR");

        // TC6: replay_rollover -> ERROR
        $display("[TC6] replay_rollover_err -> dll_error");
        rst; to_active;
        replay_rollover_err=1; @(posedge clk); #1; replay_rollover_err=0;
        @(posedge clk); #1;
        chk1(1,dll_error,"dll_error=1 on replay_rollover");

        // TC7: ERROR + dl_up -> re-init, dll_reset_seq pulse
        $display("[TC7] ERROR + dl_up -> re-init");
        rst; to_active;
        ltssm_dl_down=1; @(posedge clk); #1; ltssm_dl_down=0;
        repeat(2)@(posedge clk); #1;
        ltssm_dl_up=1; @(posedge clk); #1; ltssm_dl_up=0;
        chk1(0,dll_error,"dll_error cleared on re-init");
        chk1(1,dll_reset_seq,"dll_reset_seq on re-init");

        // TC8: Full lifecycle
        $display("[TC8] Full lifecycle");
        rst; to_active;
        chk1(1,dll_active,"ACTIVE after first init");
        dll_link_down=1; @(posedge clk); #1; dll_link_down=0;
        repeat(2)@(posedge clk); #1;
        ltssm_dl_up=1; @(posedge clk); #1; ltssm_dl_up=0;
        @(posedge clk); #1;
        fc_init_done=1; @(posedge clk); #1; fc_init_done=0;
        @(posedge clk); #1;
        chk1(1,dll_active,"ACTIVE after second init");
        chk1(1,dll_up_to_tl,"dll_up_to_tl after second init");

        $display("=== dll_init: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
