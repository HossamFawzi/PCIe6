
`timescale 1ns/1ps

module tb_dllp_receiver_decoder;

    reg         clk;
    reg         rst_n;
    reg  [47:0] dllp_clean;
    reg         dllp_clean_valid;

    wire [ 7:0] fc_update_ph;
    wire [11:0] fc_update_pd;
    wire [ 7:0] fc_update_nph;
    wire [ 7:0] fc_update_cplh;
    wire [11:0] fc_update_cpld;
    wire        fc_update_valid;
    wire [ 2:0] pm_type;
    wire        pm_valid;
    wire [23:0] ack_out;
    wire        ack_out_valid;

    dllp_receiver_decoder DUT (
        .clk             (clk),
        .rst_n           (rst_n),
        .dllp_clean      (dllp_clean),
        .dllp_clean_valid(dllp_clean_valid),
        .fc_update_ph    (fc_update_ph),
        .fc_update_pd    (fc_update_pd),
        .fc_update_nph   (fc_update_nph),
        .fc_update_cplh  (fc_update_cplh),
        .fc_update_cpld  (fc_update_cpld),
        .fc_update_valid (fc_update_valid),
        .pm_type         (pm_type),
        .pm_valid        (pm_valid),
        .ack_out         (ack_out),
        .ack_out_valid   (ack_out_valid)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    function [47:0] make_fc_dllp;
        input [7:0]  dtype;
        input [7:0]  hfc;
        input [11:0] dfc;
        begin
            make_fc_dllp = {dtype,
                            2'b00,
                            hfc[7:2],
                            hfc[1:0],
                            dfc[11:6],
                            dfc[5:0],
                            6'h00,
                            8'h00};
        end
    endfunction

    function [47:0] make_ack_dllp;
        input [7:0]  dtype;
        input [11:0] seq;
        begin
            make_ack_dllp = {dtype,
                             4'h0,
                             4'h0,
                             seq,
                             4'h0,
                             12'h000};
        end
    endfunction

    function [47:0] make_pm_dllp;
        input [7:0] dtype;
        begin
            make_pm_dllp = {dtype, 40'h0};
        end
    endfunction

    task send_dllp;
        input [47:0] body;
        begin
            @(posedge clk);
            dllp_clean       = body;
            dllp_clean_valid = 1'b1;
            @(posedge clk);
            dllp_clean_valid = 1'b0;
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
        input        cond;
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
        $dumpfile("tb_dllp_receiver_decoder.vcd");
        $dumpvars(0, tb_dllp_receiver_decoder);

        rst_n            = 1'b0;
        dllp_clean       = 48'h0;
        dllp_clean_valid = 1'b0;

        wait_cycles(4);
        rst_n = 1'b1;
        wait_cycles(2);

        $display("\n=== TEST 1: ACK DLLP decode ===");
        send_dllp(make_ack_dllp(8'h00, 12'hABC));
        wait_cycles(1);
        check(ack_out_valid   == 1'b1,      "ack_out_valid=1 on ACK");
        check(ack_out[23:16]  == 8'h00,     "ack_out type byte = 0x00 (ACK)");
        check(fc_update_valid == 1'b0,      "fc_update_valid=0 on ACK");
        check(pm_valid        == 1'b0,      "pm_valid=0 on ACK");
        wait_cycles(2);

        $display("\n=== TEST 2: NAK DLLP decode ===");
        send_dllp(make_ack_dllp(8'h10, 12'h123));
        wait_cycles(1);
        check(ack_out_valid   == 1'b1,      "ack_out_valid=1 on NAK");
        check(ack_out[23:16]  == 8'h01,     "ack_out type=0x01 (NAK flag)");
        check(fc_update_valid == 1'b0,      "fc_update_valid=0 on NAK");
        wait_cycles(2);

        $display("\n=== TEST 3: UpdateFC Posted ===");

        send_dllp(make_fc_dllp(8'h40, 8'd64, 12'd128));
        wait_cycles(1);
        check(fc_update_valid == 1'b1,      "fc_update_valid=1 on UPD_FC_P");
        check(ack_out_valid   == 1'b0,      "ack_out_valid=0 on FC");
        check(pm_valid        == 1'b0,      "pm_valid=0 on FC");
        wait_cycles(2);

        $display("\n=== TEST 4: UpdateFC Non-Posted ===");
        send_dllp(make_fc_dllp(8'h50, 8'd32, 12'd0));
        wait_cycles(1);
        check(fc_update_valid == 1'b1,      "fc_update_valid=1 on UPD_FC_NP");
        wait_cycles(2);

        $display("\n=== TEST 5: UpdateFC Completion ===");
        send_dllp(make_fc_dllp(8'h60, 8'd16, 12'd256));
        wait_cycles(1);
        check(fc_update_valid == 1'b1,      "fc_update_valid=1 on UPD_FC_CPL");
        wait_cycles(2);

        $display("\n=== TEST 6: PM Enter L1 ===");
        send_dllp(make_pm_dllp(8'h20));
        wait_cycles(1);
        check(pm_valid        == 1'b1,      "pm_valid=1 on PM_L1");
        check(pm_type         == 3'd0,      "pm_type=0 (L1)");
        check(fc_update_valid == 1'b0,      "fc_update_valid=0 on PM");
        check(ack_out_valid   == 1'b0,      "ack_out_valid=0 on PM");
        wait_cycles(2);

        $display("\n=== TEST 7: PM Enter L23 ===");
        send_dllp(make_pm_dllp(8'h21));
        wait_cycles(1);
        check(pm_valid == 1'b1,             "pm_valid=1 on PM_L23");
        check(pm_type  == 3'd1,             "pm_type=1 (L23)");
        wait_cycles(2);

        $display("\n=== TEST 8: NOP ? no output ===");
        send_dllp({8'hC8, 40'h0});
        wait_cycles(1);
        check(fc_update_valid == 1'b0,      "fc_update_valid=0 on NOP");
        check(pm_valid        == 1'b0,      "pm_valid=0 on NOP");
        check(ack_out_valid   == 1'b0,      "ack_out_valid=0 on NOP");
        wait_cycles(2);

        $display("\n=== TEST 9: Back-to-back DLLPs ===");
        @(posedge clk);
        dllp_clean       = make_ack_dllp(8'h00, 12'h001);
        dllp_clean_valid = 1'b1;
        @(posedge clk);
        dllp_clean       = make_fc_dllp(8'h40, 8'd10, 12'd20);

        @(posedge clk);
        dllp_clean_valid = 1'b0;
        wait_cycles(1);
        check(fc_update_valid == 1'b1,      "FC valid on 2nd back-to-back DLLP");
        wait_cycles(2);

        $display("\n=== TEST 10: Reset clears outputs ===");
        rst_n = 1'b0;
        wait_cycles(2);
        rst_n = 1'b1;
        wait_cycles(1);
        check(fc_update_valid == 1'b0,      "fc_update_valid=0 after reset");
        check(pm_valid        == 1'b0,      "pm_valid=0 after reset");
        check(ack_out_valid   == 1'b0,      "ack_out_valid=0 after reset");
        wait_cycles(2);

        $display("\n=================================================");
        $display("  RESULTS: %0d PASSED,  %0d FAILED", pass_count, fail_count);
        $display("=================================================\n");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else                 $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
