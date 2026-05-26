// ============================================================
//  Testbench : dllp_arb_tb
//  DUT       : dllp_arb  (DLLP_ARB)
//
//  Test cases:
//    TC1  – Reset state: outputs zero / idle
//    TC2  – ACK only: selected, type=0x0
//    TC3  – NAK only: selected, type=0x1
//    TC4  – FC only: selected, type=0x2
//    TC5  – PM only: selected, type=0x3
//    TC6  – BW only: selected, type=0x4
//    TC7  – NOP only: selected, type=0x5
//    TC8  – Priority: ACK beats FC beats PM beats BW beats NOP
//    TC9  – Priority: FC beats PM (ACK de-asserted)
//    TC10 – Priority: PM beats BW beats NOP
//    TC11 – All idle: dllp_out_valid = 0
//    TC12 – Back-to-back: ACK then FC on consecutive cycles
//    TC13 – ACK and NAK simultaneous: ACK_DLLP bus wins (type determined by byte)
//    TC14 – Single-cycle pulse on nop_valid
//    TC15 – Reset in-flight: outputs clear immediately
// ============================================================
`timescale 1ns/1ps

module dllp_arb_tb;

    // ── DUT ports ─────────────────────────────────────────────
    reg        clk;
    reg        rst_n;
    reg [63:0] ack_dllp;
    reg        ack_dllp_valid;
    reg [63:0] fc_dllp;
    reg        fc_dllp_valid;
    reg [63:0] pm_dllp;
    reg        pm_dllp_valid;
    reg        nop_valid;
    reg        bw_dllp_valid;

    wire [63:0] dllp_out;
    wire        dllp_out_valid;
    wire [3:0]  dllp_type;

    // ── DUT ───────────────────────────────────────────────────
    dllp_arb uDUT (
        .clk           (clk),
        .rst_n         (rst_n),
        .ack_dllp      (ack_dllp),
        .ack_dllp_valid(ack_dllp_valid),
        .fc_dllp       (fc_dllp),
        .fc_dllp_valid (fc_dllp_valid),
        .pm_dllp       (pm_dllp),
        .pm_dllp_valid (pm_dllp_valid),
        .nop_valid     (nop_valid),
        .bw_dllp_valid (bw_dllp_valid),
        .dllp_out      (dllp_out),
        .dllp_out_valid(dllp_out_valid),
        .dllp_type     (dllp_type)
    );

    // ── Clock 1 GHz ───────────────────────────────────────────
    initial clk = 0;
    always #0.5 clk = ~clk;

    // ── Bookkeeping ───────────────────────────────────────────
    integer pass_cnt;
    integer fail_cnt;

    task PASS;
        input [8*48-1:0] name;
        begin
            $display("PASS  %0s", name);
            pass_cnt = pass_cnt + 1;
        end
    endtask

    task FAIL;
        input [8*48-1:0] name;
        input [8*96-1:0] msg;
        begin
            $display("FAIL  %0s | %0s", name, msg);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    // ── Helper: clear all inputs ──────────────────────────────
    task all_idle;
        begin
            ack_dllp       = 64'h0;
            ack_dllp_valid = 1'b0;
            fc_dllp        = 64'h0;
            fc_dllp_valid  = 1'b0;
            pm_dllp        = 64'h0;
            pm_dllp_valid  = 1'b0;
            nop_valid      = 1'b0;
            bw_dllp_valid  = 1'b0;
        end
    endtask

    // ── Helper: clock + sample ────────────────────────────────
    task clk_and_sample;
        begin
            @(posedge clk); #0.1;
        end
    endtask

    // ── Stimulus ──────────────────────────────────────────────
    initial begin
        $dumpfile("dllp_arb_tb.vcd");
        $dumpvars(0, dllp_arb_tb);

        pass_cnt = 0;
        fail_cnt = 0;

        rst_n = 1'b0;
        all_idle;
        @(posedge clk); #0.1;
        @(posedge clk); #0.1;

        // ── TC1: Reset state ──────────────────────────────────
        if (dllp_out === 64'h0 && dllp_out_valid === 1'b0 && dllp_type === 4'hF)
            PASS("TC1_RESET");
        else
            FAIL("TC1_RESET", "outputs not idle in reset");

        rst_n = 1'b1;
        @(posedge clk); #0.1;

        // ── TC2: ACK only ─────────────────────────────────────
        all_idle;
        ack_dllp       = {8'h00, 56'hABCDEF_001122_33};  // type=0x00 = ACK
        ack_dllp_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;  // output is registered, sample after 1 cycle
        if (dllp_out_valid === 1'b1 && dllp_type === 4'h0 &&
            dllp_out === {8'h00, 56'hABCDEF_001122_33})
            PASS("TC2_ACK_ONLY");
        else
            FAIL("TC2_ACK_ONLY", "wrong output or type");

        // ── TC3: NAK only ─────────────────────────────────────
        all_idle;
        ack_dllp       = {8'h10, 56'h0011_2233_4455_66};  // type=0x10 = NAK
        ack_dllp_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_out_valid === 1'b1 && dllp_type === 4'h1)
            PASS("TC3_NAK_ONLY");
        else
            FAIL("TC3_NAK_ONLY", "wrong type for NAK");

        // ── TC4: FC only ──────────────────────────────────────
        all_idle;
        fc_dllp       = {8'h40, 56'hFC_0000_0000_0000};  // UpdateFC-P
        fc_dllp_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_out_valid === 1'b1 && dllp_type === 4'h2 &&
            dllp_out === {8'h40, 56'hFC_0000_0000_0000})
            PASS("TC4_FC_ONLY");
        else
            FAIL("TC4_FC_ONLY", "wrong output or type for FC");

        // ── TC5: PM only ──────────────────────────────────────
        all_idle;
        pm_dllp       = {8'h12, 56'h00_0000_0000_0000};  // PM_Enter_L1
        pm_dllp_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_out_valid === 1'b1 && dllp_type === 4'h3)
            PASS("TC5_PM_ONLY");
        else
            FAIL("TC5_PM_ONLY", "wrong type for PM");

        // ── TC6: BW only ──────────────────────────────────────
        all_idle;
        bw_dllp_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_out_valid === 1'b1 && dllp_type === 4'h4)
            PASS("TC6_BW_ONLY");
        else
            FAIL("TC6_BW_ONLY", "wrong type for BW notification");

        // ── TC7: NOP only ─────────────────────────────────────
        all_idle;
        nop_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_out_valid === 1'b1 && dllp_type === 4'h5)
            PASS("TC7_NOP_ONLY");
        else
            FAIL("TC7_NOP_ONLY", "wrong type for NOP");

        // ── TC8: Full priority chain: ACK > FC > PM > BW > NOP
        // Apply all at once
        ack_dllp       = {8'h00, 56'hAAAA_AAAA_AAAA_AA};
        ack_dllp_valid = 1'b1;
        fc_dllp        = {8'h40, 56'hBBBB_BBBB_BBBB_BB};
        fc_dllp_valid  = 1'b1;
        pm_dllp        = {8'h12, 56'hCCCC_CCCC_CCCC_CC};
        pm_dllp_valid  = 1'b1;
        bw_dllp_valid  = 1'b1;
        nop_valid      = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h0)   // ACK wins
            PASS("TC8_PRI_ACK_WINS");
        else
            FAIL("TC8_PRI_ACK_WINS", "ACK did not win full contention");

        // Remove ACK; FC should now win
        ack_dllp_valid = 1'b0;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h2)
            PASS("TC8_PRI_FC_WINS");
        else
            FAIL("TC8_PRI_FC_WINS", "FC did not win after ACK removed");

        // Remove FC; PM should win
        fc_dllp_valid = 1'b0;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h3)
            PASS("TC8_PRI_PM_WINS");
        else
            FAIL("TC8_PRI_PM_WINS", "PM did not win after FC removed");

        // Remove PM; BW should win
        pm_dllp_valid = 1'b0;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h4)
            PASS("TC8_PRI_BW_WINS");
        else
            FAIL("TC8_PRI_BW_WINS", "BW did not win after PM removed");

        // Remove BW; NOP should win
        bw_dllp_valid = 1'b0;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h5)
            PASS("TC8_PRI_NOP_WINS");
        else
            FAIL("TC8_PRI_NOP_WINS", "NOP did not win after BW removed");

        all_idle;

        // ── TC9: FC beats PM ──────────────────────────────────
        fc_dllp       = 64'hFC_CAFE_0000_0000;
        fc_dllp_valid = 1'b1;
        pm_dllp       = 64'h1200_BEEF_0000_0000;
        pm_dllp_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h2 && dllp_out === 64'hFC_CAFE_0000_0000)
            PASS("TC9_FC_BEATS_PM");
        else
            FAIL("TC9_FC_BEATS_PM", "FC did not beat PM");
        all_idle;

        // ── TC10: PM beats BW beats NOP ───────────────────────
        pm_dllp       = 64'h1200_DEAD_0000_0000;
        pm_dllp_valid = 1'b1;
        bw_dllp_valid = 1'b1;
        nop_valid     = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h3)
            PASS("TC10_PM_BEATS_BW_NOP");
        else
            FAIL("TC10_PM_BEATS_BW_NOP", "PM did not beat BW/NOP");
        all_idle;

        // ── TC11: All idle -> dllp_out_valid = 0 ─────────────
        clk_and_sample;
        clk_and_sample;
        if (dllp_out_valid === 1'b0 && dllp_type === 4'hF)
            PASS("TC11_ALL_IDLE");
        else
            FAIL("TC11_ALL_IDLE", "dllp_out_valid not 0 when all idle");

        // ── TC12: Back-to-back ACK then FC ────────────────────
        ack_dllp       = {8'h00, 56'h12_3456_789A_BC};
        ack_dllp_valid = 1'b1;
        @(posedge clk); #0.1;   // cycle 1: ACK latched into output
        // Check cycle 1 result (ACK latched)
        if (dllp_type === 4'h0)
            PASS("TC12_B2B_ACK");
        else
            FAIL("TC12_B2B_ACK", "wrong type in cycle 1 of back-to-back");
        ack_dllp_valid = 1'b0;
        fc_dllp        = {8'h40, 56'hDE_F012_3456_78};
        fc_dllp_valid  = 1'b1;
        @(posedge clk); #0.1;   // cycle 2: FC latched into output
        // Check cycle 2 result
        if (dllp_type === 4'h2)
            PASS("TC12_B2B_FC");
        else
            FAIL("TC12_B2B_FC", "wrong type in cycle 2 of back-to-back");
        fc_dllp_valid = 1'b0;
        @(posedge clk); #0.1;

        // ── TC13: NAK type detection ──────────────────────────
        all_idle;
        ack_dllp       = {8'h10, 56'h00_FFFF_FFFF_FFFF};  // 0x10 = NAK
        ack_dllp_valid = 1'b1;
        clk_and_sample;
        clk_and_sample;
        if (dllp_type === 4'h1)
            PASS("TC13_NAK_TYPE");
        else
            FAIL("TC13_NAK_TYPE", "NAK type not decoded correctly");
        all_idle;

        // ── TC14: Single-cycle NOP pulse ──────────────────────
        nop_valid = 1'b1;
        @(posedge clk); #0.1;   // NOP latched into output here
        if (dllp_type === 4'h5 && dllp_out_valid === 1'b1)
            PASS("TC14_NOP_PULSE_LATCHED");
        else
            FAIL("TC14_NOP_PULSE_LATCHED", "NOP pulse not latched");
        nop_valid = 1'b0;
        @(posedge clk); #0.1;
        if (dllp_out_valid === 1'b0)
            PASS("TC14_NOP_DEASSERTS");
        else
            FAIL("TC14_NOP_DEASSERTS", "dllp_out_valid did not clear after NOP");

        // ── TC15: Reset in-flight ─────────────────────────────
        ack_dllp       = 64'hDEAD_BEEF_CAFE_BABE;
        ack_dllp_valid = 1'b1;
        @(posedge clk); #0.1;
        rst_n = 1'b0;
        @(posedge clk); #0.1;
        if (dllp_out === 64'h0 && dllp_out_valid === 1'b0 && dllp_type === 4'hF)
            PASS("TC15_RESET_INFLIGHT");
        else
            FAIL("TC15_RESET_INFLIGHT", "outputs not cleared on reset");
        rst_n = 1'b1;
        all_idle;

        // ── Summary ───────────────────────────────────────────
        #10;
        $display("--------------------------------------------");
        $display("  dllp_arb TB: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
        $display("--------------------------------------------");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** FAILURES DETECTED ***");
        $finish;
    end

    // ── Timeout guard ─────────────────────────────────────────
    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
