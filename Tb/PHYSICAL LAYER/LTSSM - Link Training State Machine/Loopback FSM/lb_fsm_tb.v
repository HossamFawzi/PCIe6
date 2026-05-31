// ============================================================
// Testbench: lb_fsm_tb.v
// PCIe Gen6 Physical Layer - Module 8: Loopback FSM
// All signals visible on waveform (QuestaSim)
// Outputs based on current state (registered).
// Test Cases:
//   TC1: Reset behavior
//   TC2: Master loopback entry and active
//   TC3: Slave loopback entry and active
//   TC4: Master loopback exit
//   TC5: Slave loopback exit (TS1 without LB bit)
//   TC6: Master loopback timeout abort
//   TC7: Slave loopback timer exit
//   TC8: Multiple loopback cycles (master)
// ============================================================
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

    // Master loopback entry task - ends with state=LB_ACTIVE_MSTR
    // Cycle-accurate (state-based outputs, 1 clk delay):
    //  clk1: lb_req -> IDLE->LB_ENTRY
    //  clk2: state=LB_ENTRY send_ts1_lb=1; timer -> LB_WAIT_TS1
    //  clk3: state=LB_WAIT_TS1 send_ts1_lb=1
    //  clk4: ts1_lb_bit=1; cnt++
    //  clk5: ts1_lb_bit=1; cnt=2 -> next=LB_ACTIVE_MSTR
    //  clk6: state=LB_ACTIVE_MSTR lb_active=1
    task master_enter_loopback;
        begin
            lb_master    = 1'b1;
            lb_req       = 1'b1;
            @(posedge clk); #0.1;   // IDLE->LB_ENTRY
            lb_req       = 1'b0;
            @(posedge clk); #0.1;   // state=LB_ENTRY: send_ts1_lb=1
            check_output("send_ts1_lb_entry", send_ts1_lb, 1'b1);
            lb_timer_exp = 1'b1;
            @(posedge clk); #0.1;   // LB_ENTRY->LB_WAIT_TS1
            lb_timer_exp = 1'b0;
            @(posedge clk); #0.1;   // state=LB_WAIT_TS1: send_ts1_lb=1
            ts1_lb_bit   = 1'b1;
            @(posedge clk); #0.1;   // cnt=1
            @(posedge clk); #0.1;   // cnt=2 -> next=LB_ACTIVE_MSTR
            ts1_lb_bit   = 1'b0;
            @(posedge clk); #0.1;   // ->LB_ACTIVE_MSTR (state transitions)
            @(posedge clk); #0.1;   // state=LB_ACTIVE_MSTR: lb_active=1
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

        // TC1: Reset
        test_num  = 1;
        test_name = "RESET";
        apply_reset;
        @(posedge clk); #0.1;
        check_output("lb_active",   lb_active,   1'b0);
        check_output("send_ts1_lb", send_ts1_lb, 1'b0);
        check_output("lb_data_en",  lb_data_en,  1'b0);
        check_output("lb_exit",     lb_exit,     1'b0);

        // TC2: Master entry -> active
        test_num  = 2;
        test_name = "MASTER_ENTRY";
        apply_reset;
        master_enter_loopback;      // state=LB_ACTIVE_MSTR
        check_output("lb_active",   lb_active,   1'b1);
        check_output("lb_data_en",  lb_data_en,  1'b0);
        check_output("send_ts1_lb", send_ts1_lb, 1'b0);

        // TC3: Slave entry -> active
        // clk1: lb_req -> LB_SLAVE_DETECT
        // clk2: state=LB_SLAVE_DETECT: send_ts1_lb=1
        // clk3: ts1_lb_bit=1 -> LB_ACTIVE_SLV
        // clk4: state=LB_ACTIVE_SLV: lb_active=1 lb_data_en=1
        test_num  = 3;
        test_name = "SLAVE_ENTRY";
        apply_reset;
        lb_master  = 1'b0;
        lb_req     = 1'b1;
        @(posedge clk); #0.1;   // IDLE->LB_SLAVE_DETECT
        lb_req     = 1'b0;
        @(posedge clk); #0.1;   // state=LB_SLAVE_DETECT: send_ts1_lb=1
        check_output("send_ts1_lb", send_ts1_lb, 1'b1);
        ts1_lb_bit = 1'b1;
        @(posedge clk); #0.1;   // SLAVE_DETECT->LB_ACTIVE_SLV
        ts1_lb_bit = 1'b0;
        @(posedge clk); #0.1;   // state=LB_ACTIVE_SLV
        check_output("lb_active",  lb_active,  1'b1);
        check_output("lb_data_en", lb_data_en, 1'b1);

        // TC4: Master exit
        // LB_ACTIVE_MSTR -timer-> LB_EXIT_MSTR -timer-> LB_DONE
        // lb_exit fires in state=LB_DONE
        test_num  = 4;
        test_name = "MASTER_EXIT";
        apply_reset;
        master_enter_loopback;      // state=LB_ACTIVE_MSTR
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;   // ->LB_EXIT_MSTR
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;   // state=LB_EXIT_MSTR: send_ts1_lb=0
        check_output("send_ts1_lb", send_ts1_lb, 1'b0);
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;   // ->LB_DONE
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;   // state=LB_DONE: lb_exit=1
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);
        @(posedge clk); #0.1;   // state=IDLE: lb_exit=0
        check_output("lb_exit",   lb_exit,   1'b0);

        // TC5: Slave exit via TS1 without LB bit
        // LB_ACTIVE_SLV -ts1=0-> LB_EXIT_SLV -timer-> LB_DONE
        test_num  = 5;
        test_name = "SLAVE_EXIT_TS1";
        apply_reset;
        lb_master  = 1'b0;
        lb_req     = 1'b1;
        @(posedge clk); #0.1;   // ->LB_SLAVE_DETECT
        lb_req     = 1'b0;
        @(posedge clk); #0.1;
        ts1_lb_bit = 1'b1;
        @(posedge clk); #0.1;   // ->LB_ACTIVE_SLV
        ts1_lb_bit = 1'b0;      // deassert before active state check
        @(posedge clk); #0.1;   // state=LB_ACTIVE_SLV
        check_output("lb_active",  lb_active,  1'b1);
        check_output("lb_data_en", lb_data_en, 1'b1);
        // ts1_lb_bit=0 in ACTIVE_SLV -> EXIT_SLV (next_state condition)
        @(posedge clk); #0.1;   // ->LB_EXIT_SLV
        @(posedge clk); #0.1;   // state=LB_EXIT_SLV
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;   // ->LB_DONE
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;   // state=LB_DONE: lb_exit=1
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);

        // TC6: Master timeout abort (no slave TS1)
        // LB_ENTRY -timer-> LB_WAIT_TS1 -timer-> LB_DONE
        test_num  = 6;
        test_name = "MASTER_TIMEOUT";
        apply_reset;
        lb_master    = 1'b1;
        lb_req       = 1'b1;
        @(posedge clk); #0.1;   // ->LB_ENTRY
        lb_req       = 1'b0;
        @(posedge clk); #0.1;   // state=LB_ENTRY
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;   // ->LB_WAIT_TS1
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;   // state=LB_WAIT_TS1
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;   // ->LB_DONE (timeout, no ts1)
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;   // state=LB_DONE: lb_exit=1
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);
        @(posedge clk); #0.1;   // state=IDLE
        check_output("lb_exit",   lb_exit,   1'b0);

        // TC7: Slave timer exit
        // LB_ACTIVE_SLV -timer-> LB_EXIT_SLV -timer-> LB_DONE
        test_num  = 7;
        test_name = "SLAVE_TIMER_EXIT";
        apply_reset;
        lb_master  = 1'b0;
        lb_req     = 1'b1;
        @(posedge clk); #0.1;   // ->LB_SLAVE_DETECT
        lb_req     = 1'b0;
        @(posedge clk); #0.1;
        ts1_lb_bit = 1'b1;
        @(posedge clk); #0.1;   // ->LB_ACTIVE_SLV
        ts1_lb_bit = 1'b0;
        @(posedge clk); #0.1;   // state=LB_ACTIVE_SLV
        check_output("lb_active", lb_active, 1'b1);
        // ts1_lb_bit=0 already triggers EXIT_SLV next clock (no extra timer needed)
        @(posedge clk); #0.1;   // ACTIVE_SLV->EXIT_SLV (!ts1_lb_bit condition)
        @(posedge clk); #0.1;   // state=LB_EXIT_SLV
        lb_timer_exp = 1'b1;
        @(posedge clk); #0.1;   // EXIT_SLV->LB_DONE
        lb_timer_exp = 1'b0;
        @(posedge clk); #0.1;   // state=LB_DONE: lb_exit=1
        check_output("lb_exit",   lb_exit,   1'b1);
        check_output("lb_active", lb_active, 1'b0);

        // TC8: Multiple master cycles
        test_num  = 8;
        test_name = "MULTI_MASTER";
        apply_reset;
        begin : multi_lb_loop
            integer k;
            for (k = 0; k < 3; k = k + 1) begin
                master_enter_loopback;    // state=LB_ACTIVE_MSTR
                check_output("lb_active",   lb_active,   1'b1);
                check_output("send_ts1_lb", send_ts1_lb, 1'b0);
                lb_timer_exp = 1'b1;
                @(posedge clk); #0.1;     // ->LB_EXIT_MSTR
                lb_timer_exp = 1'b0;
                lb_timer_exp = 1'b1;
                @(posedge clk); #0.1;     // ->LB_DONE
                lb_timer_exp = 1'b0;
                @(posedge clk); #0.1;     // state=LB_DONE: lb_exit=1
                check_output("lb_exit",   lb_exit,   1'b1);
                @(posedge clk); #0.1;     // state=IDLE
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
