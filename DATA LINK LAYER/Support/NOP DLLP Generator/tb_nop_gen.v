`timescale 1ns/1ps
module tb_nop_gen;
    reg clk,rst_n,dll_active,nop_timer_exp,nop_inhibit;
    wire nop_send; wire [63:0] nop_dllp; wire [7:0] nop_count;
    integer pass_count=0,fail_count=0;

    nop_gen dut(.clk(clk),.rst_n(rst_n),.dll_active(dll_active),
        .nop_timer_exp(nop_timer_exp),.nop_inhibit(nop_inhibit),
        .nop_send(nop_send),.nop_dllp(nop_dllp),.nop_count(nop_count));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk8; input [7:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=0x%02h",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=0x%02h got=0x%02h",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;dll_active=0;nop_timer_exp=0;nop_inhibit=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    initial begin
        $display("=== TB: nop_gen ===");

        // TC1: Reset
        $display("[TC1] Reset clears outputs");
        rst; @(posedge clk); #1;
        chk1(0,nop_send,"nop_send=0 after reset");
        chk8(0,nop_count,"nop_count=0 after reset");

        // TC2: dll_active=0 suppresses NOP
        $display("[TC2] dll_active=0 suppresses NOP");
        rst; dll_active=0;
        nop_timer_exp=1; @(posedge clk); #1; nop_timer_exp=0;
        chk1(0,nop_send,"nop_send=0 when dll_active=0");

        // TC3: nop_inhibit=1 suppresses NOP
        $display("[TC3] nop_inhibit suppresses NOP");
        rst; dll_active=1; nop_inhibit=1;
        nop_timer_exp=1; @(posedge clk); #1; nop_timer_exp=0;
        chk1(0,nop_send,"nop_send=0 when nop_inhibit=1");

        // TC4: Normal NOP - input high BEFORE posedge, check AFTER posedge+#1
        $display("[TC4] Normal NOP send");
        rst; dll_active=1; nop_inhibit=0;
        nop_timer_exp=1; @(posedge clk); #1;
        // At this point: posedge registered nop_timer_exp=1 -> nop_send=1
        chk1(1,nop_send,"nop_send=1 on timer_exp");
        nop_timer_exp=0;

        // TC5: NOP DLLP type byte = 0x00
        $display("[TC5] nop_dllp type byte=0x00");
        rst; dll_active=1;
        nop_timer_exp=1; @(posedge clk); #1;
        chk8(8'h00,nop_dllp[63:56],"NOP type=0x00");
        nop_timer_exp=0;

        // TC6: nop_count increments per NOP
        $display("[TC6] nop_count increments per NOP");
        rst; dll_active=1;
        repeat(3) begin
            nop_timer_exp=1; @(posedge clk); #1; nop_timer_exp=0;
            @(posedge clk); #1;
        end
        chk8(8'd3,nop_count,"nop_count=3 after 3 NOPs");

        // TC7: count unchanged when inhibited
        $display("[TC7] nop_count unchanged when inhibited");
        rst; dll_active=1; nop_inhibit=1;
        repeat(3) begin
            nop_timer_exp=1; @(posedge clk); #1; nop_timer_exp=0;
            @(posedge clk); #1;
        end
        chk8(8'd0,nop_count,"nop_count=0 when inhibited");

        // TC8: nop_send is one-cycle pulse
        $display("[TC8] nop_send is one-cycle pulse");
        rst; dll_active=1;
        nop_timer_exp=1; @(posedge clk); #1; nop_timer_exp=0;
        @(posedge clk); #1;  // next cycle: timer=0, nop_send<=0
        chk1(0,nop_send,"nop_send auto-clears");

        $display("=== nop_gen: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #10000 begin $display("TIMEOUT");$finish;end
endmodule
