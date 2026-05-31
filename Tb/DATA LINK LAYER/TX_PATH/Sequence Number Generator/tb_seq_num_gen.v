
`timescale 1ns/1ps
module tb_seq_num_gen;

    reg clk = 0;
    always #5 clk = ~clk;

    reg rst_n = 0;
    task do_reset;
        begin rst_n=0; repeat(6)@(posedge clk); rst_n=1; @(posedge clk); end
    endtask

    integer pass_cnt; integer fail_cnt;
    initial begin pass_cnt=0; fail_cnt=0; end

    task chk;
        input [200*8-1:0] label;
        input ok;
        begin
            if(ok) begin $display("[PASS] %0s",label); pass_cnt=pass_cnt+1; end
            else   begin $display("[FAIL] %0s",label); fail_cnt=fail_cnt+1; end
        end
    endtask

    reg        tlp_valid_in = 0;
    reg [11:0] ack_seq=0, nak_seq=0;
    reg        retry_req=0, link_reset=0;

    wire [11:0] seq_num;
    wire        seq_valid, seq_wrap;

    seq_num_gen dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_valid_in(tlp_valid_in),
        .ack_seq(ack_seq), .nak_seq(nak_seq),
        .retry_req(retry_req), .link_reset(link_reset),
        .seq_num(seq_num), .seq_valid(seq_valid), .seq_wrap(seq_wrap)
    );

    task calibrate;
        reg [11:0] s0, s1, s2;
        begin
            do_reset;

            @(posedge clk); tlp_valid_in=1;
            @(posedge clk); tlp_valid_in=0; @(negedge clk); s0=seq_num;
            @(posedge clk);

            @(posedge clk); tlp_valid_in=1;
            @(posedge clk); tlp_valid_in=0; @(negedge clk); s1=seq_num;
            @(posedge clk);

            @(posedge clk); tlp_valid_in=1;
            @(posedge clk); tlp_valid_in=0; @(negedge clk); s2=seq_num;
            @(posedge clk);
            $display("[CALIBRATE] seq0=%0d seq1=%0d seq2=%0d (expect 0 1 2)",s0,s1,s2);
            if(s0===12'd0 && s1===12'd1 && s2===12'd2)
                $display("[CALIBRATE] Strategy OK: read hold value after deassert");
            else begin
                $display("[CALIBRATE] WARNING: unexpected values - check RTL");
            end
            do_reset;
        end
    endtask

    reg [11:0] last_seq;
    task dispatch_one;
        begin
            @(posedge clk); tlp_valid_in=1;
            @(posedge clk); tlp_valid_in=0;
            @(negedge clk); last_seq=seq_num;
            @(posedge clk);
        end
    endtask

    task dispatch_n;
        input integer n;
        integer j;
        begin for(j=0;j<n;j=j+1) dispatch_one; end
    endtask

    integer i, n, found;
    reg [11:0] cap[0:7];
    reg [11:0] prev_seq;

    initial begin
        $dumpfile("tb_seq_num_gen.vcd");
        $dumpvars(0, tb_seq_num_gen);

        $display("=================================================");
        $display(" tb_seq_num_gen - Sequence Number Gen Unit Tests");
        $display("=================================================");

        calibrate;

        $display("\n[T1] Reset state");
        rst_n=0; repeat(2)@(posedge clk); @(negedge clk);
        chk("T1a: seq_num=0 in reset",   seq_num   === 12'd0);
        chk("T1b: seq_valid=0 in reset", seq_valid === 1'b0);
        chk("T1c: seq_wrap=0 in reset",  seq_wrap  === 1'b0);
        do_reset;

        $display("\n[T2] First dispatch assigns seq=0");
        do_reset; dispatch_one;
        chk("T2a: seq=0 on first dispatch",      last_seq  === 12'd0);

        $display("\n[T3] Monotonic advance seq 0..7");
        do_reset;
        for(i=0;i<8;i=i+1) begin dispatch_one; cap[i]=last_seq; end
        chk("T3a: seq[0]=0", cap[0]===12'd0);
        chk("T3b: seq[1]=1", cap[1]===12'd1);
        chk("T3c: seq[2]=2", cap[2]===12'd2);
        chk("T3d: seq[3]=3", cap[3]===12'd3);
        chk("T3e: seq[4]=4", cap[4]===12'd4);
        chk("T3f: seq[5]=5", cap[5]===12'd5);
        chk("T3g: seq[6]=6", cap[6]===12'd6);
        chk("T3h: seq[7]=7", cap[7]===12'd7);

        $display("\n[T4] seq_valid=0 when idle");
        do_reset; repeat(3)@(posedge clk); @(negedge clk);
        chk("T4a: seq_valid=0 during idle", seq_valid===1'b0);
        chk("T4b: seq_wrap=0 during idle",  seq_wrap ===1'b0);

        $display("\n[T5] seq_num stable when no dispatch");
        do_reset; dispatch_n(5);
        repeat(10)@(posedge clk); @(negedge clk);
        chk("T5a: seq_valid=0 after 10 idle cycles", seq_valid===1'b0);

        $display("\n[T6] Synchronous link_reset");
        do_reset; dispatch_n(10);
        @(posedge clk); link_reset=1;
        @(posedge clk); link_reset=0; @(negedge clk);
        chk("T6a: seq_num=0 after link_reset",   seq_num  ===12'd0);
        chk("T6b: seq_valid=0 after link_reset",  seq_valid===1'b0);
        dispatch_one;
        chk("T6c: first dispatch after reset=0",  last_seq ===12'd0);

        $display("\n[T7] Async rst_n clears counter");
        do_reset; dispatch_n(50); do_reset; @(negedge clk);
        chk("T7a: seq_num=0 after rst_n", seq_num===12'd0);
        dispatch_one;
        chk("T7b: resumes from 0",         last_seq===12'd0);

        $display("\n[T8] seq_wrap fires at 4095->0 rollover");
        do_reset; found=0;
        fork
            begin : drive8
                forever begin
                    @(posedge clk); tlp_valid_in=1;
                    @(posedge clk); tlp_valid_in=0;
                    @(posedge clk);
                end
            end
            begin : watch8
                @(posedge seq_wrap); found=1; disable drive8;
            end
        join
        tlp_valid_in=0; @(negedge clk);
        chk("T8a: seq_wrap pulse observed", found   ===1);
        chk("T8b: seq_wrap=1 when seen",    seq_wrap===1'b1);

        $display("\n[T9] seq_wrap de-asserts after 1 cycle");
        @(posedge clk); @(negedge clk);
        chk("T9a: seq_wrap=0 next cycle", seq_wrap===1'b0);

        $display("\n[T10] Normal increment after wrap");
        dispatch_one; chk("T10a: seq=0 after wrap", last_seq===12'd0);
        dispatch_one; chk("T10b: seq=1",             last_seq===12'd1);
        dispatch_one; chk("T10c: seq=2",             last_seq===12'd2);

        $display("\n[T11] NAK retry: replay from nak_seq=3");
        do_reset; dispatch_n(6);
        @(posedge clk); nak_seq=12'd3; retry_req=1;
        @(posedge clk); retry_req=0; @(posedge clk);
        dispatch_one; chk("T11a: replay seq=3", last_seq===12'd3);
        dispatch_one; chk("T11b: replay seq=4", last_seq===12'd4);
        dispatch_one; chk("T11c: replay seq=5", last_seq===12'd5);

        $display("\n[T12] NAK replay from seq=0");
        do_reset; dispatch_n(4);
        @(posedge clk); nak_seq=12'd0; retry_req=1;
        @(posedge clk); retry_req=0; @(posedge clk);
        dispatch_one; chk("T12a: replay from seq=0", last_seq===12'd0);

        $display("\n[T13] link_reset during retry cancels replay");
        do_reset; dispatch_n(5);
        @(posedge clk); nak_seq=12'd1; retry_req=1;
        @(posedge clk); retry_req=0; link_reset=1;
        @(posedge clk); link_reset=0; @(negedge clk);
        dispatch_one;
        chk("T13a: seq=0 after link_reset cancels retry", last_seq===12'd0);

        $display("\n[T14] 4 consecutive dispatches");
        do_reset;
        dispatch_one; chk("T14a: seq=0", last_seq===12'd0);
        dispatch_one; chk("T14b: seq=1", last_seq===12'd1);
        dispatch_one; chk("T14c: seq=2", last_seq===12'd2);
        dispatch_one; chk("T14d: seq=3", last_seq===12'd3);

        $display("\n[T15] retry on fresh device (nak_seq=0)");
        do_reset;
        @(posedge clk); nak_seq=12'd0; retry_req=1;
        @(posedge clk); retry_req=0; @(posedge clk);
        dispatch_one; chk("T15a: replay assigns seq=0", last_seq===12'd0);

        $display("\n[T16] Each dispatch increments by exactly 1");
        do_reset;
        dispatch_one; prev_seq=last_seq;
        dispatch_one; chk("T16a: delta=1 (0->1)", last_seq===prev_seq+12'd1);
        prev_seq=last_seq;
        dispatch_one; chk("T16b: delta=1 (1->2)", last_seq===prev_seq+12'd1);
        prev_seq=last_seq;
        dispatch_one; chk("T16c: delta=1 (2->3)", last_seq===prev_seq+12'd1);

        $display("\n[T17] 20-dispatch monotonic batch");
        do_reset;
        begin : t17blk
            integer k;
            reg [11:0] expected;
            reg ok17;
            ok17=1;
            for(k=0; k<20; k=k+1) begin
                dispatch_one;
                expected=k;
                if(last_seq!==expected) ok17=0;
            end
            chk("T17a: all 20 dispatches monotonic 0..19", ok17===1);
        end

        $display("");
        $display("=================================================");
        $display(" RESULTS: %0d PASSED  /  %0d FAILED", pass_cnt, fail_cnt);
        if(fail_cnt==0) $display(" ALL TESTS PASSED");
        else            $display(" FAILURES -- inspect tb_seq_num_gen.vcd");
        $display("=================================================");
        $finish;
    end

    initial begin #10000000; $display("[WATCHDOG]"); $finish; end
endmodule