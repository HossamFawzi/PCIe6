`timescale 1ns/1ps
module tb_fc_init_fsm;
    reg clk,rst_n,dll_active; reg [71:0] initfc_rx; reg initfc_rx_valid,fc_init_timeout;
    wire [71:0] initfc_tx; wire initfc_tx_send,fc_init_done,fc_init_err; wire [2:0] fc_init_state;
    integer pass_count=0,fail_count=0;
    localparam FC1=8'hC0,FC2=8'hD0,FC3=8'hE0;
    localparam S_IDLE=3'd0,S_I1=3'd1,S_I2=3'd2,S_I3=3'd3,S_DONE=3'd4,S_ERR=3'd5;

    fc_init_fsm dut(.clk(clk),.rst_n(rst_n),.dll_active(dll_active),.initfc_rx(initfc_rx),
        .initfc_rx_valid(initfc_rx_valid),.fc_init_timeout(fc_init_timeout),
        .initfc_tx(initfc_tx),.initfc_tx_send(initfc_tx_send),
        .fc_init_done(fc_init_done),.fc_init_err(fc_init_err),.fc_init_state(fc_init_state));

    initial clk=0; always #5 clk=~clk;
    task chk1; input exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s",n);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%b got=%b",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk3; input [2:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=%0d",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=%0d got=%0d",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task chk8; input [7:0] exp,got; input [127:0] n;
        begin if(exp===got)begin $display("  PASS | %s | val=0x%02h",n,got);pass_count=pass_count+1;end
        else begin $display("  FAIL | %s | exp=0x%02h got=0x%02h",n,exp,got);fail_count=fail_count+1;end end
    endtask
    task rst; begin rst_n=0;dll_active=0;initfc_rx=0;initfc_rx_valid=0;fc_init_timeout=0;
        repeat(2)@(posedge clk);rst_n=1;#1; end endtask

    task full_handshake; begin
        dll_active=1; @(posedge clk); #1;
        @(posedge clk); #1;
        initfc_rx={64'hFFFFFFFFFFFFFFFF,FC1}; initfc_rx_valid=1;
        @(posedge clk); #1; initfc_rx_valid=0;
        @(posedge clk); #1;
        initfc_rx={64'hFFFFFFFFFFFFFFFF,FC2}; initfc_rx_valid=1;
        @(posedge clk); #1; initfc_rx_valid=0;
        @(posedge clk); #1;
        @(posedge clk); #1;
    end endtask

    initial begin
        $display("=== TB: fc_init_fsm ===");

        $display("[TC1] Reset = FC_IDLE");
        rst; @(posedge clk); #1;
        chk3(S_IDLE,fc_init_state,"state=FC_IDLE");
        chk1(0,initfc_tx_send,"initfc_tx_send=0");
        chk1(0,fc_init_done,"fc_init_done=0");

        $display("[TC2] dll_active=0 stays IDLE");
        rst; repeat(5)@(posedge clk); #1;
        chk3(S_IDLE,fc_init_state,"state=IDLE when inactive");

        $display("[TC3] dll_active=1 -> INIT1");
        rst; dll_active=1; @(posedge clk); #1;
        @(posedge clk); #1;
        chk3(S_I1,fc_init_state,"state=FC_INIT1");
        chk1(1,initfc_tx_send,"initfc_tx_send=1");
        chk8(FC1,initfc_tx[7:0],"tx=INITFC1(0xC0)");

        $display("[TC4] Peer INITFC1 -> INIT2");
        rst; dll_active=1; @(posedge clk); #1; @(posedge clk); #1;
        initfc_rx={64'hFFFFFFFFFFFFFFFF,FC1}; initfc_rx_valid=1;
        @(posedge clk); #1; initfc_rx_valid=0;
        @(posedge clk); #1;
        chk3(S_I2,fc_init_state,"state=FC_INIT2");
        chk8(FC2,initfc_tx[7:0],"tx=INITFC2(0xD0)");

        $display("[TC5] Peer INITFC2 -> INIT3");
        rst; dll_active=1; @(posedge clk); #1; @(posedge clk); #1;
        initfc_rx={64'hFFFFFFFFFFFFFFFF,FC1}; initfc_rx_valid=1;
        @(posedge clk); #1; initfc_rx_valid=0;
        @(posedge clk); #1;
        initfc_rx={64'hFFFFFFFFFFFFFFFF,FC2}; initfc_rx_valid=1;
        @(posedge clk); #1; initfc_rx_valid=0;
        @(posedge clk); #1;
        chk3(S_I3,fc_init_state,"state=FC_INIT3");
        chk8(FC3,initfc_tx[7:0],"tx=INITFC3(0xE0)");

        $display("[TC6] Full handshake -> FC_DONE");
        rst; full_handshake;
        @(posedge clk); #1;
        chk3(S_DONE,fc_init_state,"state=FC_DONE");
        chk1(1,fc_init_done,"fc_init_done=1");

        $display("[TC7] Timeout -> FC_ERROR");
        rst; dll_active=1; @(posedge clk); #1; @(posedge clk); #1;
        fc_init_timeout=1; @(posedge clk); #1; fc_init_timeout=0;
        @(posedge clk); #1;
        chk3(S_ERR,fc_init_state,"state=FC_ERROR");
        chk1(1,fc_init_err,"fc_init_err=1");

        $display("[TC8] dll_active=0 from DONE -> IDLE");
        rst; full_handshake;
        chk3(S_DONE,fc_init_state,"state=DONE first");
        dll_active=0; @(posedge clk); #1; @(posedge clk); #1;
        chk3(S_IDLE,fc_init_state,"state=IDLE after active=0");

        $display("=== fc_init_fsm: %0d PASSED, %0d FAILED ===",pass_count,fail_count);
        if(fail_count==0)$display("ALL TESTS PASSED"); else $display("SOME TESTS FAILED");
        $finish;
    end
    initial #15000 begin $display("TIMEOUT");$finish;end
endmodule
