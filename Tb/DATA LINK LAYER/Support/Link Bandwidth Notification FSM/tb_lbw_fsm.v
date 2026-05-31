`timescale 1ns/1ps
module tb_lbw_fsm;
    reg clk,rst_n; reg [3:0] ltssm_speed; reg [5:0] ltssm_width;
    reg bw_change_det,eq_req_from_phy;
    wire [63:0] bw_notif_dllp; wire bw_notif_valid,link_eq_req,link_eq_ack;
    wire [7:0] bw_status;
    integer pass_count=0,fail_count=0;

    lbw_fsm dut(.clk(clk),.rst_n(rst_n),.ltssm_speed(ltssm_speed),.ltssm_width(ltssm_width),
        .bw_change_det(bw_change_det),.eq_req_from_phy(eq_req_from_phy),
        .bw_notif_dllp(bw_notif_dllp),.bw_notif_valid(bw_notif_valid),
        .link_eq_req(link_eq_req),.link_eq_ack(link_eq_ack),.bw_status(bw_status));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk8; input [7:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=0x%02h",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=0x%02h got=0x%02h",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;ltssm_speed=0;ltssm_width=0;bw_change_det=0;eq_req_from_phy=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    initial begin
        $display("=== TB: lbw_fsm ===");

        $display("[TC1] Reset clears outputs");
        rst; @(posedge clk); #1;
        chk1(0,bw_notif_valid,"bw_notif_valid=0");
        chk1(0,link_eq_req,"link_eq_req=0");
        chk1(0,link_eq_ack,"link_eq_ack=0");

        $display("[TC2] bw_change_det -> bw_notif_valid");
        rst; ltssm_speed=4'd6; ltssm_width=6'd16;
        bw_change_det=1; @(posedge clk); #1; bw_change_det=0;
        @(posedge clk); #1;
        chk1(1,bw_notif_valid,"bw_notif_valid=1 on change");

        $display("[TC3] bw_notif_dllp[55:52] == ltssm_speed");
        rst; ltssm_speed=4'hA; ltssm_width=6'd8;
        bw_change_det=1; @(posedge clk); #1; bw_change_det=0;
        @(posedge clk); #1;
        if(bw_notif_dllp[55:52]===4'hA)begin $display("  PASS | dllp[55:52]=0xA");pass_count=pass_count+1;end
        else begin $display("  FAIL | dllp[55:52] exp=0xA got=0x%h",bw_notif_dllp[55:52]);fail_count=fail_count+1;end

        $display("[TC4] bw_status encoding");
        rst; ltssm_speed=4'd5; ltssm_width=6'd4;
        bw_change_det=1; @(posedge clk); #1; bw_change_det=0;
        @(posedge clk); #1;
        chk8({ltssm_speed,ltssm_width[3:0]},bw_status,"bw_status correct");

        $display("[TC5] Idle: bw_notif_valid stays 0");
        rst; ltssm_speed=4'd3; ltssm_width=6'd2;
        repeat(10)@(posedge clk); #1;
        chk1(0,bw_notif_valid,"bw_notif_valid=0 when idle");

        $display("[TC6] eq_req_from_phy -> link_eq_req");
        rst;
        eq_req_from_phy=1; @(posedge clk); #1;
        @(posedge clk); #1;
        chk1(1,link_eq_req,"link_eq_req=1 in EQ_REQ");

        $display("[TC7] eq_req de-asserts -> link_eq_ack");
        rst;
        eq_req_from_phy=1; @(posedge clk); #1;
        @(posedge clk); #1;

        @(negedge clk); eq_req_from_phy=0;
        @(posedge clk); #1;
        chk1(1,link_eq_ack,"link_eq_ack=1 after eq_req falls");

        $display("[TC8] bw_notif_valid auto-clears");
        rst; ltssm_speed=4'd2; ltssm_width=6'd1;
        bw_change_det=1; @(posedge clk); #1; bw_change_det=0;
        repeat(4)@(posedge clk); #1;
        chk1(0,bw_notif_valid,"bw_notif_valid=0 after notify done");

        $display("=== lbw_fsm: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
