// =============================================================================
// Testbench: tb_ack_nak_scheduler_tx
// Tests the ACK/NAK Scheduler (TX) module under these scenarios:
//   1. Single TLP with CRC OK ? ACK after threshold
//   2. Multiple TLPs coalesced ? single ACK at count threshold
//   3. TLP with CRC error ? immediate NAK
//   4. ACK timer expiry forces pending ACK
//   5. Reset behaviour
// =============================================================================

`timescale 1ns/1ps

module tb_ack_nak_scheduler_tx;

    // -------------------------------------------------------------------------
    // DUT Port Signals
    // -------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [11:0] seq_rx;
    reg         crc_ok;
    reg         tlp_rx_valid;
    reg         ack_timer_exp;
    reg  [ 7:0] ack_freq;

    wire [63:0] ack_dllp;
    wire [63:0] nak_dllp;
    wire        dllp_valid;
    wire [ 1:0] dllp_type;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    ack_nak_scheduler_tx DUT (
        .clk          (clk),
        .rst_n        (rst_n),
        .seq_rx       (seq_rx),
        .crc_ok       (crc_ok),
        .tlp_rx_valid (tlp_rx_valid),
        .ack_timer_exp(ack_timer_exp),
        .ack_freq     (ack_freq),
        .ack_dllp     (ack_dllp),
        .nak_dllp     (nak_dllp),
        .dllp_valid   (dllp_valid),
        .dllp_type    (dllp_type)
    );

    // -------------------------------------------------------------------------
    // Clock: 250 MHz (4 ns period) ? typical PCIe DLL clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #2 clk = ~clk;

    // -------------------------------------------------------------------------
    // Utility Tasks
    // -------------------------------------------------------------------------

    // Drive one valid TLP
    task send_tlp;
        input [11:0] seq;
        input        ok;
        begin
            @(posedge clk);
            seq_rx       = seq;
            crc_ok       = ok;
            tlp_rx_valid = 1'b1;
            @(posedge clk);
            tlp_rx_valid = 1'b0;
            seq_rx       = 12'h0;
            crc_ok       = 1'b0;
        end
    endtask

    // Wait N cycles
    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Pass/fail tracking
    // -------------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input        cond;
        input [63:0] tag;  // used as label index
        input [127:0] msg; // 16-char ASCII label (packed)
        begin
            if (cond) begin
                $display("  [PASS] %s", msg);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %s", msg);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_ack_nak_scheduler_tx.vcd");
        $dumpvars(0, tb_ack_nak_scheduler_tx);

        // Initialise
        rst_n        = 1'b0;
        seq_rx       = 12'h000;
        crc_ok       = 1'b0;
        tlp_rx_valid = 1'b0;
        ack_timer_exp= 1'b0;
        ack_freq     = 8'd3;   // ACK every 3 TLPs

        wait_cycles(4);
        rst_n = 1'b1;
        wait_cycles(2);

        // ==================================================================
        // TEST 1: Single TLP, CRC OK, ack_freq=1 ? immediate ACK
        // ==================================================================
        $display("\n=== TEST 1: Single TLP CRC OK, ack_freq=1 ===");
        ack_freq = 8'd1;
        send_tlp(12'h001, 1'b1);
        wait_cycles(1);
        check(dllp_valid == 1'b1,       64'd1, "dllp_valid asserted");
        check(dllp_type  == 2'b01,      64'd2, "dllp_type = ACK");
        check(ack_dllp[43:32] == 12'h001, 64'd3, "ACK seq = 0x001");
        check(ack_dllp[63:56] == 8'h00, 64'd4, "ACK type byte 0x00");
        wait_cycles(2);

        // ==================================================================
        // TEST 2: ACK coalescing ? send 3 TLPs, expect 1 ACK on 3rd
        // ==================================================================
        $display("\n=== TEST 2: ACK coalescing (ack_freq=3) ===");
        ack_freq = 8'd3;
        send_tlp(12'h010, 1'b1);
        wait_cycles(1);
        check(dllp_valid == 1'b0, 64'd5, "No ACK after 1st TLP");
        send_tlp(12'h011, 1'b1);
        wait_cycles(1);
        check(dllp_valid == 1'b0, 64'd6, "No ACK after 2nd TLP");
        send_tlp(12'h012, 1'b1);
        wait_cycles(1);
        check(dllp_valid == 1'b1,            64'd7,  "ACK on 3rd TLP");
        check(dllp_type  == 2'b01,           64'd8,  "dllp_type = ACK");
        check(ack_dllp[43:32] == 12'h012,    64'd9,  "ACK seq = last seq 0x012");
        wait_cycles(2);

        // ==================================================================
        // TEST 3: CRC Error ? immediate NAK
        // ==================================================================
        $display("\n=== TEST 3: CRC Error ? NAK emitted immediately ===");
        ack_freq = 8'd4;
        send_tlp(12'h020, 1'b0); // CRC fail
        wait_cycles(1);
        check(dllp_valid == 1'b1,         64'd10, "dllp_valid on CRC err");
        check(dllp_type  == 2'b10,        64'd11, "dllp_type = NAK");
        check(nak_dllp[43:32] == 12'h020, 64'd12, "NAK seq = 0x020");
        check(nak_dllp[63:56] == 8'h10,   64'd13, "NAK type byte 0x10");
        wait_cycles(2);

        // ==================================================================
        // TEST 4: ACK timer expiry forces pending ACK before threshold
        // ==================================================================
        $display("\n=== TEST 4: Timer expiry forces pending ACK ===");
        ack_freq = 8'd8;
        send_tlp(12'h030, 1'b1);  // pending but count=1 < 8
        wait_cycles(2);
        check(dllp_valid == 1'b0, 64'd14, "No ACK before timer");
        // Fire timer
        @(posedge clk);
        ack_timer_exp = 1'b1;
        @(posedge clk);
        ack_timer_exp = 1'b0;
        wait_cycles(1);
        check(dllp_valid == 1'b1,          64'd15, "ACK forced by timer");
        check(dllp_type  == 2'b01,         64'd16, "dllp_type = ACK");
        check(ack_dllp[43:32] == 12'h030,  64'd17, "ACK seq = 0x030");
        wait_cycles(2);

        // ==================================================================
        // TEST 5: Sequence wrap-around (12-bit, wraps at 0xFFF?0x000)
        // ==================================================================
        $display("\n=== TEST 5: Sequence wrap-around ===");
        ack_freq = 8'd1;
        send_tlp(12'hFFE, 1'b1);
        wait_cycles(1);
        check(ack_dllp[43:32] == 12'hFFE, 64'd18, "ACK seq = 0xFFE");
        send_tlp(12'hFFF, 1'b1);
        wait_cycles(1);
        check(ack_dllp[43:32] == 12'hFFF, 64'd19, "ACK seq = 0xFFF");
        send_tlp(12'h000, 1'b1);
        wait_cycles(1);
        check(ack_dllp[43:32] == 12'h000, 64'd20, "ACK seq wraps 0x000");
        wait_cycles(2);

        // ==================================================================
        // TEST 6: Reset clears all state
        // ==================================================================
        $display("\n=== TEST 6: Reset clears state ===");
        ack_freq = 8'd4;
        send_tlp(12'h100, 1'b1);
        send_tlp(12'h101, 1'b1);
        // Apply reset mid-stream
        @(posedge clk);
        rst_n = 1'b0;
        wait_cycles(2);
        rst_n = 1'b1;
        wait_cycles(2);
        check(dllp_valid == 1'b0, 64'd21, "No DLLP after reset");
        wait_cycles(2);

        // ==================================================================
        // Summary
        // ==================================================================
        $display("\n=================================================");
        $display("  RESULTS: %0d PASSED,  %0d FAILED", pass_count, fail_count);
        $display("=================================================\n");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED ? review waveform");

        $finish;
    end

endmodule
