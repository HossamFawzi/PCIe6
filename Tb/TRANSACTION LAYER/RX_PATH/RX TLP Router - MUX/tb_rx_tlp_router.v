
`timescale 1ns / 1ps

module tb_rx_tlp_router;

    reg          clk, rst_n;
    reg  [4:0]   tlp_type;
    reg          tlp_fwd_valid;
    reg  [1023:0] tlp_rx;
    reg          ecrc_ok;

    wire         to_cpl_valid;
    wire         to_mwr_valid;
    wire         to_cfg_valid;
    wire         to_msg_valid;
    wire         to_atomic_valid;
    wire [1023:0] routed_tlp;

    rx_tlp_router dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_type(tlp_type), .tlp_fwd_valid(tlp_fwd_valid),
        .tlp_rx(tlp_rx), .ecrc_ok(ecrc_ok),
        .to_cpl_valid(to_cpl_valid), .to_mwr_valid(to_mwr_valid),
        .to_cfg_valid(to_cfg_valid), .to_msg_valid(to_msg_valid),
        .to_atomic_valid(to_atomic_valid),
        .routed_tlp(routed_tlp)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    integer pass_count, fail_count;

    task send_and_check;
        input [4:0]   t_type;
        input         t_ecrc;
        input         exp_cpl, exp_mwr, exp_cfg, exp_msg, exp_atomic;
        input [127:0] label;
        begin

            tlp_type      = t_type;
            tlp_fwd_valid = 1;
            ecrc_ok       = t_ecrc;
            tlp_rx        = {1024{1'b1}};

            @(posedge clk); #1;

            if (to_cpl_valid == exp_cpl && to_mwr_valid == exp_mwr &&
                to_cfg_valid == exp_cfg && to_msg_valid == exp_msg &&
                to_atomic_valid == exp_atomic) begin
                $display("  PASS: %0s", label);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %0s (cpl=%b mwr=%b cfg=%b msg=%b atm=%b)",
                         label, to_cpl_valid, to_mwr_valid,
                         to_cfg_valid, to_msg_valid, to_atomic_valid);
                fail_count = fail_count + 1;
            end

            tlp_fwd_valid = 0;
            @(posedge clk); #1;
            #4;
        end
    endtask

    initial begin
        $display("========================================");
        $display("  TB: RX TLP Router / MUX");
        $display("========================================");

        pass_count = 0; fail_count = 0;
        rst_n = 0; tlp_type = 0; tlp_fwd_valid = 0;
        tlp_rx = 0; ecrc_ok = 0;
        #20; rst_n = 1; #10;

        send_and_check(5'b01010, 1, 1, 0, 0, 0, 0, "Completion");
        send_and_check(5'b00000, 1, 0, 1, 0, 0, 0, "Memory (MWr)");
        send_and_check(5'b00100, 1, 0, 0, 1, 0, 0, "Config Type 0");
        send_and_check(5'b00101, 1, 0, 0, 1, 0, 0, "Config Type 1");
        send_and_check(5'b00010, 1, 0, 0, 1, 0, 0, "IO Request");
        send_and_check(5'b10001, 1, 0, 0, 0, 1, 0, "Message");
        send_and_check(5'b10100, 1, 0, 0, 0, 1, 0, "Message (sub)");
        send_and_check(5'b01100, 1, 0, 0, 0, 0, 1, "AtomicOp FAdd");
        send_and_check(5'b01101, 1, 0, 0, 0, 0, 1, "AtomicOp Swap");
        send_and_check(5'b01110, 1, 0, 0, 0, 0, 1, "AtomicOp CAS");

        send_and_check(5'b01010, 0, 0, 0, 0, 0, 0, "Cpl ECRC fail");

        send_and_check(5'b11111, 1, 0, 0, 0, 0, 0, "Unknown type");

        #20;
        $display("\n========================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
