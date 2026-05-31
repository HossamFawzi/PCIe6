`timescale 1ns/1ps
module tb_dllp_gen;
    reg clk,rst_n; reg [71:0] fc_update; reg fc_update_valid,fc_update_req;
    reg [2:0] pm_type; reg pm_send,nop_send; reg [63:0] bw_notif; reg bw_notif_valid;
    wire [63:0] fc_dllp,pm_dllp,nop_dllp; wire fc_dllp_valid,pm_dllp_valid,nop_valid;
    integer pass_count=0,fail_count=0;
    localparam NOP_T=8'h00, PM_B=8'h20;

    dllp_gen dut(.clk(clk),.rst_n(rst_n),.fc_update(fc_update),.fc_update_valid(fc_update_valid),
        .fc_update_req(fc_update_req),.pm_type(pm_type),.pm_send(pm_send),.nop_send(nop_send),
        .bw_notif(bw_notif),.bw_notif_valid(bw_notif_valid),
        .fc_dllp(fc_dllp),.fc_dllp_valid(fc_dllp_valid),.pm_dllp(pm_dllp),.pm_dllp_valid(pm_dllp_valid),
        .nop_dllp(nop_dllp),.nop_valid(nop_valid));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk8; input [7:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=0x%02h",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=0x%02h got=0x%02h",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;fc_update=0;fc_update_valid=0;fc_update_req=0;
        pm_type=0;pm_send=0;nop_send=0;bw_notif=0;bw_notif_valid=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    initial begin
        $display("=== TB: dllp_gen ===");

        $display("[TC1] Reset: all valids=0");
        rst; @(posedge clk); #1;
        chk1(0,fc_dllp_valid,"fc_dllp_valid=0");
        chk1(0,pm_dllp_valid,"pm_dllp_valid=0");
        chk1(0,nop_valid,"nop_valid=0");

        $display("[TC2] fc_update_valid -> fc_dllp_valid");
        rst; fc_update=72'hABCDEF;
        fc_update_valid=1; @(posedge clk); #1;
        chk1(1,fc_dllp_valid,"fc_dllp_valid=1");
        fc_update_valid=0;

        $display("[TC3] fc_update_req alone -> fc_dllp_valid");
        rst; fc_update_req=1; @(posedge clk); #1;
        chk1(1,fc_dllp_valid,"fc_dllp_valid=1 on req alone");
        fc_update_req=0;

        $display("[TC4] pm_send -> pm_dllp_valid");
        rst; pm_type=3'd2;
        pm_send=1; @(posedge clk); #1;
        chk1(1,pm_dllp_valid,"pm_dllp_valid=1");
        chk8(PM_B|8'd2,pm_dllp[63:56],"pm_dllp type byte");
        pm_send=0;

        $display("[TC5] nop_send -> nop_valid type=0x00");
        rst;
        nop_send=1; @(posedge clk); #1;
        chk1(1,nop_valid,"nop_valid=1");
        chk8(NOP_T,nop_dllp[63:56],"nop type=0x00");
        nop_send=0;

        $display("[TC6] bw_notif_valid -> fc_dllp");
        rst; bw_notif=64'hDEADBEEF12345678;
        bw_notif_valid=1; @(posedge clk); #1;
        chk1(1,fc_dllp_valid,"fc_dllp_valid=1 for bw_notif");
        if(fc_dllp===64'hDEADBEEF12345678)begin $display("  PASS | fc_dllp=bw_notif");pass_count=pass_count+1;end
        else begin $display("  FAIL | fc_dllp mismatch: 0x%h",fc_dllp);fail_count=fail_count+1;end
        bw_notif_valid=0;

        $display("[TC7] No inputs -> all valids=0");
        rst; repeat(5)@(posedge clk); #1;
        chk1(0,fc_dllp_valid,"fc_dllp_valid=0 idle");
        chk1(0,pm_dllp_valid,"pm_dllp_valid=0 idle");
        chk1(0,nop_valid,"nop_valid=0 idle");

        $display("[TC8] Simultaneous fc_update_valid + nop_send");
        rst; fc_update=72'hFF;
        fc_update_valid=1; nop_send=1; @(posedge clk); #1;
        chk1(1,fc_dllp_valid,"fc_dllp_valid=1 simultaneous");
        chk1(1,nop_valid,"nop_valid=1 simultaneous");
        fc_update_valid=0; nop_send=0;

        $display("=== dllp_gen: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
