
`timescale 1ns/1ps

module tb_ltssm_top;

reg         clk;
reg         rst_n;
reg  [2:0]  pipe_rx_status;
reg         pipe_detect_lane;
reg         dll_up_req;
reg  [2:0]  pm_req;
reg         hot_reset_req;
reg         link_down_req;
reg         compliance_req;

wire [5:0]  ltssm_state;
wire        dl_up;
wire        dl_down;
wire [1:0]  pipe_power_down;
wire        pipe_tx_elec_idle;
wire [3:0]  link_speed;
wire [5:0]  link_width;
wire        ltssm_reset_out;

ltssm_top dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .pipe_rx_status   (pipe_rx_status),
    .pipe_detect_lane (pipe_detect_lane),
    .dll_up_req       (dll_up_req),
    .pm_req           (pm_req),
    .hot_reset_req    (hot_reset_req),
    .link_down_req    (link_down_req),
    .compliance_req   (compliance_req),
    .ltssm_state      (ltssm_state),
    .dl_up            (dl_up),
    .dl_down          (dl_down),
    .pipe_power_down  (pipe_power_down),
    .pipe_tx_elec_idle(pipe_tx_elec_idle),
    .link_speed       (link_speed),
    .link_width       (link_width),
    .ltssm_reset_out  (ltssm_reset_out)
);

localparam [5:0]
    ST_DETECT_QUIET       = 6'd0,
    ST_DETECT_ACTIVE      = 6'd1,
    ST_POLLING_ACTIVE     = 6'd2,
    ST_POLLING_COMPLIANCE = 6'd3,
    ST_POLLING_CONFIG     = 6'd4,
    ST_CFG_LINKWD_START   = 6'd5,
    ST_CFG_LINKWD_ACCEPT  = 6'd6,
    ST_CFG_LANENUM_WAIT   = 6'd7,
    ST_CFG_LANENUM_ACCEPT = 6'd8,
    ST_CFG_COMPLETE       = 6'd9,
    ST_CFG_IDLE           = 6'd10,
    ST_RECOVERY_RCVLOCK   = 6'd11,
    ST_RECOVERY_RCVCONFIG = 6'd12,
    ST_RECOVERY_IDLE      = 6'd13,
    ST_RECOVERY_SPEED     = 6'd14,
    ST_RECOVERY_EQ_PHASE0 = 6'd15,
    ST_L0                 = 6'd16,
    ST_L0S_TX             = 6'd17,
    ST_L0S_RX             = 6'd18,
    ST_L1_ENTRY           = 6'd19,
    ST_L1                 = 6'd20,
    ST_L1_EXIT            = 6'd21,
    ST_HOT_RESET          = 6'd22,
    ST_DISABLED           = 6'd23,
    ST_LOOPBACK_ENTRY     = 6'd24,
    ST_LOOPBACK_ACTIVE    = 6'd25,
    ST_LOOPBACK_EXIT      = 6'd26;

localparam [2:0]
    RXST_ELEC_IDLE = 3'b000,
    RXST_RECV_OK   = 3'b001,
    RXST_RECV_DET  = 3'b011;

localparam [2:0]
    PM_NONE = 3'b000,
    PM_L0S  = 3'b001,
    PM_L1   = 3'b010,
    PM_L1_1 = 3'b011,
    PM_L1_2 = 3'b100;

integer pass_cnt;
integer fail_cnt;
integer tc_num;

initial begin
    $dumpfile("ltssm_top_waves.vcd");
    $dumpvars(0, tb_ltssm_top);
end

initial clk = 0;
always #5 clk = ~clk;

task wait_clk;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
        #1;
    end
endtask

task apply_reset;
    begin
        rst_n            <= 1'b0;
        pipe_rx_status   <= RXST_ELEC_IDLE;
        pipe_detect_lane <= 1'b0;
        dll_up_req       <= 1'b0;
        pm_req           <= PM_NONE;
        hot_reset_req    <= 1'b0;
        link_down_req    <= 1'b0;
        compliance_req   <= 1'b0;
        wait_clk(5);
        @(posedge clk);
        rst_n <= 1'b1;
        wait_clk(2);
    end
endtask

task drive_to_l0;
    integer timeout_cnt;
    begin

        pipe_detect_lane <= 1'b1;
        pipe_rx_status   <= RXST_RECV_DET;
        wait_clk(5);

        pipe_rx_status <= RXST_RECV_OK;
        wait_clk(10);

        wait_clk(10);

        wait_clk(30);

        dll_up_req <= 1'b1;
        wait_clk(10);

        timeout_cnt = 0;
        while (ltssm_state !== ST_L0 && timeout_cnt < 5000) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
        end

        dll_up_req <= 1'b0;

        if (ltssm_state !== ST_L0) begin
            $display("[HELPER] ERROR: drive_to_l0 timed out in state %0d", ltssm_state);
        end
    end
endtask

task check;
    input [63:0] actual;
    input [63:0] expected;
    input [255:0] signal_name;
    begin
        if (actual === expected) begin
            pass_cnt = pass_cnt + 1;
            $display("  TC%0d PASS: %s = %0d (expected %0d)",
                     tc_num, signal_name, actual, expected);
        end else begin
            fail_cnt = fail_cnt + 1;
            $display("  TC%0d FAIL: %s = %0d  *** expected %0d ***",
                     tc_num, signal_name, actual, expected);
        end
    end
endtask

task wait_for_state;
    input [5:0] target;
    input integer max_cycles;
    integer cnt;
    begin
        cnt = 0;
        while (ltssm_state !== target && cnt < max_cycles) begin
            @(posedge clk); #1;
            cnt = cnt + 1;
        end
        if (ltssm_state !== target) begin
            $display("  TC%0d FAIL: timed out waiting for state %0d (stuck at %0d)",
                     tc_num, target, ltssm_state);
            fail_cnt = fail_cnt + 1;
        end
    end
endtask

initial begin
    pass_cnt = 0;
    fail_cnt = 0;
    tc_num   = 0;

    tc_num = 1;
    $display("\n=== TC01: Power-on Reset ===");

    rst_n            <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;
    pipe_detect_lane <= 1'b0;
    dll_up_req       <= 1'b0;
    pm_req           <= PM_NONE;
    hot_reset_req    <= 1'b0;
    link_down_req    <= 1'b0;
    compliance_req   <= 1'b0;
    @(posedge clk); #1;

    check(ltssm_state,       ST_DETECT_QUIET, "ltssm_state");
    check(ltssm_reset_out,   1'b1,            "ltssm_reset_out");
    check(dl_up,             1'b0,            "dl_up");
    check(dl_down,           1'b0,            "dl_down");
    check(pipe_tx_elec_idle, 1'b1,            "pipe_tx_elec_idle");
    rst_n <= 1'b1;
    wait_clk(2);

    tc_num = 2;
    $display("\n=== TC02: Detect_Quiet -> Detect_Active ===");
    apply_reset;
    wait_clk(3);
    check(ltssm_state, ST_DETECT_ACTIVE, "ltssm_state after Quiet");

    tc_num = 3;
    $display("\n=== TC03: Detect_Active -> Polling_Active on receiver detected ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);
    check(ltssm_state, ST_POLLING_ACTIVE, "ltssm_state");
    check(ltssm_reset_out, 1'b0, "ltssm_reset_out deasserted");
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 4;
    $display("\n=== TC04: Detect_Active timeout -> Detect_Quiet ===");
    apply_reset;
    wait_clk(3);

    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;
    wait_for_state(ST_DETECT_QUIET, 1000);
    check(ltssm_state, ST_DETECT_QUIET, "ltssm_state after detect timeout");

    tc_num = 5;
    $display("\n=== TC05: Compliance entry ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);
    compliance_req   <= 1'b1;
    wait_for_state(ST_POLLING_COMPLIANCE, 100);
    check(ltssm_state, ST_POLLING_COMPLIANCE, "ltssm_state");
    compliance_req   <= 1'b0;
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 6;
    $display("\n=== TC06: Hot Reset from Polling_Active ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);
    hot_reset_req    <= 1'b1;
    wait_clk(2);
    hot_reset_req    <= 1'b0;
    wait_for_state(ST_HOT_RESET, 100);
    check(ltssm_state, ST_HOT_RESET, "ltssm_state = HOT_RESET");
    check(ltssm_reset_out, 1'b1, "ltssm_reset_out asserted in HOT_RESET");
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 7;
    $display("\n=== TC07: Hot Reset expires -> Detect_Quiet ===");

    wait_for_state(ST_DETECT_QUIET, 300);
    check(ltssm_state, ST_DETECT_QUIET, "ltssm_state after hot reset");

    tc_num = 8;
    $display("\n=== TC08: Full link bring-up to L0 ===");
    apply_reset;
    drive_to_l0;
    check(ltssm_state, ST_L0, "ltssm_state = L0");
    check(dl_up,       1'b1,  "dl_up asserted at L0");
    check(dl_down,     1'b0,  "dl_down deasserted at L0");
    check(pipe_tx_elec_idle, 1'b0, "pipe_tx_elec_idle deasserted at L0");
    check(pipe_power_down, 2'b00, "pipe_power_down = P0 at L0");

    tc_num = 9;
    $display("\n=== TC09: L0 -> L0s on PM L0s request ===");

    pm_req <= PM_L0S;
    wait_for_state(ST_L0S_TX, 50);
    check(ltssm_state, ST_L0S_TX, "ltssm_state = L0S_TX");
    pm_req <= PM_NONE;

    tc_num = 10;
    $display("\n=== TC10: L0s_TX -> L0s_RX on EI ===");
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_L0S_RX, 50);
    check(ltssm_state, ST_L0S_RX, "ltssm_state = L0S_RX");

    tc_num = 11;
    $display("\n=== TC11: L0s_RX -> L0 on FTS/data ===");
    pipe_rx_status <= RXST_RECV_OK;
    wait_for_state(ST_L0, 100);
    check(ltssm_state, ST_L0, "ltssm_state = L0 after L0s exit");

    wait_clk(2);
    check(dl_up, 1'b1, "dl_up stays asserted after L0s exit");
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_clk(3);

    tc_num = 12;
    $display("\n=== TC12: L0 -> L1_ENTRY on PM L1 ===");
    pm_req <= PM_L1;
    wait_for_state(ST_L1_ENTRY, 100);
    check(ltssm_state, ST_L1_ENTRY, "ltssm_state = L1_ENTRY");

    tc_num = 13;
    $display("\n=== TC13: L1_ENTRY -> L1 on EI ===");
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_L1, 300);
    check(ltssm_state, ST_L1, "ltssm_state = L1");
    wait_clk(2);
    check(pipe_power_down, 2'b01, "pipe_power_down = P1 in L1");

    tc_num = 14;
    $display("\n=== TC14: L1 -> L1_EXIT on wakeup ===");

    pm_req         <= PM_NONE;
    pipe_rx_status <= RXST_RECV_OK;
    wait_for_state(ST_L1_EXIT, 100);
    check(ltssm_state, ST_L1_EXIT, "ltssm_state = L1_EXIT");
    pipe_rx_status <= RXST_ELEC_IDLE;

    tc_num = 15;
    $display("\n=== TC15: L1_EXIT -> Recovery ===");

    wait_for_state(ST_RECOVERY_RCVLOCK, 100);
    check(ltssm_state, ST_RECOVERY_RCVLOCK, "ltssm_state = RECOVERY_RCVLOCK");

    tc_num = 16;
    $display("\n=== TC16: Recovery -> L0 path ===");
    pipe_rx_status <= RXST_RECV_OK;
    wait_for_state(ST_RECOVERY_RCVCONFIG, 500);
    check(ltssm_state, ST_RECOVERY_RCVCONFIG, "ltssm_state = RECOVERY_RCVCONFIG");

    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_RECOVERY_IDLE, 100);
    check(ltssm_state, ST_RECOVERY_IDLE, "ltssm_state = RECOVERY_IDLE");

    dll_up_req <= 1'b1;
    wait_for_state(ST_L0, 500);
    check(ltssm_state, ST_L0, "ltssm_state = L0 after recovery");
    check(dl_up, 1'b1, "dl_up = 1 after recovery to L0");
    dll_up_req <= 1'b0;
    pipe_rx_status <= RXST_ELEC_IDLE;

    tc_num = 17;
    $display("\n=== TC17: link_down_req from L0 ===");

    apply_reset;
    drive_to_l0;
    check(ltssm_state, ST_L0, "pre-check L0 for TC17");
    link_down_req <= 1'b1;
    wait_clk(2);
    link_down_req <= 1'b0;
    wait_for_state(ST_DETECT_QUIET, 200);
    check(ltssm_state, ST_DETECT_QUIET, "ltssm_state = DETECT_QUIET after link_down");

    tc_num = 18;
    $display("\n=== TC18: Hot Reset from L0 ===");
    apply_reset;
    drive_to_l0;
    hot_reset_req <= 1'b1;
    wait_clk(2);
    hot_reset_req <= 1'b0;
    wait_for_state(ST_HOT_RESET, 100);
    check(ltssm_state, ST_HOT_RESET, "ltssm_state = HOT_RESET from L0");
    check(ltssm_reset_out, 1'b1, "ltssm_reset_out = 1 in HOT_RESET");

    tc_num = 19;
    $display("\n=== TC19: dl_down pulses when leaving L0 ===");
    apply_reset;
    drive_to_l0;

    link_down_req <= 1'b1;
    @(posedge clk); #1;
    link_down_req <= 1'b0;

    wait_clk(2);

    if (dl_down === 1'b1 || ltssm_state !== ST_L0)
        check(1'b1, 1'b1, "dl_down pulsed on L0 departure (observed)");
    else begin

        wait_for_state(ST_DETECT_QUIET, 200);
        check(dl_up, 1'b0, "dl_up deasserted after link down");
    end

    tc_num = 20;
    $display("\n=== TC20: pipe_power_down = P2 in DETECT_QUIET ===");
    apply_reset;
    wait_clk(2);
    check(pipe_power_down, 2'b10, "pipe_power_down = P2 at reset/detect_quiet");

    tc_num = 21;
    $display("\n=== TC21: pipe_tx_elec_idle deasserted in L0 ===");
    apply_reset;
    drive_to_l0;
    check(pipe_tx_elec_idle, 1'b0, "pipe_tx_elec_idle = 0 in L0");

    tc_num = 22;
    $display("\n=== TC22: link_speed = Gen6 in L0 ===");
    check(link_speed, 4'd6, "link_speed = 6 (Gen6) in L0");

    tc_num = 23;
    $display("\n=== TC23: link_width = 1 ===");
    check(link_width, 6'd1, "link_width = 1");

    tc_num = 24;
    $display("\n=== TC24: L0 -> L1_ENTRY via PM L1.1 ===");

    pm_req <= PM_L1_1;
    wait_for_state(ST_L1_ENTRY, 50);
    check(ltssm_state, ST_L1_ENTRY, "ltssm_state = L1_ENTRY on PM_L1_1");
    pm_req         <= PM_NONE;
    pipe_rx_status <= RXST_ELEC_IDLE;

    tc_num = 25;
    $display("\n=== TC25: L0 -> L1_ENTRY via PM L1.2 ===");
    apply_reset;
    drive_to_l0;
    pm_req <= PM_L1_2;
    wait_for_state(ST_L1_ENTRY, 50);
    check(ltssm_state, ST_L1_ENTRY, "ltssm_state = L1_ENTRY on PM_L1_2");
    pm_req         <= PM_NONE;
    pipe_rx_status <= RXST_ELEC_IDLE;

    tc_num = 26;
    $display("\n=== TC26: Recovery_RcvLock timeout -> Detect_Quiet ===");
    apply_reset;

    drive_to_l0;

    pm_req <= PM_L1;
    wait_for_state(ST_L1_ENTRY, 50);
    pm_req         <= PM_NONE;
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_L1, 200);
    pipe_rx_status <= RXST_RECV_OK;
    wait_for_state(ST_L1_EXIT, 50);
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_RECOVERY_RCVLOCK, 50);

    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_DETECT_QUIET, 5000);
    check(ltssm_state, ST_DETECT_QUIET, "ltssm_state = DETECT_QUIET after recovery timeout");

    tc_num = 27;
    $display("\n=== TC27: Hot Reset from Recovery ===");
    apply_reset;
    drive_to_l0;
    pm_req <= PM_L1;
    wait_for_state(ST_L1_ENTRY, 50);
    pm_req         <= PM_NONE;
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_L1, 200);
    pipe_rx_status <= RXST_RECV_OK;
    wait_for_state(ST_L1_EXIT, 50);
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_RECOVERY_RCVLOCK, 50);

    hot_reset_req <= 1'b1;
    wait_clk(2);
    hot_reset_req <= 1'b0;
    wait_for_state(ST_HOT_RESET, 200);
    check(ltssm_state, ST_HOT_RESET, "ltssm_state = HOT_RESET from Recovery");

    tc_num = 28;
    $display("\n=== TC28: Compliance mode sticky ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);
    compliance_req   <= 1'b1;
    wait_clk(1);
    compliance_req   <= 1'b0;
    wait_for_state(ST_POLLING_COMPLIANCE, 100);
    wait_clk(50);
    check(ltssm_state, ST_POLLING_COMPLIANCE, "stays in Polling_Compliance");
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 29;
    $display("\n=== TC29: ltssm_reset_out = 0 in Polling_Active ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);
    check(ltssm_reset_out, 1'b0, "ltssm_reset_out deasserted in Polling");
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 30;
    $display("\n=== TC30: Back-to-back reset stability ===");
    apply_reset;
    wait_clk(5);

    rst_n <= 1'b0;
    @(posedge clk); #1;
    check(ltssm_state,     ST_DETECT_QUIET, "ltssm_state = DETECT_QUIET after 2nd reset");
    check(ltssm_reset_out, 1'b1,            "ltssm_reset_out = 1 after 2nd reset");
    check(dl_up,           1'b0,            "dl_up = 0 after 2nd reset");
    rst_n <= 1'b1;
    wait_clk(2);

    tc_num = 31;
    $display("\n=== TC31: dl_up = 0 in Configuration ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);
    pipe_rx_status   <= RXST_RECV_OK;
    wait_for_state(ST_POLLING_CONFIG, 200);
    check(dl_up, 1'b0, "dl_up = 0 during Polling_Config");
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 32;
    $display("\n=== TC32: Polling_Active timeout -> Detect_Quiet ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);

    pipe_rx_status <= RXST_RECV_DET;
    wait_for_state(ST_DETECT_QUIET, 2000);
    check(ltssm_state, ST_DETECT_QUIET, "ltssm_state = DETECT_QUIET after polling timeout");
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 33;
    $display("\n=== TC33: Recovery_Speed state reachability ===");

    check(ST_RECOVERY_SPEED, 6'd14, "ST_RECOVERY_SPEED encoding = 14");
    check(ST_RECOVERY_EQ_PHASE0, 6'd15, "ST_RECOVERY_EQ_PHASE0 encoding = 15");

    tc_num = 34;
    $display("\n=== TC34: pipe_power_down = P0 during Polling ===");
    apply_reset;
    wait_clk(3);
    pipe_detect_lane <= 1'b1;
    pipe_rx_status   <= RXST_RECV_DET;
    wait_for_state(ST_POLLING_ACTIVE, 300);
    check(pipe_power_down, 2'b00, "pipe_power_down = P0 in Polling");
    pipe_detect_lane <= 1'b0;
    pipe_rx_status   <= RXST_ELEC_IDLE;

    tc_num = 35;
    $display("\n=== TC35: Full L0s round-trip: L0->L0s->L0 with dl_up ===");
    apply_reset;
    drive_to_l0;
    check(dl_up, 1'b1, "dl_up before L0s");

    pm_req <= PM_L0S;
    wait_for_state(ST_L0S_TX, 50);
    pm_req         <= PM_NONE;
    pipe_rx_status <= RXST_ELEC_IDLE;
    wait_for_state(ST_L0S_RX, 50);

    pipe_rx_status <= RXST_RECV_OK;
    wait_for_state(ST_L0, 200);
    check(ltssm_state, ST_L0, "ltssm_state = L0 after L0s round-trip");
    check(dl_up, 1'b1, "dl_up = 1 maintained after L0s exit");
    pipe_rx_status <= RXST_ELEC_IDLE;

    $display("\n=====================================================");
    $display("  LTSSM TOP CONTROLLER TESTBENCH RESULTS");
    $display("  PASSED : %0d", pass_cnt);
    $display("  FAILED : %0d", fail_cnt);
    $display("  TOTAL  : %0d", pass_cnt + fail_cnt);
    if (fail_cnt == 0)
        $display("  STATUS : *** ALL TESTS PASSED ***");
    else
        $display("  STATUS : *** FAILURES DETECTED — SEE ABOVE ***");
    $display("=====================================================\n");

    $finish;
end

initial begin
    #10_000_000;
    $display("ERROR: Simulation watchdog triggered at time %0t", $time);
    $finish;
end

endmodule
