// ============================================================
//  Testbench: fec_syndrome_calculator_tb
//  QuestaSim / ModelSim compatible (Verilog-2001)
// ============================================================
//
//  Test plan:
//    TC1 - Reset: all outputs zero
//    TC2 - All-zero FLIT+parity -> zero syndrome
//    TC3 - flit_valid=0 -> syndrome_valid=0
//    TC4 - zero_syndrome=1 confirmed for all-zero codeword
//    TC5 - Injected byte error -> non-zero syndrome, zero_syndrome=0
//    TC6 - Back-to-back valid cycles
//    TC7 - zero_syndrome de-asserts for non-zero parity region
// ============================================================

`timescale 1ns/1ps

module fec_syndrome_calculator_tb;

    // ----------------------------------------------------------
    // Clock
    // ----------------------------------------------------------
    localparam CLK_PERIOD = 10;

    reg clk;
    reg rst_n;

    // ----------------------------------------------------------
    // DUT ports
    // ----------------------------------------------------------
    reg  [2303:0] flit_rx;
    reg           flit_valid;

    wire [255:0]  syndrome;
    wire          syndrome_valid;
    wire          zero_syndrome;

    // ----------------------------------------------------------
    // Module-level variables (no declarations inside begin/end)
    // ----------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;

    // Capture registers used across tasks
    reg [255:0] got_s;
    reg         got_v;
    reg         got_z;

    // Scratch for TC6 back-to-back capture
    reg [255:0] got_s0;
    reg         got_v0;
    reg         got_z0;
    reg [255:0] got_s1;
    reg         got_v1;
    reg         got_z1;

    // Error-injection scratch
    reg [2303:0] err_flit;

    // ----------------------------------------------------------
    // DUT instance
    // ----------------------------------------------------------
    fec_syndrome_calculator dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_rx        (flit_rx),
        .flit_valid     (flit_valid),
        .syndrome       (syndrome),
        .syndrome_valid (syndrome_valid),
        .zero_syndrome  (zero_syndrome)
    );

    // ----------------------------------------------------------
    // Clock generator
    // ----------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ----------------------------------------------------------
    // Task: wait_cycle
    // ----------------------------------------------------------
    task wait_cycle;
        begin
            @(posedge clk); #1;
        end
    endtask

    // ----------------------------------------------------------
    // Task: drive_and_capture
    //   Drives flit_rx & flit_valid, waits 2 cycles, captures outputs
    //   into module-level got_s / got_v / got_z.
    // ----------------------------------------------------------
    task drive_and_capture;
        input [2303:0] flit;
        input          valid;
        begin
            @(negedge clk);
            flit_rx    = flit;
            flit_valid = valid;
            @(posedge clk); #1;    // inputs registered
            @(posedge clk); #1;    // outputs stable
            got_s = syndrome;
            got_v = syndrome_valid;
            got_z = zero_syndrome;
        end
    endtask

    // ----------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------
    initial begin
        $display("================================================");
        $display("  FEC Syndrome Calculator - Testbench Start");
        $display("================================================");

        pass_cnt   = 0;
        fail_cnt   = 0;
        flit_rx    = 2304'b0;
        flit_valid = 1'b0;
        rst_n      = 1'b0;

        // ======================================================
        // TC1: Reset
        // ======================================================
        $display("\n[TC1] Reset: all outputs must be zero");
        repeat(4) @(posedge clk); #1;
        if (syndrome       === 256'b0 &&
            syndrome_valid === 1'b0   &&
            zero_syndrome  === 1'b0) begin
            $display("  PASS  outputs zeroed in reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  syndrome=%h valid=%b zero=%b",
                     syndrome, syndrome_valid, zero_syndrome);
            fail_cnt = fail_cnt + 1;
        end

        @(negedge clk); rst_n = 1'b1;
        wait_cycle;

        // ======================================================
        // TC2: All-zero input -> zero syndrome
        // ======================================================
        $display("\n[TC2] All-zero FLIT+parity -> zero syndrome");
        drive_and_capture(2304'b0, 1'b1);
        if (got_z === 1'b1 && got_v === 1'b1 && got_s === 256'b0) begin
            $display("  PASS  zero syndrome for all-zero input");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  syndrome=%h valid=%b zero=%b",
                     got_s, got_v, got_z);
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // TC3: flit_valid=0 -> syndrome_valid=0
        // ======================================================
        $display("\n[TC3] flit_valid=0 -> syndrome_valid=0");
        drive_and_capture(2304'hDEAD, 1'b0);
        if (got_v === 1'b0) begin
            $display("  PASS  syndrome_valid de-asserted correctly");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  syndrome_valid should be 0, got %b", got_v);
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // TC4: zero_syndrome=1 confirmed for all-zero codeword
        // ======================================================
        $display("\n[TC4] zero_syndrome=1 for all-zero codeword");
        drive_and_capture(2304'b0, 1'b1);
        if (got_z === 1'b1) begin
            $display("  PASS  zero_syndrome=1 for all-zero codeword");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  zero_syndrome should be 1");
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // TC5: Injected single-byte error -> non-zero syndrome
        // ======================================================
        $display("\n[TC5] Single-byte error injection -> non-zero syndrome");
        err_flit               = 2304'b0;
        err_flit[2303:2296]    = 8'hAB;    // corrupt first byte of data region
        drive_and_capture(err_flit, 1'b1);
        if (got_z === 1'b0 && got_v === 1'b1 && got_s !== 256'b0) begin
            $display("  PASS  Non-zero syndrome detected for injected error");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  Expected non-zero syndrome");
            $display("        syndrome=%h zero=%b", got_s, got_z);
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // TC6: Back-to-back valid cycles
        // ======================================================
        $display("\n[TC6] Back-to-back valid cycles");

        // Drive word 0 (all-zero) on negedge; DUT latches on posedge1
        @(negedge clk);
        flit_rx    = 2304'b0;
        flit_valid = 1'b1;

        // posedge1: DUT latches word0; capture Cycle A output NOW before
        // inputs change (combinatorial syndrome_comb updates immediately
        // when flit_rx changes, so we must read before driving word1)
        @(posedge clk); #1;
        got_s0 = syndrome;
        got_v0 = syndrome_valid;
        got_z0 = zero_syndrome;

        // Drive word 1 (non-zero) on negedge; DUT latches on posedge2
        @(negedge clk);
        flit_rx = 2304'hFF;

        // posedge2: DUT latches word1; capture Cycle B output
        @(posedge clk); #1;
        got_s1 = syndrome;
        got_v1 = syndrome_valid;
        got_z1 = zero_syndrome;

        if (got_v0 === 1'b1 && got_z0 === 1'b1) begin
            $display("  PASS  Cycle A: all-zero word -> zero_syndrome=1");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  Cycle A: valid=%b zero=%b", got_v0, got_z0);
            fail_cnt = fail_cnt + 1;
        end

        if (got_v1 === 1'b1 && got_z1 === 1'b0) begin
            $display("  PASS  Cycle B: non-zero word -> zero_syndrome=0");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  Cycle B: valid=%b zero=%b", got_v1, got_z1);
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // TC7: Non-zero parity region only -> zero_syndrome=0
        // ======================================================
        $display("\n[TC7] Non-zero parity field only -> zero_syndrome=0");
        drive_and_capture({2048'b0, 256'h01}, 1'b1);
        if (got_z === 1'b0) begin
            $display("  PASS  zero_syndrome=0 for corrupt parity field");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  FAIL  zero_syndrome should be 0");
            fail_cnt = fail_cnt + 1;
        end

        // ======================================================
        // Summary
        // ======================================================
        @(negedge clk); flit_valid = 1'b0;
        wait_cycle;

        $display("\n================================================");
        $display("  Results: %0d PASS  |  %0d FAIL", pass_cnt, fail_cnt);
        $display("================================================");
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  *** FAILURES DETECTED ***");

        #20;
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("fec_syndrome_calculator_tb.vcd");
        $dumpvars(0, fec_syndrome_calculator_tb);
    end

endmodule
