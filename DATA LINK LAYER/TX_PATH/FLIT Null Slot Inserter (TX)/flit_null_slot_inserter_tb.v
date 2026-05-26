// ============================================================================
// Testbench: flit_null_slot_inserter_tb
// DUT      : flit_null_slot_inserter  (PCIe Gen6 DLL TX — NULL_INS)
//
// Timing model:
//   The DUT has 1 pipeline register.  Stimulus driven at posedge N is
//   captured by the DUT at posedge N, and the registered OUTPUT is readable
//   from posedge N+1 onward.
//
//   Protocol for every TC:
//     Step 1 (DEASSERT): de-assert flit_valid at posedge N-1
//     Step 2 (SNAPSHOT): sample null_count after #1 at posedge N  (DUT idle)
//     Step 3 (DRIVE):    assert stimulus at posedge N
//     Step 4 (SAMPLE):   sample all outputs at posedge N+1 + #1 delta
//
//   Because the counter only increments when both flit_valid AND any_null are
//   true at the registered clock edge, de-asserting valid between TCs ensures
//   exactly one increment per intentional test transaction.
//
// Test Cases  (10 TCs, 48 individual checks):
//   TC01 - Reset: all outputs zero
//   TC02 - Both slots used: data passes through, counter stays 0
//   TC03 - Slot 0 empty:  slot 0 replaced, counter +1
//   TC04 - Slot 1 empty:  slot 1 replaced, counter +1
//   TC05 - Both empty:    both replaced,   counter +1
//   TC06 - null_count saturates at 0xFF
//   TC07 - flit_valid=0: outputs stay quiet
//   TC08 - Back-to-back FLITs, alternating slot patterns
//   TC09 - null_pattern change mid-stream
//   TC10 - null_inserted de-asserts when both slots used
// ============================================================================

`timescale 1ns / 1ps

module flit_null_slot_inserter_tb;

    // ------------------------------------------------------------------ //
    //  DUT ports
    // ------------------------------------------------------------------ //
    reg          clk;
    reg          rst_n;
    reg  [2047:0] flit_in;
    reg           flit_valid;
    reg  [1:0]    flit_slot_used;
    reg  [1023:0] null_pattern;

    wire [2047:0] flit_out;
    wire          flit_out_valid;
    wire          null_inserted;
    wire [7:0]    null_count;

    // ------------------------------------------------------------------ //
    //  DUT
    // ------------------------------------------------------------------ //
    flit_null_slot_inserter DUT (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_in        (flit_in),
        .flit_valid     (flit_valid),
        .flit_slot_used (flit_slot_used),
        .null_pattern   (null_pattern),
        .flit_out       (flit_out),
        .flit_out_valid (flit_out_valid),
        .null_inserted  (null_inserted),
        .null_count     (null_count)
    );

    // ------------------------------------------------------------------ //
    //  Clock: 10 ns period, 100 MHz
    // ------------------------------------------------------------------ //
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // ------------------------------------------------------------------ //
    //  Scoreboard
    // ------------------------------------------------------------------ //
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task automatic chk;
        input integer  tc_num;
        input [511:0]  label;
        input          cond;
        begin
            if (cond) begin
                $display("  PASS  TC%02d : %0s", tc_num, label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL  TC%02d : %0s", tc_num, label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------ //
    //  QUIESCE helper: de-assert valid, let pipeline drain, read counter
    //  Returns the stable null_count value after one idle cycle.
    // ------------------------------------------------------------------ //
    task automatic quiesce;
        output [7:0] cnt_snapshot;
        begin
            // Drive flit_valid low at the next posedge
            @(posedge clk);
            flit_valid     = 1'b0;
            flit_slot_used = 2'b11;
            // One cycle later outputs are stable (pipeline flushed)
            @(posedge clk);
            #1;
            cnt_snapshot = null_count;
        end
    endtask

    // ------------------------------------------------------------------ //
    //  DRIVE_AND_SAMPLE: apply one FLIT stimulus, return after sampling
    // ------------------------------------------------------------------ //
    task automatic drive_and_sample;
        input [2047:0] fin;
        input          fv;
        input [1:0]    fsu;
        input [1023:0] np;
        begin
            // Apply stimulus on a rising edge
            @(posedge clk);
            flit_in        = fin;
            flit_valid     = fv;
            flit_slot_used = fsu;
            null_pattern   = np;
            // Outputs appear on the NEXT rising edge
            @(posedge clk);
            #1; // settle delta
        end
    endtask

    // ------------------------------------------------------------------ //
    //  Test patterns
    // ------------------------------------------------------------------ //
    localparam [1023:0] SLOT0_PAT  = {128{8'hA5}};
    localparam [1023:0] SLOT1_PAT  = {128{8'h5A}};
    localparam [1023:0] NULL_PAT_A = {128{8'hCC}};
    localparam [1023:0] NULL_PAT_B = {128{8'h33}};

    reg [7:0] cnt_snap;
    integer   tc, i;

    // ------------------------------------------------------------------ //
    //  Test sequence
    // ------------------------------------------------------------------ //
    initial begin
        $display("========================================================");
        $display("  PCIe Gen6 - FLIT Null Slot Inserter (TX) Testbench");
        $display("  DUT: flit_null_slot_inserter  |  NULL_INS");
        $display("========================================================");

        // Power-on defaults
        rst_n          = 1'b0;
        flit_in        = {2048{1'b0}};
        flit_valid     = 1'b0;
        flit_slot_used = 2'b11;
        null_pattern   = NULL_PAT_A;

        // ==============================================================
        // TC01 – Reset
        // ==============================================================
        tc = 1;
        $display("\n[TC%02d] Reset behaviour", tc);
        repeat (3) @(posedge clk); #1;
        chk(tc, "flit_out_valid=0 in reset",  flit_out_valid == 1'b0);
        chk(tc, "null_inserted=0 in reset",   null_inserted  == 1'b0);
        chk(tc, "null_count=0 in reset",      null_count     == 8'h00);
        chk(tc, "flit_out=0 in reset",        flit_out       == {2048{1'b0}});

        @(posedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk); #1;

        // ==============================================================
        // TC02 – Both slots used: pure pass-through, counter stays 0
        // ==============================================================
        tc = 2;
        $display("\n[TC%02d] Both slots USED - pass-through, no null insertion", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b11, NULL_PAT_A);
        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 0",             null_inserted  == 1'b0);
        chk(tc, "slot0 data preserved",           flit_out[1023:0]    == SLOT0_PAT);
        chk(tc, "slot1 data preserved",           flit_out[2047:1024] == SLOT1_PAT);
        chk(tc, "null_count unchanged",           null_count == cnt_snap);

        // ==============================================================
        // TC03 – Slot 0 empty: slot 0 → null_pattern
        // ==============================================================
        tc = 3;
        $display("\n[TC%02d] Slot 0 EMPTY - null fill in slot 0", tc);
        quiesce(cnt_snap);                // de-assert + snapshot counter
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b10, NULL_PAT_A);
        // slot_used[1]=1 keeps slot1; slot_used[0]=0 → slot0 gets null
        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 1",             null_inserted  == 1'b1);
        chk(tc, "slot0 = null_pattern",           flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "slot1 = original SLOT1_PAT",     flit_out[2047:1024] == SLOT1_PAT);
        chk(tc, "null_count incremented by 1",    null_count == cnt_snap + 8'h01);

        // ==============================================================
        // TC04 – Slot 1 empty: slot 1 → null_pattern
        // ==============================================================
        tc = 4;
        $display("\n[TC%02d] Slot 1 EMPTY - null fill in slot 1", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b01, NULL_PAT_A);
        // slot_used[0]=1 keeps slot0; slot_used[1]=0 → slot1 gets null
        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 1",             null_inserted  == 1'b1);
        chk(tc, "slot0 = original SLOT0_PAT",     flit_out[1023:0]    == SLOT0_PAT);
        chk(tc, "slot1 = null_pattern",           flit_out[2047:1024] == NULL_PAT_A);
        chk(tc, "null_count incremented by 1",    null_count == cnt_snap + 8'h01);

        // ==============================================================
        // TC05 – Both slots empty: both → null_pattern
        // ==============================================================
        tc = 5;
        $display("\n[TC%02d] BOTH slots EMPTY - null fill both", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b00, NULL_PAT_A);
        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 1",             null_inserted  == 1'b1);
        chk(tc, "slot0 = null_pattern",           flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "slot1 = null_pattern",           flit_out[2047:1024] == NULL_PAT_A);
        chk(tc, "null_count incremented by 1",    null_count == cnt_snap + 8'h01);

        // ==============================================================
        // TC06 – null_count saturates at 0xFF
        // ==============================================================
        tc = 6;
        $display("\n[TC%02d] null_count saturation at 255", tc);
        // Current count = 3 (one per TC03/04/05).
        // Stream 252 null FLITs to reach 255, then one more to verify saturation.
        for (i = 0; i < 252; i = i + 1) begin
            @(posedge clk);
            flit_in        = {SLOT1_PAT, SLOT0_PAT};
            flit_valid     = 1'b1;
            flit_slot_used = 2'b00;
        end
        @(posedge clk); #1;
        chk(tc, "null_count reached 255",          null_count == 8'hFF);

        // One additional null FLIT — must not roll over
        @(posedge clk);
        flit_valid     = 1'b1;
        flit_slot_used = 2'b00;
        @(posedge clk); #1;
        chk(tc, "null_count saturated (stays 255)", null_count == 8'hFF);

        // ==============================================================
        // TC07 – flit_valid=0: outputs stay de-asserted
        // ==============================================================
        tc = 7;
        $display("\n[TC%02d] flit_valid=0 - output stays de-asserted", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b0, 2'b00, NULL_PAT_A);
        chk(tc, "flit_out_valid=0 when invalid",   flit_out_valid == 1'b0);
        chk(tc, "null_inserted=0  when invalid",   null_inserted  == 1'b0);
        chk(tc, "null_count unchanged",            null_count == cnt_snap);

        // ==============================================================
        // TC08 – Back-to-back FLITs (no idle gaps between cycles)
        // ==============================================================
        tc = 8;
        $display("\n[TC%02d] Back-to-back FLITs, alternating slot usage", tc);
        quiesce(cnt_snap);

        // Cycle A: both used
        @(posedge clk);
        flit_in        = {SLOT1_PAT, SLOT0_PAT};
        flit_valid     = 1'b1;
        flit_slot_used = 2'b11;
        null_pattern   = NULL_PAT_A;
        @(posedge clk); #1;
        chk(tc, "[A] flit_out_valid = 1",          flit_out_valid == 1'b1);
        chk(tc, "[A] null_inserted  = 0",          null_inserted  == 1'b0);
        chk(tc, "[A] slot0 = SLOT0_PAT",           flit_out[1023:0]    == SLOT0_PAT);
        chk(tc, "[A] slot1 = SLOT1_PAT",           flit_out[2047:1024] == SLOT1_PAT);

        // Cycle B: slot0 empty — immediate back-to-back, no idle
        @(posedge clk);
        flit_in        = {SLOT1_PAT, SLOT0_PAT};
        flit_valid     = 1'b1;
        flit_slot_used = 2'b10;   // slot1 occupied, slot0 empty
        null_pattern   = NULL_PAT_A;
        @(posedge clk); #1;
        chk(tc, "[B] flit_out_valid = 1",          flit_out_valid == 1'b1);
        chk(tc, "[B] null_inserted  = 1",          null_inserted  == 1'b1);
        chk(tc, "[B] slot0 = null_pattern",        flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "[B] slot1 = SLOT1_PAT",           flit_out[2047:1024] == SLOT1_PAT);

        // Cycle C: both empty — still back-to-back
        @(posedge clk);
        flit_in        = {SLOT1_PAT, SLOT0_PAT};
        flit_valid     = 1'b1;
        flit_slot_used = 2'b00;
        null_pattern   = NULL_PAT_A;
        @(posedge clk); #1;
        chk(tc, "[C] null_inserted  = 1",          null_inserted  == 1'b1);
        chk(tc, "[C] slot0 = null_pattern",        flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "[C] slot1 = null_pattern",        flit_out[2047:1024] == NULL_PAT_A);

        // ==============================================================
        // TC09 – null_pattern change mid-stream
        // ==============================================================
        tc = 9;
        $display("\n[TC%02d] null_pattern change is reflected immediately", tc);
        quiesce(cnt_snap);

        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b00, NULL_PAT_A);
        chk(tc, "[PAT_A] slot0 filled with PAT_A", flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "[PAT_A] slot1 filled with PAT_A", flit_out[2047:1024] == NULL_PAT_A);

        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b00, NULL_PAT_B);
        chk(tc, "[PAT_B] slot0 filled with PAT_B", flit_out[1023:0]    == NULL_PAT_B);
        chk(tc, "[PAT_B] slot1 filled with PAT_B", flit_out[2047:1024] == NULL_PAT_B);

        // Sanity: PAT_A and PAT_B must differ
        chk(tc, "PAT_A != PAT_B (patterns distinct)", NULL_PAT_A !== NULL_PAT_B);

        // ==============================================================
        // TC10 – null_inserted de-asserts when both slots used
        // ==============================================================
        tc = 10;
        $display("\n[TC%02d] null_inserted de-asserts when both slots used", tc);
        quiesce(cnt_snap);

        // Force a null insertion
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b00, NULL_PAT_A);
        chk(tc, "null_inserted=1 (both slots empty)",  null_inserted == 1'b1);

        // Follow immediately with both slots occupied (no quiesce — tests rapid toggle)
        @(posedge clk);
        flit_in        = {SLOT1_PAT, SLOT0_PAT};
        flit_valid     = 1'b1;
        flit_slot_used = 2'b11;
        null_pattern   = NULL_PAT_A;
        @(posedge clk); #1;
        chk(tc, "null_inserted=0 (both slots used)",   null_inserted  == 1'b0);
        chk(tc, "flit_out_valid stays 1",              flit_out_valid == 1'b1);
        chk(tc, "slot0 intact after deassertion",      flit_out[1023:0]    == SLOT0_PAT);
        chk(tc, "slot1 intact after deassertion",      flit_out[2047:1024] == SLOT1_PAT);

        // ==============================================================
        // Summary
        // ==============================================================
        repeat (3) @(posedge clk);
        $display("");
        $display("========================================================");
        $display("  Test Results:");
        $display("    PASS : %0d", pass_cnt);
        $display("    FAIL : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("  *** ALL TEST CASES PASSED ***");
        else
            $display("  *** %0d TEST CASE(S) FAILED ***", fail_cnt);
        $display("========================================================");
        $finish;
    end

    // Watchdog
    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule
