
`timescale 1ns/1ps
module tb_vc_arbiter;

    reg        clk = 0;
    always #5 clk = ~clk;
    reg        rst_n;
    reg        vc0_req, vc1_req, vc2_req, vc3_req;
    reg [1:0]  vc_arb_scheme;
    reg [31:0] vc_weight;

    wire [3:0] vc_grant;
    wire [2:0] vc_grant_id;
    wire       vc_arb_valid;

    vc_arbiter dut (
        .clk(clk),.rst_n(rst_n),
        .vc0_req(vc0_req),.vc1_req(vc1_req),
        .vc2_req(vc2_req),.vc3_req(vc3_req),
        .vc_arb_scheme(vc_arb_scheme),.vc_weight(vc_weight),
        .vc_grant(vc_grant),.vc_grant_id(vc_grant_id),
        .vc_arb_valid(vc_arb_valid)
    );

    integer pass_count=0, fail_count=0;

    task chk1(input got, input exp, input [127:0] name);
        if (got===exp) begin $display("  PASS  %0s",name); pass_count=pass_count+1; end
        else begin $display("  FAIL  %0s  got=%0b exp=%0b",name,got,exp); fail_count=fail_count+1; end
    endtask

    task chkN(input [2:0] got, input [2:0] exp, input [127:0] name);
        if (got===exp) begin $display("  PASS  %0s=%0d",name,got); pass_count=pass_count+1; end
        else begin $display("  FAIL  %0s  got=%0d exp=%0d",name,got,exp); fail_count=fail_count+1; end
    endtask

    task do_reset;
        begin
            rst_n=0; vc0_req=0; vc1_req=0; vc2_req=0; vc3_req=0;
            vc_arb_scheme=2'b00; vc_weight=32'h0101_0101;
            repeat(4) @(posedge clk); rst_n=1; @(posedge clk);
        end
    endtask

    task set_reqs(input r0, input r1, input r2, input r3);
        begin
            @(negedge clk);
            vc0_req=r0; vc1_req=r1; vc2_req=r2; vc3_req=r3;
        end
    endtask

    integer vc0_cnt, vc1_cnt;
    integer k;

    initial begin
        $display("=== vc_arbiter Testbench ===");

        $display("\n[T1] RR: only VC0 requesting");
        do_reset;
        set_reqs(1,0,0,0);
        @(posedge clk); #1;
        chkN(vc_grant_id, 3'd0, "vc_grant_id=0");
        chk1(vc_arb_valid, 1'b1, "vc_arb_valid=1");
        set_reqs(0,0,0,0);

        $display("\n[T2] RR: only VC1");
        do_reset;
        set_reqs(0,1,0,0);
        @(posedge clk); #1;
        chkN(vc_grant_id, 3'd1, "vc_grant_id=1");
        set_reqs(0,0,0,0);

        $display("\n[T3] RR: VC0+VC2 alternate");
        do_reset;
        vc_arb_scheme=2'b00;
        set_reqs(1,0,1,0);
        begin : T3_BLK
            integer prev;
            integer alt_ok;
            integer seen;
            prev=99; alt_ok=1; seen=0;
            for (k=0; k<6; k=k+1) begin
                @(posedge clk); #1;
                if (vc_arb_valid) begin
                    $display("  grant[%0d]=VC%0d", k, vc_grant_id);
                    if (seen && vc_grant_id==prev) alt_ok=0;
                    prev=vc_grant_id; seen=1;
                end
            end
            chk1(alt_ok, 1'b1, "grants alternate");
        end
        set_reqs(0,0,0,0);

        $display("\n[T4] RR: all 4 VCs cycle 0→1→2→3");
        do_reset;
        vc_arb_scheme=2'b00;
        set_reqs(1,1,1,1);
        begin : T4_BLK
            integer grant_log [0:7];
            integer idx;
            integer cycle_ok;
            for (k=0; k<8; k=k+1) begin
                @(posedge clk); #1;
                if (vc_arb_valid) begin
                    grant_log[k]=vc_grant_id;
                    $display("  grant[%0d]=VC%0d", k, vc_grant_id);
                end
            end

            cycle_ok=1;
            for (idx=0; idx<4; idx=idx+1) begin
                if (grant_log[idx] !== idx[2:0]) cycle_ok=0;
            end
            chk1(cycle_ok, 1'b1, "RR cycle 0-1-2-3");
        end
        set_reqs(0,0,0,0);

        $display("\n[T5] WRR: VC0 w=4, VC1 w=1");
        do_reset;
        vc_arb_scheme=2'b01;
        vc_weight=32'h0000_0104;
        set_reqs(1,1,0,0);
        vc0_cnt=0; vc1_cnt=0;
        for (k=0; k<10; k=k+1) begin
            @(posedge clk); #1;
            if (vc_arb_valid) begin
                $display("  grant[%0d]=VC%0d", k, vc_grant_id);
                if (vc_grant_id==3'd0) vc0_cnt=vc0_cnt+1;
                if (vc_grant_id==3'd1) vc1_cnt=vc1_cnt+1;
            end
        end
        if (vc0_cnt>vc1_cnt) begin
            $display("  PASS  WRR VC0(%0d)>VC1(%0d)", vc0_cnt, vc1_cnt);
            pass_count=pass_count+1;
        end else begin
            $display("  FAIL  WRR VC0(%0d) not > VC1(%0d)", vc0_cnt, vc1_cnt);
            fail_count=fail_count+1;
        end
        set_reqs(0,0,0,0);

        $display("\n[T6] No requests → idle");
        do_reset;
        @(posedge clk); #1;
        chk1(vc_arb_valid, 1'b0, "vc_arb_valid=0");

        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================");
        if (fail_count==0) $display("ALL TESTS PASSED");
        else               $display("SOME TESTS FAILED");
        $finish;
    end
endmodule
