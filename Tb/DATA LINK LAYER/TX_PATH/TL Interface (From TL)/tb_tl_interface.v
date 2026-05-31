
`timescale 1ns/1ps
module tb_tl_interface;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    task do_reset;
        begin
            rst_n = 0;
            repeat(6) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    integer pass_cnt; integer fail_cnt;
    initial begin pass_cnt = 0; fail_cnt = 0; end

    task chk;
        input [200*8-1:0] label;
        input             ok;
        begin
            if (ok) begin $display("[PASS] %0s", label); pass_cnt = pass_cnt + 1; end
            else    begin $display("[FAIL] %0s", label); fail_cnt = fail_cnt + 1; end
        end
    endtask

    reg  [1023:0] tlp_in        = 0;
    reg           tlp_valid_in  = 0;
    reg  [2047:0] flit_in       = 0;
    reg           flit_valid_in = 0;
    reg           flit_mode_en  = 0;
    reg  [7:0]    fc_update_ph  = 0;
    reg           fc_update_valid = 0;

    wire [1023:0] dll_tlp;
    wire          dll_tlp_valid;
    wire [2047:0] dll_flit;
    wire          dll_flit_valid;
    wire          tl_ready;
    wire [71:0]   fc_to_dllp;
    wire          fc_dllp_send;

    tl_interface dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_in(tlp_in),   .tlp_valid_in(tlp_valid_in),
        .flit_in(flit_in), .flit_valid_in(flit_valid_in),
        .flit_mode_en(flit_mode_en),
        .fc_update_ph(fc_update_ph),
        .fc_update_valid(fc_update_valid),
        .dll_tlp(dll_tlp),   .dll_tlp_valid(dll_tlp_valid),
        .dll_flit(dll_flit), .dll_flit_valid(dll_flit_valid),
        .tl_ready(tl_ready),
        .fc_to_dllp(fc_to_dllp),
        .fc_dllp_send(fc_dllp_send)
    );

    task send_tlp;
        input [1023:0] data;
        begin
            @(posedge clk);
            tlp_in = data; tlp_valid_in = 1;
            @(posedge clk);
            tlp_valid_in = 0;

            @(posedge dll_tlp_valid);
            @(negedge clk);
        end
    endtask

    task send_flit;
        input [2047:0] data;
        begin
            @(posedge clk);
            flit_in = data; flit_valid_in = 1;
            @(posedge clk);
            flit_valid_in = 0;
            @(posedge dll_flit_valid);
            @(negedge clk);
        end
    endtask

    task idle;
        input integer n;
        begin repeat(n) @(posedge clk); @(negedge clk); end
    endtask

    integer i;

    initial begin
        $dumpfile("tb_tl_interface.vcd");
        $dumpvars(0, tb_tl_interface);

        $display("=================================================");
        $display(" tb_tl_interface - TL/DLL Boundary Unit Tests");
        $display("=================================================");

        $display("\n[T1] Reset state");
        rst_n = 0; repeat(2) @(posedge clk); @(negedge clk);
        chk("T1a: dll_tlp_valid low during reset",   dll_tlp_valid  === 1'b0);
        chk("T1b: dll_flit_valid low during reset",   dll_flit_valid === 1'b0);
        chk("T1c: fc_dllp_send low during reset",     fc_dllp_send   === 1'b0);
        do_reset;

        $display("\n[T2] tl_ready after reset");
        @(negedge clk);
        chk("T2a: tl_ready=1 after reset", tl_ready === 1'b1);

        $display("\n[T3] TLP data integrity (Gen1-5 mode)");
        do_reset; flit_mode_en = 0;
        send_tlp(1024'hDEAD_BEEF_CAFE_0001);
        chk("T3a: dll_tlp_valid asserted",      dll_tlp_valid  === 1'b1);
        chk("T3b: dll_tlp[31:0]=0xCAFE_0001",   dll_tlp[31:0]  === 32'hCAFE_0001);
        chk("T3c: dll_tlp[63:32]=0xDEAD_BEEF",  dll_tlp[63:32] === 32'hDEAD_BEEF);
        chk("T3d: dll_flit_valid stays low",     dll_flit_valid === 1'b0);

        $display("\n[T4] TLP all-zero payload");
        do_reset; flit_mode_en = 0;
        send_tlp({1024{1'b0}});
        chk("T4a: dll_tlp_valid asserted", dll_tlp_valid === 1'b1);
        chk("T4b: dll_tlp = all-zero",     dll_tlp       === {1024{1'b0}});

        $display("\n[T5] TLP all-ones payload");
        do_reset; flit_mode_en = 0;
        send_tlp({1024{1'b1}});
        chk("T5a: dll_tlp_valid asserted", dll_tlp_valid === 1'b1);
        chk("T5b: dll_tlp = all-ones",     dll_tlp       === {1024{1'b1}});

        $display("\n[T6] TLP suppressed when flit_mode_en=1");
        do_reset; flit_mode_en = 1;
        @(posedge clk); tlp_in = 1024'hCAFE_BABE; tlp_valid_in = 1;
        @(posedge clk); tlp_valid_in = 0;
        idle(6);
        chk("T6a: dll_tlp_valid suppressed",           dll_tlp_valid  === 1'b0);
        chk("T6b: dll_flit_valid stays low (no flit)", dll_flit_valid === 1'b0);

        $display("\n[T7] FLIT pass-through (Gen6 mode)");
        do_reset; flit_mode_en = 1;
        send_flit({2048{1'b1}});
        chk("T7a: dll_flit_valid asserted",          dll_flit_valid      === 1'b1);
        chk("T7b: dll_tlp_valid stays low",          dll_tlp_valid       === 1'b0);
        chk("T7c: dll_flit top 32b = 0xFFFFFFFF",    dll_flit[2047:2016] === 32'hFFFF_FFFF);
        chk("T7d: dll_flit bottom 32b = 0xFFFFFFFF", dll_flit[31:0]      === 32'hFFFF_FFFF);

        $display("\n[T8] FLIT data integrity (pattern)");
        do_reset; flit_mode_en = 1;
        send_flit(2048'hA5A5_DEAD_BEEF_CAFE);
        chk("T8a: dll_flit_valid asserted",    dll_flit_valid === 1'b1);
        chk("T8b: dll_flit[31:0]=0xBEEF_CAFE", dll_flit[31:0] === 32'hBEEF_CAFE);

        $display("\n[T9] FLIT suppressed in TLP mode");
        do_reset; flit_mode_en = 0;
        @(posedge clk); flit_in = {2048{1'b1}}; flit_valid_in = 1;
        @(posedge clk); flit_valid_in = 0;
        idle(6);
        chk("T9a: dll_flit_valid suppressed",        dll_flit_valid === 1'b0);
        chk("T9b: dll_tlp_valid stays low (no TLP)", dll_tlp_valid  === 1'b0);

        $display("\n[T10] dll_tlp_valid is single-cycle pulse");
        do_reset; flit_mode_en = 0;
        send_tlp(1024'hABCD);

        chk("T10a: dll_tlp_valid high on pulse cycle", dll_tlp_valid === 1'b1);
        @(posedge clk); @(negedge clk);
        chk("T10b: dll_tlp_valid low next cycle",      dll_tlp_valid === 1'b0);

        $display("\n[T11] Back-to-back TLP dispatch");
        do_reset; flit_mode_en = 0;
        send_tlp(1024'h1111);
        chk("T11a: tl_ready after 1st TLP",           tl_ready      === 1'b1);
        send_tlp(1024'h2222);
        chk("T11b: dll_tlp_valid high for 2nd TLP",   dll_tlp_valid === 1'b1);
        chk("T11c: dll_tlp[31:0]=0x2222 for 2nd TLP", dll_tlp[31:0] === 32'h0000_2222);

        $display("\n[T12] Mode switch TLP->FLIT mid-stream");
        do_reset; flit_mode_en = 0;
        send_tlp(1024'hAAAA);
        flit_mode_en = 1;
        send_flit({2048{1'b0}});
        chk("T12a: dll_flit_valid after mode switch", dll_flit_valid === 1'b1);
        chk("T12b: dll_flit = all-zero",              dll_flit       === {2048{1'b0}});

        $display("\n[T13] FC update forwarding");
        do_reset;
        @(posedge clk); fc_update_ph = 8'hA5; fc_update_valid = 1;
        @(posedge fc_dllp_send); @(negedge clk);
        chk("T13a: fc_dllp_send pulsed",    fc_dllp_send    === 1'b1);
        chk("T13b: fc_to_dllp[7:0]=0xA5",  fc_to_dllp[7:0] === 8'hA5);
        fc_update_valid = 0;
        @(posedge clk); @(negedge clk);
        chk("T13c: fc_dllp_send de-asserts", fc_dllp_send   === 1'b0);

        $display("\n[T14] FC update different values");
        do_reset;
        @(posedge clk); fc_update_ph = 8'hFF; fc_update_valid = 1;
        @(posedge fc_dllp_send); @(negedge clk);
        chk("T14a: fc_to_dllp[7:0]=0xFF",  fc_to_dllp[7:0] === 8'hFF);
        fc_update_valid = 0;
        @(posedge clk);
        @(posedge clk); fc_update_ph = 8'h00; fc_update_valid = 1;
        @(posedge fc_dllp_send); @(negedge clk);
        chk("T14b: fc_to_dllp[7:0]=0x00",  fc_to_dllp[7:0] === 8'h00);
        fc_update_valid = 0;

        $display("\n[T15] FC update works in FLIT mode");
        do_reset; flit_mode_en = 1;
        @(posedge clk); fc_update_ph = 8'h3C; fc_update_valid = 1;
        @(posedge fc_dllp_send); @(negedge clk);
        chk("T15a: fc_dllp_send in FLIT mode", fc_dllp_send    === 1'b1);
        chk("T15b: fc_to_dllp[7:0]=0x3C",     fc_to_dllp[7:0] === 8'h3C);
        fc_update_valid = 0;

        $display("\n[T16] TLP dispatch concurrent with FC update");
        do_reset; flit_mode_en = 0;
        @(posedge clk);
        tlp_in = 1024'hBEEF; tlp_valid_in = 1;
        fc_update_ph = 8'h77; fc_update_valid = 1;
        @(posedge fc_dllp_send); @(negedge clk);
        chk("T16a: fc_dllp_send asserted",  fc_dllp_send    === 1'b1);
        chk("T16b: fc_to_dllp[7:0]=0x77",  fc_to_dllp[7:0] === 8'h77);
        tlp_valid_in = 0; fc_update_valid = 0;
        @(posedge dll_tlp_valid); @(negedge clk);
        chk("T16c: dll_tlp_valid asserted", dll_tlp_valid   === 1'b1);

        $display("\n[T17] Multiple resets clear outputs");
        flit_mode_en = 0;
        send_tlp(1024'hABCD_EFFF);
        do_reset; @(negedge clk);
        chk("T17a: dll_tlp_valid cleared",  dll_tlp_valid  === 1'b0);
        chk("T17b: dll_flit_valid cleared",  dll_flit_valid === 1'b0);
        chk("T17c: fc_dllp_send cleared",    fc_dllp_send   === 1'b0);
        chk("T17d: tl_ready restored",       tl_ready       === 1'b1);

        $display("\n[T18] FLIT all-zero payload");
        do_reset; flit_mode_en = 1;
        send_flit({2048{1'b0}});
        chk("T18a: dll_flit_valid asserted", dll_flit_valid === 1'b1);
        chk("T18b: dll_flit = all-zero",     dll_flit       === {2048{1'b0}});

        $display("\n[T19] Mode change does not corrupt latched data");
        do_reset; flit_mode_en = 0;
        send_tlp(1024'hDEAD_F00D);
        chk("T19a: dll_tlp[31:0]=0xDEAD_F00D", dll_tlp[31:0] === 32'hDEAD_F00D);
        flit_mode_en = 1; @(negedge clk);
        chk("T19b: dll_tlp holds after mode switch", dll_tlp[31:0] === 32'hDEAD_F00D);

        $display("\n[T20] Idle gap between TLPs");
        do_reset; flit_mode_en = 0;
        send_tlp(1024'h1234_5678);
        repeat(5) @(posedge clk);
        send_tlp(1024'hABCD_EF01);
        chk("T20a: dll_tlp_valid on 2nd TLP after idle", dll_tlp_valid === 1'b1);
        chk("T20b: dll_tlp[31:0]=0xABCD_EF01",           dll_tlp[31:0] === 32'hABCD_EF01);

        $display("");
        $display("=================================================");
        $display(" RESULTS: %0d PASSED  /  %0d FAILED", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display(" ALL TESTS PASSED");
        else               $display(" FAILURES -- inspect tb_tl_interface.vcd");
        $display("=================================================");
        $finish;
    end

    initial begin #5000000; $display("[WATCHDOG]"); $finish; end

endmodule