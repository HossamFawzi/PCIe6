`timescale 1ns/1ps
module tb_pm_fsm;
    reg clk,rst_n; reg [2:0] pm_req_sw,pm_dllp_rx;
    reg pm_dllp_valid,l0s_timer_exp,l1_timer_exp;
    wire [2:0] pm_dllp_type,link_state,ltssm_pm_req; wire pm_dllp_send;
    integer pass_count=0,fail_count=0;
    localparam LS_L0=3'd0,LS_L0s=3'd1,LS_L1=3'd2;
    localparam PM_L1=3'd1,PM_L23=3'd2,PM_ACK=3'd3,PM_L0S=3'd4;

    pm_fsm dut(.clk(clk),.rst_n(rst_n),.pm_req_sw(pm_req_sw),.pm_dllp_rx(pm_dllp_rx),
        .pm_dllp_valid(pm_dllp_valid),.l0s_timer_exp(l0s_timer_exp),.l1_timer_exp(l1_timer_exp),
        .pm_dllp_type(pm_dllp_type),.pm_dllp_send(pm_dllp_send),
        .link_state(link_state),.ltssm_pm_req(ltssm_pm_req));

    initial clk=0; always #5 clk=~clk;
    task chkS; input [2:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=%0d",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%0d got=%0d",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;pm_req_sw=0;pm_dllp_rx=0;pm_dllp_valid=0;
        l0s_timer_exp=0;l1_timer_exp=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    initial begin
        $display("=== TB: pm_fsm ===");

        // TC1: Reset -> L0
        $display("[TC1] Reset -> link_state=L0");
        rst; @(posedge clk); #1;
        chkS(LS_L0,link_state,"link_state=L0 after reset");

        // TC2: pm_req_sw=L0S -> L0s, pm_dllp_send=1 same clock
        $display("[TC2] PM_ENTER_L0S -> L0s + pm_dllp_send");
        rst;
        pm_req_sw=PM_L0S; @(posedge clk); #1;
        chkS(LS_L0s,link_state,"link_state=L0s");
        chk1(1,pm_dllp_send,"pm_dllp_send=1 on L0s entry");
        chkS(PM_L0S,pm_dllp_type,"pm_dllp_type=ENTER_L0S");
        pm_req_sw=0;

        // TC3: l0s_timer_exp -> L0s
        $display("[TC3] l0s_timer_exp -> L0s");
        rst;
        l0s_timer_exp=1; @(posedge clk); #1; l0s_timer_exp=0;
        chkS(LS_L0s,link_state,"link_state=L0s via timer");

        // TC4: pm_req_sw=L1 -> L1
        $display("[TC4] PM_ENTER_L1 -> L1 + pm_dllp_send");
        rst;
        pm_req_sw=PM_L1; @(posedge clk); #1;
        chkS(LS_L1,link_state,"link_state=L1");
        chk1(1,pm_dllp_send,"pm_dllp_send=1 on L1 entry");
        pm_req_sw=0;

        // TC5: L0s + PM_REQ_ACK -> L0
        $display("[TC5] L0s + PM_REQ_ACK -> L0");
        rst; pm_req_sw=PM_L0S; @(posedge clk); #1; pm_req_sw=0;
        @(posedge clk); #1;
        pm_dllp_rx=PM_ACK; pm_dllp_valid=1;
        @(posedge clk); #1; pm_dllp_valid=0;
        @(posedge clk); #1;
        chkS(LS_L0,link_state,"link_state=L0 after L0s ACK");

        // TC6: L0s + pm_req_sw=0 -> L0
        $display("[TC6] L0s + pm_req_sw=0 -> L0");
        rst; pm_req_sw=PM_L0S; @(posedge clk); #1;
        pm_req_sw=3'd0; @(posedge clk); #1; @(posedge clk); #1;
        chkS(LS_L0,link_state,"link_state=L0 after L0s exit");

        // TC7: L1 + PM_REQ_ACK -> L0
        $display("[TC7] L1 + PM_REQ_ACK -> L0");
        rst; pm_req_sw=PM_L1; @(posedge clk); #1; pm_req_sw=0;
        @(posedge clk); #1;
        pm_dllp_rx=PM_ACK; pm_dllp_valid=1;
        @(posedge clk); #1; pm_dllp_valid=0; @(posedge clk); #1;
        chkS(LS_L0,link_state,"link_state=L0 from L1 ACK");

        // TC8: ltssm_pm_req
        $display("[TC8] ltssm_pm_req on L1 entry");
        rst; pm_req_sw=PM_L1; @(posedge clk); #1; pm_req_sw=0;
        @(posedge clk); #1;
        chkS(PM_L1,ltssm_pm_req,"ltssm_pm_req=PM_ENTER_L1");

        $display("=== pm_fsm: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
