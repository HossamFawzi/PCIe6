`timescale 1ns/1ps
module tb_tx_elastic_buffer;

    localparam DW = 256;
    localparam DEPTH = 16;
    localparam AW = 4;

    reg                clk_core, clk_pipe, rst_n;
    reg  [DW-1:0]      data_in;
    reg                data_valid;
    reg                skp_insert_req;
    reg                pipe_ready;
    reg                skp_remove_req;
    wire [DW-1:0]      data_out;
    wire               data_out_valid;
    wire               buf_full, buf_empty, buf_half;
    wire               skp_inserted, skp_removed;
    wire [AW:0]        fill_level;

    integer pass=0, fail=0;

    tx_elastic_buffer #(.DATA_WIDTH(DW), .DEPTH(DEPTH), .ADDR_W(AW)) dut(
        .clk_core(clk_core), .rst_n(rst_n),
        .data_in(data_in), .data_valid(data_valid),
        .skp_insert_req(skp_insert_req),
        .clk_pipe(clk_pipe), .pipe_ready(pipe_ready),
        .skp_remove_req(skp_remove_req),
        .data_out(data_out), .data_out_valid(data_out_valid),
        .buf_full(buf_full), .buf_empty(buf_empty), .buf_half(buf_half),
        .skp_inserted(skp_inserted), .skp_removed(skp_removed),
        .fill_level(fill_level)
    );

    always #5  clk_core = ~clk_core;
    always #6  clk_pipe = ~clk_pipe;

    task tick_core; input integer n; integer i; begin for(i=0;i<n;i=i+1) @(posedge clk_core); #1; end endtask
    task tick_pipe; input integer n; integer i; begin for(i=0;i<n;i=i+1) @(posedge clk_pipe); #1; end endtask

    initial begin
        clk_core=0; clk_pipe=0; rst_n=0;
        data_in=0; data_valid=0; skp_insert_req=0;
        pipe_ready=0; skp_remove_req=0;
        tick_core(4); rst_n=1; tick_core(2);

        $display("Test 1: Initially empty");
        if (buf_empty) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: Not empty at start"); fail=fail+1; end

        $display("Test 2: Write one entry");
        @(posedge clk_core); #1;
        data_in = 256'hDEAD_BEEF; data_valid=1;
        @(posedge clk_core); #1; data_valid=0;
        tick_core(6);
        if (!buf_empty) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: Still empty after write"); fail=fail+1; end

        $display("Test 3: Read one entry - data_out_valid");
        tick_pipe(6);
        @(posedge clk_pipe); #1;
        pipe_ready=1;
        @(posedge clk_pipe); #1;
        if (data_out_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: data_out_valid not seen"); fail=fail+1; end
        pipe_ready=0;

        $display("Test 4: Fill buffer half");
        begin : fill
            integer i;
            for (i=0; i<DEPTH/2; i=i+1) begin
                @(posedge clk_core); #1;
                data_in = i * 256'h1 + 256'h1111; data_valid=1;
                @(posedge clk_core); #1; data_valid=0;
            end
            tick_core(10);
            if (!buf_empty) begin $display("PASS: Buffer has data"); pass=pass+1; end
            else begin $display("FAIL: Buffer empty after fills"); fail=fail+1; end
        end

        $display("Test 5: SKP insert");
        begin : skip
            reg was_ins;
            was_ins=0;
            @(posedge clk_core); #1; skp_insert_req=1;
            @(posedge clk_core); #1;
            if (skp_inserted) was_ins=1;
            skp_insert_req=0;
            tick_core(2);
            if (skp_inserted) was_ins=1;
            if (was_ins) begin $display("PASS"); pass=pass+1; end
            else begin $display("FAIL: skp_inserted never seen"); fail=fail+1; end
        end

        $display("Test 6: Reset");
        rst_n=0; tick_core(3);
        if (buf_empty && !data_out_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: Reset incomplete"); fail=fail+1; end
        rst_n=1; tick_core(2);

        $display("Test 7: Data integrity");
        begin : integ
            reg [255:0] test_data;
            integer found;
            test_data = 256'hFEEDFACE_CAFEBABE_DEADBEEF_12345678;
            @(posedge clk_core); #1;
            data_in=test_data; data_valid=1;
            @(posedge clk_core); #1; data_valid=0;
            tick_pipe(10);
            found=0;
            begin : search
                integer i;
                for (i=0; i<20; i=i+1) begin
                    @(posedge clk_pipe); #1;
                    pipe_ready=1;
                    @(posedge clk_pipe); #1;
                    pipe_ready=0;
                    if (data_out_valid && data_out==test_data) found=1;
                    tick_pipe(2);
                end
            end
            if (found) begin $display("PASS: Data integrity preserved"); pass=pass+1; end
            else begin $display("FAIL: Data not found after 20 reads"); fail=fail+1; end
        end

        $display("Test 8: Buffer empty after drain");
        rst_n=0; tick_core(2); rst_n=1; tick_core(2);
        @(posedge clk_core); #1; data_in=256'h1; data_valid=1;
        @(posedge clk_core); #1; data_valid=0;
        tick_pipe(10);
        @(posedge clk_pipe); #1; pipe_ready=1;
        @(posedge clk_pipe); #1; pipe_ready=0;
        tick_core(15);
        if (buf_empty) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: Buffer not empty after drain"); fail=fail+1; end

        $display("\n=== tx_elastic_buffer: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #100000 begin $display("TIMEOUT"); $finish; end
endmodule
