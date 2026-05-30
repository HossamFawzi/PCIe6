// ============================================================
// Testbench for Module 52 (53) : Power State Timer L0s/L1
// ============================================================
`timescale 1ns/1ps

module tb_pwr_tmr;

    reg        clk, rst_n;
    reg        l0s_entry_req, l1_entry_req;
    reg        l0s_exit_req,  l1_exit_req;
    reg [11:0] l0s_entry_limit;
    reg [15:0] l1_entry_limit;

    wire       l0s_entry_timer_exp, l1_entry_timer_exp;
    wire       l0s_exit_timer_exp,  l1_exit_timer_exp;

    pwr_tmr dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .l0s_entry_req       (l0s_entry_req),
        .l1_entry_req        (l1_entry_req),
        .l0s_exit_req        (l0s_exit_req),
        .l1_exit_req         (l1_exit_req),
        .l0s_entry_limit     (l0s_entry_limit),
        .l1_entry_limit      (l1_entry_limit),
        .l0s_entry_timer_exp (l0s_entry_timer_exp),
        .l1_entry_timer_exp  (l1_entry_timer_exp),
        .l0s_exit_timer_exp  (l0s_exit_timer_exp),
        .l1_exit_timer_exp   (l1_exit_timer_exp)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        rst_n=0;
        l0s_entry_req=0; l1_entry_req=0;
        l0s_exit_req=0;  l1_exit_req=0;
        l0s_entry_limit=12'd5;
        l1_entry_limit=16'd10;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        // TC1: L0s entry timer expires
        @(posedge clk); #1; l0s_entry_req=1;
        @(posedge clk); #1; l0s_entry_req=0;
        begin : TC1
            integer cnt; cnt=0;
            repeat(30) begin @(posedge clk); #1; if(l0s_entry_timer_exp) cnt=cnt+1; end
            if (cnt===1) begin $display("PASS [TC1_l0s_entry_exp]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC1_l0s_entry_exp] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        // TC2: L0s entry expires after correct delay
        l0s_entry_limit=12'd8;
        @(posedge clk); #1; l0s_entry_req=1;
        @(posedge clk); #1; l0s_entry_req=0;
        begin : TC2
            integer cyc;
            integer found;
            cyc=0; found=0;
            repeat(30) begin
                @(posedge clk); #1;
                cyc=cyc+1;
                if (l0s_entry_timer_exp && !found) begin
                    found=1;
                    if (cyc >= 8 && cyc <= 12) begin
                        $display("PASS [TC2_l0s_delay] cyc=%0d", cyc); pass_count=pass_count+1;
                    end else begin
                        $display("FAIL [TC2_l0s_delay] cyc=%0d", cyc); fail_count=fail_count+1;
                    end
                end
            end
            if (!found) begin $display("FAIL [TC2_l0s_delay] never expired"); fail_count=fail_count+1; end
        end

        // TC3: L1 entry timer expires
        @(posedge clk); #1; l1_entry_req=1;
        @(posedge clk); #1; l1_entry_req=0;
        begin : TC3
            integer cnt; cnt=0;
            repeat(30) begin @(posedge clk); #1; if(l1_entry_timer_exp) cnt=cnt+1; end
            if (cnt===1) begin $display("PASS [TC3_l1_entry_exp]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC3_l1_entry_exp] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        // TC4: L0s exit timer expires (fixed ~4 cycles)
        @(posedge clk); #1; l0s_exit_req=1;
        @(posedge clk); #1; l0s_exit_req=0;
        begin : TC4
            integer cnt; cnt=0;
            repeat(20) begin @(posedge clk); #1; if(l0s_exit_timer_exp) cnt=cnt+1; end
            if (cnt===1) begin $display("PASS [TC4_l0s_exit_exp]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC4_l0s_exit_exp] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        // TC5: L1 exit timer expires (fixed ~8 cycles)
        @(posedge clk); #1; l1_exit_req=1;
        @(posedge clk); #1; l1_exit_req=0;
        begin : TC5
            integer cnt; cnt=0;
            repeat(30) begin @(posedge clk); #1; if(l1_exit_timer_exp) cnt=cnt+1; end
            if (cnt===1) begin $display("PASS [TC5_l1_exit_exp]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC5_l1_exit_exp] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        // TC6: L0s entry cancelled by exit_req
        l0s_entry_limit=12'd20;
        @(posedge clk); #1; l0s_entry_req=1;
        @(posedge clk); #1; l0s_entry_req=0;
        repeat(3) @(posedge clk);
        @(posedge clk); #1; l0s_exit_req=1;
        @(posedge clk); #1; l0s_exit_req=0;
        begin : TC6
            integer cnt; cnt=0;
            repeat(30) begin @(posedge clk); #1; if(l0s_entry_timer_exp) cnt=cnt+1; end
            if (cnt===0) begin $display("PASS [TC6_l0s_cancel]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC6_l0s_cancel] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        // TC7: L1 entry cancelled by l1_exit_req
        l1_entry_limit=16'd20;
        @(posedge clk); #1; l1_entry_req=1;
        @(posedge clk); #1; l1_entry_req=0;
        repeat(3) @(posedge clk);
        @(posedge clk); #1; l1_exit_req=1;
        @(posedge clk); #1; l1_exit_req=0;
        begin : TC7
            integer cnt; cnt=0;
            repeat(30) begin @(posedge clk); #1; if(l1_entry_timer_exp) cnt=cnt+1; end
            if (cnt===0) begin $display("PASS [TC7_l1_cancel]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC7_l1_cancel] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        // TC8: All timers pulse only once per request
        l0s_entry_limit=12'd4; l1_entry_limit=16'd6;
        @(posedge clk); #1;
        l0s_entry_req=1; l1_entry_req=1;
        @(posedge clk); #1;
        l0s_entry_req=0; l1_entry_req=0;
        begin : TC8
            integer c0; integer c1; c0=0; c1=0;
            repeat(40) begin
                @(posedge clk); #1;
                if (l0s_entry_timer_exp) c0=c0+1;
                if (l1_entry_timer_exp)  c1=c1+1;
            end
            if (c0===1 && c1===1) begin $display("PASS [TC8_once_each]"); pass_count=pass_count+1; end
            else begin $display("FAIL [TC8_once_each] c0=%0d c1=%0d",c0,c1); fail_count=fail_count+1; end
        end

        // TC9: Reset clears all
        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!l0s_entry_timer_exp && !l1_entry_timer_exp &&
            !l0s_exit_timer_exp  && !l1_exit_timer_exp) begin
            $display("PASS [TC9_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC9_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        #20;
        $display("===========================================");
        $display("  PWR_TMR Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
