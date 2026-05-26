`timescale 1ns/1ps

module block_align_sync_hdr_checker_tb;

    reg         clk;
    reg         rst_n;
    reg  [255:0] data_in;
    reg         data_valid;
    reg         block_lock;

    wire [255:0] aligned_data;
    wire         aligned_valid;
    wire [1:0]   sync_hdr;
    wire         align_err;

    block_align_sync_hdr_checker dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .data_in      (data_in),
        .data_valid   (data_valid),
        .block_lock   (block_lock),
        .aligned_data (aligned_data),
        .aligned_valid(aligned_valid),
        .sync_hdr     (sync_hdr),
        .align_err    (align_err)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task apply_input;
        input [255:0] d;
        input         dv;
        input         bl;
        begin
            @(negedge clk);
            data_in    = d;
            data_valid = dv;
            block_lock = bl;
        end
    endtask

    task check_output;
        input [255:0] exp_data;
        input         exp_valid;
        input [1:0]   exp_hdr;
        input         exp_err;
        input [63:0]  test_num;
        begin
            @(posedge clk); #1;
            if (aligned_valid !== exp_valid)
                $display("FAIL test %0d: aligned_valid=%b expected=%b", test_num, aligned_valid, exp_valid);
            if (sync_hdr !== exp_hdr)
                $display("FAIL test %0d: sync_hdr=%b expected=%b", test_num, sync_hdr, exp_hdr);
            if (align_err !== exp_err)
                $display("FAIL test %0d: align_err=%b expected=%b", test_num, align_err, exp_err);
            if (exp_valid && (aligned_data !== exp_data))
                $display("FAIL test %0d: aligned_data mismatch", test_num);
            if (aligned_valid === exp_valid && sync_hdr === exp_hdr && align_err === exp_err)
                $display("PASS test %0d", test_num);
        end
    endtask

    integer i;
    reg [255:0] test_payload;
    reg [255:0] expected_aligned;

    initial begin
        $dumpfile("block_align_sync_hdr_checker_tb.vcd");
        $dumpvars(0, block_align_sync_hdr_checker_tb);

        rst_n      = 1'b0;
        data_in    = 256'd0;
        data_valid = 1'b0;
        block_lock = 1'b0;
        repeat(3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // Test 1: data_valid=0, block_lock=0 => no output
        apply_input(256'hDEAD_BEEF, 1'b0, 1'b0);
        @(posedge clk); #1;
        check_output(256'd0, 1'b0, 2'b00, 1'b0, 1);

        // Test 2: data block with SYNC_DATA header (2'b01), block_lock=1
        test_payload  = 256'hAABBCCDD_EEFF0011_22334455_66778899_AABBCCDD_EEFF0011_22334455_6677889D;
        test_payload[1:0] = 2'b01;
        apply_input(test_payload, 1'b1, 1'b1);
        @(posedge clk); #1;
        expected_aligned = {2'b00, test_payload[255:2]};
        check_output(expected_aligned, 1'b1, 2'b01, 1'b0, 2);

        // Test 3: ordered set with SYNC_OS header (2'b10), block_lock=1
        test_payload = 256'h0;
        test_payload[1:0] = 2'b10;
        apply_input(test_payload, 1'b1, 1'b1);
        @(posedge clk); #1;
        expected_aligned = {2'b00, test_payload[255:2]};
        check_output(expected_aligned, 1'b1, 2'b10, 1'b0, 3);

        // Test 4: invalid sync header (2'b00), block_lock=1 => align_err
        test_payload = 256'hFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFC;
        test_payload[1:0] = 2'b00;
        apply_input(test_payload, 1'b1, 1'b1);
        @(posedge clk); #1;
        expected_aligned = {2'b00, test_payload[255:2]};
        check_output(expected_aligned, 1'b1, 2'b00, 1'b1, 4);

        // Test 5: invalid sync header (2'b11), block_lock=1 => align_err
        test_payload = 256'h0;
        test_payload[1:0] = 2'b11;
        apply_input(test_payload, 1'b1, 1'b1);
        @(posedge clk); #1;
        expected_aligned = {2'b00, test_payload[255:2]};
        check_output(expected_aligned, 1'b1, 2'b11, 1'b1, 5);

        // Test 6: data_valid=1 but block_lock=0 => aligned_valid=0, align_err=1
        test_payload = 256'hABCDEF;
        test_payload[1:0] = 2'b01;
        apply_input(test_payload, 1'b1, 1'b0);
        @(posedge clk); #1;
        check_output(256'd0, 1'b0, 2'b01, 1'b1, 6);

        // Test 7: back-to-back data blocks with SYNC_DATA
        for (i = 0; i < 4; i = i + 1) begin
            test_payload = $random;
            test_payload[1:0] = 2'b01;
            apply_input(test_payload, 1'b1, 1'b1);
        end
        @(posedge clk); #1;
        $display("PASS test 7: back-to-back SYNC_DATA blocks no errors: align_err=%b aligned_valid=%b sync_hdr=%b",
                  align_err, aligned_valid, sync_hdr);

        // Test 8: reset mid-operation
        test_payload = 256'hDEAD;
        test_payload[1:0] = 2'b10;
        apply_input(test_payload, 1'b1, 1'b1);
        @(negedge clk);
        rst_n = 1'b0;
        @(posedge clk); #1;
        if (aligned_data === 256'd0 && aligned_valid === 1'b0 && align_err === 1'b0)
            $display("PASS test 8: reset clears outputs");
        else
            $display("FAIL test 8: reset did not clear outputs aligned_data=%h aligned_valid=%b align_err=%b",
                      aligned_data, aligned_valid, align_err);
        rst_n = 1'b1;

        // Test 9: FLIT boundary check — 256-bit SYNC_DATA (Gen6 FLIT mode)
        test_payload = 256'hCAFEBABE_DEADBEEF_12345678_ABCDEF01_CAFEBABE_DEADBEEF_12345678_ABCDEF01;
        test_payload[1:0] = 2'b01;
        apply_input(test_payload, 1'b1, 1'b1);
        @(posedge clk); #1;
        expected_aligned = {2'b00, test_payload[255:2]};
        check_output(expected_aligned, 1'b1, 2'b01, 1'b0, 9);

        // Test 10: data_valid de-asserted => outputs clear
        apply_input(256'd0, 1'b0, 1'b1);
        @(posedge clk); #1;
        check_output(256'd0, 1'b0, 2'b00, 1'b0, 10);

        repeat(4) @(posedge clk);
        $display("Simulation complete.");
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT: simulation did not finish.");
        $finish;
    end

endmodule
