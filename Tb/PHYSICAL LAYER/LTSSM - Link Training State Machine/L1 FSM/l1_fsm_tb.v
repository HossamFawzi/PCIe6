
`timescale 1ns/1ps

module l1_fsm_tb;

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

    integer     test_num;
    integer     pass_count;
    integer     fail_count;
    reg [127:0] test_name;

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

    initial clk = 1'b0;
    always #1 clk = ~clk;

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

    task enter_l1;
        begin

            l1_req = 1'b1;
            @(posedge clk); #0.1;
            l1_req = 1'b0;

            @(posedge clk); #0.1;

            pm_dllp_rx = 1'b1;
            @(posedge clk); #0.1;
            pm_dllp_rx = 1'b0;

            l1_timer_exp = 1'b1;
            @(posedge clk); #0.1;
            l1_timer_exp = 1'b0;

            @(posedge clk); #0.1;
        end
    endtask

    initial begin
        $dumpfile("l1_fsm_tb.vcd");
        $dumpvars(0, l1_fsm_tb);

        pass_count = 0;
        fail_count = 0;

        $display("===================================================");
        $display("  PCIe Gen6 PHY - L1 FSM Testbench");
        $display("===================================================");

        test_num  = 1;
        test_name = "RESET";
        apply_reset;
        @(posedge clk); #0.1;

        check_output("l1_active",       l1_active,       1'b0);
        check_output("send_eios",       send_eios,       1'b0);
        check_output("l1_exit",         l1_exit,         1'b0);
        check_output2("pipe_power_down",pipe_power_down, 2'b00);
        check_output("l1_timeout_err",  l1_timeout_err,  1'b0);

        test_num  = 2;
        test_name = "L1_ENTRY_EXIT";
        apply_reset;

        l1_req = 1'b1;
        @(posedge clk); #0.1;
        l1_req = 1'b0;

        @(posedge clk); #0.1;

        pm_dllp_rx = 1'b1;
        @(posedge clk); #0.1;
        pm_dllp_rx = 1'b0;
        @(posedge clk); #0.1;

        check_output("send_eios", send_eios, 1'b1);

        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10);

        l1_exit_req = 1'b1;
        @(posedge clk); #0.1;
        l1_exit_req = 1'b0;

        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;

        @(posedge clk); #0.1;

        check_output("l1_exit",          l1_exit,         1'b1);
        @(posedge clk); #0.1;
        check_output("l1_active",        l1_active,       1'b0);
        check_output2("pipe_power_down", pipe_power_down, 2'b00);
        check_output("l1_exit",          l1_exit,         1'b0);

        test_num  = 3;
        test_name = "L1_1_SUBSTATE";
        apply_reset;
        enter_l1;

        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10);

        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10);

        test_num  = 4;
        test_name = "L1_2_SUBSTATE";

        l1_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b11);

        test_num  = 5;
        test_name = "L1_TIMEOUT_ERR";
        apply_reset;

        l1_req = 1'b1;
        @(posedge clk); #0.1;
        l1_req = 1'b0;
        @(posedge clk); #0.1;

        begin : timeout_loop
            integer i;
            for (i = 0; i < 4100; i = i + 1) begin
                @(posedge clk);
            end
        end
        #0.1;

        check_output("l1_timeout_err", l1_timeout_err, 1'b1);
        check_output("l1_active",      l1_active,      1'b0);

        test_num  = 6;
        test_name = "L1_2_DIRECT_EXIT";
        apply_reset;
        enter_l1;

        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output2("pipe_power_down", pipe_power_down, 2'b11);

        l1_exit_req = 1'b1;
        @(posedge clk); #0.1;
        l1_exit_req = 1'b0;

        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;

        @(posedge clk); #0.1;

        check_output("l1_exit",          l1_exit,         1'b1);
        @(posedge clk); #0.1;
        check_output("l1_active",        l1_active,       1'b0);
        check_output2("pipe_power_down", pipe_power_down, 2'b00);

        test_num  = 7;
        test_name = "L1_ACK_PATH";
        apply_reset;

        l1_req = 1'b1;
        @(posedge clk); #0.1;
        l1_req = 1'b0;
        @(posedge clk); #0.1;

        l1_ack = 1'b1;
        @(posedge clk); #0.1;
        l1_ack = 1'b0;
        @(posedge clk); #0.1;

        check_output("send_eios", send_eios, 1'b1);

        l1_timer_exp = 1'b1; @(posedge clk); #0.1; l1_timer_exp = 1'b0;
        @(posedge clk); #0.1;

        check_output("l1_active",        l1_active,       1'b1);
        check_output2("pipe_power_down", pipe_power_down, 2'b10);

        test_num  = 8;
        test_name = "MULTI_CYCLE";
        apply_reset;
        begin : multi_loop
            integer k;
            for (k = 0; k < 3; k = k + 1) begin
                enter_l1;
                check_output("l1_active", l1_active, 1'b1);

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

    initial begin
        #500000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
