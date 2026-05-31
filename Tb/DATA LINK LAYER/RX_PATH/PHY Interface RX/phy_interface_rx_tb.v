
`timescale 1ns/1ps

module phy_interface_rx_tb;

    reg          clk;
    reg          rst_n;

    reg  [255:0] phy_rxd;
    reg          phy_rx_valid;
    reg  [2:0]   phy_rx_status;
    reg  [15:0]  fec_syndrome;
    reg          fec_corrected;
    reg          ltssm_dl_up;

    wire [255:0] rx_data;
    wire         rx_valid;
    wire [2047:0]rx_flit;
    wire         rx_flit_valid;

    phy_interface_rx DUT (
        .clk           (clk),
        .rst_n         (rst_n),
        .phy_rxd       (phy_rxd),
        .phy_rx_valid  (phy_rx_valid),
        .phy_rx_status (phy_rx_status),
        .fec_syndrome  (fec_syndrome),
        .fec_corrected (fec_corrected),
        .ltssm_dl_up   (ltssm_dl_up),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .rx_flit       (rx_flit),
        .rx_flit_valid (rx_flit_valid)
    );

    initial clk = 0;
    always #0.5 clk = ~clk;

    integer test_num;
    integer pass_cnt;
    integer fail_cnt;
    integer flit_valid_edges;

    reg [2047:0] captured_flit;

    task apply_reset;
        begin
            rst_n        <= 1'b0;
            phy_rxd      <= {256{1'b0}};
            phy_rx_valid <= 1'b0;
            phy_rx_status<= 3'b000;
            fec_syndrome <= 16'h0000;
            fec_corrected<= 1'b0;
            ltssm_dl_up  <= 1'b0;
            @(posedge clk); #0.1;
            @(posedge clk); #0.1;
            rst_n        <= 1'b1;
            ltssm_dl_up  <= 1'b1;
            @(posedge clk); #0.1;
        end
    endtask

    task send_beat;
        input [255:0] data;
        begin
            phy_rxd       <= data;
            phy_rx_valid  <= 1'b1;
            phy_rx_status <= 3'b000;
            fec_syndrome  <= 16'h0000;
            fec_corrected <= 1'b0;
            @(posedge clk); #0.1;
            phy_rx_valid  <= 1'b0;
        end
    endtask

    task send_beat_ce;
        input [255:0] data;
        input [15:0]  synd;
        begin
            phy_rxd       <= data;
            phy_rx_valid  <= 1'b1;
            phy_rx_status <= 3'b000;
            fec_syndrome  <= synd;
            fec_corrected <= 1'b1;
            @(posedge clk); #0.1;
            phy_rx_valid  <= 1'b0;
            fec_corrected <= 1'b0;
            fec_syndrome  <= 16'h0000;
        end
    endtask

    task send_beat_ue;
        input [255:0] data;
        input [15:0]  synd;
        begin
            phy_rxd       <= data;
            phy_rx_valid  <= 1'b1;
            phy_rx_status <= 3'b000;
            fec_syndrome  <= synd;
            fec_corrected <= 1'b0;
            @(posedge clk); #0.1;
            phy_rx_valid  <= 1'b0;
            fec_syndrome  <= 16'h0000;
        end
    endtask

    task send_beat_bad_status;
        input [255:0] data;
        input [2:0]   status;
        begin
            phy_rxd       <= data;
            phy_rx_valid  <= 1'b1;
            phy_rx_status <= status;
            fec_syndrome  <= 16'h0000;
            fec_corrected <= 1'b0;
            @(posedge clk); #0.1;
            phy_rx_valid  <= 1'b0;
            phy_rx_status <= 3'b000;
        end
    endtask

    task send_clean_flit;
        input [7:0] seed;
        output [2047:0] expected;
        integer b;
        reg [255:0] beat_data;
        begin
            expected = {2048{1'b0}};
            for (b = 0; b < 8; b = b+1) begin
                beat_data = {32{seed ^ b[7:0]}};
                expected[(b*256)+:256] = beat_data;
                send_beat(beat_data);
            end
        end
    endtask

    task check;
        input        cond;
        input [127:0] msg;
        begin
            if (cond) begin
                $display("  PASS TC-%02d : %s", test_num, msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL TC-%02d : %s", test_num, msg);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task wait_flit_valid;
        input integer max_cycles;
        output        seen;
        integer i;
        begin
            seen = 0;

            #0.2;
            if (rx_flit_valid) begin
                seen = 1;
                captured_flit = rx_flit;
            end
            for (i = 0; i < max_cycles && !seen; i = i+1) begin
                @(posedge clk); #0.2;
                if (rx_flit_valid) begin
                    seen = 1;
                    captured_flit = rx_flit;
                end
            end
        end
    endtask

    integer         flit_seen;
    reg  [2047:0]   exp_flit;
    integer         b;
    reg  [255:0]    bdata;

    initial begin
        $dumpfile("phy_interface_rx_tb.vcd");
        $dumpvars(0, phy_interface_rx_tb);

        pass_cnt = 0;
        fail_cnt = 0;
        test_num = 0;

        $display("=============================================================");
        $display("  PCIe 6.0 PHY Interface RX — Testbench");
        $display("  PCI Express Base Spec Rev 6.0  |  PIPE Spec Rev 5.1");
        $display("=============================================================");

        test_num = 1;
        $display("\n[TC-01] Reset / idle check");
        apply_reset();

        @(posedge clk); #0.1;
        check(rx_valid      == 1'b0,    "rx_valid=0 after reset");
        check(rx_flit_valid == 1'b0,    "rx_flit_valid=0 after reset");
        check(rx_data       == {256{1'b0}}, "rx_data=0 after reset");

        test_num = 2;
        $display("\n[TC-02] Single clean flit — 8 consecutive clean beats");
        apply_reset();
        send_clean_flit(8'hAA, exp_flit);
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 1,           "rx_flit_valid asserted");
        check(captured_flit == exp_flit,"rx_flit content correct");

        test_num = 3;
        $display("\n[TC-03] Two back-to-back clean flits");
        apply_reset();

        send_clean_flit(8'h11, exp_flit);
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 1,           "Flit A: rx_flit_valid asserted");

        send_clean_flit(8'h22, exp_flit);
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 1,           "Flit B: rx_flit_valid asserted");
        check(captured_flit == exp_flit,"Flit B: rx_flit content correct");

        test_num = 4;
        $display("\n[TC-04] Correctable FEC error (CE) mid-flit → flit delivered");
        apply_reset();

        exp_flit = {2048{1'b0}};
        for (b = 0; b < 8; b = b+1) begin
            bdata = {32{8'hAB ^ b[7:0]}};
            exp_flit[(b*256)+:256] = bdata;
            if (b == 3)
                send_beat_ce(bdata, 16'h0042);
            else
                send_beat(bdata);
        end
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 1,           "CE: rx_flit_valid still asserted");
        check(captured_flit == exp_flit,"CE: rx_flit content correct");

        test_num = 5;
        $display("\n[TC-05] Uncorrectable FEC error (UE) mid-flit → flit suppressed");
        apply_reset();
        for (b = 0; b < 8; b = b+1) begin
            bdata = 256'hC001C001C001C001_C001C001C001C001_C001C001C001C001_C001C001C001C001
                    + b;
            if (b == 4)
                send_beat_ue(bdata, 16'hDEAD);
            else
                send_beat(bdata);
        end
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 0,           "UE: rx_flit_valid NOT asserted");

        test_num = 6;
        $display("\n[TC-06] phy_rx_valid stall mid-flit → resumes correctly");
        apply_reset();
        exp_flit = {2048{1'b0}};
        for (b = 0; b < 8; b = b+1) begin
            bdata = {32{8'h5A ^ b[7:0]}};
            exp_flit[(b*256)+:256] = bdata;
            if (b == 2) begin
                send_beat(bdata);

                phy_rx_valid <= 1'b0;
                @(posedge clk); @(posedge clk); @(posedge clk); #0.1;
            end else begin
                send_beat(bdata);
            end
        end
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 1,           "Stall: rx_flit_valid asserted after stall");
        check(captured_flit == exp_flit,"Stall: rx_flit content correct");

        test_num = 7;
        $display("\n[TC-07] Bad PHY RxStatus (3'b001) → beats ignored");
        apply_reset();

        for (b = 0; b < 8; b = b+1) begin
            send_beat_bad_status({256{1'b1}}, 3'b001);
        end
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 0,           "Bad status: rx_flit_valid NOT asserted");

        test_num = 8;
        $display("\n[TC-08] ltssm_dl_up de-asserted mid-flit → state flushed");
        apply_reset();

        for (b = 0; b < 4; b = b+1)
            send_beat({256{1'b1}});

        ltssm_dl_up <= 1'b0;
        @(posedge clk); #0.1;

        ltssm_dl_up <= 1'b1;
        @(posedge clk); #0.1;
        send_clean_flit(8'h55, exp_flit);
        wait_flit_valid(4, flit_seen);

        check(flit_seen == 1,           "DL_down flush: clean flit appears after recovery");
        check(captured_flit == exp_flit,"DL_down flush: correct flit content");

        test_num = 9;
        $display("\n[TC-09] UE only on last beat → flit suppressed");
        apply_reset();
        for (b = 0; b < 8; b = b+1) begin
            bdata = {32{8'hF0 ^ b[7:0]}};
            if (b == 7)
                send_beat_ue(bdata, 16'hBEEF);
            else
                send_beat(bdata);
        end
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 0,           "UE last beat: rx_flit_valid NOT asserted");

        test_num = 10;
        $display("\n[TC-10] Multiple CE errors across flit → flit still delivered");
        apply_reset();
        exp_flit = {2048{1'b0}};
        for (b = 0; b < 8; b = b+1) begin
            bdata = {32{8'hC3 ^ b[7:0]}};
            exp_flit[(b*256)+:256] = bdata;

            if (b == 1 || b == 3 || b == 5)
                send_beat_ce(bdata, 16'h0001 << b);
            else
                send_beat(bdata);
        end
        wait_flit_valid(4, flit_seen);
        check(flit_seen == 1,           "Multi-CE: rx_flit_valid asserted");
        check(captured_flit == exp_flit,"Multi-CE: rx_flit content correct");

        $display("\n=============================================================");
        $display("  Results : %0d PASS  /  %0d FAIL  (of %0d tests)",
                 pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        $display("=============================================================\n");

        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED — see FAIL lines above");

        $finish;
    end

    initial begin
        #50000;
        $display("FAIL : Watchdog timeout at %0t", $time);
        $finish;
    end

    always @(posedge clk) begin
        if (rx_flit_valid)
            $display("  [%0t] rx_flit_valid asserted — flit[255:0] = %h ...",
                     $time, rx_flit[255:0]);
        if (rx_valid)
            $display("  [%0t] rx_valid — rx_data[63:0] = %h",
                     $time, rx_data[63:0]);
    end

endmodule
