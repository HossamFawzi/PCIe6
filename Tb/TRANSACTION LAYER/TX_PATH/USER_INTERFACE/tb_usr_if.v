`timescale 1ns / 1ps

module tb_usr_if;

    parameter CLK_PERIOD = 10;

    reg          clk;
    reg          rst_n;

    reg  [3:0]   req_type;
    reg  [63:0]  req_addr;
    reg  [9:0]   req_len;
    reg  [511:0] req_data;
    reg          req_valid;
    reg  [2:0]   req_attr;
    reg  [2:0]   req_tc;
    reg  [3:0]   req_first_be;
    reg  [3:0]   req_last_be;
    wire         req_ready;

    wire [603:0] pkt_out;
    wire         pkt_valid;
    reg          pkt_ready;

    reg  [511:0] cpl_data;
    reg          cpl_valid;
    reg  [2:0]   cpl_status;
    reg  [9:0]   cpl_tag;

    wire [511:0] usr_cpl_data;
    wire         usr_cpl_valid;
    wire [2:0]   usr_cpl_status;
    wire [9:0]   usr_cpl_tag;

    reg  [511:0] mwr_data;
    reg          mwr_valid;
    reg  [63:0]  mwr_addr;

    wire [511:0] usr_mwr_data;
    wire         usr_mwr_valid;
    wire [63:0]  usr_mwr_addr;

    usr_if dut (
        .clk(clk),
        .rst_n(rst_n),

        .req_type(req_type),
        .req_addr(req_addr),
        .req_len(req_len),
        .req_data(req_data),
        .req_valid(req_valid),
        .req_attr(req_attr),
        .req_tc(req_tc),
        .req_first_be(req_first_be),
        .req_last_be(req_last_be),
        .req_ready(req_ready),

        .pkt_out(pkt_out),
        .pkt_valid(pkt_valid),
        .pkt_ready(pkt_ready),

        .cpl_data(cpl_data),
        .cpl_valid(cpl_valid),
        .cpl_status(cpl_status),
        .cpl_tag(cpl_tag),
        .usr_cpl_data(usr_cpl_data),
        .usr_cpl_valid(usr_cpl_valid),
        .usr_cpl_status(usr_cpl_status),
        .usr_cpl_tag(usr_cpl_tag),

        .mwr_data(mwr_data),
        .mwr_valid(mwr_valid),
        .mwr_addr(mwr_addr),
        .usr_mwr_data(usr_mwr_data),
        .usr_mwr_valid(usr_mwr_valid),
        .usr_mwr_addr(usr_mwr_addr)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass = 0;
    integer fail = 0;
    integer test_id = 0;

    task check;
        input boolean_cond;
        input [80*8:1] test_name;
    begin
        test_id = test_id + 1;
        if (boolean_cond) begin
            $display("[PASS] T%0d: %0s", test_id, test_name);
            pass = pass + 1;
        end else begin
            $display("[FAIL] T%0d: %0s", test_id, test_name);
            fail = fail + 1;
        end
    end
    endtask

    task reset_dut;
    begin
        rst_n = 0;
        req_type = 0; req_addr = 0; req_len = 0; req_data = 0; req_valid = 0;
        req_attr = 0; req_tc = 0; req_first_be = 0; req_last_be = 0;
        pkt_ready = 0;
        cpl_data = 0; cpl_valid = 0; cpl_status = 0; cpl_tag = 0;
        mwr_data = 0; mwr_valid = 0; mwr_addr = 0;

        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    end
    endtask

    initial begin
        $display("==== TB usr_if START ====");
        reset_dut();

        req_type     = 4'hA;
        req_addr     = 64'h1122_3344_5566_7788;
        req_len      = 10'h2AA;
        req_attr     = 3'h5;
        req_tc       = 3'h7;
        req_first_be = 4'hF;
        req_last_be  = 4'h1;
        req_data     = {16{32'hDEAD_BEEF}};

        #1;

        check(
            pkt_out[603:600] == req_type     &&
            pkt_out[599:536] == req_addr     &&
            pkt_out[535:526] == req_len      &&
            pkt_out[525:523] == req_attr     &&
            pkt_out[522:520] == req_tc       &&
            pkt_out[519:516] == req_first_be &&
            pkt_out[515:512] == req_last_be  &&
            pkt_out[511:0]   == req_data,
            "Static Packet Packing Alignment"
        );

        req_valid = 1'b1;
        pkt_ready = 1'b0;
        #1;
        check(pkt_valid == 1'b1 && req_ready == 1'b0, "Handshake: req_valid pass-through");

        req_valid = 1'b0;
        pkt_ready = 1'b1;
        #1;
        check(pkt_valid == 1'b0 && req_ready == 1'b1, "Handshake: pkt_ready pass-through");

        cpl_data   = {16{32'hCAFE_BABE}};
        cpl_valid  = 1'b1;
        cpl_status = 3'h3;
        cpl_tag    = 10'h1FF;
        #1;
        check(
            usr_cpl_data   == cpl_data   &&
            usr_cpl_valid  == cpl_valid  &&
            usr_cpl_status == cpl_status &&
            usr_cpl_tag    == cpl_tag,
            "CPL Return Path Pass-through"
        );

        mwr_data  = {16{32'hFACE_FEED}};
        mwr_valid = 1'b1;
        mwr_addr  = 64'h9988_7766_5544_3322;
        #1;
        check(
            usr_mwr_data  == mwr_data  &&
            usr_mwr_valid == mwr_valid &&
            usr_mwr_addr  == mwr_addr,
            "MWR Return Path Pass-through"
        );

        repeat(10) begin
            @(posedge clk);

            req_type     = {$random} % 6;
            req_len      = ({$random} % 1023) + 1;

            req_addr     = {{$random}, {$random}};
            req_attr     = {$random} % 8;
            req_tc       = {$random} % 8;
            req_first_be = {$random} % 16;
            req_last_be  = {$random} % 16;
            req_data     = {16{$random}};

            #1;
            if (
                pkt_out[603:600] !== req_type     ||
                pkt_out[599:536] !== req_addr     ||
                pkt_out[535:526] !== req_len      ||
                pkt_out[525:523] !== req_attr     ||
                pkt_out[522:520] !== req_tc       ||
                pkt_out[519:516] !== req_first_be ||
                pkt_out[515:512] !== req_last_be  ||
                pkt_out[511:0]   !== req_data
            ) begin
                $display("[FAIL] Random Stress Packing Mismatch");
                fail = fail + 1;
            end
        end

        check(1, "Random Stress Packing Constraints");

        #20;
        $display("=================================");
        $display("==== RESULTS: PASS=%0d FAIL=%0d ====", pass, fail);
        $display("=================================");
        $finish;
    end

endmodule
