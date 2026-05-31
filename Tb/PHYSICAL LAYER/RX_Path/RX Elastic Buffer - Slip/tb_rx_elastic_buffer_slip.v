`timescale 1ns/1ps
module tb_rx_elastic_buffer_slip;

    localparam DW    = 256;
    localparam DEPTH = 32;
    localparam AW    = 5;

    reg               clk_pipe, clk_core, rst_n;
    reg  [DW-1:0]     data_in;
    reg               data_valid;
    reg               slip_req;
    reg               pipe_ready;
    wire [DW-1:0]     data_out;
    wire              data_out_valid;
    wire              buf_empty, buf_full;
    wire              slip_done;
    wire [AW:0]       fill_level;
    wire              buf_center;

    integer pass=0, fail=0;

    rx_elastic_buffer_slip #(.DATA_WIDTH(DW), .DEPTH(DEPTH), .ADDR_W(AW)) dut(
        .clk_pipe(clk_pipe), .rst_n(rst_n),
        .data_in(data_in), .data_valid(data_valid), .slip_req(slip_req),
        .clk_core(clk_core), .pipe_ready(pipe_ready),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .buf_empty(buf_empty), .buf_full(buf_full),
        .slip_done(slip_done), .fill_level(fill_level), .buf_center(buf_center)
    );

    always #5  clk_pipe = ~clk_pipe;
    always #7  clk_core = ~clk_core;

    task tick_pipe; input integer n; integer i; begin for(i=0;i<n;i=i+1) @(posedge clk_pipe); #1; end endtask
    task tick_core; input integer n; integer i; begin for(i=0;i<n;i=i+1) @(posedge clk_core); #1; end endtask

    task write_one; input [DW-1:0] d;
        begin
            @(posedge clk_pipe); #1; data_in=d; data_valid=1;
            @(posedge clk_pipe); #1; data_valid=0;
        end
    endtask

    task read_one; output reg [DW-1:0] got; output reg valid;
        begin
            @(posedge clk_core); #1; pipe_ready=1;
            @(posedge clk_core); #1; pipe_ready=0;
            got   = data_out;
            valid = data_out_valid;
            tick_core(2);
        end
    endtask

    reg [DW-1:0] rdata;
    reg rvalid;

    initial begin
        clk_pipe=0; clk_core=0; rst_n=0;
        data_in=0; data_valid=0; slip_req=0; pipe_ready=0;
        tick_pipe(4); rst_n=1;
        tick_pipe(4); tick_core(4);

        $display("Test 1: Initially empty");
        if (buf_empty) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: Not empty"); fail=fail+1; end

        $display("Test 2: Basic write and read");
        write_one(256'hCAFEBABE_12345678);
        tick_core(12);
        read_one(rdata, rvalid);
        if (rvalid && rdata==256'hCAFEBABE_12345678) begin
            $display("PASS"); pass=pass+1;
        end else begin
            $display("FAIL: valid=%b data=%h", rvalid, rdata[63:0]); fail=fail+1;
        end

        $display("Test 3: Slip operation");
        rst_n=0; tick_pipe(3); rst_n=1; tick_pipe(3); tick_core(3);
        write_one(256'hDEAD_0001);
        write_one(256'hBEEF_0002);
        tick_core(16);

        @(posedge clk_core); #1; slip_req=1;
        tick_core(8);
        @(posedge clk_core); #1; slip_req=0;
        tick_core(6);

        read_one(rdata, rvalid);
        if (rvalid && rdata==256'hBEEF_0002) begin
            $display("PASS: Second entry after slip"); pass=pass+1;
        end else if (rvalid && rdata==256'hDEAD_0001) begin
            $display("FAIL: Got first entry (slip had no effect)"); fail=fail+1;
        end else begin
            $display("FAIL: valid=%b data=%h", rvalid, rdata[63:0]); fail=fail+1;
        end

        $display("Test 4: Fill level tracking");
        begin : fl
            integer i;
            rst_n=0; tick_pipe(3); rst_n=1; tick_pipe(3); tick_core(3);
            for (i=0; i<8; i=i+1) write_one(i * 256'h1 + 256'hABCD);
            tick_core(20);
            if (!buf_empty && fill_level > 0) begin
                $display("PASS: fill=%0d", fill_level); pass=pass+1;
            end else begin
                $display("FAIL: fill=%0d empty=%b", fill_level, buf_empty); fail=fail+1;
            end
        end

        $display("Test 5: Buffer full detection");
        begin : full
            integer i;
            rst_n=0; tick_pipe(3); rst_n=1; tick_pipe(3); tick_core(3);
            for (i=0; i<DEPTH; i=i+1) write_one(i * 256'h1 + 256'h1);
            tick_pipe(5);
            if (buf_full) begin $display("PASS"); pass=pass+1; end
            else begin $display("FAIL: buf_full not set (fill=%0d)", fill_level); fail=fail+1; end
        end

        $display("Test 6: Reset");
        rst_n=0; tick_pipe(3);
        if (buf_empty && !data_out_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL"); fail=fail+1; end
        rst_n=1;

        $display("Test 7: buf_center at half fill");
        begin : ctr
            integer i;
            tick_pipe(3); tick_core(3);
            for (i=0; i<DEPTH/2; i=i+1) write_one(256'h1);
            tick_core(25);
            if (buf_center) begin $display("PASS: center at fill=%0d", fill_level); pass=pass+1; end
            else begin $display("FAIL: center=%b fill=%0d", buf_center, fill_level); fail=fail+1; end
        end

        $display("Test 8: slip_done pulse");
        begin : sd
            reg got_done;
            integer i;
            rst_n=0; tick_core(3); rst_n=1;
            write_one(256'hAAAA);
            tick_core(15);
            got_done=0;
            @(posedge clk_core); #1; slip_req=1;
            for (i=0; i<15; i=i+1) begin
                @(posedge clk_core); #1;
                if (slip_done) got_done=1;
            end
            slip_req=0;
            tick_core(5);
            if (got_done) begin $display("PASS: slip_done seen"); pass=pass+1; end
            else begin $display("FAIL: slip_done not seen"); fail=fail+1; end
        end

        $display("\n=== rx_elastic_buffer_slip: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #500000 begin $display("TIMEOUT"); $finish; end
endmodule
