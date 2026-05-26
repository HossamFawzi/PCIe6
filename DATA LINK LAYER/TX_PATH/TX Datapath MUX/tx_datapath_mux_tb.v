// =============================================================================
// Module   : tx_datapath_mux_tb
// Project  : PCIe 6.0 Data Link Layer — TX Datapath MUX Testbench
//
// Test Plan:
//   TC1  – Reset: all PHY outputs = 0
//   TC2  – DLLP only: 1 beat, SOP+EOP same cycle
//   TC3  – New TLP only: 5 beats, correct per-beat data
//   TC4  – Retry TLP only: 5 beats
//   TC5  – Priority: retry > new TLP
//   TC6  – Priority: new TLP > DLLP
//   TC7  – Priority: retry > DLLP
//   TC8  – Back-to-back: DLLP -> TLP -> Retry
//   TC9  – retry_req high, retry_valid=0: arb selects retry over new TLP
//   TC10 – DLLP queued during TLP; sent immediately after
// =============================================================================

`timescale 1ns / 1ps

module tx_datapath_mux_tb;

    reg          clk;
    reg          rst_n;
    reg  [1055:0] tlp_tx;
    reg           tlp_tx_valid;
    reg  [1055:0] retry_tlp;
    reg           retry_valid;
    reg  [63:0]   dllp_out;
    reg           dllp_valid;
    reg           retry_req;

    wire [255:0]  phy_tx_data;
    wire          phy_tx_valid;
    wire          phy_tx_sop;
    wire          phy_tx_eop;

    tx_datapath_mux dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_tx(tlp_tx), .tlp_tx_valid(tlp_tx_valid),
        .retry_tlp(retry_tlp), .retry_valid(retry_valid),
        .dllp_out(dllp_out), .dllp_valid(dllp_valid),
        .retry_req(retry_req),
        .phy_tx_data(phy_tx_data), .phy_tx_valid(phy_tx_valid),
        .phy_tx_sop(phy_tx_sop), .phy_tx_eop(phy_tx_eop)
    );

    initial clk = 0;
    always #1 clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check;
        input [7:0]   tid;
        input         cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("[PASS] TC%0d: %0s", tid, msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] TC%0d: %0s  t=%0t", tid, msg, $time);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task clear_all;
        begin
            tlp_tx = 0; tlp_tx_valid = 0;
            retry_tlp = 0; retry_valid = 0;
            dllp_out = 0; dllp_valid = 0;
            retry_req = 0;
        end
    endtask

    // Collect one complete packet (SOP..EOP). All sampling is blocking.
    task collect;
        output integer    nb;
        output reg        sop, eop;
        output reg [255:0] b0,b1,b2,b3,b4;
        integer tout;
        begin
            nb=0; sop=0; eop=0;
            b0=0;b1=0;b2=0;b3=0;b4=0;
            tout=0;
            // wait for SOP
            while(!sop && tout<500) begin
                @(posedge clk); #0.1;
                if(phy_tx_valid && phy_tx_sop) begin
                    sop=1;
                    case(nb) 0:b0=phy_tx_data; 1:b1=phy_tx_data; 2:b2=phy_tx_data;
                              3:b3=phy_tx_data; 4:b4=phy_tx_data; default:; endcase
                    nb=nb+1;
                    if(phy_tx_eop) eop=1;
                end
                tout=tout+1;
            end
            if(!sop) $display("[TIMEOUT] no SOP  t=%0t",$time);
            // collect rest
            tout=0;
            while(!eop && tout<500) begin
                @(posedge clk); #0.1;
                if(phy_tx_valid) begin
                    case(nb) 0:b0=phy_tx_data; 1:b1=phy_tx_data; 2:b2=phy_tx_data;
                              3:b3=phy_tx_data; 4:b4=phy_tx_data; default:; endcase
                    nb=nb+1;
                    if(phy_tx_eop) eop=1;
                end
                tout=tout+1;
            end
            if(!eop) $display("[TIMEOUT] no EOP  t=%0t",$time);
        end
    endtask

    task wait_idle;
        integer t;
        begin t=0;
            while(dut.state!==3'b001 && t<30) begin @(posedge clk);#0.1; t=t+1; end
        end
    endtask

    reg [1055:0] TLP_A, TLP_B;
    reg [63:0]   DLLP_C;
    integer nb;
    reg sop_ok, eop_ok;
    reg [255:0] b0,b1,b2,b3,b4, exp;

    initial begin
        $dumpfile("tx_datapath_mux_tb.vcd");
        $dumpvars(0,tx_datapath_mux_tb);
        clear_all(); rst_n=0;

        TLP_A=0; TLP_A[1055:992]=64'hDEAD_BEEF_CAFE_0001;
                 TLP_A[991:928] =64'hDEAD_BEEF_CAFE_0002;
                 TLP_A[31:0]    =32'hAABBCCDD;

        TLP_B=0; TLP_B[1055:992]=64'hFEED_FACE_1234_5678;
                 TLP_B[31:0]    =32'h11223344;

        DLLP_C = 64'h0A0B_0C0D_0E0F_AABB;

        repeat(4) @(posedge clk);
        rst_n=1; @(posedge clk); #0.1;

        // ------------------------------------------------------------------
        // TC1 Reset
        // ------------------------------------------------------------------
        rst_n=0; @(posedge clk); #0.1;
        check(1, phy_tx_valid===0, "phy_tx_valid=0 during reset");
        check(1, phy_tx_sop  ===0, "phy_tx_sop=0 during reset");
        check(1, phy_tx_eop  ===0, "phy_tx_eop=0 during reset");
        check(1, phy_tx_data ===0, "phy_tx_data=0 during reset");
        rst_n=1; @(posedge clk); #0.1;

        // ------------------------------------------------------------------
        // TC2 DLLP only
        // ------------------------------------------------------------------
        clear_all();
        dllp_out=DLLP_C; dllp_valid=1;
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        dllp_valid=0;
        check(2, sop_ok,          "DLLP: SOP seen");
        check(2, eop_ok,          "DLLP: EOP seen");
        check(2, nb==1,           "DLLP: 1 beat");
        check(2, b0[255:192]===DLLP_C, "DLLP: data[255:192]=DLLP_C");
        check(2, b0[191:0]===192'h0,   "DLLP: padding zeros");
        wait_idle();

        // ------------------------------------------------------------------
        // TC3 New TLP only (5 beats)
        // ------------------------------------------------------------------
        clear_all();
        tlp_tx=TLP_A; tlp_tx_valid=1;
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        tlp_tx_valid=0;
        check(3, sop_ok,        "TLP: SOP seen");
        check(3, eop_ok,        "TLP: EOP seen");
        check(3, nb==5,         "TLP: 5 beats");
        check(3, b0===TLP_A[255:0],    "TLP beat0");
        check(3, b1===TLP_A[511:256],  "TLP beat1");
        check(3, b2===TLP_A[767:512],  "TLP beat2");
        check(3, b3===TLP_A[1023:768], "TLP beat3");
        exp = {TLP_A[1055:1024],{224{1'b0}}};
        check(3, b4===exp,             "TLP beat4 padded");
        wait_idle();

        // ------------------------------------------------------------------
        // TC4 Retry TLP only
        // ------------------------------------------------------------------
        clear_all();
        retry_tlp=TLP_B; retry_valid=1;
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        retry_valid=0;
        check(4, sop_ok,        "Retry: SOP seen");
        check(4, eop_ok,        "Retry: EOP seen");
        check(4, nb==5,         "Retry: 5 beats");
        check(4, b0===TLP_B[255:0],    "Retry beat0");
        check(4, b3===TLP_B[1023:768], "Retry beat3");
        wait_idle();

        // ------------------------------------------------------------------
        // TC5 Priority: retry > new TLP
        // ------------------------------------------------------------------
        clear_all();
        tlp_tx=TLP_A; tlp_tx_valid=1;
        retry_tlp=TLP_B; retry_valid=1;
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        tlp_tx_valid=0; retry_valid=0;
        check(5, b0===TLP_B[255:0], "Priority retry>TLP: beat0=TLP_B");
        check(5, nb==5,             "Priority retry>TLP: 5 beats");
        wait_idle();

        // ------------------------------------------------------------------
        // TC6 Priority: new TLP > DLLP
        // ------------------------------------------------------------------
        clear_all();
        tlp_tx=TLP_A; tlp_tx_valid=1;
        dllp_out=DLLP_C; dllp_valid=1;
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        tlp_tx_valid=0; dllp_valid=0;
        check(6, nb==5,             "Priority TLP>DLLP: 5 beats");
        check(6, b0===TLP_A[255:0], "Priority TLP>DLLP: beat0=TLP_A");
        wait_idle();

        // ------------------------------------------------------------------
        // TC7 Priority: retry > DLLP
        // ------------------------------------------------------------------
        clear_all();
        retry_tlp=TLP_B; retry_valid=1;
        dllp_out=DLLP_C; dllp_valid=1;
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        retry_valid=0; dllp_valid=0;
        check(7, nb==5,             "Priority retry>DLLP: 5 beats");
        check(7, b0===TLP_B[255:0], "Priority retry>DLLP: beat0=TLP_B");
        wait_idle();

        // ------------------------------------------------------------------
        // TC8 Back-to-back DLLP -> TLP -> Retry
        // Present each source sequentially; collect each packet separately.
        // ------------------------------------------------------------------
        clear_all();

        // --- DLLP packet ---
        dllp_out=DLLP_C; dllp_valid=1;
        @(posedge clk); #0.1;   // FSM: IDLE->DLLP_SEND, outputs valid NOW
        // Capture this single beat directly
        b0 = phy_tx_data;
        sop_ok = phy_tx_sop;
        eop_ok = phy_tx_eop;
        nb = (phy_tx_valid) ? 1 : 0;
        dllp_valid=0;
        check(8, sop_ok,                "B2B: DLLP 1st SOP");
        check(8, eop_ok,                "B2B: DLLP 1st EOP");
        check(8, nb==1,                 "B2B: DLLP 1st (1 beat)");
        check(8, b0[255:192]===DLLP_C,  "B2B: DLLP data correct");
        wait_idle();

        // --- New TLP packet (present alone so it wins arbitration) ---
        // Do NOT advance clock here; let collect() catch the SOP
        tlp_tx=TLP_A; tlp_tx_valid=1;
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        tlp_tx_valid=0;
        // Queue retry after TLP has been fully transmitted
        retry_tlp=TLP_B; retry_valid=1;
        check(8, nb==5,              "B2B: TLP 2nd (5 beats)");
        check(8, b0===TLP_A[255:0], "B2B: TLP_A beat0 correct");

        // --- Retry packet ---
        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        retry_valid=0;
        check(8, nb==5,              "B2B: Retry 3rd (5 beats)");
        check(8, b0===TLP_B[255:0], "B2B: TLP_B beat0 correct");
        wait_idle();

        // ------------------------------------------------------------------
        // TC9 retry_req=1, retry_valid=0 -> arb selects SRC_RETRY (not TLP)
        // ------------------------------------------------------------------
        clear_all();
        retry_req=1; retry_valid=0;
        tlp_tx=TLP_A; tlp_tx_valid=1;
        @(posedge clk); #0.1;
        check(9, dut.arb_winner===2'b01, "retry_req: arb=SRC_RETRY (not SRC_TLP)");
        retry_req=0; tlp_tx_valid=0;
        wait_idle();

        // ------------------------------------------------------------------
        // TC10 DLLP queued during TLP -> follows without bubble
        // ------------------------------------------------------------------
        clear_all();
        tlp_tx=TLP_A; tlp_tx_valid=1;
        dllp_out=DLLP_C; dllp_valid=1;

        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        tlp_tx_valid=0;
        check(10, nb==5,            "Post-TLP: TLP sent 1st");
        check(10, b0===TLP_A[255:0],"Post-TLP: TLP_A data correct");

        collect(nb,sop_ok,eop_ok,b0,b1,b2,b3,b4);
        dllp_valid=0;
        check(10, nb==1,                 "Post-TLP: DLLP 2nd (1 beat)");
        check(10, b0[255:192]===DLLP_C,  "Post-TLP: DLLP data correct");
        check(10, b0[191:0]===192'h0,    "Post-TLP: DLLP padding zeros");
        wait_idle();

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("\n========================================");
        $display(" TX Datapath MUX Testbench Summary");
        $display("========================================");
        $display(" PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        $display("========================================");
        if(fail_cnt==0) $display(">>> ALL TESTS PASSED <<<");
        else            $display(">>> %0d FAILED <<<", fail_cnt);
        $display("");
        $finish;
    end

    initial begin #500000; $display("[WATCHDOG] timeout"); $finish; end

endmodule
