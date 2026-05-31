
`timescale 1ns/1ps

module tb_rx_det;

    reg        clk, rst_n;
    reg        detect_start;
    reg        pipe_rx_elec_idle;
    reg        pipe_phystatus;
    reg [15:0] detect_timeout_val;

    wire        receiver_detected;
    wire [15:0] lanes_det;
    wire        detect_done;
    wire        detect_timeout;

    rx_det dut (
        .clk                 (clk),
        .rst_n               (rst_n),
        .detect_start        (detect_start),
        .pipe_rx_elec_idle   (pipe_rx_elec_idle),
        .pipe_phystatus      (pipe_phystatus),
        .detect_timeout_val  (detect_timeout_val),
        .receiver_detected   (receiver_detected),
        .lanes_det           (lanes_det),
        .detect_done         (detect_done),
        .detect_timeout      (detect_timeout)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task start_det;
        begin
            @(posedge clk); #1; detect_start=1;
            @(posedge clk); #1; detect_start=0;
        end
    endtask

    task wait_done;
        begin
            repeat(100) begin
                @(posedge clk); #1;
                if (detect_done) disable wait_done;
            end
        end
    endtask

    initial begin
        rst_n=0; detect_start=0; pipe_rx_elec_idle=1;
        pipe_phystatus=0; detect_timeout_val=16'd50;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        pipe_rx_elec_idle = 0;
        start_det;
        repeat(5) @(posedge clk);

        @(posedge clk); #1; pipe_phystatus=1;
        @(posedge clk); #1; pipe_phystatus=0;
        wait_done;
        if (receiver_detected && detect_done && !detect_timeout) begin
            $display("PASS [TC1_receiver_detected]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC1_receiver_detected] det=%b done=%b to=%b", receiver_detected, detect_done, detect_timeout);
            fail_count=fail_count+1;
        end

        pipe_rx_elec_idle = 1;
        start_det;
        repeat(5) @(posedge clk);
        @(posedge clk); #1; pipe_phystatus=1;
        @(posedge clk); #1; pipe_phystatus=0;
        wait_done;
        if (!receiver_detected && detect_done && !detect_timeout && lanes_det===16'd0) begin
            $display("PASS [TC2_no_receiver]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC2_no_receiver] det=%b done=%b to=%b", receiver_detected, detect_done, detect_timeout);
            fail_count=fail_count+1;
        end

        begin : TC3
            integer saw_to; saw_to=0;
            detect_timeout_val = 16'd10;
            pipe_rx_elec_idle = 0;
            start_det;
            repeat(25) begin
                @(posedge clk); #1;
                if(detect_timeout && detect_done) saw_to=1;
            end
            if (saw_to) begin
                $display("PASS [TC3_timeout]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC3_timeout] never saw timeout pulse"); fail_count=fail_count+1;
            end
            detect_timeout_val = 16'd50;
        end

        begin : TC4
            integer cnt; cnt=0;
            pipe_rx_elec_idle=0;
            start_det;
            repeat(3) @(posedge clk);
            @(posedge clk); #1; pipe_phystatus=1;
            @(posedge clk); #1; pipe_phystatus=0;
            repeat(20) begin @(posedge clk); #1; if(detect_done) cnt=cnt+1; end
            if (cnt===1) begin $display("PASS [TC4_done_pulse]"); pass_count=pass_count+1; end
            else         begin $display("FAIL [TC4_done_pulse] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        pipe_rx_elec_idle=0; pipe_phystatus=1;
        @(posedge clk); #1; pipe_phystatus=0;
        repeat(5) @(posedge clk);
        if (!detect_done) begin
            $display("PASS [TC5_no_start_no_action]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC5_no_start_no_action]"); fail_count=fail_count+1;
        end

        pipe_rx_elec_idle=0;
        start_det;
        repeat(3) @(posedge clk);
        @(posedge clk); #1; pipe_phystatus=1;
        @(posedge clk); #1; pipe_phystatus=0;
        wait_done;
        if (lanes_det===16'hFFFF) begin
            $display("PASS [TC6_lanes_det]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC6_lanes_det] got=%h", lanes_det); fail_count=fail_count+1;
        end

        rst_n=0; repeat(3) @(posedge clk); #1;
        if (!receiver_detected && !detect_done && !detect_timeout && lanes_det===16'd0) begin
            $display("PASS [TC7_reset]"); pass_count=pass_count+1;
        end else begin
            $display("FAIL [TC7_reset]"); fail_count=fail_count+1;
        end
        rst_n=1;

        begin : TC8
            integer j;
            for (j=0; j<3; j=j+1) begin
                pipe_rx_elec_idle=0;
                start_det;
                repeat(3) @(posedge clk);
                @(posedge clk); #1; pipe_phystatus=1;
                @(posedge clk); #1; pipe_phystatus=0;
                wait_done;
            end
            $display("PASS [TC8_back_to_back]"); pass_count=pass_count+1;
        end

        #20;
        $display("===========================================");
        $display("  RX_DET Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #50000; $display("TIMEOUT"); $finish; end

endmodule
