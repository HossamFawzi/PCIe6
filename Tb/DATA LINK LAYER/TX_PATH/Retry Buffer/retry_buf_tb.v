
`timescale 1ns/1ps

module retry_buf_tb;

    localparam BUF_DEPTH = 16;
    localparam TLP_WIDTH = 1056;
    localparam PTR_W     = 4;

    reg                  clk;
    reg                  rst_n;
    reg  [TLP_WIDTH-1:0] tlp_in;
    reg                  tlp_write_en;
    reg  [11:0]          seq_num_in;
    reg  [11:0]          ack_seq;
    reg  [11:0]          nak_seq;
    reg                  retry_req;

    wire [TLP_WIDTH-1:0] retry_tlp;
    wire                 retry_valid;
    wire [11:0]          retry_seq;
    wire                 buf_full;
    wire [11:0]          buf_occ;
    wire                 purge_done;

    retry_buf #(
        .BUF_DEPTH (BUF_DEPTH),
        .TLP_WIDTH (TLP_WIDTH),
        .PTR_W     (PTR_W)
    ) uDUT (
        .clk         (clk),
        .rst_n       (rst_n),
        .tlp_in      (tlp_in),
        .tlp_write_en(tlp_write_en),
        .seq_num_in  (seq_num_in),
        .ack_seq     (ack_seq),
        .nak_seq     (nak_seq),
        .retry_req   (retry_req),
        .retry_tlp   (retry_tlp),
        .retry_valid (retry_valid),
        .retry_seq   (retry_seq),
        .buf_full    (buf_full),
        .buf_occ     (buf_occ),
        .purge_done  (purge_done)
    );

    initial clk = 0;
    always #0.5 clk = ~clk;

    integer pass_cnt;
    integer fail_cnt;
    integer loop_i;
    integer loop_j;
    integer loop_k;
    integer got_replay;
    integer got_wrap;

    task PASS;
        input [8*40-1:0] name;
        begin
            $display("PASS  %0s", name);
            pass_cnt = pass_cnt + 1;
        end
    endtask

    task FAIL;
        input [8*40-1:0] name;
        input [8*80-1:0] msg;
        begin
            $display("FAIL  %0s | %0s", name, msg);
            fail_cnt = fail_cnt + 1;
        end
    endtask

    task write_tlp;
        input [TLP_WIDTH-1:0] data;
        input [11:0]          seq;
        begin
            tlp_in       = data;
            seq_num_in   = seq;
            tlp_write_en = 1'b1;
            @(posedge clk); #0.1;
            tlp_write_en = 1'b0;
        end
    endtask

    task wait_clk;
        input integer n;
        integer tmp;
        begin
            for (tmp = 0; tmp < n; tmp = tmp + 1) begin
                @(posedge clk); #0.1;
            end
        end
    endtask

    initial begin
        $dumpfile("retry_buf_tb.vcd");
        $dumpvars(0, retry_buf_tb);

        pass_cnt     = 0;
        fail_cnt     = 0;
        rst_n        = 1'b0;
        tlp_in       = {TLP_WIDTH{1'b0}};
        tlp_write_en = 1'b0;
        seq_num_in   = 12'h000;
        ack_seq      = 12'hFFF;
        nak_seq      = 12'h000;
        retry_req    = 1'b0;
        wait_clk(2);

        if (buf_occ === 12'h0 && buf_full === 1'b0 &&
            retry_valid === 1'b0 && purge_done === 1'b0)
            PASS("TC1_RESET");
        else
            FAIL("TC1_RESET", "outputs not zeroed in reset");

        rst_n = 1'b1;
        wait_clk(1);

        write_tlp({16'hA5A5, {(TLP_WIDTH-16){1'b0}}}, 12'h001);
        wait_clk(1);
        if (buf_occ === 12'h1 && buf_full === 1'b0)
            PASS("TC2_WRITE_ONE");
        else
            FAIL("TC2_WRITE_ONE", "wrong buf_occ or buf_full");

        ack_seq = 12'h001;
        wait_clk(3);
        if (buf_occ === 12'h0)
            PASS("TC3_ACK_PURGE");
        else
            FAIL("TC3_ACK_PURGE", "buffer not purged after ACK");

        for (loop_i = 2; loop_i <= 6; loop_i = loop_i + 1)
          write_tlp({{(TLP_WIDTH-32){1'b0}}, loop_i}, loop_i & 12'hFFF);
        wait_clk(1);
        if (buf_occ === 12'h5)
            PASS("TC4_WRITE_5");
        else
            FAIL("TC4_WRITE_5", "wrong occ after 5 writes");

        ack_seq = 12'h006;
        wait_clk(8);
        if (buf_occ === 12'h0)
            PASS("TC4_PURGE_5");
        else
            FAIL("TC4_PURGE_5", "not all purged");

        ack_seq = 12'hFFF;
        for (loop_i = 0; loop_i < BUF_DEPTH-1; loop_i = loop_i + 1)
           write_tlp(loop_i[TLP_WIDTH-1:0], (loop_i + 7) & 12'hFFF);
        wait_clk(1);
        if (buf_full === 1'b1)
            PASS("TC5_BUF_FULL");
        else
            FAIL("TC5_BUF_FULL", "buf_full not asserted");

        ack_seq = 12'd21;
        wait_clk(18);

        write_tlp({16'hBAD1, {(TLP_WIDTH-16){1'b1}}}, 12'h016);
        write_tlp({16'hBAD2, {(TLP_WIDTH-16){1'b1}}}, 12'h017);
        write_tlp({16'hBAD3, {(TLP_WIDTH-16){1'b1}}}, 12'h018);
        wait_clk(1);

        nak_seq   = 12'h016;
        retry_req = 1'b1;
        @(posedge clk); #0.1;
        retry_req = 1'b0;

        got_replay = 0;
        for (loop_j = 0; loop_j < 10; loop_j = loop_j + 1) begin
            @(posedge clk); #0.1;
            if (retry_valid) got_replay = got_replay + 1;
        end
        if (got_replay === 3)
            PASS("TC6_REPLAY_COUNT");
        else begin
            $display("FAIL  TC6_REPLAY_COUNT | got=%0d exp=3", got_replay);
            fail_cnt = fail_cnt + 1;
        end

        wait_clk(2);

        ack_seq = 12'h018;
        wait_clk(5);
        write_tlp({16'h1111, {(TLP_WIDTH-16){1'b0}}}, 12'h019);
        write_tlp({16'h2222, {(TLP_WIDTH-16){1'b0}}}, 12'h01A);
        write_tlp({16'h3333, {(TLP_WIDTH-16){1'b0}}}, 12'h01B);
        write_tlp({16'h4444, {(TLP_WIDTH-16){1'b0}}}, 12'h01C);

        nak_seq   = 12'h019;
        retry_req = 1'b1;
        @(posedge clk); #0.1;
        retry_req = 1'b0;

        @(posedge clk); #0.1;
        @(posedge clk); #0.1;
        ack_seq = 12'h01A;
        wait_clk(6);

        PASS("TC7_ACK_DURING_REPLAY");

        ack_seq = 12'h01C;
        wait_clk(6);
        write_tlp({16'hFACE, {(TLP_WIDTH-16){1'b0}}}, 12'h01D);
        wait_clk(1);
        if (buf_occ === 12'h1)
            PASS("TC8_WRITE_AFTER_REPLAY");
        else
            FAIL("TC8_WRITE_AFTER_REPLAY", "buffer not reusable");

        ack_seq = 12'h01D;
        wait_clk(3);
        write_tlp({16'hFF01, {(TLP_WIDTH-16){1'b0}}}, 12'hFFE);
        write_tlp({16'hFF02, {(TLP_WIDTH-16){1'b0}}}, 12'hFFF);
        write_tlp({16'hFF03, {(TLP_WIDTH-16){1'b0}}}, 12'h000);
        wait_clk(1);

        nak_seq   = 12'hFFE;
        retry_req = 1'b1;
        @(posedge clk); #0.1;
        retry_req = 1'b0;

        got_wrap = 0;
        for (loop_k = 0; loop_k < 10; loop_k = loop_k + 1) begin
            @(posedge clk); #0.1;
            if (retry_valid) got_wrap = got_wrap + 1;
        end
        if (got_wrap === 3)
            PASS("TC9_SEQ_WRAP");
        else begin
            $display("FAIL  TC9_SEQ_WRAP | got=%0d exp=3", got_wrap);
            fail_cnt = fail_cnt + 1;
        end

        ack_seq = 12'h000;
        wait_clk(5);
        write_tlp({16'hC0DE, {(TLP_WIDTH-16){1'b0}}}, 12'h100);
        wait_clk(4);
        if (retry_valid === 1'b0)
            PASS("TC10_NO_SPURIOUS_REPLAY");
        else
            FAIL("TC10_NO_SPURIOUS_REPLAY", "retry_valid high without retry_req");

        #10;
        $display("--------------------------------------------");
        $display("  retry_buf TB: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
        $display("--------------------------------------------");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** FAILURES DETECTED ***");
        $finish;
    end

    initial begin
        #500000;
        $display("TIMEOUT — simulation ran too long");
        $finish;
    end

endmodule
