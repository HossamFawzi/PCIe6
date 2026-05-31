
`timescale 1ns/1ps
module tb_dll_err;

    reg  clk, rst_n;
    reg  replay_rollover_err, dllp_crc_err, dllp_mal_err;
    reg  lcrc_err, flit_uncorr_err, lfsr_sync_err;
    wire [5:0] dll_err_to_aer;
    wire       dll_err_valid;
    wire [3:0] dll_err_type;
    wire [1:0] dll_err_severity;

    integer pass_count = 0;
    integer fail_count = 0;

    localparam ERR_NONE            = 4'd0;
    localparam ERR_REPLAY_ROLLOVER = 4'd1;
    localparam ERR_DLLP_CRC        = 4'd2;
    localparam ERR_DLLP_MAL        = 4'd3;
    localparam ERR_LCRC            = 4'd4;
    localparam ERR_FLIT_UNCORR     = 4'd5;
    localparam ERR_LFSR_SYNC       = 4'd6;
    localparam SEV_COR      = 2'd0;
    localparam SEV_NONFATAL = 2'd1;
    localparam SEV_FATAL    = 2'd2;

    dll_err dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .replay_rollover_err(replay_rollover_err),
        .dllp_crc_err      (dllp_crc_err),
        .dllp_mal_err      (dllp_mal_err),
        .lcrc_err          (lcrc_err),
        .flit_uncorr_err   (flit_uncorr_err),
        .lfsr_sync_err     (lfsr_sync_err),
        .dll_err_to_aer    (dll_err_to_aer),
        .dll_err_valid     (dll_err_valid),
        .dll_err_type      (dll_err_type),
        .dll_err_severity  (dll_err_severity)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check1(input exp, input got, input [127:0] name);
        if (exp === got) begin
            $display("  PASS | %s", name);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL | %s | exp=%b got=%b", name, exp, got);
            fail_count = fail_count + 1;
        end
    endtask

    task check4(input [3:0] exp, input [3:0] got, input [127:0] name);
        if (exp === got) begin
            $display("  PASS | %s | val=%0d", name, got);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL | %s | exp=%0d got=%0d", name, exp, got);
            fail_count = fail_count + 1;
        end
    endtask

    task check2(input [1:0] exp, input [1:0] got, input [127:0] name);
        if (exp === got) begin
            $display("  PASS | %s | val=%0d", name, got);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL | %s | exp=%0d got=%0d", name, exp, got);
            fail_count = fail_count + 1;
        end
    endtask

    task clear_errors;
      begin
        replay_rollover_err = 0; dllp_crc_err = 0; dllp_mal_err = 0;
        lcrc_err = 0; flit_uncorr_err = 0; lfsr_sync_err = 0;
      end
    endtask

    task apply_reset;
      begin
        rst_n = 0; clear_errors;
        repeat(2) @(posedge clk); rst_n = 1; @(posedge clk);
      end
    endtask

    initial begin
        $display("=== TB: dll_err ===");

        $display("[TC1] Reset: no errors");
        apply_reset;
        @(posedge clk);
        check1(0, dll_err_valid, "dll_err_valid=0");
        check4(ERR_NONE, dll_err_type, "dll_err_type=NONE");

        $display("[TC2] replay_rollover_err -> FATAL");
        apply_reset;
        replay_rollover_err = 1; @(posedge clk); @(posedge clk);
        check1(1, dll_err_valid,          "dll_err_valid=1");
        check1(1, dll_err_to_aer[0],      "aer bit[0]=1 (replay_rollover)");
        check4(ERR_REPLAY_ROLLOVER, dll_err_type, "type=REPLAY_ROLLOVER");
        check2(SEV_FATAL, dll_err_severity, "severity=FATAL");
        replay_rollover_err = 0;

        $display("[TC3] dllp_crc_err -> COR");
        apply_reset;
        dllp_crc_err = 1; @(posedge clk); @(posedge clk);
        check1(1, dll_err_valid,      "dll_err_valid=1");
        check1(1, dll_err_to_aer[1],  "aer bit[1]=1 (dllp_crc)");
        check4(ERR_DLLP_CRC, dll_err_type, "type=DLLP_CRC");
        check2(SEV_COR, dll_err_severity,  "severity=COR");
        dllp_crc_err = 0;

        $display("[TC4] dllp_mal_err -> NONFATAL");
        apply_reset;
        dllp_mal_err = 1; @(posedge clk); @(posedge clk);
        check1(1, dll_err_to_aer[2],       "aer bit[2]=1 (dllp_mal)");
        check4(ERR_DLLP_MAL, dll_err_type, "type=DLLP_MAL");
        check2(SEV_NONFATAL, dll_err_severity, "severity=NONFATAL");
        dllp_mal_err = 0;

        $display("[TC5] lcrc_err -> NONFATAL");
        apply_reset;
        lcrc_err = 1; @(posedge clk); @(posedge clk);
        check1(1, dll_err_to_aer[3],    "aer bit[3]=1 (lcrc)");
        check4(ERR_LCRC, dll_err_type,  "type=LCRC");
        check2(SEV_NONFATAL, dll_err_severity, "severity=NONFATAL");
        lcrc_err = 0;

        $display("[TC6] flit_uncorr_err -> FATAL");
        apply_reset;
        flit_uncorr_err = 1; @(posedge clk); @(posedge clk);
        check1(1, dll_err_to_aer[4],          "aer bit[4]=1 (flit_uncorr)");
        check4(ERR_FLIT_UNCORR, dll_err_type, "type=FLIT_UNCORR");
        check2(SEV_FATAL, dll_err_severity,   "severity=FATAL");
        flit_uncorr_err = 0;

        $display("[TC7] lfsr_sync_err -> FATAL");
        apply_reset;
        lfsr_sync_err = 1; @(posedge clk); @(posedge clk);
        check1(1, dll_err_to_aer[5],         "aer bit[5]=1 (lfsr_sync)");
        check4(ERR_LFSR_SYNC, dll_err_type,  "type=LFSR_SYNC");
        check2(SEV_FATAL, dll_err_severity,  "severity=FATAL");
        lfsr_sync_err = 0;

        $display("[TC8] Priority: replay_rollover wins over dllp_crc");
        apply_reset;
        replay_rollover_err = 1; dllp_crc_err = 1;
        @(posedge clk); @(posedge clk);
        check4(ERR_REPLAY_ROLLOVER, dll_err_type, "replay_rollover has priority");
        check2(SEV_FATAL, dll_err_severity,       "severity=FATAL with priority err");
        replay_rollover_err = 0; dllp_crc_err = 0;

        $display("[TC9] No error -> dll_err_valid=0");
        apply_reset;
        @(posedge clk); @(posedge clk);
        check1(0, dll_err_valid, "dll_err_valid=0 when no errors");

        $display("=== dll_err: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #3000 begin $display("TIMEOUT"); $finish; end
endmodule
