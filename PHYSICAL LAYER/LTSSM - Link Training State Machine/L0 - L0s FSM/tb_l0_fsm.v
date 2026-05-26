// ============================================================
//  Testbench ? PCIe Gen6 L0 / L0s FSM (L0_FSM)
//  Verifies:
//    TC1 ? Normal L0 (idle, no transitions)
//    TC2 ? TX side enters and exits L0s (sends EIOS then FTS)
//    TC3 ? RX side detects EIOS, receives FTS, exits L0s
//    TC4 ? recv_req in L0s forces return to L0
// ============================================================

`timescale 1ns/1ps

module tb_l0_fsm;

    // ?? DUT ports ?????????????????????????????????????????????
    reg  clk;
    reg  rst_n;
    reg  l0s_req;
    reg  fts_detected;
    reg  eios_detected;
    reg  l0s_timer_exp;
    reg  recv_req;

    wire send_fts;
    wire send_eios;
    wire l0_active;
    wire l0s_tx_active;
    wire l0s_rx_active;
    wire l0s_exit;

    // ?? Instantiate DUT ???????????????????????????????????????
    l0_fsm DUT (
        .clk          (clk),
        .rst_n        (rst_n),
        .l0s_req      (l0s_req),
        .fts_detected (fts_detected),
        .eios_detected(eios_detected),
        .l0s_timer_exp(l0s_timer_exp),
        .recv_req     (recv_req),
        .send_fts     (send_fts),
        .send_eios    (send_eios),
        .l0_active    (l0_active),
        .l0s_tx_active(l0s_tx_active),
        .l0s_rx_active(l0s_rx_active),
        .l0s_exit     (l0s_exit)
    );

    // ?? Clock: 10 ns period ???????????????????????????????????
    initial clk = 0;
    always #5 clk = ~clk;

    // ?? Helpers ???????????????????????????????????????????????
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task check(input [8*64-1:0] msg, input condition);
        begin
            if (condition) begin
                $display("[PASS] %s", msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %s  (time=%0t)", msg, $time);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task apply_reset;
        begin
            rst_n         = 0;
            l0s_req       = 0;
            fts_detected  = 0;
            eios_detected = 0;
            l0s_timer_exp = 0;
            recv_req      = 0;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task wait_clk(input integer n);
        integer i;
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC1 ? Steady L0: link idles with no L0s transitions
    // ?????????????????????????????????????????????????????????
    task tc1_l0_idle;
        begin
            $display("\n=== TC1: L0 steady state ===");
            apply_reset;

            wait_clk(5);

            check("TC1: l0_active high at reset",     l0_active     == 1'b1);
            check("TC1: l0s_tx_active low at reset",  l0s_tx_active == 1'b0);
            check("TC1: l0s_rx_active low at reset",  l0s_rx_active == 1'b0);
            check("TC1: send_eios low",               send_eios     == 1'b0);
            check("TC1: send_fts low",                send_fts      == 1'b0);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC2 ? TX side L0s entry and exit
    // ?????????????????????????????????????????????????????????
    task tc2_tx_l0s;
        integer timeout_cnt;
        begin
            $display("\n=== TC2: TX-side L0s entry and FTS exit ===");
            apply_reset;

            // Request L0s from PM FSM
            @(posedge clk); #1;
            l0s_req = 1;
            @(posedge clk); #1;
            l0s_req = 0;

            // In ST_L0S_TX_ENTRY ? send_eios should be asserted
            // Registered output takes 2 cycles after state transition
            wait_clk(2);
            check("TC2: send_eios in TX_ENTRY",       send_eios == 1'b1);
            check("TC2: l0_active drops in TX_ENTRY", l0_active == 1'b0);

            // Timer expires ? advance to ST_L0S_TX
            @(posedge clk); #1;
            l0s_timer_exp = 1;
            @(posedge clk); #1;
            l0s_timer_exp = 0;

            wait_clk(2);
            check("TC2: l0s_tx_active asserted in ST_L0S_TX", l0s_tx_active == 1'b1);

            // Second timer expiry ? exit L0s (send FTS burst)
            @(posedge clk); #1;
            l0s_timer_exp = 1;
            @(posedge clk); #1;
            l0s_timer_exp = 0;

            wait_clk(2);
            check("TC2: send_fts in TX_EXIT", send_fts == 1'b1);

            // Third timer expiry ? exit done
            @(posedge clk); #1;
            l0s_timer_exp = 1;
            @(posedge clk); #1;
            l0s_timer_exp = 0;

            timeout_cnt = 0;
            while (!l0s_exit && timeout_cnt < 10) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            check("TC2: l0s_exit pulsed",         l0s_exit == 1'b1);
            @(posedge clk);
            check("TC2: l0_active restored",       l0_active == 1'b1);
            check("TC2: l0s_tx_active cleared",    l0s_tx_active == 1'b0);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC3 ? RX side: partner sends EIOS then FTS
    // ?????????????????????????????????????????????????????????
    task tc3_rx_l0s;
        integer timeout_cnt;
        reg     saw_exit;
        begin
            $display("\n=== TC3: RX-side L0s (EIOS received then FTS exit) ===");
            apply_reset;
            saw_exit = 0;

            wait_clk(2);

            // Partner sends EIOS ? RX detects it
            @(posedge clk); #1;
            eios_detected = 1;
            @(posedge clk); #1;
            eios_detected = 0;

            wait_clk(2);
            check("TC3: l0s_rx_active after EIOS",    l0s_rx_active == 1'b1);
            check("TC3: l0_active drops after EIOS",  l0_active == 1'b0);

            // Partner sends 4 FTS pulses so fts_rx_cnt surpasses FTS_REQUIRED(2)
            repeat(4) begin
                @(posedge clk); #1;
                fts_detected = 1;
                @(posedge clk); #1;
                fts_detected = 0;
            end

            // Poll every posedge so we never miss the single-cycle l0s_exit pulse
            timeout_cnt = 0;
            while (timeout_cnt < 20) begin
                @(posedge clk);
                if (l0s_exit) saw_exit = 1;
                timeout_cnt = timeout_cnt + 1;
            end

            check("TC3: l0s_exit pulsed after FTS",   saw_exit == 1'b1);
            check("TC3: l0_active restored",           l0_active == 1'b1);
            check("TC3: l0s_rx_active cleared",        l0s_rx_active == 1'b0);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  TC4 ? recv_req while in TX L0s forces back to L0
    // ?????????????????????????????????????????????????????????
    task tc4_recv_req_in_l0s;
        begin
            $display("\n=== TC4: recv_req forces exit from TX L0s ===");
            apply_reset;

            // Enter L0s TX
            @(posedge clk); #1;
            l0s_req = 1;
            @(posedge clk); #1;
            l0s_req = 0;

            l0s_timer_exp = 1;
            @(posedge clk); #1;
            l0s_timer_exp = 0;

            wait_clk(2);
            check("TC4: in L0s_TX", l0s_tx_active == 1'b1);

            // Error forces Recovery ? l0_fsm should drop back to L0
            @(posedge clk); #1;
            recv_req = 1;
            @(posedge clk); #1;
            recv_req = 0;

            wait_clk(2);
            check("TC4: l0_active restored after recv_req", l0_active == 1'b1);
            check("TC4: l0s_tx_active cleared",            l0s_tx_active == 1'b0);
        end
    endtask

    // ?????????????????????????????????????????????????????????
    //  Top-level stimulus
    // ?????????????????????????????????????????????????????????
    initial begin
        $dumpfile("l0_fsm.vcd");
        $dumpvars(0, tb_l0_fsm);

        tc1_l0_idle;
        tc2_tx_l0s;
        tc3_rx_l0s;
        tc4_recv_req_in_l0s;

        $display("\n========================================");
        $display(" RESULTS: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("========================================\n");

        if (fail_cnt == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED ? review waveform");

        $finish;
    end

endmodule
