
`timescale 1ns/1ps

module tb_hot_rst;

    reg       clk, rst_n;
    reg       ts1_hot_reset_bit, hot_reset_req_sw, ts1_detected;
    reg [5:0] ltssm_state;

    wire      hot_reset_active, send_ts1_hot_reset, hot_reset_done, pipe_reset_out;

    hot_rst dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .ts1_hot_reset_bit (ts1_hot_reset_bit),
        .hot_reset_req_sw  (hot_reset_req_sw),
        .ts1_detected      (ts1_detected),
        .ltssm_state       (ltssm_state),
        .hot_reset_active  (hot_reset_active),
        .send_ts1_hot_reset(send_ts1_hot_reset),
        .hot_reset_done    (hot_reset_done),
        .pipe_reset_out    (pipe_reset_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task send_ts1_with_hr;
        input do_hr;
        begin
            @(posedge clk); #1;
            ts1_detected     = 1;
            ts1_hot_reset_bit= do_hr;
            @(posedge clk); #1;
            ts1_detected     = 0;
            ts1_hot_reset_bit= 0;
        end
    endtask

    task wait_done;
        begin
            repeat(50) begin
                @(posedge clk); #1;
                if (hot_reset_done) disable wait_done;
            end
        end
    endtask

    initial begin
        rst_n=0; ts1_hot_reset_bit=0; hot_reset_req_sw=0;
        ts1_detected=0; ltssm_state=6'd0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        send_ts1_with_hr(1);
        send_ts1_with_hr(1);
        wait_done;
        if (hot_reset_done) begin
            $display("PASS [TC1_two_ts1_hr]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC1_two_ts1_hr]"); fail_count=fail_count+1;
        end

        send_ts1_with_hr(1);
        repeat(5) @(posedge clk);
        send_ts1_with_hr(0);
        repeat(10) @(posedge clk);
        if (!hot_reset_done && !hot_reset_active) begin
            $display("PASS [TC2_one_ts1_no_rst]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC2_one_ts1_no_rst] active=%b done=%b", hot_reset_active, hot_reset_done);
            fail_count=fail_count+1;
        end

        @(posedge clk); #1; hot_reset_req_sw=1;
        @(posedge clk); #1; hot_reset_req_sw=0;
        wait_done;
        if (hot_reset_done) begin
            $display("PASS [TC3_sw_hot_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC3_sw_hot_reset]"); fail_count=fail_count+1;
        end

        begin : TC4
            integer seen; seen=0;
            send_ts1_with_hr(1);
            send_ts1_with_hr(1);
            repeat(20) begin @(posedge clk); #1; if(pipe_reset_out) seen=seen+1; end
            wait_done;
            if (seen > 0) begin $display("PASS [TC4_pipe_reset]"); pass_count=pass_count+1; end
            else          begin $display("FAIL [TC4_pipe_reset]"); fail_count=fail_count+1; end
        end

        begin : TC5
            integer seen; seen=0;
            send_ts1_with_hr(1);
            send_ts1_with_hr(1);
            repeat(20) begin @(posedge clk); #1; if(send_ts1_hot_reset) seen=seen+1; end
            wait_done;
            if (seen > 0) begin $display("PASS [TC5_send_ts1_hr]"); pass_count=pass_count+1; end
            else          begin $display("FAIL [TC5_send_ts1_hr]"); fail_count=fail_count+1; end
        end

        begin : TC6
            integer cnt; cnt=0;
            send_ts1_with_hr(1);
            send_ts1_with_hr(1);
            repeat(50) begin @(posedge clk); #1; if(hot_reset_done) cnt=cnt+1; end
            if (cnt===1) begin $display("PASS [TC6_done_pulse]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC6_done_pulse] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!hot_reset_active && !send_ts1_hot_reset && !pipe_reset_out) begin
            $display("PASS [TC7_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC7_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        send_ts1_with_hr(0);
        send_ts1_with_hr(0);
        repeat(10) @(posedge clk);
        if (!hot_reset_active && !hot_reset_done) begin
            $display("PASS [TC8_no_hr_no_rst]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC8_no_hr_no_rst]"); fail_count=fail_count+1;
        end

        #20;
        $display("===========================================");
        $display("  HOT_RST Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #20000; $display("TIMEOUT"); $finish; end

endmodule
