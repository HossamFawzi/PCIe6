
`timescale 1ns / 1ps

module flit_null_slot_inserter_tb;

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

    initial clk = 1'b0;
    always  #5 clk = ~clk;

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

    task automatic quiesce;
        output [7:0] cnt_snapshot;
        begin

            @(posedge clk);
            flit_valid     = 1'b0;
            flit_slot_used = 2'b11;

            @(posedge clk);
            #1;
            cnt_snapshot = null_count;
        end
    endtask

    task automatic drive_and_sample;
        input [2047:0] fin;
        input          fv;
        input [1:0]    fsu;
        input [1023:0] np;
        begin

            @(posedge clk);
            flit_in        = fin;
            flit_valid     = fv;
            flit_slot_used = fsu;
            null_pattern   = np;

            @(posedge clk);
            #1;
        end
    endtask

    localparam [1023:0] SLOT0_PAT  = {128{8'hA5}};
    localparam [1023:0] SLOT1_PAT  = {128{8'h5A}};
    localparam [1023:0] NULL_PAT_A = {128{8'hCC}};
    localparam [1023:0] NULL_PAT_B = {128{8'h33}};

    reg [7:0] cnt_snap;
    integer   tc, i;

    initial begin
        $display("========================================================");
        $display("  PCIe Gen6 - FLIT Null Slot Inserter (TX) Testbench");
        $display("  DUT: flit_null_slot_inserter  |  NULL_INS");
        $display("========================================================");

        rst_n          = 1'b0;
        flit_in        = {2048{1'b0}};
        flit_valid     = 1'b0;
        flit_slot_used = 2'b11;
        null_pattern   = NULL_PAT_A;

        tc = 1;
        $display("\n[TC%02d] Reset behaviour", tc);
        repeat (3) @(posedge clk); #1;
        chk(tc, "flit_out_valid=0 in reset",  flit_out_valid == 1'b0);
        chk(tc, "null_inserted=0 in reset",   null_inserted  == 1'b0);
        chk(tc, "null_count=0 in reset",      null_count     == 8'h00);
        chk(tc, "flit_out=0 in reset",        flit_out       == {2048{1'b0}});

        @(posedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk); #1;

        tc = 2;
        $display("\n[TC%02d] Both slots USED - pass-through, no null insertion", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b11, NULL_PAT_A);
        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 0",             null_inserted  == 1'b0);
        chk(tc, "slot0 data preserved",           flit_out[1023:0]    == SLOT0_PAT);
        chk(tc, "slot1 data preserved",           flit_out[2047:1024] == SLOT1_PAT);
        chk(tc, "null_count unchanged",           null_count == cnt_snap);

        tc = 3;
        $display("\n[TC%02d] Slot 0 EMPTY - null fill in slot 0", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b10, NULL_PAT_A);

        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 1",             null_inserted  == 1'b1);
        chk(tc, "slot0 = null_pattern",           flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "slot1 = original SLOT1_PAT",     flit_out[2047:1024] == SLOT1_PAT);
        chk(tc, "null_count incremented by 1",    null_count == cnt_snap + 8'h01);

        tc = 4;
        $display("\n[TC%02d] Slot 1 EMPTY - null fill in slot 1", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b01, NULL_PAT_A);

        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 1",             null_inserted  == 1'b1);
        chk(tc, "slot0 = original SLOT0_PAT",     flit_out[1023:0]    == SLOT0_PAT);
        chk(tc, "slot1 = null_pattern",           flit_out[2047:1024] == NULL_PAT_A);
        chk(tc, "null_count incremented by 1",    null_count == cnt_snap + 8'h01);

        tc = 5;
        $display("\n[TC%02d] BOTH slots EMPTY - null fill both", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b00, NULL_PAT_A);
        chk(tc, "flit_out_valid = 1",             flit_out_valid == 1'b1);
        chk(tc, "null_inserted  = 1",             null_inserted  == 1'b1);
        chk(tc, "slot0 = null_pattern",           flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "slot1 = null_pattern",           flit_out[2047:1024] == NULL_PAT_A);
        chk(tc, "null_count incremented by 1",    null_count == cnt_snap + 8'h01);

        tc = 6;
        $display("\n[TC%02d] null_count saturation at 255", tc);

        for (i = 0; i < 252; i = i + 1) begin
            @(posedge clk);
            flit_in        = {SLOT1_PAT, SLOT0_PAT};
            flit_valid     = 1'b1;
            flit_slot_used = 2'b00;
        end
        @(posedge clk); #1;
        chk(tc, "null_count reached 255",          null_count == 8'hFF);

        @(posedge clk);
        flit_valid     = 1'b1;
        flit_slot_used = 2'b00;
        @(posedge clk); #1;
        chk(tc, "null_count saturated (stays 255)", null_count == 8'hFF);

        tc = 7;
        $display("\n[TC%02d] flit_valid=0 - output stays de-asserted", tc);
        quiesce(cnt_snap);
        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b0, 2'b00, NULL_PAT_A);
        chk(tc, "flit_out_valid=0 when invalid",   flit_out_valid == 1'b0);
        chk(tc, "null_inserted=0  when invalid",   null_inserted  == 1'b0);
        chk(tc, "null_count unchanged",            null_count == cnt_snap);

        tc = 8;
        $display("\n[TC%02d] Back-to-back FLITs, alternating slot usage", tc);
        quiesce(cnt_snap);

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

        @(posedge clk);
        flit_in        = {SLOT1_PAT, SLOT0_PAT};
        flit_valid     = 1'b1;
        flit_slot_used = 2'b10;
        null_pattern   = NULL_PAT_A;
        @(posedge clk); #1;
        chk(tc, "[B] flit_out_valid = 1",          flit_out_valid == 1'b1);
        chk(tc, "[B] null_inserted  = 1",          null_inserted  == 1'b1);
        chk(tc, "[B] slot0 = null_pattern",        flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "[B] slot1 = SLOT1_PAT",           flit_out[2047:1024] == SLOT1_PAT);

        @(posedge clk);
        flit_in        = {SLOT1_PAT, SLOT0_PAT};
        flit_valid     = 1'b1;
        flit_slot_used = 2'b00;
        null_pattern   = NULL_PAT_A;
        @(posedge clk); #1;
        chk(tc, "[C] null_inserted  = 1",          null_inserted  == 1'b1);
        chk(tc, "[C] slot0 = null_pattern",        flit_out[1023:0]    == NULL_PAT_A);
        chk(tc, "[C] slot1 = null_pattern",        flit_out[2047:1024] == NULL_PAT_A);

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

        chk(tc, "PAT_A != PAT_B (patterns distinct)", NULL_PAT_A !== NULL_PAT_B);

        tc = 10;
        $display("\n[TC%02d] null_inserted de-asserts when both slots used", tc);
        quiesce(cnt_snap);

        drive_and_sample({SLOT1_PAT, SLOT0_PAT}, 1'b1, 2'b00, NULL_PAT_A);
        chk(tc, "null_inserted=1 (both slots empty)",  null_inserted == 1'b1);

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

    initial begin #2_000_000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule
