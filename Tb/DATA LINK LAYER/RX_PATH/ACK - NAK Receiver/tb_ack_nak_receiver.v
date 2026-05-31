
`timescale 1ns/1ps

module tb_ack_nak_receiver;

    reg         clk;
    reg         rst_n;
    reg  [23:0] ack_out;
    reg         ack_out_valid;

    wire [11:0] ack_seq;
    wire [11:0] nak_seq;
    wire        ack_valid;
    wire        nak_valid;
    wire        retry_req;

    ack_nak_receiver DUT (
        .clk          (clk),
        .rst_n        (rst_n),
        .ack_out      (ack_out),
        .ack_out_valid(ack_out_valid),
        .ack_seq      (ack_seq),
        .nak_seq      (nak_seq),
        .ack_valid    (ack_valid),
        .nak_valid    (nak_valid),
        .retry_req    (retry_req)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    task send_ack;
        input [11:0] seq;
        begin
            @(posedge clk);
            ack_out       = {8'h00, seq, 4'h0};
            ack_out_valid = 1'b1;
            @(posedge clk);
            ack_out_valid = 1'b0;
        end
    endtask

    task send_nak;
        input [11:0] seq;
        begin
            @(posedge clk);
            ack_out       = {8'h01, seq, 4'h0};
            ack_out_valid = 1'b1;
            @(posedge clk);
            ack_out_valid = 1'b0;
        end
    endtask

    task wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input cond;
        input [200*8-1:0] msg;
        begin
            if (cond) begin
                $display("  [PASS] %0s", msg);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] %0s", msg);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_ack_nak_receiver.vcd");
        $dumpvars(0, tb_ack_nak_receiver);

        rst_n         = 1'b0;
        ack_out       = 24'h0;
        ack_out_valid = 1'b0;

        wait_cycles(4);
        rst_n = 1'b1;
        wait_cycles(2);

        $display("\n=== TEST 1: ACK decode + oldest_unacked advance ===");
        send_ack(12'h005);
        wait_cycles(1);
        check(ack_valid == 1'b1,        "ack_valid=1");
        check(ack_seq   == 12'h005,     "ack_seq=0x005");
        check(nak_valid == 1'b0,        "nak_valid=0");
        check(retry_req == 1'b0,        "retry_req=0");
        wait_cycles(2);

        $display("\n=== TEST 2: Second ACK advances window ===");
        send_ack(12'h010);
        wait_cycles(1);
        check(ack_valid == 1'b1,        "ack_valid=1 on 2nd ACK");
        check(ack_seq   == 12'h010,     "ack_seq=0x010");
        wait_cycles(2);

        $display("\n=== TEST 3: NAK decode + retry_req ===");
        send_nak(12'h011);
        wait_cycles(1);
        check(nak_valid == 1'b1,        "nak_valid=1");
        check(nak_seq   == 12'h011,     "nak_seq=0x011");
        check(retry_req == 1'b1,        "retry_req=1");
        check(ack_valid == 1'b0,        "ack_valid=0 on NAK");
        wait_cycles(2);

        check(retry_req == 1'b0,        "retry_req clears after 1 cycle");

        $display("\n=== TEST 4: Out-of-window ACK discarded ===");

        @(posedge clk);
        ack_out       = {8'h00, 12'hD00, 4'h0};
        ack_out_valid = 1'b1;
        @(posedge clk);
        ack_out_valid = 1'b0;
        wait_cycles(1);
        check(ack_valid == 1'b0,        "ack_valid=0 (out-of-window discarded)");
        check(nak_valid == 1'b0,        "nak_valid=0 on out-of-window");
        wait_cycles(2);

        $display("\n=== TEST 5: Wrap-around at seq 0xFFF ===");

        send_ack(12'hFFD);
        wait_cycles(1);
        check(ack_seq == 12'hFFD,       "ACK 0xFFD ok");
        send_ack(12'hFFE);
        wait_cycles(1);
        check(ack_seq == 12'hFFE,       "ACK 0xFFE ok");
        send_ack(12'hFFF);
        wait_cycles(1);
        check(ack_seq == 12'hFFF,       "ACK 0xFFF ok");

        send_ack(12'h000);
        wait_cycles(1);
        check(ack_seq == 12'h000,       "ACK wraps to 0x000");
        wait_cycles(2);

        $display("\n=== TEST 6: Back-to-back ACK then NAK ===");
        @(posedge clk);
        ack_out       = {8'h00, 12'h020, 4'h0};
        ack_out_valid = 1'b1;
        @(posedge clk);
        ack_out       = {8'h01, 12'h021, 4'h0};

        @(posedge clk);
        ack_out_valid = 1'b0;
        wait_cycles(1);
        check(nak_valid == 1'b1,        "nak_valid on 2nd back-to-back");
        check(nak_seq   == 12'h021,     "nak_seq=0x021");
        wait_cycles(2);

        $display("\n=== TEST 7: Reset clears all state ===");
        rst_n = 1'b0;
        wait_cycles(3);
        rst_n = 1'b1;
        wait_cycles(1);
        check(ack_valid == 1'b0,        "ack_valid=0 after reset");
        check(nak_valid == 1'b0,        "nak_valid=0 after reset");
        check(retry_req == 1'b0,        "retry_req=0 after reset");
        check(ack_seq   == 12'h000,     "ack_seq=0 after reset");
        check(nak_seq   == 12'h000,     "nak_seq=0 after reset");
        wait_cycles(2);

        $display("\n=================================================");
        $display("  RESULTS: %0d PASSED,  %0d FAILED", pass_count, fail_count);
        $display("=================================================\n");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
