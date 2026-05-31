
`timescale 1ns / 1ps

module tb_tlp_header_parser;

    reg          clk;
    reg          rst_n;

    reg  [1023:0] tlp_rx;
    reg           tlp_rx_valid;
    reg           tlp_rx_sop;

    wire [4:0]    tlp_type;
    wire [2:0]    tlp_fmt;
    wire [2:0]    tlp_tc;
    wire [2:0]    tlp_attr;
    wire [9:0]    tlp_len;
    wire [9:0]    tlp_tag;
    wire [15:0]   tlp_req_id;
    wire [63:0]   tlp_addr;
    wire          tlp_ep_bit;
    wire          tlp_td_bit;
    wire          parse_err;
    wire          parse_valid;

    tlp_header_parser dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .tlp_rx       (tlp_rx),
        .tlp_rx_valid (tlp_rx_valid),
        .tlp_rx_sop   (tlp_rx_sop),
        .tlp_type     (tlp_type),
        .tlp_fmt      (tlp_fmt),
        .tlp_tc       (tlp_tc),
        .tlp_attr     (tlp_attr),
        .tlp_len      (tlp_len),
        .tlp_tag      (tlp_tag),
        .tlp_req_id   (tlp_req_id),
        .tlp_addr     (tlp_addr),
        .tlp_ep_bit   (tlp_ep_bit),
        .tlp_td_bit   (tlp_td_bit),
        .parse_err    (parse_err),
        .parse_valid  (parse_valid)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    function [31:0] build_dw0;
        input [2:0] fmt;
        input [4:0] typ;
        input [2:0] tc;
        input       td;
        input       ep;
        input [2:0] attr;
        input [9:0] len;
        begin

            build_dw0 = { fmt,
                          typ,
                          1'b0,
                          tc,
                          1'b0,
                          attr[2],
                          1'b0,
                          1'b0,
                          td,
                          ep,
                          attr[1:0],
                          2'b00,
                          len
                        };
        end
    endfunction

    integer test_num;
    integer pass_count;
    integer fail_count;

    task drive_tlp;
        begin
            tlp_rx_valid = 1;
            tlp_rx_sop   = 1;
            @(posedge clk);
            #1;
            tlp_rx_valid = 0;
            tlp_rx_sop   = 0;
        end
    endtask

    initial begin
        $display("========================================");
        $display("  TB: TLP Header Parser");
        $display("========================================");

        pass_count = 0;
        fail_count = 0;

        rst_n        = 0;
        tlp_rx       = 1024'b0;
        tlp_rx_valid = 0;
        tlp_rx_sop   = 0;
        #20;
        rst_n = 1;
        #6;

        test_num = 1;
        $display("\nTest %0d: MRd 3DW, TC=1, Len=4, Addr=0xDEAD_BEE0", test_num);
        tlp_rx        = 1024'b0;

        tlp_rx[31:0]  = build_dw0(3'b000, 5'b00000, 3'b001,
                                   1'b0, 1'b0, 3'b000, 10'd4);

        tlp_rx[63:32] = {16'hABCD, 8'h42, 4'hF, 4'hF};

        tlp_rx[95:64] = 32'hDEADBEE0;

        drive_tlp;

        if (parse_valid && !parse_err &&
            tlp_fmt  == 3'b000     &&
            tlp_type == 5'b00000   &&
            tlp_tc   == 3'b001     &&
            tlp_len  == 10'd4      &&
            tlp_addr[31:0] == 32'hDEADBEE0) begin
            $display("  PASS: fmt=%b type=%b tc=%0d len=%0d addr=0x%08h",
                     tlp_fmt, tlp_type, tlp_tc, tlp_len, tlp_addr[31:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: valid=%b err=%b fmt=%b type=%b tc=%0d len=%0d addr=0x%08h",
                     parse_valid, parse_err, tlp_fmt, tlp_type,
                     tlp_tc, tlp_len, tlp_addr[31:0]);
            fail_count = fail_count + 1;
        end

        #10;

        test_num = 2;
        $display("\nTest %0d: MWr 4DW with Poisoned bit (EP=1)", test_num);
        tlp_rx        = 1024'b0;

        tlp_rx[31:0]  = build_dw0(3'b011, 5'b00000, 3'b000,
                                   1'b0, 1'b1, 3'b000, 10'd8);

        tlp_rx[63:32] = {16'h1234, 8'hAA, 4'hF, 4'hF};

        tlp_rx[95:64]  = 32'h0000_00FF;

        tlp_rx[127:96] = 32'hCAFE_BAB0;

        drive_tlp;

        if (parse_valid && !parse_err &&
            tlp_ep_bit  == 1'b1    &&
            tlp_fmt[0]  == 1'b1    &&
            tlp_fmt[1]  == 1'b1    &&
            tlp_type    == 5'b00000) begin
            $display("  PASS: 4DW + EP detected, fmt=%b ep=%b", tlp_fmt, tlp_ep_bit);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: valid=%b err=%b fmt=%b ep=%b type=%b",
                     parse_valid, parse_err, tlp_fmt, tlp_ep_bit, tlp_type);
            fail_count = fail_count + 1;
        end

        #10;

        test_num = 3;
        $display("\nTest %0d: Completion with Data (CplD), TD=1", test_num);
        tlp_rx        = 1024'b0;

        tlp_rx[31:0]  = build_dw0(3'b010, 5'b01010, 3'b000,
                                   1'b1, 1'b0, 3'b000, 10'd1);

        tlp_rx[63:32] = {16'h5678, 8'h10, 4'h0, 4'hF};

        tlp_rx[95:64] = 32'h0000_0000;

        drive_tlp;

        if (parse_valid && !parse_err &&
            tlp_type   == 5'b01010  &&
            tlp_fmt    == 3'b010    &&
            tlp_td_bit == 1'b1) begin
            $display("  PASS: CplD parsed, type=%b fmt=%b td=%b",
                     tlp_type, tlp_fmt, tlp_td_bit);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: valid=%b err=%b type=%b fmt=%b td=%b",
                     parse_valid, parse_err, tlp_type, tlp_fmt, tlp_td_bit);
            fail_count = fail_count + 1;
        end

        #20;

        $display("\n========================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
