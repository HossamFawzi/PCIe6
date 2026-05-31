`timescale 1ns / 1ps

module tb_pcie_completion_handler;

    parameter CLK_PERIOD = 4;

    reg          clk, rst_n;
    reg [1023:0] tlp_cpl;
    reg          tlp_cpl_valid;
    reg  [9:0]   outstanding_tag;
    reg  [9:0]   expected_len;

    wire [511:0] cpl_data;
    wire         cpl_valid;
    wire [9:0]   cpl_tag;
    wire [2:0]   cpl_status;
    wire         cpl_match_err;
    wire [9:0]   tag_return;
    wire         tag_return_valid;
    wire         cr_return_cplh;
    wire [3:0]   cr_return_cpld;

    pcie_completion_handler dut (.*);

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0, test_num = 0;

    task apply_reset;
        begin
            rst_n = 1'b0;
            tlp_cpl = 0; tlp_cpl_valid = 0;
            repeat(5) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task send_cpl;
        input [9:0]   tag;
        input [2:0]   status;
        input [9:0]   length;
        input [11:0]  bc;
        input [511:0] data;
        begin
            tlp_cpl = 1024'd0;
            tlp_cpl[31:29]  = 3'b010;
            tlp_cpl[28:24]  = 5'b01010;
            tlp_cpl[9:0]    = length;
            tlp_cpl[47:45]  = status;
            tlp_cpl[43:32]  = bc;
            tlp_cpl[79:70]  = tag;
            tlp_cpl[607:96] = data;

            tlp_cpl_valid = 1'b1;
            @(posedge clk);
            tlp_cpl_valid = 1'b0;
        end
    endtask

    task check;
        input         exp_cpl_valid;
        input         exp_match_err;
        input [9:0]   exp_tag;
        input [2:0]   exp_status;
        input [511:0] exp_data;
        input [799:0] test_id;
        begin

            @(posedge clk);
            #1;
            test_num = test_num + 1;

            if (cpl_valid     === exp_cpl_valid &&
                cpl_match_err === exp_match_err &&
                cpl_tag       === exp_tag       &&
                cpl_status    === exp_status    &&
                (exp_cpl_valid ? (cpl_data === exp_data) : 1'b1)) begin
                $display("[PASS] T%02d: %0s", test_num, test_id);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] T%02d: %0s", test_num, test_id);
                $display("       GOT: vld=%b err=%b tag=%0d stat=%0b", cpl_valid, cpl_match_err, cpl_tag, cpl_status);
                $display("       EXP: vld=%b err=%b tag=%0d stat=%0b", exp_cpl_valid, exp_match_err, exp_tag, exp_status);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        apply_reset();

        outstanding_tag = 42; expected_len = 4;
        fork
            send_cpl(42, 3'b000, 4, 16, 512'hDEADBEEF);
            check(1'b1, 1'b0, 42, 3'b000, 512'hDEADBEEF, "Tag Match Successful");
        join

        outstanding_tag = 100;
        fork
            send_cpl(55, 3'b000, 2, 8, 512'hCAFE);
            check(1'b0, 1'b1, 55, 3'b000, 0, "Tag Mismatch Detected");
        join

        outstanding_tag = 7;
        fork
            send_cpl(7, 3'b001, 0, 0, 0);
            check(1'b1, 1'b0, 7, 3'b001, 0, "Unsupported Request Status");
        join

        #50;
        $display("Final Results: %0d PASS, %0d FAIL", pass_cnt, fail_cnt);
        $finish;
    end
endmodule