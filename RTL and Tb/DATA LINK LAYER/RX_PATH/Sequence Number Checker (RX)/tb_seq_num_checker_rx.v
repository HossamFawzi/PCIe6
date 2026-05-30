// =============================================================================
// Testbench : tb_seq_num_checker_rx
// DUT       : seq_num_checker_rx
// Coverage  :
//   TC1  – Normal in-order sequence (0,1,2,3)       → tlp_seq_ok x4
//   TC2  – Duplicate TLP (seq = expected-1)          → tlp_dup, seq_dup_ack
//   TC3  – Sequence error (gap: 0→2)                 → tlp_seq_err, nak_req
//   TC4  – CRC fail (tlp_ok=0) skips seq check       → no ok/dup/err outputs
//   TC5  – 12-bit wrap-around (4094→4095→0)          → correct wrap, no error
//   TC6  – link_reset resets expected_seq to 0        → counter cleared
//   TC7  – Duplicate at seq=0 (boundary: prev=4095)  → tlp_dup
//   TC8  – Back-to-back good TLPs (pipeline stress)  → all ok, counter advances
//   TC9  – Error then recovery (seq resumes correct)  → ok after error
//   TC10 – tlp_rx_valid=0 → outputs stay low          → no side effects
//
// Timing model (same as tb_nullified_tlp_handler fixed version):
//   Drive inputs #1 ns after posedge.
//   Sample outputs #1 ns after the following posedge (registered DUT).
//   Inputs de-asserted after each check to avoid bleed.
// =============================================================================

`timescale 1ns/1ps

module tb_seq_num_checker_rx;

    // ── DUT ports ─────────────────────────────────────────────────────────────
    reg          clk;
    reg          rst_n;
    reg          link_reset;
    reg  [11:0]  seq_rx;
    reg          tlp_rx_valid;
    reg          tlp_ok;
    reg  [1023:0] tlp_clean;

    wire          tlp_seq_ok;
    wire          tlp_dup;
    wire          tlp_seq_err;
    wire          nak_req;
    wire          seq_dup_ack;
    wire [11:0]   seq_err_val;
    wire [11:0]   next_expected;
    wire [1023:0] tlp_fwd;
    wire          tlp_fwd_valid;

    // ── DUT instantiation ─────────────────────────────────────────────────────
    seq_num_checker_rx dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .link_reset   (link_reset),
        .seq_rx       (seq_rx),
        .tlp_rx_valid (tlp_rx_valid),
        .tlp_ok       (tlp_ok),
        .tlp_clean    (tlp_clean),
        .tlp_seq_ok   (tlp_seq_ok),
        .tlp_dup      (tlp_dup),
        .tlp_seq_err  (tlp_seq_err),
        .nak_req      (nak_req),
        .seq_dup_ack  (seq_dup_ack),
        .seq_err_val  (seq_err_val),
        .next_expected(next_expected),
        .tlp_fwd      (tlp_fwd),
        .tlp_fwd_valid(tlp_fwd_valid)
    );

    // ── Clock: 250 MHz (4 ns period) ─────────────────────────────────────────
    initial clk = 0;
    always #2 clk = ~clk;

    // ── Scoreboard ────────────────────────────────────────────────────────────
    integer pass_count = 0;
    integer fail_count = 0;

    task check1;
        input [255:0] label;
        input         expected;
        input         actual;
        begin
            if (expected === actual) begin
                $display("[PASS] %0s | exp=%b got=%b", label, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | exp=%b got=%b  @%0t", label, expected, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check12;
        input [255:0] label;
        input [11:0]  expected;
        input [11:0]  actual;
        begin
            if (expected === actual) begin
                $display("[PASS] %0s | exp=0x%03h got=0x%03h", label, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | exp=0x%03h got=0x%03h  @%0t", label, expected, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Drive one TLP and sample outputs ─────────────────────────────────────
    // Inputs driven #1 after posedge; outputs sampled #1 after next posedge.
    task send_tlp;
        input [11:0]  seq;
        input         crc_ok;
        input [1023:0] payload;
        begin
            @(posedge clk); #1;
            seq_rx       <= seq;
            tlp_rx_valid <= 1'b1;
            tlp_ok       <= crc_ok;
            tlp_clean    <= payload;

            @(posedge clk); #1;
            // outputs now stable — caller checks here

            // de-assert
            tlp_rx_valid <= 1'b0;
            tlp_ok       <= 1'b0;
            seq_rx       <= 12'h000;
            tlp_clean    <= 1024'b0;
        end
    endtask

    // ── Idle one cycle (no TLP) ───────────────────────────────────────────────
    task idle_cycle;
        begin
            @(posedge clk); #1;
            tlp_rx_valid <= 1'b0;
        end
    endtask

    // ── Test sequence ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_seq_num_checker_rx.vcd");
        $dumpvars(0, tb_seq_num_checker_rx);

        // ── Reset ──────────────────────────────────────────────────────────
        rst_n        = 1'b0;
        link_reset   = 1'b0;
        seq_rx       = 12'h000;
        tlp_rx_valid = 1'b0;
        tlp_ok       = 1'b0;
        tlp_clean    = 1024'b0;
        repeat(4) @(posedge clk);
        #1; rst_n = 1'b1;
        repeat(2) @(posedge clk); #1;

        // ==================================================================
        // TC1 – Normal in-order sequence: 0, 1, 2, 3
        // ==================================================================
        $display("\n--- TC1: In-order sequence 0→1→2→3 ---");
        begin : tc1
            integer i;
            for (i = 0; i < 4; i = i + 1) begin
                send_tlp(i[11:0], 1'b1, {1012'b0, i[11:0]});
                check1("TC1 tlp_seq_ok",   1'b1, tlp_seq_ok);
                check1("TC1 tlp_dup",      1'b0, tlp_dup);
                check1("TC1 tlp_seq_err",  1'b0, tlp_seq_err);
                check1("TC1 tlp_fwd_valid",1'b1, tlp_fwd_valid);
                check12("TC1 next_expected", i[11:0]+12'd1, next_expected);
                idle_cycle;
            end
        end

        // ==================================================================
        // TC2 – Duplicate TLP (seq == expected_seq - 1 = 3)
        // expected_seq is now 4; duplicate = seq 3
        // ==================================================================
        $display("\n--- TC2: Duplicate TLP (seq=3, expected=4) ---");
        send_tlp(12'h003, 1'b1, 1024'hDEAD);
        check1("TC2 tlp_dup",       1'b1, tlp_dup);
        check1("TC2 seq_dup_ack",   1'b1, seq_dup_ack);
        check1("TC2 tlp_seq_ok",    1'b0, tlp_seq_ok);
        check1("TC2 tlp_seq_err",   1'b0, tlp_seq_err);
        check1("TC2 tlp_fwd_valid", 1'b0, tlp_fwd_valid);
        check12("TC2 next_expected unchanged", 12'h004, next_expected);
        idle_cycle;

        // ==================================================================
        // TC3 – Sequence error: gap from 4 → 6 (expected=4, got=6)
        // ==================================================================
        $display("\n--- TC3: Sequence error (expected=4, got=6) ---");
        send_tlp(12'h006, 1'b1, 1024'hBAD);
        check1("TC3 tlp_seq_err",  1'b1, tlp_seq_err);
        check1("TC3 nak_req",      1'b1, nak_req);
        check1("TC3 tlp_seq_ok",   1'b0, tlp_seq_ok);
        check1("TC3 tlp_dup",      1'b0, tlp_dup);
        check1("TC3 tlp_fwd_valid",1'b0, tlp_fwd_valid);
        check12("TC3 seq_err_val", 12'h006, seq_err_val);
        check12("TC3 next_expected unchanged", 12'h004, next_expected);
        idle_cycle;

        // ==================================================================
        // TC4 – CRC fail: tlp_ok=0, seq would be correct (4) but ignored
        // ==================================================================
        $display("\n--- TC4: CRC fail (tlp_ok=0), seq correct but must be ignored ---");
        send_tlp(12'h004, 1'b0 /*CRC bad*/, 1024'hABCDEF);
        check1("TC4 tlp_seq_ok",   1'b0, tlp_seq_ok);
        check1("TC4 tlp_dup",      1'b0, tlp_dup);
        check1("TC4 tlp_seq_err",  1'b0, tlp_seq_err);
        check1("TC4 nak_req",      1'b0, nak_req);
        check1("TC4 tlp_fwd_valid",1'b0, tlp_fwd_valid);
        check12("TC4 next_expected unchanged", 12'h004, next_expected);
        idle_cycle;

        // ==================================================================
        // TC5 – 12-bit wrap-around: advance to 4094, 4095, then 0
        // First get expected_seq to 4094 (need to inject 4090 good TLPs)
        // ==================================================================
        $display("\n--- TC5: 12-bit wrap-around (4094→4095→0) ---");
        // Currently expected=4; drive seq 4..4093 (4090 TLPs) without checking each
        begin : tc5_advance
            integer i;
            for (i = 4; i < 12'hFFE; i = i + 1) begin  // stop at 4094 (0xFFE)
                @(posedge clk); #1;
                seq_rx       <= i[11:0];
                tlp_rx_valid <= 1'b1;
                tlp_ok       <= 1'b1;
                tlp_clean    <= 1024'b0;
            end
            @(posedge clk); #1;
            tlp_rx_valid <= 1'b0;
        end
        // Now send 4094 (0xFFE)
        send_tlp(12'hFFE, 1'b1, 1024'h1111);
        check1("TC5 seq=4094 ok",         1'b1, tlp_seq_ok);
        check12("TC5 next_expected=4095", 12'hFFF, next_expected);
        idle_cycle;

        // Send 4095 (0xFFF)
        send_tlp(12'hFFF, 1'b1, 1024'h2222);
        check1("TC5 seq=4095 ok",        1'b1, tlp_seq_ok);
        check12("TC5 next_expected=0",   12'h000, next_expected);  // wrap!
        idle_cycle;

        // Send 0 (wrap)
        send_tlp(12'h000, 1'b1, 1024'h3333);
        check1("TC5 seq=0 (wrap) ok",    1'b1, tlp_seq_ok);
        check12("TC5 next_expected=1",   12'h001, next_expected);
        idle_cycle;

        // ==================================================================
        // TC6 – link_reset resets expected_seq to 0
        // ==================================================================
        $display("\n--- TC6: link_reset clears expected_seq ---");
        @(posedge clk); #1; link_reset <= 1'b1;
        @(posedge clk); #1; link_reset <= 1'b0;
        @(posedge clk); #1;
        check12("TC6 next_expected==0 after link_reset", 12'h000, next_expected);
        check1("TC6 tlp_seq_ok==0",   1'b0, tlp_seq_ok);
        check1("TC6 tlp_seq_err==0",  1'b0, tlp_seq_err);
        idle_cycle;

        // ==================================================================
        // TC7 – Duplicate at seq=0 (boundary: expected=1, dup=prev=0)
        // ==================================================================
        $display("\n--- TC7: Duplicate at boundary (expected=1, dup=seq=0) ---");
        // First send seq=0 to advance expected to 1
        send_tlp(12'h000, 1'b1, 1024'h4444);
        check1("TC7 good seq=0", 1'b1, tlp_seq_ok);
        idle_cycle;
        // Now send seq=0 again (duplicate)
        send_tlp(12'h000, 1'b1, 1024'hDEAD);
        check1("TC7 tlp_dup",       1'b1, tlp_dup);
        check1("TC7 seq_dup_ack",   1'b1, seq_dup_ack);
        check1("TC7 tlp_seq_ok",    1'b0, tlp_seq_ok);
        check12("TC7 expected unchanged=1", 12'h001, next_expected);
        idle_cycle;

        // ==================================================================
        // TC8 – Back-to-back good TLPs (no idle between them)
        // ==================================================================
        $display("\n--- TC8: Back-to-back good TLPs (1,2,3,4,5) ---");
        begin : tc8
            integer i;
            for (i = 1; i <= 5; i = i + 1) begin
                @(posedge clk); #1;
                seq_rx       <= i[11:0];
                tlp_rx_valid <= 1'b1;
                tlp_ok       <= 1'b1;
                tlp_clean    <= {1012'b0, i[11:0]};
            end
            @(posedge clk); #1;
            tlp_rx_valid <= 1'b0;
        end
        // After 5 back-to-back starting from 1, expected = 6
        check12("TC8 next_expected==6", 12'h006, next_expected);
        check1("TC8 last tlp_seq_ok",   1'b1, tlp_seq_ok);
        idle_cycle;

        // ==================================================================
        // TC9 – Error then recovery: inject bad seq, then resume correct
        // ==================================================================
        $display("\n--- TC9: Error then recovery ---");
        // expected=6; inject seq=9 (error)
        send_tlp(12'h009, 1'b1, 1024'hBAD2);
        check1("TC9a tlp_seq_err",  1'b1, tlp_seq_err);
        check12("TC9a expected still 6", 12'h006, next_expected);
        idle_cycle;

        // Retry from seq=6 (recovery by sender after NAK)
        send_tlp(12'h006, 1'b1, 1024'h6666);
        check1("TC9b tlp_seq_ok",   1'b1, tlp_seq_ok);
        check12("TC9b expected=7",   12'h007, next_expected);
        idle_cycle;

        // ==================================================================
        // TC10 – tlp_rx_valid=0, all outputs must stay low
        // ==================================================================
        $display("\n--- TC10: No TLP (valid=0), outputs must stay low ---");
        @(posedge clk); #1;
        seq_rx       <= 12'h007;
        tlp_rx_valid <= 1'b0;   // not valid
        tlp_ok       <= 1'b1;
        @(posedge clk); #1;
        check1("TC10 tlp_seq_ok==0",   1'b0, tlp_seq_ok);
        check1("TC10 tlp_dup==0",      1'b0, tlp_dup);
        check1("TC10 tlp_seq_err==0",  1'b0, tlp_seq_err);
        check1("TC10 tlp_fwd_valid==0",1'b0, tlp_fwd_valid);
        check12("TC10 expected unchanged", 12'h007, next_expected);
        tlp_rx_valid <= 1'b0;
        tlp_ok       <= 1'b0;
        idle_cycle;

        // ── Summary ───────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  Seq Num Checker RX TB: %0d PASS / %0d FAIL", pass_count, fail_count);
        $display("========================================\n");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    // ── Timeout watchdog ─────────────────────────────────────────────────────
    initial begin
        #500000;
        $display("[TIMEOUT] Testbench exceeded 500 us");
        $finish;
    end

endmodule
