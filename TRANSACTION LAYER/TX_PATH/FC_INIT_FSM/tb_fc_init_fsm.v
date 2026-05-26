// =============================================================================
// Testbench : tb_fc_init_fsm
// DUT       : fc_init_fsm (PCIe 6.0 TL FC Init FSM)
// Language  : Verilog (converted from SystemVerilog)
//
// Test cases:
//   TC1  Normal handshake: IFC1 partner replies arrive in order
//   TC2  Out-of-order partner replies (IFC1 CPL arrives before NP)
//   TC3  dll_up deasserted before handshake (no init should start)
//   TC4  Partner IFC2 replies arrive before IFC2 send (pre-loaded)
//   TC5  Reset mid-handshake; verify clean restart
// =============================================================================

`timescale 1ns/1ps

module tb_fc_init_fsm;

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
parameter CLK_PERIOD = 10; // 10 ns = 100 MHz

// DLLP type codes (mirror RTL)
parameter [7:0] TYPE_IFC1_P   = 8'h40;
parameter [7:0] TYPE_IFC1_NP  = 8'h50;
parameter [7:0] TYPE_IFC1_CPL = 8'h60;
parameter [7:0] TYPE_IFC2_P   = 8'hC0;
parameter [7:0] TYPE_IFC2_NP  = 8'hD0;
parameter [7:0] TYPE_IFC2_CPL = 8'hE0;

// Expected advertised credit constants (must match RTL localparam)
parameter [7:0]  EXP_PH   = 8'd32;
parameter [11:0] EXP_PD   = 12'd128;
parameter [7:0]  EXP_NPH  = 8'd8;
parameter [7:0]  EXP_CPLH = 8'd32;
parameter [11:0] EXP_CPLD = 12'd128;

// ---------------------------------------------------------------------------
// DUT signals
// ---------------------------------------------------------------------------
reg          clk;
reg          rst_n;
reg          dll_up;
reg  [71:0]  initfc_rx;
reg          initfc_rx_valid;

wire [71:0]  initfc_tx;
wire         initfc_tx_send;
wire         fc_init_done;
wire [ 7:0]  adv_ph;
wire [11:0]  adv_pd;
wire [ 7:0]  adv_nph;
wire [ 7:0]  adv_cplh;
wire [11:0]  adv_cpld;

// ---------------------------------------------------------------------------
// DUT instantiation
// ---------------------------------------------------------------------------
fc_init_fsm dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .dll_up         (dll_up),
    .initfc_rx      (initfc_rx),
    .initfc_rx_valid(initfc_rx_valid),
    .initfc_tx      (initfc_tx),
    .initfc_tx_send (initfc_tx_send),
    .fc_init_done   (fc_init_done),
    .adv_ph         (adv_ph),
    .adv_pd         (adv_pd),
    .adv_nph        (adv_nph),
    .adv_cplh       (adv_cplh),
    .adv_cpld       (adv_cpld)
);

// ---------------------------------------------------------------------------
// Clock generation
// ---------------------------------------------------------------------------
initial clk = 0;
always #(CLK_PERIOD/2) clk = ~clk;

// ---------------------------------------------------------------------------
// Test result counters
// ---------------------------------------------------------------------------
integer pass_count;
integer fail_count;

// ---------------------------------------------------------------------------
// TX capture storage
// ---------------------------------------------------------------------------
integer      tx_send_count;
reg [71:0]   tx_log [0:7];  // log up to 8 DLLPs

// ---------------------------------------------------------------------------
// Utility tasks
// ---------------------------------------------------------------------------

// Apply reset
task apply_reset;
    input integer cycles;
    integer k;
    begin
        rst_n           = 1'b0;
        dll_up          = 1'b0;
        initfc_rx       = 72'h0;
        initfc_rx_valid = 1'b0;
        for (k = 0; k < cycles; k = k + 1)
            @(posedge clk);
        #1;
        rst_n = 1'b1;
        @(posedge clk);
    end
endtask

// Inject one InitFC DLLP from the simulated partner
task inject_rx_dllp;
    input [7:0] dtype;
    begin
        @(posedge clk); #1;
        initfc_rx       = {dtype, 64'h0};
        initfc_rx_valid = 1'b1;
        @(posedge clk); #1;
        initfc_rx_valid = 1'b0;
    end
endtask

// Inject all three InitFC1 DLLPs
task inject_all_ifc1;
    begin
        inject_rx_dllp(TYPE_IFC1_P);
        inject_rx_dllp(TYPE_IFC1_NP);
        inject_rx_dllp(TYPE_IFC1_CPL);
    end
endtask

// Inject all three InitFC2 DLLPs
task inject_all_ifc2;
    begin
        inject_rx_dllp(TYPE_IFC2_P);
        inject_rx_dllp(TYPE_IFC2_NP);
        inject_rx_dllp(TYPE_IFC2_CPL);
    end
endtask

// Wait for fc_init_done with timeout
task wait_done;
    input integer timeout_cycles;
    integer i;
    begin
        for (i = 0; i < timeout_cycles; i = i + 1) begin
            if (fc_init_done) i = timeout_cycles + 1; // break
            else @(posedge clk);
        end
        if (i == timeout_cycles)
            $display("  [WARN] wait_done timed out after %0d cycles", timeout_cycles);
    end
endtask

// Assertion helper (1-bit)
task check;
    input [127:0] label;  // fixed-width string substitute
    input         got;
    input         exp;
    begin
        if (got === exp) begin
            $display("  [PASS] %s : got=%0b exp=%0b", label, got, exp);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] %s : got=%0b exp=%0b  <---", label, got, exp);
            fail_count = fail_count + 1;
        end
    end
endtask

// Assertion helper (integer/wide value)
task check_val;
    input [127:0] label;  // fixed-width string substitute
    input [63:0]  got;
    input [63:0]  exp;
    begin
        if (got === exp) begin
            $display("  [PASS] %s : got=%0d exp=%0d", label, got, exp);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] %s : got=%0d exp=%0d  <---", label, got, exp);
            fail_count = fail_count + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// TEST CASES
// ---------------------------------------------------------------------------

// TC1: Normal handshake
task tc1_normal_handshake;
    begin
        $display("\n=== TC1: Normal handshake (in-order partner replies) ===");
        apply_reset(5);

        @(posedge clk); #1;
        dll_up = 1'b1;

        repeat(3) @(posedge clk);
        inject_all_ifc1();

        repeat(3) @(posedge clk);
        inject_all_ifc2();

        wait_done(100);

        @(posedge clk);
        check    ("TC1 fc_init_done",  fc_init_done, 1'b1);
        check_val("TC1 adv_ph",        {56'd0, adv_ph},   {56'd0, EXP_PH});
        check_val("TC1 adv_pd",        {52'd0, adv_pd},   {52'd0, EXP_PD});
        check_val("TC1 adv_nph",       {56'd0, adv_nph},  {56'd0, EXP_NPH});
        check_val("TC1 adv_cplh",      {56'd0, adv_cplh}, {56'd0, EXP_CPLH});
        check_val("TC1 adv_cpld",      {52'd0, adv_cpld}, {52'd0, EXP_CPLD});

        dll_up = 1'b0;
    end
endtask

// TC2: Out-of-order partner InitFC1 replies
task tc2_ooo_ifc1;
    begin
        $display("\n=== TC2: Out-of-order InitFC1 from partner (CPL first) ===");
        apply_reset(5);

        @(posedge clk); #1;
        dll_up = 1'b1;
        repeat(3) @(posedge clk);

        inject_rx_dllp(TYPE_IFC1_CPL);
        repeat(2) @(posedge clk);
        inject_rx_dllp(TYPE_IFC1_NP);
        repeat(2) @(posedge clk);
        inject_rx_dllp(TYPE_IFC1_P);

        repeat(3) @(posedge clk);
        inject_all_ifc2();

        wait_done(100);
        @(posedge clk);

        check("TC2 fc_init_done after OOO IFC1", fc_init_done, 1'b1);

        dll_up = 1'b0;
    end
endtask

// TC3: dll_up never asserted
task tc3_no_dll_up;
    begin
        $display("\n=== TC3: dll_up never asserted FSM must stay IDLE ===");
        apply_reset(5);

        repeat(20) @(posedge clk);

        check("TC3 fc_init_done stays 0",    fc_init_done,   1'b0);
        check("TC3 initfc_tx_send stays 0",  initfc_tx_send, 1'b0);
    end
endtask

// TC4: Partner IFC2 arrives before DUT sends IFC2
task tc4_early_ifc2;
    begin
        $display("\n=== TC4: Partner IFC2 pre-loads while DUT still in WAIT_IFC1 ===");
        apply_reset(5);

        @(posedge clk); #1;
        dll_up = 1'b1;
        repeat(3) @(posedge clk);

        inject_all_ifc1();
        inject_all_ifc2();

        wait_done(100);
        @(posedge clk);

        check("TC4 fc_init_done", fc_init_done, 1'b1);

        dll_up = 1'b0;
    end
endtask

// TC5: Reset mid-handshake
task tc5_reset_mid_handshake;
    begin
        $display("\n=== TC5: Reset asserted mid-handshake, then clean restart ===");
        apply_reset(5);

        @(posedge clk); #1;
        dll_up = 1'b1;
        repeat(3) @(posedge clk);

        inject_rx_dllp(TYPE_IFC1_P);
        repeat(3) @(posedge clk);

        rst_n  = 1'b0;
        dll_up = 1'b0;
        repeat(3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        check("TC5 fc_init_done=0 after mid-reset", fc_init_done, 1'b0);

        @(posedge clk); #1;
        dll_up = 1'b1;
        repeat(3) @(posedge clk);
        inject_all_ifc1();
        repeat(3) @(posedge clk);
        inject_all_ifc2();
        wait_done(100);
        @(posedge clk);

        check("TC5 fc_init_done after restart", fc_init_done, 1'b1);

        dll_up = 1'b0;
    end
endtask

// TC6: Verify TX DLLP types in correct order
task tc6_tx_type_order;
    integer ci;
    begin
        $display("\n=== TC6: Verify DUT sends IFC1 P, NP, CPL then IFC2 P, NP, CPL ===");
        apply_reset(5);

        tx_send_count = 0;

        @(posedge clk); #1;
        dll_up = 1'b1;

        for (ci = 0; ci < 30; ci = ci + 1) begin
            @(posedge clk);
            if (initfc_tx_send) begin
                tx_log[tx_send_count] = initfc_tx;
                tx_send_count = tx_send_count + 1;
            end
            if (ci == 4)  begin #1; inject_rx_dllp(TYPE_IFC1_P);   end
            if (ci == 5)  begin #1; inject_rx_dllp(TYPE_IFC1_NP);  end
            if (ci == 6)  begin #1; inject_rx_dllp(TYPE_IFC1_CPL); end
            if (ci == 12) begin #1; inject_rx_dllp(TYPE_IFC2_P);   end
            if (ci == 13) begin #1; inject_rx_dllp(TYPE_IFC2_NP);  end
            if (ci == 14) begin #1; inject_rx_dllp(TYPE_IFC2_CPL); end
        end

        check_val("TC6 total TX DLLPs sent", tx_send_count, 6);
        if (tx_send_count >= 6) begin
            check_val("TC6 TX[0] type = IFC1_P",   {56'd0, tx_log[0][71:64]}, {56'd0, TYPE_IFC1_P});
            check_val("TC6 TX[1] type = IFC1_NP",  {56'd0, tx_log[1][71:64]}, {56'd0, TYPE_IFC1_NP});
            check_val("TC6 TX[2] type = IFC1_CPL", {56'd0, tx_log[2][71:64]}, {56'd0, TYPE_IFC1_CPL});
            check_val("TC6 TX[3] type = IFC2_P",   {56'd0, tx_log[3][71:64]}, {56'd0, TYPE_IFC2_P});
            check_val("TC6 TX[4] type = IFC2_NP",  {56'd0, tx_log[4][71:64]}, {56'd0, TYPE_IFC2_NP});
            check_val("TC6 TX[5] type = IFC2_CPL", {56'd0, tx_log[5][71:64]}, {56'd0, TYPE_IFC2_CPL});
        end

        dll_up = 1'b0;
    end
endtask

// ---------------------------------------------------------------------------
// Top-level stimulus
// ---------------------------------------------------------------------------
initial begin
    pass_count = 0;
    fail_count = 0;

    $display("============================================================");
    $display("  PCIe Gen6 FC Init FSM Testbench");
    $display("============================================================");

    tc1_normal_handshake;
    tc2_ooo_ifc1;
    tc3_no_dll_up;
    tc4_early_ifc2;
    tc5_reset_mid_handshake;
    tc6_tx_type_order;

    $display("\n============================================================");
    $display("  Results:  PASS=%0d   FAIL=%0d", pass_count, fail_count);
    $display("============================================================");

    if (fail_count == 0)
        $display("  *** ALL TESTS PASSED ***");
    else
        $display("  *** SOME TESTS FAILED ***");

    $finish;
end

// ---------------------------------------------------------------------------
// Waveform dump (optional - comment out if not needed)
// ---------------------------------------------------------------------------
initial begin
    $dumpfile("fc_init_fsm.vcd");
    $dumpvars(0, tb_fc_init_fsm);
end

// ---------------------------------------------------------------------------
// Timeout watchdog
// ---------------------------------------------------------------------------
initial begin
    #100000;
    $display("[WATCHDOG] Simulation exceeded 100 us - force finish");
    $finish;
end

endmodule
