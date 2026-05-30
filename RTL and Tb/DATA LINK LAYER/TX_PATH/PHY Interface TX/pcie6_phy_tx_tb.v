`timescale 1ns / 1ps
module pcie6_phy_tx_tb;
    localparam CLK_PERIOD   = 10;
    localparam [255:0] COMPLIANCE_PATTERN = {8{32'hBCD5BCD5}};

    reg         clk, rst_n;
    reg  [255:0] tx_data;
    reg          tx_valid, tx_sop, tx_eop, tx_elec_idle_req, tx_compliance_req;
    wire [255:0] phy_txd;
    wire         phy_tx_valid, phy_tx_elec_idle, phy_tx_compliance;

    pcie6_phy_tx dut(clk,rst_n,tx_data,tx_valid,tx_sop,tx_eop,
        tx_elec_idle_req,tx_compliance_req,
        phy_txd,phy_tx_valid,phy_tx_elec_idle,phy_tx_compliance);

    initial clk=0;
    always #(CLK_PERIOD/2) clk=~clk;

    integer pass_cnt, fail_cnt;

    task check; input [63:0] id; input cond; begin
        if(cond) begin $display("[PASS] TC-%0d",id); pass_cnt=pass_cnt+1; end
        else     begin $display("[FAIL] TC-%0d  t=%0t",id,$time); fail_cnt=fail_cnt+1; end
    end endtask

    task si; input [255:0] d; input v,sop,eop,ei,comp; begin
        tx_data=d; tx_valid=v; tx_sop=sop; tx_eop=eop;
        tx_elec_idle_req=ei; tx_compliance_req=comp;
    end endtask

    task idle; begin si(0,0,0,0,0,0); end endtask

    // Continuous assertion check
    always @(posedge clk) if(rst_n && phy_tx_elec_idle && phy_tx_compliance) begin
        $display("[ASSERT-FAIL] ElecIdle+Compliance both high t=%0t",$time);
        fail_cnt=fail_cnt+1;
    end

    initial begin
        $dumpfile("pcie6_phy_tx_tb.vcd"); $dumpvars(0,pcie6_phy_tx_tb);
        pass_cnt=0; fail_cnt=0;
        rst_n=0; idle();
        repeat(5) @(posedge clk); #1;

        //--TC-01: Reset--
        $display("\n--- TC-01: Reset ---");
        @(negedge clk);
        check(1,  phy_tx_elec_idle==1);
        check(2,  phy_tx_valid==0);
        check(3,  phy_tx_compliance==0);
        check(4,  phy_txd==0);

        @(posedge clk); #1; rst_n=1; idle();
        repeat(3) @(posedge clk); #1;

        //--TC-02: Single-word FLIT--
        $display("\n--- TC-02: Single-word FLIT ---");
        begin : b2
            reg [255:0] D; D={8{32'hDEADBEEF}};
            @(posedge clk); #1; si(D,1,1,1,0,0);
            @(posedge clk); #1; idle();
            @(posedge clk); #1;
            @(negedge clk);
            check(5,  phy_tx_valid==1);
            check(6,  phy_txd==D);
            check(7,  phy_tx_elec_idle==0);
            check(8,  phy_tx_compliance==0);
        end
        repeat(3) @(posedge clk); #1; idle();

        //--TC-03: Multi-word FLIT--
        $display("\n--- TC-03: Multi-word FLIT ---");
        begin : b3
            reg [255:0] SD,PD,ED;
            SD={8{32'hAAAABBBB}}; PD={8{32'h11112222}}; ED={8{32'hFFFFEEEE}};
            @(posedge clk); #1; si(SD,1,1,0,0,0); // SOP
            @(posedge clk); #1; si(PD,1,0,0,0,0); // payload
            @(posedge clk); #1; si(ED,1,0,1,0,0); // EOP
            // SOP arrives at output now (2 cycles after driven)
            @(negedge clk);
            check(9,  phy_tx_valid==1);
            check(10, phy_txd==SD);
            @(posedge clk); #1; idle();
            @(negedge clk);
            check(11, phy_tx_valid==1);
            check(12, phy_txd==PD);
            @(posedge clk); #1;
            @(negedge clk);
            check(13, phy_tx_valid==1);
            check(14, phy_txd==ED);
        end
        repeat(3) @(posedge clk); #1; idle();

        //--TC-04: Back-to-back FLITs--
        $display("\n--- TC-04: Back-to-back FLITs ---");
        begin : b4
            reg [255:0] FA,FB;
            FA={8{32'hA0A0A0A0}}; FB={8{32'hB0B0B0B0}};
            @(posedge clk); #1; si(FA,1,1,1,0,0); // FLIT A
            @(posedge clk); #1; si(FB,1,1,1,0,0); // FLIT B
            @(posedge clk); #1; idle();
            @(negedge clk);
            check(15, phy_tx_valid==1);
            check(16, phy_txd==FA);
            @(posedge clk); #1;
            @(negedge clk);
            check(17, phy_tx_valid==1);
            check(18, phy_txd==FB);
        end
        repeat(3) @(posedge clk); #1; idle();

        //--TC-05: Electrical Idle--
        $display("\n--- TC-05: Electrical Idle ---");
        @(posedge clk); #1; si({8{32'hC0C0C0C0}},1,1,0,0,0);
        @(posedge clk); #1; si(0,0,0,0,1,0);
        @(posedge clk); #1; si(0,0,0,0,1,0);
        @(posedge clk); #1; si(0,0,0,0,1,0);
        @(negedge clk);
        check(19, phy_tx_elec_idle==1);
        check(20, phy_tx_valid==0);
        check(21, phy_txd==0);
        check(22, phy_tx_compliance==0);
        repeat(3) @(posedge clk); #1; idle(); repeat(2) @(posedge clk); #1;

        //--TC-06: Compliance--
        $display("\n--- TC-06: Compliance ---");
        @(posedge clk); #1; si(0,0,0,0,0,1);
        @(posedge clk); #1; si(0,0,0,0,0,1);
        @(posedge clk); #1; si(0,0,0,0,0,1);
        @(negedge clk);
        check(23, phy_tx_compliance==1);
        check(24, phy_tx_valid==1);
        check(25, phy_txd==COMPLIANCE_PATTERN);
        check(26, phy_tx_elec_idle==0);
        repeat(3) @(posedge clk); #1; idle(); repeat(2) @(posedge clk); #1;

        //--TC-07: ElecIdle > Compliance priority--
        $display("\n--- TC-07: ElecIdle Priority over Compliance ---");
        @(posedge clk); #1; si(0,0,0,0,1,1);
        @(posedge clk); #1; si(0,0,0,0,1,1);
        @(posedge clk); #1; si(0,0,0,0,1,1);
        @(negedge clk);
        check(27, phy_tx_elec_idle==1);
        check(28, phy_tx_compliance==0);
        check(29, phy_tx_valid==0);
        repeat(3) @(posedge clk); #1; idle(); repeat(2) @(posedge clk); #1;

        //--TC-08: Inter-FLIT gap--
        $display("\n--- TC-08: Inter-FLIT Gap ---");
        @(posedge clk); #1; si({8{32'hDEADDEAD}},1,1,1,0,0);
        @(posedge clk); #1; idle();
        @(posedge clk); #1; idle();
        @(posedge clk); #1;
        @(negedge clk);
        check(30, phy_tx_valid==0);
        check(31, phy_tx_elec_idle==0);

        $display("\n=================================================");
        $display("  PCIe 6.0 PHY TX TB   PASS:%0d  FAIL:%0d",pass_cnt,fail_cnt);
        $display("=================================================");
        if(fail_cnt==0) $display(">>> ALL TESTS PASSED <<<\n");
        else            $display(">>> %0d FAILED <<<\n",fail_cnt);
        $finish;
    end

    initial begin #200_000; $display("[TIMEOUT]"); $finish; end
endmodule
