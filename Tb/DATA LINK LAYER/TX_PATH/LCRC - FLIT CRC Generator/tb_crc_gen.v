// =============================================================================
// Testbench: tb_crc_gen  ? portable across all simulators
// Module under test: crc_gen
//
// send_tlp_get_crc task (simulator-agnostic):
//   1. Assert tlp_valid for exactly 1 clock cycle
//   2. Deassert tlp_valid at the next posedge
//   3. Sample lcrc_out at the negedge AFTER deassert
//      lcrc_out is a registered hold ? stays valid after valid drops
//   4. crc_valid is 0 at this sample point (deasserted), but lcrc_out is valid
//
// This avoids all races: we read a registered hold value, never a live
// combinational signal. Works on any IEEE 1364-2001 simulator.
//
// Self-calibration verifies hold behaviour at startup.
// =============================================================================
`timescale 1ns/1ps
module tb_crc_gen;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    task do_reset;
        begin rst_n=0; repeat(6)@(posedge clk); rst_n=1; @(posedge clk); end
    endtask

    integer pass_cnt; integer fail_cnt;
    initial begin pass_cnt=0; fail_cnt=0; end

    task chk;
        input [200*8-1:0] label;
        input ok;
        begin
            if(ok) begin $display("[PASS] %0s",label); pass_cnt=pass_cnt+1; end
            else   begin $display("[FAIL] %0s",label); fail_cnt=fail_cnt+1; end
        end
    endtask

    // ?? DUT ???????????????????????????????????????????????????????????????????
    reg  [1023:0] tlp_in=0;     reg tlp_valid=0;
    reg  [2047:0] flit_in=0;    reg flit_valid=0;
    reg           flit_mode_en=0;
    reg  [11:0]   seq_num=0;

    wire [31:0]   lcrc_out;
    wire [23:0]   flit_crc_out;
    wire          crc_valid;

    crc_gen dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_in(tlp_in),   .tlp_valid(tlp_valid),
        .flit_in(flit_in), .flit_valid(flit_valid),
        .flit_mode_en(flit_mode_en), .seq_num(seq_num),
        .lcrc_out(lcrc_out), .flit_crc_out(flit_crc_out), .crc_valid(crc_valid)
    );

    // ?? CALIBRATION ???????????????????????????????????????????????????????????
    task calibrate;
        reg [31:0] v;
        begin
            do_reset; flit_mode_en=0;
            @(posedge clk); tlp_in={1024{1'b0}}; tlp_valid=1;
            @(posedge clk); tlp_valid=0; @(negedge clk); v=lcrc_out;
            $display("[CALIBRATE] lcrc after deassert = 0x%08h (expect 0xC2A8FA9D)", v);
            if(v===32'hC2A8FA9D)
                $display("[CALIBRATE] Hold strategy OK");
            else
                $display("[CALIBRATE] WARNING: lcrc=%h unexpected", v);
            do_reset;
        end
    endtask

    // send_tlp_get_crc:
    //   Assert tlp_valid 1 cycle. Deassert. Sample lcrc_out at negedge after
    //   deassert (registered hold value). Returns with lcrc_out valid.
    task send_tlp_get_crc;
        input [1023:0] data;
        begin
            @(posedge clk); tlp_in=data; tlp_valid=1;
            @(posedge clk); tlp_valid=0;
            @(negedge clk);  // sample hold: lcrc_out valid here
            @(posedge clk);  // idle gap
        end
    endtask

    task send_flit_get_crc;
        input [2047:0] data;
        input [11:0]   snum;
        begin
            seq_num=snum;
            @(posedge clk); flit_in=data; flit_valid=1;
            @(posedge clk); flit_valid=0;
            @(negedge clk);  // flit_crc_out hold valid here
            @(posedge clk);
        end
    endtask

    reg [31:0] crc_a, crc_b, crc_c;
    reg [23:0] fcrc_a, fcrc_b;

    initial begin
        $dumpfile("tb_crc_gen.vcd");
        $dumpvars(0, tb_crc_gen);

        $display("=================================================");
        $display(" tb_crc_gen - CRC Generator Unit Tests");
        $display("=================================================");

        calibrate;

        // ?? T1: Reset state ???????????????????????????????????????????????????
        $display("\n[T1] Reset state");
        rst_n=0; repeat(2)@(posedge clk); @(negedge clk);
        chk("T1a: crc_valid=0 in reset",    crc_valid    ===1'b0);
        chk("T1b: lcrc_out=0 in reset",     lcrc_out     ===32'h0);
        chk("T1c: flit_crc_out=0 in reset", flit_crc_out ===24'h0);
        do_reset;

        // ?? T2: LCRC non-trivial for all-zero TLP ?????????????????????????????
        $display("\n[T2] LCRC for all-zero TLP");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc({1024{1'b0}});
        chk("T2a: lcrc_out != 0",  lcrc_out!==32'h0);
        $display("      lcrc(all-0) = 0x%08h", lcrc_out);

        // ?? T3: LCRC for all-ones TLP ?????????????????????????????????????????
        $display("\n[T3] LCRC for all-ones TLP");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc({1024{1'b1}});
        chk("T3a: lcrc_out != 0", lcrc_out!==32'h0);
        $display("      lcrc(all-1) = 0x%08h", lcrc_out);

        // ?? T4: Different TLPs ? different LCRCs ??????????????????????????????
        $display("\n[T4] Different TLPs produce different LCRCs");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc({1024{1'b0}}); crc_a=lcrc_out;
        do_reset; flit_mode_en=0;
        send_tlp_get_crc({1024{1'b1}}); crc_b=lcrc_out;
        chk("T4a: lcrc(all-0)!=lcrc(all-1)", crc_a!==crc_b);
        do_reset; flit_mode_en=0;
        send_tlp_get_crc(1024'hDEAD_BEEF); crc_c=lcrc_out;
        chk("T4b: lcrc(pattern)!=lcrc(all-0)", crc_c!==crc_a);
        chk("T4c: lcrc(pattern)!=lcrc(all-1)", crc_c!==crc_b);

        // ?? T5: LCRC determinism ??????????????????????????????????????????????
        $display("\n[T5] LCRC determinism");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc(1024'hCAFE_BABE_1234_5678); crc_a=lcrc_out;
        do_reset; flit_mode_en=0;
        send_tlp_get_crc(1024'hCAFE_BABE_1234_5678); crc_b=lcrc_out;
        chk("T5a: same TLP -> same LCRC", crc_a===crc_b);

        // ?? T6: lcrc_out holds after valid de-asserts ?????????????????????????
        $display("\n[T6] lcrc_out holds after tlp_valid de-asserts");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc(1024'hA5A5A5A5); crc_a=lcrc_out;
        repeat(5)@(posedge clk); @(negedge clk);
        chk("T6a: lcrc_out stable 5 cycles later", lcrc_out===crc_a);

        // ?? T7: TLP mode ignores flit_valid ???????????????????????????????????
        $display("\n[T7] TLP mode: flit_valid ignored");
        do_reset; flit_mode_en=0;
        // save current lcrc
        send_tlp_get_crc(1024'hABCD); crc_a=lcrc_out;
        // now drive flit_valid ? should not change lcrc_out
        @(posedge clk); flit_in={2048{1'b1}}; flit_valid=1;
        @(posedge clk); flit_valid=0; @(negedge clk);
        chk("T7a: lcrc_out unchanged by flit_valid", lcrc_out===crc_a);

        // ?? T8: FLIT CRC non-trivial for all-zero FLIT ????????????????????????
        $display("\n[T8] FLIT CRC for all-zero 256B FLIT");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'd0);
        chk("T8a: flit_crc_out != 0", flit_crc_out!==24'h0);
        $display("      flit_crc(all-0,seq=0) = 0x%06h", flit_crc_out);

        // ?? T9: FLIT CRC for all-ones FLIT ???????????????????????????????????
        $display("\n[T9] FLIT CRC for all-ones 256B FLIT");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b1}}, 12'd0);
        chk("T9a: flit_crc_out != 0", flit_crc_out!==24'h0);
        $display("      flit_crc(all-1,seq=0) = 0x%06h", flit_crc_out);

        // ?? T10: Different FLITs ? different CRCs ?????????????????????????????
        $display("\n[T10] Different FLITs produce different CRCs");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'd0); fcrc_a=flit_crc_out;
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b1}}, 12'd0); fcrc_b=flit_crc_out;
        chk("T10a: flit_crc(0)!=flit_crc(1)", fcrc_a!==fcrc_b);

        // ?? T11: FLIT CRC determinism ?????????????????????????????????????????
        $display("\n[T11] FLIT CRC determinism");
        do_reset; flit_mode_en=1;
        send_flit_get_crc(2048'hDEAD_BEEF_CAFE, 12'd5); fcrc_a=flit_crc_out;
        do_reset; flit_mode_en=1;
        send_flit_get_crc(2048'hDEAD_BEEF_CAFE, 12'd5); fcrc_b=flit_crc_out;
        chk("T11a: same FLIT+seq -> same CRC", fcrc_a===fcrc_b);

        // ?? T12: Different seq_num ? different CRC ????????????????????????????
        $display("\n[T12] Same FLIT, different seq_num -> different CRC");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'd0); fcrc_a=flit_crc_out;
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'd1); fcrc_b=flit_crc_out;
        chk("T12a: CRC changes with seq_num", fcrc_a!==fcrc_b);
        $display("      seq=0->0x%06h  seq=1->0x%06h", fcrc_a, fcrc_b);

        // ?? T13: FLIT mode ignores tlp_valid ??????????????????????????????????
        $display("\n[T13] FLIT mode: tlp_valid ignored");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b1}}, 12'd3); fcrc_a=flit_crc_out;
        // now drive tlp_valid ? should not change flit_crc_out
        @(posedge clk); tlp_in={1024{1'b1}}; tlp_valid=1;
        @(posedge clk); tlp_valid=0; @(negedge clk);
        chk("T13a: flit_crc_out unchanged by tlp_valid", flit_crc_out===fcrc_a);

        // ?? T14: flit_crc_out holds after de-assert ???????????????????????????
        $display("\n[T14] flit_crc_out holds after flit_valid de-asserts");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b1}}, 12'd7); fcrc_a=flit_crc_out;
        repeat(5)@(posedge clk); @(negedge clk);
        chk("T14a: flit_crc_out stable 5 cycles later", flit_crc_out===fcrc_a);

        // ?? T15: lcrc_out not clobbered by FLIT dispatch ??????????????????????
        $display("\n[T15] lcrc_out unchanged after FLIT dispatch");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc(1024'hABCD); crc_a=lcrc_out;
        flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'd0);
        chk("T15a: lcrc_out unchanged", lcrc_out===crc_a);

        // ?? T16: flit_crc_out not clobbered by TLP dispatch ???????????????????
        $display("\n[T16] flit_crc_out unchanged after TLP dispatch");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b1}}, 12'd3); fcrc_a=flit_crc_out;
        flit_mode_en=0;
        send_tlp_get_crc(1024'hDEAD);
        chk("T16a: flit_crc_out unchanged", flit_crc_out===fcrc_a);

        // ?? T17: Consecutive independent LCRCs ????????????????????????????????
        $display("\n[T17] Consecutive TLPs produce independent LCRCs");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc(1024'h1111); crc_a=lcrc_out;
        send_tlp_get_crc(1024'h2222); crc_b=lcrc_out;
        send_tlp_get_crc(1024'h3333); crc_c=lcrc_out;
        chk("T17a: crc(1111)!=crc(2222)", crc_a!==crc_b);
        chk("T17b: crc(1111)!=crc(3333)", crc_a!==crc_c);
        chk("T17c: crc(2222)!=crc(3333)", crc_b!==crc_c);

        // ?? T18: Reset clears outputs ?????????????????????????????????????????
        $display("\n[T18] Reset clears all outputs");
        flit_mode_en=0; send_tlp_get_crc(1024'hABCD_EF01);
        do_reset; @(negedge clk);
        chk("T18a: crc_valid=0 after reset",    crc_valid   ===1'b0);
        chk("T18b: lcrc_out=0 after reset",     lcrc_out    ===32'h0);
        chk("T18c: flit_crc_out=0 after reset", flit_crc_out===24'h0);

        // ?? T19: FLIT CRC with max seq_num ????????????????????????????????????
        $display("\n[T19] FLIT CRC with seq_num=4095");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'hFFF);
        chk("T19a: flit_crc_out != 0", flit_crc_out!==24'h0);
        $display("      flit_crc(all-0,seq=4095) = 0x%06h", flit_crc_out);

        // ?? T20: CRC sensitive to all seq bits ????????????????????????????????
        $display("\n[T20] FLIT CRC sensitive to all seq_num bits");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'd0);   fcrc_a=flit_crc_out;
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'hFFF); fcrc_b=flit_crc_out;
        chk("T20a: CRC(seq=0)!=CRC(seq=4095)", fcrc_a!==fcrc_b);

        // ?? T21: Known-good LCRC ??????????????????????????????????????????????
        $display("\n[T21] LCRC known-good (CRC-32/ISO-HDLC of 128 zero bytes)");
        do_reset; flit_mode_en=0;
        send_tlp_get_crc({1024{1'b0}});
        chk("T21a: lcrc(128 zeros)=0xC2A8FA9D", lcrc_out===32'hC2A8FA9D);
        $display("      got 0x%08h  expected 0xC2A8FA9D", lcrc_out);

        // ?? T22: Known-good FLIT CRC ??????????????????????????????????????????
        $display("\n[T22] FLIT CRC known-good (CRC-24/OpenPGP, 256 zero bytes, seq=0)");
        do_reset; flit_mode_en=1;
        send_flit_get_crc({2048{1'b0}}, 12'd0);
        chk("T22a: flit_crc(256 zeros,seq=0)=0xC1D636", flit_crc_out===24'hC1D636);
        $display("      got 0x%06h  expected 0xC1D636", flit_crc_out);

        // ?? SUMMARY ??????????????????????????????????????????????????????????
        $display("");
        $display("=================================================");
        $display(" RESULTS: %0d PASSED  /  %0d FAILED", pass_cnt, fail_cnt);
        if(fail_cnt==0) $display(" ALL TESTS PASSED");
        else            $display(" FAILURES -- inspect tb_crc_gen.vcd");
        $display("=================================================");
        $finish;
    end

    initial begin #2000000; $display("[WATCHDOG]"); $finish; end
endmodule