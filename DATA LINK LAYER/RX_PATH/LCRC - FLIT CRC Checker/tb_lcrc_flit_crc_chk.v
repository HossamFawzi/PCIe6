// =============================================================================
// tb_lcrc_flit_crc_chk.v  — FINAL VERSION (timing fixed)
// PCIe Gen6 — Module 17: LCRC / FLIT CRC Checker Testbench
// =============================================================================
//
// ROOT CAUSE OF ALL PREVIOUS FAILURES — TIMING BUG:
//   Old send_pkt task:
//     @(negedge)  drive valid=1          ← posedge here captures valid=1
//     @(negedge)  deassert valid=0       ← task returns here
//     [caller]    @(posedge clk); #1     ← this posedge sees valid=0 → DUT outputs 0
//
//   Fix: task drives valid=1 at negedge, then waits for the POSEDGE that
//   captures it, THEN deasserts. Caller samples at posedge+1ns inside task,
//   and task returns the output values via output arguments so the caller
//   can check them. For simplicity: drive at negedge, wait ONE full clock
//   BEFORE deasserting, sample at posedge+1ns BEFORE deasserting.
//
// NEW APPROACH:
//   send_and_check task: drives packet, waits posedge+1ns, samples AND checks
//   outputs internally, then deasserts. This guarantees correct sampling.
//
// ALL reg declarations at MODULE LEVEL — no unnamed begin/end block errors.
// =============================================================================

`timescale 1ns/1ps

module tb_lcrc_flit_crc_chk;

    // ── DUT ports ─────────────────────────────────────────────────────────────
    reg           clk;
    reg           rst_n;
    reg  [1055:0] tlp_rx;
    reg           tlp_rx_valid;
    reg           flit_mode_en;

    wire          crc_ok;
    wire          crc_err;
    wire [1023:0] tlp_clean;
    wire          tlp_clean_valid;
    wire [11:0]   seq_rx;

    // ── Test counters and helpers — ALL at module level ───────────────────────
    integer pass_count;
    integer fail_count;
    integer test_num;

    // packet building
    reg [11:0]   b_seq;
    reg [991:0]  b_body;
    reg [31:0]   b_crc;
    reg [1055:0] b_pkt;

    // saved packets for multi-step tests
    reg [1055:0] pkt_bb1;       // back-to-back first
    reg [1055:0] pkt_bb2;       // back-to-back second
    reg [1055:0] pkt_mix_g1;   // mixed burst good1
    reg [1055:0] pkt_mix_bad;  // mixed burst bad
    reg [1055:0] pkt_mix_g2;   // mixed burst good2

    // burst counters
    integer burst_ok;
    integer burst_err_cnt;
    integer mix_ok;
    integer mix_err;
    integer i;

    // ── DUT instantiation ─────────────────────────────────────────────────────
    lcrc_flit_crc_chk u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_rx         (tlp_rx),
        .tlp_rx_valid   (tlp_rx_valid),
        .flit_mode_en   (flit_mode_en),
        .crc_ok         (crc_ok),
        .crc_err        (crc_err),
        .tlp_clean      (tlp_clean),
        .tlp_clean_valid(tlp_clean_valid),
        .seq_rx         (seq_rx)
    );

    // ── Clock: 100 MHz ────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always  #5  clk = ~clk;

    // ── Waveform dump ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("lcrc_flit_crc_chk.vcd");
        $dumpvars(0, tb_lcrc_flit_crc_chk);
    end

    // =========================================================================
    // REFERENCE CRC-32  (identical algorithm to DUT calc_crc32)
    // =========================================================================
    function [31:0] ref_crc32;
        input [991:0] data;
        integer       byte_idx;
        integer       bit_idx;
        reg [31:0]    crc;
        reg           data_bit;
        reg           xor_flag;
        reg [7:0]     cur_byte;
        begin
            crc = 32'hFFFF_FFFF;
            for (byte_idx = 123; byte_idx >= 0; byte_idx = byte_idx - 1) begin
                cur_byte = data[(byte_idx * 8) +: 8];
                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    data_bit = cur_byte[bit_idx];
                    xor_flag = crc[31] ^ data_bit;
                    crc      = crc << 1;
                    if (xor_flag) crc = crc ^ 32'h04C1_1DB7;
                end
            end
            ref_crc32 = crc;
        end
    endfunction

    // =========================================================================
    // HELPER: build_pkt(seq, body, corrupt)
    // Fills b_pkt with a complete 1056-bit packet.
    // corrupt=1 → XORs the CRC with 0xDEADBEEF so it will fail.
    // =========================================================================
    task build_pkt;
        input [11:0]  seq;
        input [991:0] body;
        input         corrupt;
        begin
            b_seq  = seq;
            b_body = body;
            b_crc  = ref_crc32(body);
            if (corrupt) b_crc = b_crc ^ 32'hDEAD_BEEF;
            // [1055:1044]=seq, [1043:1024]=20'b0, [1023:32]=body, [31:0]=crc
            b_pkt = {seq, 20'd0, body, b_crc};
        end
    endtask

    // =========================================================================
    // HELPER: check(condition, label)
    // =========================================================================
    task check;
        input        condition;
        input [255:0] label;
        begin
            test_num = test_num + 1;
            if (condition) begin
                $display("  [PASS] TC%0d: %s  (t=%0t)", test_num, label, $time);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] TC%0d: %s  (t=%0t) *** FAIL ***",
                         test_num, label, $time);
                $display("         crc_ok=%b crc_err=%b clean_valid=%b seq_rx=%h",
                         crc_ok, crc_err, tlp_clean_valid, seq_rx);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // HELPER: drive_pkt(pkt)
    // Drives one packet for exactly one clock cycle.
    // CORRECT TIMING:
    //   1. At negedge: put data on bus, assert valid
    //   2. At posedge: DUT captures data (outputs will appear one cycle later)
    //   3. At negedge: deassert valid (data held through the posedge)
    //   After this task the NEXT posedge will have the DUT outputs ready.
    // =========================================================================
    task drive_pkt;
        input [1055:0] pkt;
        begin
            @(negedge clk);
            tlp_rx       = pkt;
            tlp_rx_valid = 1'b1;
            @(posedge clk);      // DUT captures here
            @(negedge clk);      // now safe to deassert
            tlp_rx_valid = 1'b0;
            tlp_rx       = 1056'd0;
        end
    endtask

    // =========================================================================
    // HELPER: idle(n)
    // =========================================================================
    task idle;
        input integer n;
        begin repeat(n) @(posedge clk); end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        // init all module-level variables
        pass_count    = 0;
        fail_count    = 0;
        test_num      = 0;
        burst_ok      = 0;
        burst_err_cnt = 0;
        mix_ok        = 0;
        mix_err       = 0;
        i             = 0;
        rst_n         = 1'b0;
        tlp_rx        = 1056'd0;
        tlp_rx_valid  = 1'b0;
        flit_mode_en  = 1'b0;
        b_seq         = 12'd0;
        b_body        = 992'd0;
        b_crc         = 32'd0;
        b_pkt         = 1056'd0;
        pkt_bb1       = 1056'd0;
        pkt_bb2       = 1056'd0;
        pkt_mix_g1    = 1056'd0;
        pkt_mix_bad   = 1056'd0;
        pkt_mix_g2    = 1056'd0;

        $display("\n================================================================");
        $display("  PCIe Gen6 DLL RX — Module 17: LCRC/FLIT CRC Checker TB");
        $display("================================================================\n");

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[RESET] Released.\n");

        // =====================================================================
        // TC1: Basic correct packet → crc_ok + clean_valid
        // =====================================================================
        $display("--- TC1: Basic correct packet ---");
        build_pkt(12'h001,
                  {32'h60000010, 32'h00000001, 32'hDEADBEEF, 32'hCAFE0000, 928'hA5A5A5A5},
                  1'b0);
        drive_pkt(b_pkt);
        // drive_pkt returns AFTER posedge and negedge — DUT output is at
        // the posedge that just happened. Sample 1ns after that posedge.
        #1;
        check(crc_ok          === 1'b1,       "TC1: crc_ok");
        check(tlp_clean_valid === 1'b1,       "TC1: tlp_clean_valid");
        check(crc_err         === 1'b0,       "TC1: no crc_err");
        check(seq_rx          === 12'h001,    "TC1: seq_rx=0x001");
        idle(2);

        // =====================================================================
        // TC2: Single bit flip in body → crc_err
        // =====================================================================
        $display("\n--- TC2: Body bit flip → crc_err ---");
        build_pkt(12'h002, 992'hB1B2B3B4B5B6B7B8, 1'b0);
        b_pkt[132] = ~b_pkt[132];   // flip one bit in body region AFTER building
        drive_pkt(b_pkt);
        #1;
        check(crc_err         === 1'b1,    "TC2: crc_err on body flip");
        check(crc_ok          === 1'b0,    "TC2: no crc_ok");
        check(tlp_clean_valid === 1'b0,    "TC2: no clean_valid");
        check(tlp_clean       === 1024'd0, "TC2: tlp_clean=0 (no leak)");
        idle(2);

        // =====================================================================
        // TC3: Correct body, corrupted CRC field → crc_err
        // =====================================================================
        $display("\n--- TC3: Corrupted CRC field → crc_err ---");
        build_pkt(12'h003, 992'hC1C2C3C4C5C6C7C8, 1'b1);  // corrupt=1
        drive_pkt(b_pkt);
        #1;
        check(crc_err         === 1'b1, "TC3: crc_err on bad CRC field");
        check(crc_ok          === 1'b0, "TC3: no crc_ok");
        check(tlp_clean_valid === 1'b0, "TC3: no clean_valid");
        idle(2);

        // =====================================================================
        // TC4: valid=0 → all outputs zero
        // =====================================================================
        $display("\n--- TC4: valid=0 → outputs stay zero ---");
        @(negedge clk);
        tlp_rx       = 1056'hDEAD;
        tlp_rx_valid = 1'b0;         // valid LOW
        @(posedge clk); #1;
        check(crc_ok          === 1'b0, "TC4: no crc_ok");
        check(crc_err         === 1'b0, "TC4: no crc_err");
        check(tlp_clean_valid === 1'b0, "TC4: no clean_valid");
        check(seq_rx          === 12'd0,"TC4: seq_rx=0");
        @(negedge clk);
        tlp_rx = 1056'd0;
        idle(2);

        // =====================================================================
        // TC5: SEQ correctly extracted on pass
        // =====================================================================
        $display("\n--- TC5: SEQ extracted on pass ---");
        build_pkt(12'hABC, 992'h12345678ABCDEF, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok  === 1'b1,    "TC5: crc_ok");
        check(seq_rx  === 12'hABC, "TC5: seq_rx=0xABC");
        idle(2);

        // =====================================================================
        // TC6: SEQ extracted on CRC fail (ACK_TX needs it for NAK)
        // =====================================================================
        $display("\n--- TC6: SEQ extracted on CRC fail ---");
        build_pkt(12'hDEF, 992'hABCDEF01, 1'b1);  // corrupt CRC
        drive_pkt(b_pkt);
        #1;
        check(crc_err === 1'b1,    "TC6: crc_err asserted");
        check(seq_rx  === 12'hDEF, "TC6: seq_rx=0xDEF despite fail");
        idle(2);

        // =====================================================================
        // TC7: tlp_clean body matches input body
        // tlp_clean[1023:32] must equal b_body (the 992-bit body)
        // =====================================================================
        $display("\n--- TC7: tlp_clean body matches input ---");
        build_pkt(12'h007, 992'hFEDCBA9876543210, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok             === 1'b1,  "TC7: crc_ok");
        check(tlp_clean[1023:32] === b_body,"TC7: tlp_clean body correct");
        idle(2);

        // =====================================================================
        // TC8: tlp_clean lower 32 bits = 0 (CRC field stripped)
        // =====================================================================
        $display("\n--- TC8: tlp_clean[31:0]=0 (CRC stripped) ---");
        build_pkt(12'h008, 992'h1111222233334444, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1,  "TC8: crc_ok");
        check(tlp_clean[31:0] === 32'd0, "TC8: CRC stripped lower 32b=0");
        idle(2);

        // =====================================================================
        // TC9: flit_mode_en=1 → same algorithm, same pass
        // =====================================================================
        $display("\n--- TC9: flit_mode_en=1 ---");
        flit_mode_en = 1'b1;
        build_pkt(12'h009, 992'hCAFEBABEDEADBEEF, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1, "TC9: flit mode crc_ok");
        check(tlp_clean_valid === 1'b1, "TC9: flit mode clean_valid");
        check(crc_err         === 1'b0, "TC9: flit mode no crc_err");
        flit_mode_en = 1'b0;
        idle(2);

        // =====================================================================
        // TC10: Mode switch legacy→FLIT, both pass
        // =====================================================================
        $display("\n--- TC10: Mode switch 0→1 ---");
        flit_mode_en = 1'b0;
        build_pkt(12'h010, 992'hAAAABBBBCCCCDDDD, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok === 1'b1, "TC10: legacy mode crc_ok");

        flit_mode_en = 1'b1;
        build_pkt(12'h011, 992'hEEEEFFFF00001111, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok === 1'b1, "TC10: flit mode crc_ok after switch");
        flit_mode_en = 1'b0;
        idle(2);

        // =====================================================================
        // TC11: All-zero body with correct CRC → pass
        // =====================================================================
        $display("\n--- TC11: All-zero body ---");
        build_pkt(12'h011, 992'd0, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1, "TC11: all-zero crc_ok");
        check(tlp_clean_valid === 1'b1, "TC11: all-zero clean_valid");
        idle(2);

        // =====================================================================
        // TC12: All-ones body with correct CRC → pass
        // =====================================================================
        $display("\n--- TC12: All-ones body ---");
        build_pkt(12'h012, {992{1'b1}}, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1, "TC12: all-ones crc_ok");
        check(tlp_clean_valid === 1'b1, "TC12: all-ones clean_valid");
        idle(2);

        // =====================================================================
        // TC13: MSB of body flipped → crc_err
        // =====================================================================
        $display("\n--- TC13: MSB of body flipped ---");
        build_pkt(12'h013, 992'h80000000, 1'b0);
        b_pkt[1023] = ~b_pkt[1023];   // flip MSB of body field in pkt
        drive_pkt(b_pkt);
        #1;
        check(crc_err === 1'b1, "TC13: MSB flip crc_err");
        check(crc_ok  === 1'b0, "TC13: MSB flip no crc_ok");
        idle(2);

        // =====================================================================
        // TC14: LSB of body flipped → crc_err
        // =====================================================================
        $display("\n--- TC14: LSB of body flipped ---");
        build_pkt(12'h014, 992'h00000001, 1'b0);
        b_pkt[32] = ~b_pkt[32];       // flip LSB of body field (bit 32 of pkt)
        drive_pkt(b_pkt);
        #1;
        check(crc_err === 1'b1, "TC14: LSB flip crc_err");
        check(crc_ok  === 1'b0, "TC14: LSB flip no crc_ok");
        idle(2);

        // =====================================================================
        // TC15: Back-to-back two correct packets
        // Drive both with valid=1 back to back (no gap).
        // First capture posedge is for pkt_bb1, second for pkt_bb2.
        // =====================================================================
        $display("\n--- TC15: Back-to-back two correct packets ---");
        build_pkt(12'h015, 992'hAAAA1111, 1'b0);
        pkt_bb1 = b_pkt;
        build_pkt(12'h016, 992'hBBBB2222, 1'b0);
        pkt_bb2 = b_pkt;

        // Drive pkt1
        @(negedge clk);
        tlp_rx       = pkt_bb1;
        tlp_rx_valid = 1'b1;
        @(posedge clk);   // DUT captures pkt_bb1 here
        #1;               // sample outputs for pkt_bb1
        check(crc_ok       === 1'b1,    "TC15: pkt1 crc_ok");
        check(tlp_clean_valid=== 1'b1,  "TC15: pkt1 clean_valid");
        check(seq_rx       === 12'h015, "TC15: pkt1 seq=0x015");

        // Drive pkt2 immediately (still at posedge, go to negedge then drive)
        @(negedge clk);
        tlp_rx       = pkt_bb2;
        tlp_rx_valid = 1'b1;
        @(posedge clk);   // DUT captures pkt_bb2 here
        #1;               // sample outputs for pkt_bb2
        check(crc_ok       === 1'b1,    "TC15: pkt2 crc_ok");
        check(tlp_clean_valid=== 1'b1,  "TC15: pkt2 clean_valid");
        check(seq_rx       === 12'h016, "TC15: pkt2 seq=0x016");

        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        idle(2);

        // =====================================================================
        // TC16: 1-cycle pulse check
        // =====================================================================
        $display("\n--- TC16: 1-cycle pulse check ---");
        build_pkt(12'h017, 992'hC3C3C3C3, 1'b0);
        // Drive, check HIGH at the capture posedge
        @(negedge clk);
        tlp_rx       = b_pkt;
        tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(crc_ok          === 1'b1, "TC16: crc_ok HIGH at N+1");
        check(tlp_clean_valid === 1'b1, "TC16: clean_valid HIGH at N+1");
        // Deassert, check cleared next posedge
        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        @(posedge clk); #1;
        check(crc_ok          === 1'b0, "TC16: crc_ok cleared N+2 (pulse)");
        check(tlp_clean_valid === 1'b0, "TC16: clean_valid cleared N+2 (pulse)");
        idle(2);

        // =====================================================================
        // TC17: Reset during operation
        // =====================================================================
        $display("\n--- TC17: Reset during operation ---");
        build_pkt(12'h018, 992'hD4D4D4D4, 1'b0);
        @(negedge clk);
        tlp_rx       = b_pkt;
        tlp_rx_valid = 1'b1;
        @(negedge clk);
        rst_n        = 1'b0;
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        @(posedge clk); #1;
        check(crc_ok          === 1'b0,    "TC17: crc_ok=0 in reset");
        check(crc_err         === 1'b0,    "TC17: crc_err=0 in reset");
        check(tlp_clean_valid === 1'b0,    "TC17: clean_valid=0 in reset");
        check(tlp_clean       === 1024'd0, "TC17: tlp_clean=0 in reset");
        check(seq_rx          === 12'd0,   "TC17: seq_rx=0 in reset");
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[INFO] Reset released.");
        idle(2);

        // =====================================================================
        // TC18: tlp_clean=0 on CRC fail (data leak check)
        // =====================================================================
        $display("\n--- TC18: tlp_clean=0 on fail (no leak) ---");
        build_pkt(12'h019, 992'hE5E5E5E5DEADBEEF, 1'b1);
        drive_pkt(b_pkt);
        #1;
        check(crc_err         === 1'b1,    "TC18: crc_err");
        check(tlp_clean       === 1024'd0, "TC18: tlp_clean=0 (no leak)");
        check(tlp_clean_valid === 1'b0,    "TC18: no clean_valid");
        idle(2);

        // =====================================================================
        // TC19: Burst of 6 correct packets — all must pass
        // Each iteration: drive at negedge, posedge captures, sample at posedge+1ns
        // =====================================================================
        $display("\n--- TC19: Burst of 6 correct packets ---");
        burst_ok      = 0;
        burst_err_cnt = 0;
        for (i = 0; i < 6; i = i + 1) begin
            b_body = {i[7:0], 8'hAA, 8'hBB, 8'hCC, {956{1'b0}}};
            build_pkt(i[11:0], b_body, 1'b0);
            @(negedge clk);
            tlp_rx       = b_pkt;
            tlp_rx_valid = 1'b1;
            @(posedge clk); #1;
            if (crc_ok && tlp_clean_valid) burst_ok      = burst_ok + 1;
            if (crc_err)                   burst_err_cnt = burst_err_cnt + 1;
        end
        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        check(burst_ok      === 6, "TC19: all 6 burst packets passed");
        check(burst_err_cnt === 0, "TC19: zero crc_err in burst");
        idle(3);

        // =====================================================================
        // TC20: Mixed burst: correct / bad / correct → 2 ok, 1 err
        // =====================================================================
        $display("\n--- TC20: Mixed burst correct/bad/correct ---");
        build_pkt(12'h020, 992'hF1F1F1F1, 1'b0);
        pkt_mix_g1 = b_pkt;
        build_pkt(12'h021, 992'h22223333, 1'b1);  // corrupt
        pkt_mix_bad = b_pkt;
        build_pkt(12'h022, 992'h44445555, 1'b0);
        pkt_mix_g2 = b_pkt;
        mix_ok  = 0;
        mix_err = 0;

        @(negedge clk); tlp_rx = pkt_mix_g1; tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (crc_ok)  mix_ok  = mix_ok  + 1;

        @(negedge clk); tlp_rx = pkt_mix_bad; tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (crc_err) mix_err = mix_err + 1;

        @(negedge clk); tlp_rx = pkt_mix_g2; tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (crc_ok)  mix_ok  = mix_ok  + 1;

        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;

        check(mix_ok  === 2, "TC20: exactly 2 crc_ok");
        check(mix_err === 1, "TC20: exactly 1 crc_err");
        idle(3);

        // =====================================================================
        // FINAL RESULTS
        // =====================================================================
        $display("\n================================================================");
        $display("  LCRC / FLIT CRC Checker — Final Result");
        $display("  PASS = %0d  |  FAIL = %0d  |  TOTAL = %0d",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TESTS FAILED ***", fail_count);
        $display("================================================================\n");
        $finish;
    end

    // ── Watchdog ──────────────────────────────────────────────────────────────
    initial begin
        #500000;
        $display("[WATCHDOG] 500us — force finish.");
        $finish;
    end

endmodule