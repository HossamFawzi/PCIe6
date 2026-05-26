
// ============================================================================
//  TESTBENCH : tb_pcie_gen6_dll_if
// ============================================================================
module tb_pcie_gen6_dll_if;

    //------------------------------------------------------------------
    // Signals
    //------------------------------------------------------------------
    reg               clk_tb;
    reg               rst_n_tb;

    reg  [2047:0]     flit_in_tb;
    reg               flit_valid_in_tb;

    reg               dll_ack_tb;
    reg               dll_nak_tb;
    reg               dll_up_tb;

    reg  [71:0]       cr_update_tb;
    reg               cr_update_valid_tb;

    wire [1023:0]     tlp_rx_out_tb;
    wire              tlp_rx_valid_tb;

    wire [2047:0]     flit_to_dll_tb;
    wire              flit_to_dll_valid_tb;

    wire              dll_ready_tb;

    //------------------------------------------------------------------
    // DUT
    //------------------------------------------------------------------
    DLL_IF #(
        .TIMEOUT_MAX (200),
        .RETRY_MAX   (4)
    ) dut (
        .clk               (clk_tb),
        .rst_n             (rst_n_tb),
        .flit_in           (flit_in_tb),
        .flit_valid_in     (flit_valid_in_tb),
        .dll_ack           (dll_ack_tb),
        .dll_nak           (dll_nak_tb),
        .dll_up            (dll_up_tb),
        .cr_update         (cr_update_tb),
        .cr_update_valid   (cr_update_valid_tb),
        .tlp_rx_out        (tlp_rx_out_tb),
        .tlp_rx_valid      (tlp_rx_valid_tb),
        .flit_to_dll       (flit_to_dll_tb),
        .flit_to_dll_valid (flit_to_dll_valid_tb),
        .dll_ready         (dll_ready_tb)
    );

    //------------------------------------------------------------------
    // Clock (10 ns period)
    //------------------------------------------------------------------
    initial  clk_tb = 1'b0;
    always #5 clk_tb = ~clk_tb;

    //------------------------------------------------------------------
    // Scoreboard
    //------------------------------------------------------------------
    integer      error_count;
    integer      send_count;
    reg [2047:0] expected_flit;

    //------------------------------------------------------------------
    // Monitor
    //------------------------------------------------------------------
    always @(posedge clk_tb) begin
        if (!dll_up_tb && flit_to_dll_valid_tb) begin
            $display("[%0t] ERROR: TX while dll_up=0", $time);
            error_count = error_count + 1;
        end
        if (flit_to_dll_valid_tb) begin
            send_count = send_count + 1;
            if (flit_to_dll_tb !== expected_flit) begin
                $display("[%0t] ERROR: FLIT mismatch got=%0h exp=%0h",
                    $time, flit_to_dll_tb[31:0], expected_flit[31:0]);
                error_count = error_count + 1;
            end
            else begin
                $display("[%0t] INFO : FLIT #%0d sent correctly",
                    $time, send_count);
            end
        end
    end

    //------------------------------------------------------------------
    // Tasks
    //------------------------------------------------------------------
    task send_flit;
        input [2047:0] flit;
        begin
            @(posedge clk_tb); #1;
            flit_in_tb       = flit;
            flit_valid_in_tb = 1'b1;
            @(posedge clk_tb); #1;
            flit_valid_in_tb = 1'b0;
        end
    endtask

    task pulse_ack;
        begin
            @(posedge clk_tb); #1;
            dll_ack_tb = 1'b1;
            @(posedge clk_tb); #1;
            dll_ack_tb = 1'b0;
        end
    endtask

    task pulse_nak;
        begin
            @(posedge clk_tb); #1;
            dll_nak_tb = 1'b1;
            @(posedge clk_tb); #1;
            dll_nak_tb = 1'b0;
        end
    endtask

    //------------------------------------------------------------------
    // Test sequence
    //------------------------------------------------------------------
    initial begin

        // Init
        rst_n_tb           = 1'b0;
        flit_in_tb         = 2048'h0;
        flit_valid_in_tb   = 1'b0;
        dll_ack_tb         = 1'b0;
        dll_nak_tb         = 1'b0;
        dll_up_tb          = 1'b0;
        cr_update_tb       = 72'h0;
        cr_update_valid_tb = 1'b0;
        error_count        = 0;
        send_count         = 0;
        expected_flit      = 2048'h0;

        // Release reset
        repeat(4) @(posedge clk_tb);
        #1 rst_n_tb = 1'b1;
        repeat(2) @(posedge clk_tb);

        //==============================================================
        // TEST 1 - Link-Up: dll_ready must follow dll_up
        //==============================================================
        $display("");
        $display("[%0t] ===== TEST 1: Link-Up =====", $time);

        @(posedge clk_tb); #1;
        dll_up_tb = 1'b1;
        @(posedge clk_tb); #1;

        if (!dll_ready_tb) begin
            $display("[%0t] ERROR: dll_ready not set after dll_up=1", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : dll_ready=1 when dll_up=1", $time);
        end

        //==============================================================
        // TEST 2 - Normal TX + ACK
        // Expect: FLIT sent exactly once.
        //==============================================================
        $display("");
        $display("[%0t] ===== TEST 2: Normal TX + ACK =====", $time);

        send_count    = 0;           // reset BEFORE test
        expected_flit = 2048'hAAAA;  // set BEFORE send

        send_flit(expected_flit);
        repeat(3) @(posedge clk_tb);
        pulse_ack;
        repeat(2) @(posedge clk_tb);

        if (send_count !== 1) begin
            $display("[%0t] ERROR: Test2 - expected 1 send, got %0d",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test2 - Normal TX OK (sends=%0d)",
                $time, send_count);
        end

        //==============================================================
        // TEST 3 - NAK + Replay
        // Expect: FLIT sent >= 2 times.
        //==============================================================
        $display("");
        $display("[%0t] ===== TEST 3: NAK + Replay =====", $time);

        send_count    = 0;
        expected_flit = 2048'hBBBB;

        send_flit(expected_flit);
        repeat(3) @(posedge clk_tb);
        pulse_nak;
        repeat(4) @(posedge clk_tb);
        pulse_ack;
        repeat(2) @(posedge clk_tb);

        if (send_count < 2) begin
            $display("[%0t] ERROR: Test3 - replay did not occur (sends=%0d)",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test3 - NAK replay OK (sends=%0d)",
                $time, send_count);
        end

        //==============================================================
        // TEST 4 - Timeout Replay
        //
        // TIMEOUT_MAX=200 clock cycles (10 ns each) = 2000 ns minimum.
        // We wait #2200 ns > 2000 ns to guarantee timeout fires, then
        // ACK the retried FLIT.
        // Expect: FLIT sent >= 2 times.
        //==============================================================
        $display("");
        $display("[%0t] ===== TEST 4: Timeout Replay =====", $time);
        $display("[%0t] INFO : Waiting 2200ns for TIMEOUT_MAX=200 cycles...",
            $time);

        send_count    = 0;
        expected_flit = 2048'hCCCC;

        send_flit(expected_flit);   // starts WAIT_ACK countdown

        #2200;                      // wait for timeout to fire + replay

        pulse_ack;                  // ACK the retried FLIT
        repeat(2) @(posedge clk_tb);

        if (send_count < 2) begin
            $display("[%0t] ERROR: Test4 - timeout replay failed (sends=%0d)",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test4 - Timeout replay OK (sends=%0d)",
                $time, send_count);
        end

        //==============================================================
        // TEST 5 - Link-Down Protection
        // Expect: zero FLITs sent while dll_up=0.
        //==============================================================
        $display("");
        $display("[%0t] ===== TEST 5: Link-Down Protection =====", $time);

        send_count = 0;

        @(posedge clk_tb); #1;
        dll_up_tb = 1'b0;
        repeat(2) @(posedge clk_tb);

        @(posedge clk_tb); #1;
        flit_in_tb       = 2048'hDDDD;
        flit_valid_in_tb = 1'b1;
        @(posedge clk_tb); #1;
        flit_valid_in_tb = 1'b0;

        repeat(5) @(posedge clk_tb);

        if (send_count !== 0) begin
            $display("[%0t] ERROR: Test5 - TX during link-down (sends=%0d)",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test5 - No TX during link-down", $time);
        end

        //==============================================================
        // TEST 6 - Credit-Update RX Path
        //
        // [TB-7] BUG FIX (root cause of the only remaining failure):
        //
        //   tlp_rx_valid is a REGISTERED output (set synchronously in
        //   always @(posedge clk)).  The default assignment clears it
        //   every cycle UNLESS cr_update_valid overrides it.
        //
        //   Failing sequence in original TB:
        //     @(posedge clk); #1;  cr_update_valid = 1        <- Cycle N
        //     @(posedge clk); #1;  cr_update_valid = 0        <- posedge N: DUT sets tlp_rx_valid=1
        //     @(posedge clk); #1;                             <- posedge N+1: DUT clears tlp_rx_valid=0
        //     check tlp_rx_valid -> sees 0 -> FALSE FAIL
        //
        //   Fixed sequence:
        //     @(posedge clk); #1;  cr_update_valid = 1        <- Cycle N
        //     @(posedge clk); #1;  cr_update_valid = 0        <- posedge N: DUT sets tlp_rx_valid=1
        //     // *** sample HERE, #1 after posedge N, before N+1 clears it ***
        //     check tlp_rx_valid -> sees 1 -> PASS
        //
        // Expect: tlp_rx_valid=1 sampled immediately after the clock edge
        //         that latched cr_update_valid=1.
        //==============================================================
        $display("");
        $display("[%0t] ===== TEST 6: Credit-Update RX Path =====", $time);

        dll_up_tb = 1'b1;

        // Apply cr_update_valid for one cycle
        @(posedge clk_tb); #1;
        cr_update_tb       = 72'hDEAD_BEEF_0000_0000_00;
        cr_update_valid_tb = 1'b1;

        // posedge fires here; DUT registers tlp_rx_valid=1
        @(posedge clk_tb); #1;
        cr_update_valid_tb = 1'b0;

        // [TB-7 FIX] Sample tlp_rx_valid NOW (1 ns after the posedge that set it)
        // DO NOT take another @(posedge clk_tb) here ? that would let the
        // synchronous default clear tlp_rx_valid before we check it.
        if (!tlp_rx_valid_tb) begin
            $display("[%0t] ERROR: Test6 - tlp_rx_valid not set", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test6 - tlp_rx_valid=1 data[31:0]=%0h",
                $time, tlp_rx_out_tb[31:0]);
        end

        repeat(3) @(posedge clk_tb);

        //==============================================================
        // FINAL REPORT
        //==============================================================
        $display("");
        $display("====================================");
        if (error_count == 0)
            $display("TEST PASSED SUCCESSFULLY  (errors=0)");
        else
            $display("TEST FAILED  Errors = %0d", error_count);
        $display("====================================");
        $display("");

        #20 $stop;
    end

endmodule  // tb_pcie_gen6_dll_if