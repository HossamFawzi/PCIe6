
`timescale 1ns/1ps

module tb_beacon_ei_logic;

    reg        clk;
    reg        rst_n;
    reg        beacon_req;
    reg        ei_req;
    reg        pipe_rx_elec_idle;
    reg [2:0]  pm_state;

    wire       pipe_tx_elec_idle;
    wire       beacon_detect;
    wire       ei_detect;
    wire       wakeup_req;

    beacon_ei_logic DUT (
        .clk               (clk),
        .rst_n             (rst_n),
        .beacon_req        (beacon_req),
        .ei_req            (ei_req),
        .pipe_rx_elec_idle (pipe_rx_elec_idle),
        .pm_state          (pm_state),
        .pipe_tx_elec_idle (pipe_tx_elec_idle),
        .beacon_detect     (beacon_detect),
        .ei_detect         (ei_detect),
        .wakeup_req        (wakeup_req)
    );

    initial clk = 0;
    always  #2 clk = ~clk;

    localparam PM_L0  = 3'b000;
    localparam PM_L0S = 3'b001;
    localparam PM_L1  = 3'b010;
    localparam PM_L2  = 3'b011;
    localparam PM_L3  = 3'b100;

    task wait_clks;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    integer pass_count;
    integer fail_count;

    task check;
        input [63:0] got;
        input [63:0] expected;
        input [127:0] label;
        begin
            if (got === expected) begin
                $display("  PASS  %-40s  got=%0d", label, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL  %-40s  got=%0d  expected=%0d",
                         label, got, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin

        pass_count        = 0;
        fail_count        = 0;
        rst_n             = 0;
        beacon_req        = 0;
        ei_req            = 0;
        pipe_rx_elec_idle = 1;
        pm_state          = PM_L0;

        $display("\n=== beacon_ei_logic Testbench ===\n");

        $display("--- Test 1: Reset State ---");
        wait_clks(4);
        @(posedge clk);
        check(pipe_tx_elec_idle, 1, "pipe_tx_elec_idle during reset");
        check(beacon_detect,     0, "beacon_detect during reset");
        check(ei_detect,         0, "ei_detect during reset");
        check(wakeup_req,        0, "wakeup_req during reset");

        @(posedge clk);
        rst_n = 1;
        wait_clks(2);

        $display("\n--- Test 2: EI Request ? pipe_tx_elec_idle ---");
        ei_req = 1;
        wait_clks(3);
        check(pipe_tx_elec_idle, 1, "TX idle asserted with ei_req");
        ei_req = 0;
        wait_clks(2);

        $display("\n--- Test 3: Beacon TX state machine (L2) ---");
        pm_state    = PM_L2;
        beacon_req  = 1;

        wait_clks(4);

        check(pipe_tx_elec_idle, 0, "TX not idle during beacon assert");

        wait_clks(260);

        check(pipe_tx_elec_idle, 1, "TX idle during beacon off-phase");

        wait_clks(2100);
        beacon_req = 0;
        wait_clks(5);
        check(pipe_tx_elec_idle, 1, "TX idle after beacon done");
        pm_state = PM_L0;

        $display("\n--- Test 4: RX EI detect debounce (8-cycle threshold) ---");

        pipe_rx_elec_idle = 0;
        wait_clks(3);

        pipe_rx_elec_idle = 1;
        wait_clks(4);
        check(ei_detect, 0, "ei_detect NOT set on 4-cycle EI pulse");

        pipe_rx_elec_idle = 1;
        wait_clks(10);
        check(ei_detect, 1, "ei_detect SET after 8-cycle EI");

        pipe_rx_elec_idle = 0;
        wait_clks(3);
        check(ei_detect, 0, "ei_detect cleared after EI release");

        $display("\n--- Test 5: RX Beacon detect in L2 ? wakeup_req ---");
        pm_state          = PM_L2;
        pipe_rx_elec_idle = 0;

        wait_clks(510);
        check(beacon_detect, 1, "beacon_detect after 500-cycle burst");
        check(wakeup_req,    1, "wakeup_req asserted after beacon");

        pipe_rx_elec_idle = 1;
        wait_clks(5);
        check(beacon_detect, 0, "beacon_detect cleared");

        check(wakeup_req, 1, "wakeup_req held until L0");

        $display("\n--- Test 6: wakeup_req clears on L0 ---");
        pm_state = PM_L0;
        wait_clks(3);
        check(wakeup_req, 0, "wakeup_req cleared after returning to L0");

        $display("\n--- Test 7: No beacon detect in L0 state ---");
        pm_state          = PM_L0;
        pipe_rx_elec_idle = 0;
        wait_clks(600);
        check(beacon_detect, 0, "beacon_detect suppressed in L0");
        pipe_rx_elec_idle = 1;

        $display("\n=== SUMMARY: %0d passed, %0d failed ===\n",
                 pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED\n");
        else
            $display("SOME TESTS FAILED\n");

        $finish;
    end

    initial begin
        #200_000;
        $display("TIMEOUT: simulation exceeded 200 us");
        $finish;
    end

    initial begin
        $dumpfile("beacon_ei_logic.vcd");
        $dumpvars(0, tb_beacon_ei_logic);
    end

endmodule
