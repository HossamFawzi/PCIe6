
`timescale 1ns/1ps

module lb_fsm_tb;

    reg         clk;
    reg         rst_n;
    reg         lb_req;
    reg         lb_master;
    reg         ts1_lb_bit;
    reg         lb_timer_exp;

    wire        lb_active;
    wire        send_ts1_lb;
    wire        lb_data_en;
    wire        lb_exit;

    integer     test_num;
    integer     pass_count;
    integer     fail_count;
    reg [127:0] test_name;

    lb_fsm u_lb_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .lb_req      (lb_req),
        .lb_master   (lb_master),
        .ts1_lb_bit  (ts1_lb_bit),
        .lb_timer_exp(lb_timer_exp),
        .lb_active   (lb_active),
        .send_ts1_lb (send_ts1_lb),
        .lb_data_en  (lb_data_en),
        .lb_exit     (lb_exit)
    );

    initial clk = 1'b0;
    always #1 clk = ~clk;

    task apply_reset;
        begin
            rst_n        <= 1'b0;
            lb_req       <= 1'b0;
            lb_master    <= 1'b0;
            ts1_lb_bit   <= 1'b0;
            lb_timer_exp <= 1'b0;
            repeat(4) @(posedge clk); #0.1;
            rst_n <= 1'b1;
            @(posedge clk); #0.1;
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

    task master_enter_loopback;
        begin
            lb_master    = 1'b1;
            lb_req       = 1'b1;
            @(posedge clk); #0.1;
            lb_req       = 1'b0;
            @(posedge clk); #0.1;
            check_output("send_ts1_lb_entry", send_ts1_lb, 1'b1);
            lb_timer_exp = 1'b1;
            @(posedge clk); #0.1;
            lb_timer_exp = 1'b0;
            @(posedge clk); #0.1;
            ts1_lb_bit   = 1'b1;
            @(posedge clk); #0.1;
            @(posedge clk); #0.1;
            ts1_lb_bit   = 1'b0;
            @(posedge clk); #0.1;
            @(posedge clk); #0.1;
        end
    endtask

    initial begin
        $dumpfile("lb_fsm_tb.vcd");
        $dumpvars(0, lb_fsm_tb);

        pass_count = 0;
        fail_count = 0;

        $display("===================================================");
        $display("  PCIe Gen6 PHY - Loopback FSM Testbench");
        $display("===================================================");

        test_num  = 1;
        test_name = "RESET";
        apply_reset;
        @(posedge clk); #0.1;
        check_output("lb_active",   lb_active,   1'b0);
        check_output("send_ts1_lb", send_ts1_lb, 1'b0);
        check_output("lb_data_en",  lb_data_en,  1'b0);
        check_output("lb_exit",     lb_exit,     1'b0);

        test_num  = 2;
        test_name = "MASTER_ENTRY";
        apply_reset;
        master_enter_loopback;
        check_output("lb_active",   lb_active,   1'b1);
        check_output("lb_data_en",  lb_data_en,  1'b0);
        check_output("send_ts1_lb", send_ts1_lb, 1'b0);

        test_num  = 3;
        test_name = "SLAVE_ENTRY";
        apply_reset;
        lb_master  = 1'b0;
        lb_req     = 1'b1;
        @(posedge clk); #0.1;
        lb_req     = 1'b0;
        @(posedge clk); #0.1;
        check_output("send_ts1_lb", send_ts1_lb, 1'b1);
        ts1_lb_bit = 1'b1;
        @(posedge clk); #0.1;
        ts1_lb_bit = 1'b0;
        @(posedge clk); #0.1;
        check_output("lb_active",  lb_active,  1'b1);
        check_output("lb_data_en", lb_data_en, 1'b1);

        test_num  = 4;
        test_name = "MASTER_EXIT";
        apply_reset;
        master_enter_loopback;
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        check_output("send_ts1_lb", send_ts1_lb, 1'b0);
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);
        @(posedge clk); #0.1;
        check_output("lb_exit",   lb_exit,   1'b0);

        test_num  = 5;
        test_name = "SLAVE_EXIT_TS1";
        apply_reset;
        lb_master  = 1'b0;
        lb_req     = 1'b1;
        @(posedge clk); #0.1;
        lb_req     = 1'b0;
        @(posedge clk); #0.1;
        ts1_lb_bit = 1'b1;
        @(posedge clk); #0.1;
        ts1_lb_bit = 1'b0;
        @(posedge clk); #0.1;
        check_output("lb_active",  lb_active,  1'b1);
        check_output("lb_data_en", lb_data_en, 1'b1);

        @(posedge clk); #0.1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);

        test_num  = 6;
        test_name = "MASTER_TIMEOUT";
        apply_reset;
        lb_master    = 1'b1;
        lb_req       = 1'b1;
        @(posedge clk); #0.1;
        lb_req       = 1'b0;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);
        @(posedge clk); #0.1;
        check_output("lb_exit",   lb_exit,   1'b0);

        test_num  = 7;
        test_name = "SLAVE_TIMER_EXIT";
        apply_reset;
        lb_master  = 1'b0;
        lb_req     = 1'b1;
        @(posedge clk); #0.1;
        lb_req     = 1'b0;
        @(posedge clk); #0.1;
        ts1_lb_bit = 1'b1;
        @(posedge clk); #0.1;
        ts1_lb_bit = 1'b0;
        @(posedge clk); #0.1;
        check_output("lb_active", lb_active, 1'b1);

        @(posedge clk); #0.1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);

        test_num  = 8;
        test_name = "MULTI_MASTER";
        apply_reset;
        begin : multi_lb_loop
            integer k;
            for (k = 0; k < 3; k = k + 1) begin
                master_enter_loopback;
                check_output("lb_active",   lb_active,   1'b1);
                check_output("send_ts1_lb", send_ts1_lb, 1'b0);
                lb_timer_exp = 1'b1;
                @(posedge clk); #0.1;
                lb_timer_exp = 1'b0;
                lb_timer_exp = 1'b1;
                @(posedge clk); #0.1;
                lb_timer_exp = 1'b0;
                @(posedge clk); #0.1;
                check_output("lb_exit",   lb_exit,   1'b1);
                @(posedge clk); #0.1;
                check_output("lb_active", lb_active, 1'b0);
                check_output("lb_exit",   lb_exit,   1'b0);
            end
        end

        #10;
        $display("===================================================");
        $display("  LB FSM Test Summary: PASS=%0d  FAIL=%0d",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED - review above");
        $display("===================================================");
        $finish;
    end

    initial begin
        #200000;
        $display("[ERROR] Simulation timeout!");
        $finish;
    end

endmodule
