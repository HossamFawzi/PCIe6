// ============================================================
// Testbench: l1_fsm_tb.v
// PCIe Gen6 Physical Layer - Module 7: L1 FSM
// All signals visible on waveform (QuestaSim)
// Test Cases:
//   TC1: Reset behavior
//   TC2: L0 -> L1 normal entry and exit
//   TC3: L1.1 sub-state entry
//   TC4: L1.2 sub-state entry (deepest)
//   TC5: L1 entry timeout / error detection
//   TC6: Exit from L1.2 directly
//   TC7: Multiple L1 cycles
// ============================================================
`timescale 1ns/1ps

module l1_fsm_tb;

    // --------------------------------------------------------
    // DUT Port Connections (all reg/wire for waveform visibility)
    // --------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg         l1_req;
    reg         l1_ack;
    reg         l1_timer_exp;
    reg         pm_dllp_rx;
    reg         l1_exit_req;

    wire        send_eios;
    wire        l1_active;
    wire        l1_exit;
    wire [1:0]  pipe_power_down;
    wire        l1_timeout_err;

    // --------------------------------------------------------
    // Test tracking
    // --------------------------------------------------------
    integer     test_num;
    integer     pass_count;
    integer     fail_count;
    reg [127:0] test_name;

    // --------------------------------------------------------
    // DUT Instance
    // --------------------------------------------------------
    l1_fsm u_l1_fsm (
        .clk             (clk),
        .rst_n           (rst_n),
        .l1_req          (l1_req),
        .l1_ack          (l1_ack),
        .l1_timer_exp    (l1_timer_exp),
        .pm_dllp_rx      (pm_dllp_rx),
        .l1_exit_req     (l1_exit_req),
        .send_eios       (send_eios),
        .l1_active       (l1_active),
        .l1_exit         (l1_exit),
        .pipe_power_down (pipe_power_down),
        .l1_timeout_err  (l1_timeout_err)
    );

    // --------------------------------------------------------
    // Clock: 500MHz (2ns period) = PCIe Gen6 ref
    // --------------------------------------------------------
    initial clk = 1'b0;
    always #1 clk = ~clk;

    // --------------------------------------------------------
    // Task: apply reset
    // --------------------------------------------------------
    task apply_reset;
        begin
            rst_n        <= 1'b0;
            l1_req       <= 1'b0;
            l1_ack       <= 1'b0;
            l1_timer_exp <= 1'b0;
            pm_dllp_rx   <= 1'b0;
            l1_exit_req  <= 1'b0;
            repeat(4) @(posedge clk);
            #0.1;
            rst_n <= 1'b1;
            @(posedge clk);
            #0.1;
        end
    endtask

    // --------------------------------------------------------
    // Task: check output with pass/fail reporting
    // --------------------------------------------------------
    task check_output;
        input [127:0] signal_name;
        input         actual;
        input         expected;
        begin
            if (actual === expected) begin
                $display("[PASS] TC%0d %s: %s = %0b (expected %0b)",
                         test_num, test_name, signal_name, actual, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] TC%0d %s: %s = %0b (expected %0b) at time %0t",
                         test_num, test_name, signal_name, actual, expected, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_output2;
        input [127:0] signal_name;
        input [1:0]   actual;
        input [1:0]   expected;
        begin
            if (actual === expected) begin
                $display("[PASS] TC%0d %s: %s = %0b (expected %0b)",
                         test_num, test_name, signal_name, actual, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] TC%0d %s: %s = %0b (expected %0b) at time %0t",
                         test_num, test_name, signal_name, actual, expected, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // --------------------------------------------------------
    // Task: full L1 entry sequence (helper)
    //   Cycle-accurate per PCIe Gen6 spec:
    //   clk1: assert l1_req -> FSM moves ST_L0->ST_L1_ENTRY
    //   clk2: FSM moves ST_L1_ENTRY->ST_L1_WAIT_ACK
    //   clk3: drive pm_dllp_rx while in WAIT_ACK -> FSM moves to ST_L1_SEND_EI
    //   clk4: send_eios asserted; drive l1_timer_exp -> ST_L1
    //   clk5: l1_active=1
    // --------------------------------------------------------
    task enter_l1;
        begin
            // Cycle 1: request L1
            l1_req = 1'b1;
            @(posedge clk); #0.1;
            l1_req = 1'b0;
            // Cycle 2: FSM in ST_L1_ENTRY -> moves to WAIT_ACK next clock
            @(posedge clk); #0.1;
            // Cycle 3: now in ST_L1_WAIT_ACK; give pm_dllp_rx ack
            pm_dllp_rx = 1'b1;
            @(posedge clk); #0.1;
            pm_dllp_rx = 1'b0;
            // Cycle 4: in ST_L1_SEND_EI (send_eios=1); timer_exp to go to ST_L1
            l1_timer_exp = 1'b1;
            @(posedge clk); #0.1;
            l1_timer_exp = 1'b0;
            // Cycle 5: now in ST_L1 with l1_active=1
            @(posedge clk); #0.1;
        end
    endtask

    // --------------------------------------------------------
    // Main Simulation
    // --------------------------------------------------------
    initial begin
        $dumpfile("l1_fsm_tb.vcd");
        $dumpvars(0, l1_fsm_tb);

        pass_count = 0;
        fail_count = 0;

        $display("===================================================");
        $display("  PCIe Gen6 PHY - L1 FSM Testbench");
        $display("===================================================");

        // ==================================================
        // TC1: Reset Behavior
        // ==================================================
        test_num  = 1;
        test_name = "RESET";
        apply_reset;
        @(posedge clk); #0.1;

        check_output("l1_active",       l1_active,       1'b0);
        check_output("send_eios",       send_eios,       1'b0);
        check_output("l1_exit",         l1_exit,         1'b0);
        check_output2("pipe_power_down",pipe_power_down, 2'b00);
        check_output("l1_timeout_err",  l1_timeout_err,  1'b0);

        // ==================================================
        // TC2: Normal L1 Entry -> L1 Active -> Exit
        // ==================================================
        test_num  = 2;
        test_name = "L1_ENTRY_EXIT";
        apply_reset;

        // Step 1: Request L1 - FSM: L0->ENTRY
        l1_req = 1'b1;
        @(posedge clk); #0.1;
        l1_req = 1'b0;
        // Step 2: FSM: ENTRY->WAIT_ACK (one clock auto)
        @(posedge clk); #0.1;

        // Step 3: Now in WAIT_ACK - drive pm_dllp_rx -> FSM: WAIT_ACK->SEND_EI
        pm_dllp_rx = 1'b1;
        @(posedge clk); #0.1;
        pm_dllp_rx = 1'b0;
        @(posedge clk); #0.1;

        // Step 4: Check EIOS sent (registered in SEND_EI state)
        check_output("send_eios", send_eios, 1'b1);

        // Step 5: Timer expires -> FSM: SEND_EI->L1
        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10);

        // Step 6: Assert l1_exit_req -> FSM: L1->EXIT_EI
        l1_exit_req = 1'b1;
        @(posedge clk); #0.1;
        l1_exit_req = 1'b0;
        // Step 7: Timer -> FSM: EXIT_EI->ST_L1_EXIT; l1_exit fires NEXT clock
        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;
        // One more clock: state becomes ST_L1_EXIT, registered outputs fire
        @(posedge clk); #0.1;
        // l1_exit=1 now (state=ST_L1_EXIT), auto-transitions to ST_L0 next
        check_output("l1_exit",          l1_exit,         1'b1);
        @(posedge clk); #0.1;
        check_output("l1_active",        l1_active,       1'b0);
        check_output2("pipe_power_down", pipe_power_down, 2'b00);
        check_output("l1_exit",          l1_exit,         1'b0);

        // ==================================================
        // TC3: L1 -> L1.1 Sub-state
        // ==================================================
        test_num  = 3;
        test_name = "L1_1_SUBSTATE";
        apply_reset;
        enter_l1;

        // Confirm in L1
        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10);

        // Timer expiry from L1 -> L1.1
        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10); // L1.1 still P1

        // ==================================================
        // TC4: L1.1 -> L1.2 (deepest power down)
        // ==================================================
        test_num  = 4;
        test_name = "L1_2_SUBSTATE";
        // Continue from TC3 (already in L1.1)
        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b11); // P2 deepest

        // ==================================================
        // TC5: Timeout Error - partner never acks
        // ==================================================
        test_num  = 5;
        test_name = "L1_TIMEOUT_ERR";
        apply_reset;

        l1_req = 1'b1;
        @(posedge clk); #0.1;
        l1_req = 1'b0;
        @(posedge clk); #0.1;

        // Drive timeout counter to max (run 4096 cycles without ack)
        begin : timeout_loop
            integer i;
            for (i = 0; i < 4100; i = i + 1) begin
                @(posedge clk);
            end
        end
        #0.1;

        check_output("l1_timeout_err", l1_timeout_err, 1'b1);
        check_output("l1_active",      l1_active,      1'b0);

        // ==================================================
        // TC6: Direct exit from L1.2
        // ==================================================
        test_num  = 6;
        test_name = "L1_2_DIRECT_EXIT";
        apply_reset;
        enter_l1;

        // Go to L1.1
        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        // Go to L1.2
        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output2("pipe_power_down", pipe_power_down, 2'b11);

        // Exit from L1.2: assert exit_req, then timer through ST_L1_EXIT_EI
        l1_exit_req = 1'b1;
        @(posedge clk); #0.1;
        l1_exit_req = 1'b0;
        // Timer moves ST_L1_EXIT_EI -> ST_L1_EXIT
        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
        // Registered outputs for ST_L1_EXIT appear now
        @(posedge clk); #0.1;

        check_output("l1_exit",          l1_exit,         1'b1);
        @(posedge clk); #0.1;
        check_output("l1_active",        l1_active,       1'b0);
        check_output2("pipe_power_down", pipe_power_down, 2'b00);

        // ==================================================
        // TC7: l1_ack path (instead of pm_dllp_rx)
        // ==================================================
        test_num  = 7;
        test_name = "L1_ACK_PATH";
        apply_reset;

        l1_req = 1'b1;
        @(posedge clk); #0.1;
        l1_req = 1'b0;
        @(posedge clk); #0.1;

        // Use l1_ack instead of pm_dllp_rx
        l1_ack = 1'b1;
        @(posedge clk); #0.1;
        l1_ack = 1'b0;
        @(posedge clk); #0.1;

        check_output("send_eios", send_eios, 1'b1);

        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10);

        // ==================================================
        // TC8: Multiple L1 Cycles (stress)
        // ==================================================
        test_num  = 8;
        test_name = "MULTI_CYCLE";
        apply_reset;
        begin : multi_loop
            integer k;
            for (k = 0; k < 3; k = k + 1) begin
                enter_l1;
                check_output("l1_active", l1_active, 1'b1);

                // Exit: exit_req -> EXIT_EI, then timer -> ST_L1_EXIT (l1_exit=1)
                l1_exit_req  = 1'b1;
                @(posedge clk); #0.1;
                l1_exit_req  = 1'b0;
                l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
                @(posedge clk); #0.1;

                check_output("l1_exit",   l1_exit,   1'b1);
                @(posedge clk); #0.1;
                check_output("l1_active", l1_active, 1'b0);
            end
        end

        // ==================================================
        // Final Report
        // ==================================================
        #10;
        $display("===================================================");
        $display("  L1 FSM Test Summary: PASS=%0d  FAIL=%0d",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED - review above");
        $display("===================================================");
        $finish;
    end

    // --------------------------------------------------------
    // Timeout watchdog
    // --------------------------------------------------------
    initial begin
        #500000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
