
module tb_tlp_malformed_checker;

    reg         clk, rst_n;
    reg  [4:0]  tlp_type;
    reg  [2:0]  tlp_fmt;
    reg  [9:0]  tlp_len;
    reg  [3:0]  tlp_first_be;
    reg  [3:0]  tlp_last_be;
    reg         parse_valid;

    wire        malformed_err;
    wire [3:0]  malformed_type;
    wire        tlp_ok;

    tlp_malformed_checker dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_type(tlp_type), .tlp_fmt(tlp_fmt),
        .tlp_len(tlp_len), .tlp_first_be(tlp_first_be),
        .tlp_last_be(tlp_last_be), .parse_valid(parse_valid),
        .malformed_err(malformed_err),
        .malformed_type(malformed_type),
        .tlp_ok(tlp_ok)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    integer pass_count, fail_count;

    
    task send_and_check;
        input integer   test_id;
        input [4:0]     t_type;
        input [2:0]     t_fmt;
        input [9:0]     t_len;
        input [3:0]     t_fbe;
        input [3:0]     t_lbe;
        input           exp_ok;
        input           exp_err;
        input [127:0]   label;
        begin
            tlp_type     = t_type;
            tlp_fmt      = t_fmt;
            tlp_len      = t_len;
            tlp_first_be = t_fbe;
            tlp_last_be  = t_lbe;
            parse_valid  = 1;
            @(posedge clk); // DUT registers inputs on this edge
            #1;             // outputs settle after posedge
            parse_valid = 0;
            // Sample outputs NOW ? still valid this delta
            if (tlp_ok == exp_ok && malformed_err == exp_err) begin
                $display("  Test %0d [%0s]: PASS", test_id, label);
                pass_count = pass_count + 1;
            end else begin
                $display("  Test %0d [%0s]: FAIL (ok=%b err=%b type=%b)",
                         test_id, label, tlp_ok, malformed_err, malformed_type);
                fail_count = fail_count + 1;
            end
            #6; // gap before next test
        end
    endtask

    initial begin
        $display("========================================");
        $display("  TB: TLP Malformed Checker");
        $display("========================================");

        pass_count = 0;
        fail_count = 0;

        rst_n = 0;
        tlp_type = 0; tlp_fmt = 0; tlp_len = 0;
        tlp_first_be = 0; tlp_last_be = 0;
        parse_valid = 0;
        #20; rst_n = 1;
        #6; // phase-align before first posedge

        // Test 1: Valid MRd 3DW, Len=4, BEs correct
        // Expect: tlp_ok=1, malformed_err=0
        send_and_check(1, 5'b00000, 3'b000, 10'd4,  4'hF, 4'hF, 1, 0, "Valid MRd");

        // Test 2: Reserved/unknown TLP type
        // Expect: tlp_ok=0, malformed_err=1 (MAL_RSVD_TYPE)
        send_and_check(2, 5'b11111, 3'b000, 10'd1,  4'hF, 4'h0, 0, 1, "Rsvd Type");

        // Test 3: IO request with length != 1 (len=4 is illegal)
        // Expect: tlp_ok=0, malformed_err=1 (MAL_INVALID_LEN)
        send_and_check(3, 5'b00010, 3'b000, 10'd4,  4'hF, 4'hF, 0, 1, "IO bad len");

        // Test 4: Single-DW transfer (len=1) with non-zero last_be
        // Expect: tlp_ok=0, malformed_err=1 (MAL_BE_VIOLATION)
        send_and_check(4, 5'b00000, 3'b010, 10'd1,  4'hF, 4'hF, 0, 1, "BE viol L1");

        // Test 5: Valid CplD ? Fmt=010(with data), Len=8, BEs OK
        // Expect: tlp_ok=1, malformed_err=0
        send_and_check(5, 5'b01010, 3'b010, 10'd8,  4'hF, 4'hF, 1, 0, "Valid CplD");

        // Test 6: Zero length with data payload (Fmt[1]=1)
        // Expect: tlp_ok=0, malformed_err=1 (MAL_ZERO_LEN)
        send_and_check(6, 5'b00000, 3'b010, 10'd0,  4'h0, 4'h0, 0, 1, "Zero len+data");

        #20;
        $display("\n========================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
