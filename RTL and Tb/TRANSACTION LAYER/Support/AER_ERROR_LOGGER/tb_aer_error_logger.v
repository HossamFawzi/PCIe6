// =============================================================
//  TESTBENCH : tb_aer_error_logger  (fixed)
//  DUT       : aer_error_logger
// =============================================================
`timescale 1ns/1ps
module tb_aer_error_logger;

    reg        clk = 0;
    always #5 clk = ~clk;

    reg        rst_n;
    reg [3:0]  err_from_tmo, err_from_cpl, dll_err;
    reg        err_from_mal, err_from_psnd, err_from_msg, err_from_flit;
    reg [1:0]  err_severity;

    wire [31:0]  aer_status, aer_mask;
    wire         aer_int, err_msg_valid;
    wire [255:0] err_msg_tlp;

    aer_error_logger dut (
        .clk(clk),.rst_n(rst_n),
        .err_from_tmo(err_from_tmo),.err_from_cpl(err_from_cpl),
        .err_from_mal(err_from_mal),.err_from_psnd(err_from_psnd),
        .err_from_msg(err_from_msg),.err_from_flit(err_from_flit),
        .dll_err(dll_err),.err_severity(err_severity),
        .aer_status(aer_status),.aer_mask(aer_mask),
        .aer_int(aer_int),.err_msg_tlp(err_msg_tlp),.err_msg_valid(err_msg_valid)
    );

    integer pass_count=0, fail_count=0;

    task chk1(input got, input exp, input [127:0] name);
        if (got===exp) begin $display("  PASS  %0s",name); pass_count=pass_count+1; end
        else begin $display("  FAIL  %0s  got=%0b exp=%0b",name,got,exp); fail_count=fail_count+1; end
    endtask
    task chk8(input [7:0] got, input [7:0] exp, input [127:0] name);
        if (got===exp) begin $display("  PASS  %0s=0x%02h",name,got); pass_count=pass_count+1; end
        else begin $display("  FAIL  %0s  got=0x%02h exp=0x%02h",name,got,exp); fail_count=fail_count+1; end
    endtask
    task chk_bits(input [31:0] got, input [31:0] mask, input [127:0] name);
        if ((got&mask)===mask) begin
            $display("  PASS  %0s (status=0x%08h)",name,got); pass_count=pass_count+1;
        end else begin
            $display("  FAIL  %0s  got=0x%08h need=0x%08h",name,got,mask); fail_count=fail_count+1;
        end
    endtask

    task do_reset;
        begin
            rst_n=0; err_from_tmo=0; err_from_cpl=0; dll_err=0;
            err_from_mal=0; err_from_psnd=0; err_from_msg=0; err_from_flit=0;
            err_severity=2'b01;
            repeat(4) @(posedge clk); rst_n=1; @(posedge clk);
        end
    endtask

    // Pulse capture regs
    reg cap_valid, cap_int;
    reg [255:0] cap_tlp;

    initial begin
        $display("=== aer_error_logger Testbench ===");

        // T1: Malformed TLP → BIT_MTLP(18), NONFATAL, aer_int
        $display("\n[T1] Malformed TLP error");
        do_reset;
        @(negedge clk); err_from_mal=1; err_severity=2'b01;
        @(posedge clk); #1;
        cap_valid=err_msg_valid; cap_int=aer_int; cap_tlp=err_msg_tlp;
        err_from_mal=0;
        @(posedge clk); #1;
        chk_bits(aer_status, 32'h0004_0000, "BIT_MTLP(18)");
        chk1(cap_valid, 1'b1, "err_msg_valid pulse");
        chk1(cap_int,   1'b1, "aer_int pulse");
        chk8(cap_tlp[231:224], 8'h31, "msg_code=0x31 NONFATAL");

        // T2: Poisoned TLP → BIT_PTLP(12), aer_int
        $display("\n[T2] Poisoned TLP error");
        do_reset;
        @(negedge clk); err_from_psnd=1;
        @(posedge clk); #1;
        cap_int=aer_int; err_from_psnd=0;
        @(posedge clk); #1;
        chk_bits(aer_status, 32'h0000_1000, "BIT_PTLP(12)");
        chk1(cap_int, 1'b1, "aer_int raised");

        // T3: DLL error → BIT_DLPE(4)
        $display("\n[T3] DLL protocol error");
        do_reset;
        @(negedge clk); dll_err=4'h1;
        @(posedge clk); #1;
        cap_int=aer_int; dll_err=4'h0;
        @(posedge clk); #1;
        chk_bits(aer_status, 32'h0000_0010, "BIT_DLPE(4)");
        chk1(cap_int, 1'b1, "aer_int for DLL err");

        // T4: Gen6 FLIT CRC → BIT_FLIT(24)
        $display("\n[T4] FLIT CRC error (Gen6) — BIT_FLIT[24]");
        do_reset;
        @(negedge clk); err_from_flit=1;
        @(posedge clk); #1;
        cap_int=aer_int; err_from_flit=0;
        @(posedge clk); #1;
        chk_bits(aer_status, 32'h0100_0000, "BIT_FLIT(24)");
        chk1(cap_int, 1'b1, "aer_int for FLIT err");

        // T5: Severity=FATAL → msg_code=0x33
        $display("\n[T5] FATAL severity → msg_code=0x33");
        do_reset;
        @(negedge clk); err_from_mal=1; err_severity=2'b10;
        @(posedge clk); #1;
        cap_valid=err_msg_valid; cap_tlp=err_msg_tlp; err_from_mal=0;
        chk8(cap_tlp[231:224], 8'h33, "msg_code=0x33 FATAL");
        chk1(cap_valid, 1'b1, "err_msg_valid");

        // T6: No errors → no interrupt
        $display("\n[T6] No errors → no interrupt");
        do_reset;
        repeat(5) @(posedge clk); #1;
        chk1(aer_int,       1'b0, "aer_int=0");
        chk1(err_msg_valid, 1'b0, "err_msg_valid=0");

        // T7: Multiple simultaneous errors
        $display("\n[T7] Multiple simultaneous errors");
        do_reset;
        @(negedge clk); err_from_mal=1; err_from_psnd=1; dll_err=4'h1;
        @(posedge clk); #1;
        cap_int=aer_int; err_from_mal=0; err_from_psnd=0; dll_err=4'h0;
        @(posedge clk); #1;
        chk_bits(aer_status, 32'h0004_1010, "MTLP+PTLP+DLPE bits");
        chk1(cap_int, 1'b1, "aer_int multi-err");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count==0) $display("ALL TESTS PASSED");
        else               $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
