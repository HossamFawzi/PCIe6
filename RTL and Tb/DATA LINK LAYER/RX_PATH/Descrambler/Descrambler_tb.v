// =============================================================================
// Testbench   : Descrambler_tb
// Description : Comprehensive testbench for PCIe 6.0 RX Descrambler
//
// Test Plan   :
//   TC1  - Reset behaviour (outputs zero/inactive after rst_n)
//   TC2  - Bypass mode (scramble_en=0): data passes through unchanged
//   TC3  - Descramble mode: scrambled input XOR'd with LFSR keystream
//   TC4  - TX↔RX symmetry: Scrambler(Descrambler(data)) == data
//   TC5  - Link reset: LFSR reseeds to lfsr_seed, output clears
//   TC6  - LFSR sync-error detection: wrong seed triggers lfsr_sync_err
//   TC7  - data_valid_in=0: output freezes, no LFSR advance
//   TC8  - Back-to-back transfers (no gap)
//   TC9  - All-zero data vector
//   TC10 - All-ones data vector
//   TC11 - Alternating pattern 0xAA...AA / 0x55...55
//
// References  : PCIe Base Spec 6.0, Section 4.2.2 (Scrambling)
// =============================================================================

`timescale 1ns/1ps

module Descrambler_tb;

    // -------------------------------------------------------------------------
    // DUT Port Connections
    // -------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg [255:0] data_in;
    reg         data_valid_in;
    reg [22:0]  lfsr_seed;
    reg         scramble_en;
    reg         link_reset;

    wire [255:0] data_out;
    wire         data_valid_out;
    wire         lfsr_sync_err;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    Descrambler DUT (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (data_in),
        .data_valid_in (data_valid_in),
        .lfsr_seed     (lfsr_seed),
        .scramble_en   (scramble_en),
        .link_reset    (link_reset),
        .data_out      (data_out),
        .data_valid_out(data_valid_out),
        .lfsr_sync_err (lfsr_sync_err)
    );

    // -------------------------------------------------------------------------
    // Clock Generation: 200 MHz (5 ns period) — PCIe 6.0 datapath clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #2.5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Test counters
    // -------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    // -------------------------------------------------------------------------
    // Reference LFSR model (mirrors DUT logic)
    // Polynomial: x^23+x^21+x^16+x^8+x^5+x^2+1
    // -------------------------------------------------------------------------
    reg [22:0] ref_lfsr;

    task ref_lfsr_init;
        input [22:0] seed;
        begin
            ref_lfsr = seed;
        end
    endtask

    // Advance reference LFSR by 1 step, return output bit
    function automatic ref_step;
        // No input needed; uses ref_lfsr
        input dummy;
        reg feedback;
        begin
            feedback   = ref_lfsr[22] ^ ref_lfsr[20] ^ ref_lfsr[15]
                       ^ ref_lfsr[7]  ^ ref_lfsr[4]  ^ ref_lfsr[1]
                       ^ ref_lfsr[0];
            ref_step   = ref_lfsr[0];
            ref_lfsr   = {feedback, ref_lfsr[22:1]};
        end
    endfunction

    // Generate 256-bit keystream from current ref_lfsr
    function automatic [255:0] ref_keystream;
        input dummy;
        integer b;
        begin
            for (b = 0; b < 256; b = b + 1)
                ref_keystream[b] = ref_step(1'b0);
        end
    endfunction

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------

    // Apply synchronous reset
    task apply_reset;
        begin
            rst_n         = 0;
            link_reset    = 0;
            data_valid_in = 0;
            data_in       = 256'b0;
            lfsr_seed     = 23'h7FFFFF;
            scramble_en   = 1;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst_n = 1;
            @(posedge clk); #1;
        end
    endtask

    // Drive one cycle of data and wait for output
    task drive_cycle;
        input [255:0] din;
        input         valid;
        begin
            data_in       = din;
            data_valid_in = valid;
            @(posedge clk); #1;
        end
    endtask

    // Check with pass/fail reporting
    task check;
        input [255:0] got;
        input [255:0] expected;
        input [127:0] test_name;
        begin
            if (got === expected) begin
                $display("  PASS | %s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL | %s", test_name);
                $display("         Got      : %h", got);
                $display("         Expected : %h", expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_bit;
        input got;
        input expected;
        input [127:0] test_name;
        begin
            if (got === expected) begin
                $display("  PASS | %s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL | %s | got=%b expected=%b", test_name, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    reg [255:0] ref_ks;
    reg [255:0] scrambled_data;
    reg [255:0] raw_data;

    initial begin
        $dumpfile("Descrambler_tb.vcd");
        $dumpvars(0, Descrambler_tb);

        $display("====================================================");
        $display("  PCIe 6.0 Descrambler Testbench");
        $display("  Polynomial: x^23+x^21+x^16+x^8+x^5+x^2+1");
        $display("====================================================");

        // ==============================================================
        // TC1: Reset Behaviour
        // ==============================================================
        $display("\n--- TC1: Reset Behaviour ---");
        apply_reset;
        check(data_out,       256'b0, "data_out=0 after reset");
        check_bit(data_valid_out, 1'b0,   "data_valid_out=0 after reset");
        check_bit(lfsr_sync_err,  1'b0,   "lfsr_sync_err=0 after reset");

        // ==============================================================
        // TC2: Bypass Mode (scramble_en=0)
        // ==============================================================
        $display("\n--- TC2: Bypass Mode (scramble_en=0) ---");
        apply_reset;
        scramble_en = 0;
        raw_data    = 256'hDEADBEEFCAFEBABE_0123456789ABCDEF_FEEDFACE_DEADC0DE_BADDCAFE_12345678_AABBCCDD_EEFF0011;
        drive_cycle(raw_data, 1'b1);
        @(posedge clk); #1;          // one extra cycle for registered output
        check(data_out, raw_data, "bypass: data_out==data_in");
        check_bit(data_valid_out, 1'b1, "bypass: data_valid_out=1");

        // ==============================================================
        // TC3: Descramble Mode — verify XOR with reference LFSR
        // ==============================================================
        $display("\n--- TC3: Descramble mode (scramble_en=1) ---");
        apply_reset;
        scramble_en = 1;
        lfsr_seed   = 23'h7FFFFF;

        // Initialise reference LFSR to same seed as DUT reset state
        ref_lfsr_init(23'h7FFFFF);

        // Build scrambled input (what TX would have sent)
        ref_ks       = ref_keystream(1'b0);
        raw_data     = 256'hA5A5A5A5A5A5A5A5_5A5A5A5A5A5A5A5A_F0F0F0F0F0F0F0F0_0F0F0F0F0F0F0F0F;
        scrambled_data = raw_data ^ ref_ks;   // what arrived on the wire

        // Drive the scrambled data into the DUT
        drive_cycle(scrambled_data, 1'b1);
        @(posedge clk); #1;
        check(data_out, raw_data, "descramble: recovered original data");
        check_bit(data_valid_out, 1'b1, "descramble: data_valid_out=1");

        // ==============================================================
        // TC4: TX↔RX Symmetry (double descramble == identity)
        // ==============================================================
        $display("\n--- TC4: TX/RX Symmetry ---");
        // After TC3 the DUT LFSR has advanced 256 steps.
        // ref_lfsr has also advanced. Drive another 256 bits.
        raw_data       = 256'hFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000;
        ref_ks         = ref_keystream(1'b0);
        scrambled_data = raw_data ^ ref_ks;

        drive_cycle(scrambled_data, 1'b1);
        @(posedge clk); #1;
        check(data_out, raw_data, "symmetry: descramble(scramble(data))==data");

        // ==============================================================
        // TC5: Link Reset → LFSR re-seeds
        // ==============================================================
        $display("\n--- TC5: Link Reset ---");
        // While data is flowing, assert link_reset
        lfsr_seed     = 23'h123456 & 23'h7FFFFF;  // arbitrary new seed
        link_reset    = 1;
        data_valid_in = 1;
        data_in       = 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
        @(posedge clk); #1;
        link_reset = 0;
        // After link_reset, data_out should be 0 and DUT LFSR = new seed
        check(data_out, 256'b0,  "link_reset: data_out clears");
        check_bit(data_valid_out, 1'b0, "link_reset: data_valid_out=0");

        // Now re-seed reference LFSR and verify first output after reset
        ref_lfsr_init(23'h123456 & 23'h7FFFFF);

        raw_data       = 256'hBEEFBEEFBEEFBEEF_CAFECAFECAFECAFE_DEADDEADDEADDEAD_BABABABABABABABA;
        ref_ks         = ref_keystream(1'b0);
        scrambled_data = raw_data ^ ref_ks;

        data_in        = scrambled_data;
        data_valid_in  = 1;
        scramble_en    = 1;
        @(posedge clk); #1;   // DUT latches data_in, computes XOR, drives data_out
        check(data_out, raw_data, "post link_reset: descramble with new seed");

        // ==============================================================
        // TC6: LFSR Sync Error Detection
        // ==============================================================
        $display("\n--- TC6: LFSR Sync Error ---");
        apply_reset;
        scramble_en   = 1;
        // Inject wrong seed (different from DUT's internal state 7FFFFF)
        lfsr_seed     = 23'h000001;
        data_in       = 256'hABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD_ABCD;
        data_valid_in = 1;
        @(posedge clk); #1;
        check_bit(lfsr_sync_err, 1'b1, "sync_err: wrong seed → lfsr_sync_err=1");

        // Correct the seed
        lfsr_seed = 23'h7FFFFF;
        @(posedge clk); #1;
        check_bit(lfsr_sync_err, 1'b0, "sync_err: correct seed → lfsr_sync_err=0 (may take cycle)");

        // ==============================================================
        // TC7: data_valid_in=0 — Output freezes, no LFSR advance
        // ==============================================================
        $display("\n--- TC7: data_valid_in=0 (stall) ---");
        apply_reset;
        scramble_en   = 1;
        lfsr_seed     = 23'h7FFFFF;
        ref_lfsr_init(23'h7FFFFF);

        // Send one valid beat
        raw_data       = 256'h1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000;
        ref_ks         = ref_keystream(1'b0);
        drive_cycle(raw_data ^ ref_ks, 1'b1);
        @(posedge clk); #1;

        // Hold valid=0 for 3 cycles
        drive_cycle(256'b0, 1'b0);
        drive_cycle(256'b0, 1'b0);
        drive_cycle(256'b0, 1'b0);

        // Send second valid beat — LFSR should NOT have advanced during stall
        raw_data       = 256'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999;
        ref_ks         = ref_keystream(1'b0);        // continues from where it left off
        drive_cycle(raw_data ^ ref_ks, 1'b1);
        @(posedge clk); #1;
        check(data_out, raw_data, "stall: LFSR does not advance during valid=0");

        // ==============================================================
        // TC8: Back-to-Back Transfers
        // ==============================================================
        $display("\n--- TC8: Back-to-Back Transfers (4 beats) ---");
        apply_reset;
        scramble_en = 1;
        lfsr_seed   = 23'h7FFFFF;
        ref_lfsr_init(23'h7FFFFF);

        begin : B2B
            integer b;
            reg [255:0] beat_data [0:3];
            reg [255:0] beat_scr  [0:3];
            reg [255:0] beat_ks   [0:3];

            beat_data[0] = 256'h0000_0000_0000_0001_0000_0000_0000_0002_0000_0000_0000_0003_0000_0000_0000_0004;
            beat_data[1] = 256'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_FEED_FACE_DEAD_C0DE_0BAD_CAFE_DEAD_BEEF;
            beat_data[2] = 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_0000_0000_0000_0000_0000_0000_0000_0000;
            beat_data[3] = 256'hA5A5_A5A5_A5A5_A5A5_5A5A_5A5A_5A5A_5A5A_F0F0_F0F0_F0F0_F0F0_0F0F_0F0F_0F0F_0F0F;

            // Pre-compute scrambled inputs
            for (b = 0; b < 4; b = b + 1) begin
                beat_ks[b]  = ref_keystream(1'b0);
                beat_scr[b] = beat_data[b] ^ beat_ks[b];
            end

            // Drive beats back-to-back
            for (b = 0; b < 4; b = b + 1) begin
                drive_cycle(beat_scr[b], 1'b1);
            end
            // One extra cycle for registered output to settle on last beat
            @(posedge clk); #1;
            check(data_out, beat_data[3], "b2b: beat 4 descrambled correctly");
        end

        // ==============================================================
        // TC9: All-Zero Data
        // ==============================================================
        $display("\n--- TC9: All-Zero Data ---");
        apply_reset;
        scramble_en = 1;
        lfsr_seed   = 23'h7FFFFF;
        ref_lfsr_init(23'h7FFFFF);
        // All-zero scrambled = pure keystream on wire
        ref_ks  = ref_keystream(1'b0);
        drive_cycle(ref_ks, 1'b1);   // XOR(0, ks) = ks; DUT XOR(ks, ks) = 0
        @(posedge clk); #1;
        check(data_out, 256'b0, "all-zero: data_out=0 when data_in=keystream");

        // ==============================================================
        // TC10: All-Ones Data
        // ==============================================================
        $display("\n--- TC10: All-Ones Data ---");
        apply_reset;
        scramble_en = 1;
        lfsr_seed   = 23'h7FFFFF;
        ref_lfsr_init(23'h7FFFFF);
        raw_data   = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        ref_ks     = ref_keystream(1'b0);
        drive_cycle(raw_data ^ ref_ks, 1'b1);
        @(posedge clk); #1;
        check(data_out, raw_data, "all-ones: descrambled correctly");

        // ==============================================================
        // TC11: Alternating 0xAA / 0x55 pattern
        // ==============================================================
        $display("\n--- TC11: Alternating 0xAA/0x55 Pattern ---");
        apply_reset;
        scramble_en = 1;
        lfsr_seed   = 23'h7FFFFF;
        ref_lfsr_init(23'h7FFFFF);
        raw_data   = {32{8'hAA}};
        ref_ks     = ref_keystream(1'b0);
        drive_cycle(raw_data ^ ref_ks, 1'b1);
        @(posedge clk); #1;
        check(data_out, raw_data, "alternating 0xAA: descrambled correctly");

        raw_data   = {32{8'h55}};
        ref_ks     = ref_keystream(1'b0);
        drive_cycle(raw_data ^ ref_ks, 1'b1);
        @(posedge clk); #1;
        check(data_out, raw_data, "alternating 0x55: descrambled correctly");

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n====================================================");
        $display("  TEST COMPLETE: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("====================================================\n");

        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED — DUT Ready for Integration ***\n");
        else
            $display("  *** FAILURES DETECTED — Review waveform in .vcd  ***\n");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout Watchdog
    // -------------------------------------------------------------------------
    initial begin
        #50000;
        $display("TIMEOUT: Simulation exceeded 50us limit.");
        $finish;
    end

endmodule
