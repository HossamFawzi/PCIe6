
`timescale 1ns/1ps

module flit_mode_controller_tb;

    reg          clk;
    reg          rst_n;
    reg [1023:0] tlp_in;
    reg          tlp_valid_in;
    reg          flit_mode_en;
    reg          dll_flit_ack;

    wire [2047:0] flit_out;
    wire          flit_valid;
    wire [23:0]   flit_crc;
    wire [11:0]   flit_seq;
    wire          flit_retry_req;
    wire          flit_overflow_err;

    flit_mode_controller dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .tlp_in           (tlp_in),
        .tlp_valid_in     (tlp_valid_in),
        .flit_mode_en     (flit_mode_en),
        .dll_flit_ack     (dll_flit_ack),
        .flit_out         (flit_out),
        .flit_valid       (flit_valid),
        .flit_crc         (flit_crc),
        .flit_seq         (flit_seq),
        .flit_retry_req   (flit_retry_req),
        .flit_overflow_err(flit_overflow_err)
    );

    initial clk = 0;
    always  #2 clk = ~clk;

    task apply_reset;
        begin
            rst_n        <= 0;
            tlp_in       <= {1024{1'b0}};
            tlp_valid_in <= 0;
            flit_mode_en <= 0;
            dll_flit_ack <= 0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            rst_n <= 1;
            @(posedge clk); #1;
        end
    endtask

    task send_tlp_pair;
        input [1023:0] chunk0;
        input [1023:0] chunk1;
        begin
            tlp_in       <= chunk0;
            tlp_valid_in <= 1;
            flit_mode_en <= 1;
            @(posedge clk); #1;
            tlp_in       <= chunk1;
            tlp_valid_in <= 1;
            @(posedge clk); #1;
            tlp_valid_in <= 0;
            tlp_in       <= {1024{1'b0}};
        end
    endtask

    task wait_flit_valid;
        input integer timeout;
        integer cnt;
        begin
            cnt = 0;
            while (!flit_valid && cnt < timeout) begin
                @(posedge clk); #1;
                cnt = cnt + 1;
            end
            if (cnt == timeout)
                $display("[TIMEOUT] flit_valid never asserted!");
        end
    endtask

    integer pass_cnt, fail_cnt;

    task check;
        input        condition;
        input [255:0] label;
        begin
            if (condition) begin
                $display("  [PASS] %s", label);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] %s", label);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    integer      i;
    reg [23:0]   crc_first;

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        $dumpfile("flit_mode_controller_tb.vcd");
        $dumpvars(0, flit_mode_controller_tb);

        apply_reset;

        $display("\n=== TC1: Normal FLIT Assembly + ACK ===");
        dll_flit_ack <= 0;

        send_tlp_pair({128{8'hAB}}, {128{8'hCD}});

        wait_flit_valid(20);

        check(flit_valid         == 1,      "TC1: flit_valid asserted");
        check(flit_retry_req     == 0,      "TC1: no retry_req before ACK");
        check(flit_seq           == 12'h0,  "TC1: seq == 0");
        check(flit_out[1023:0]   == {128{8'hAB}}, "TC1: lower chunk correct");
        check(flit_out[2047:1024]== {128{8'hCD}}, "TC1: upper chunk correct");

        $display("  flit_seq = %0d  flit_crc = 0x%06h  flit_valid = %b",
                 flit_seq, flit_crc, flit_valid);

        dll_flit_ack <= 1;
        @(posedge clk); #1;
        dll_flit_ack <= 0;
        @(posedge clk); #1;

        check(flit_retry_req == 0, "TC1: no retry after ACK");
        @(posedge clk); #1;

        $display("\n=== TC2: Retry After ACK Timeout ===");
        dll_flit_ack <= 0;

        send_tlp_pair({128{8'h11}}, {128{8'h22}});
        wait_flit_valid(20);

        repeat(12) @(posedge clk);
        #1;

        check(flit_retry_req == 1, "TC2: retry_req asserted after timeout");
        check(flit_seq       == 12'h1, "TC2: seq still 1 (not incremented on NACK)");

        dll_flit_ack <= 1;
        @(posedge clk); #1;
        dll_flit_ack <= 0;
        @(posedge clk); #1;

        check(flit_retry_req == 0, "TC2: retry_req cleared after ACK");
        @(posedge clk); #1;

        $display("\n=== TC3: Back-to-Back FLITs ===");

        dll_flit_ack <= 0;
        send_tlp_pair({128{8'hAA}}, {128{8'hBB}});
        wait_flit_valid(20);
        check(flit_seq == 12'h2, "TC3: FLIT-A seq == 2");
        dll_flit_ack <= 1;
        @(posedge clk); #1;
        dll_flit_ack <= 0;
        @(posedge clk); #1;

        send_tlp_pair({128{8'hCC}}, {128{8'hDD}});
        wait_flit_valid(20);
        check(flit_seq == 12'h3, "TC3: FLIT-B seq == 3");
        dll_flit_ack <= 1;
        @(posedge clk); #1;
        dll_flit_ack <= 0;
        @(posedge clk); #1;

        $display("\n=== TC4: flit_mode_en Disabled ===");
        flit_mode_en <= 0;
        tlp_in       <= {1024{8'hFF}};
        tlp_valid_in <= 1;
        @(posedge clk); #1;
        tlp_valid_in <= 0;
        repeat(8) @(posedge clk);
        #1;
        check(flit_valid == 0, "TC4: flit_valid stays 0 when disabled");
        flit_mode_en <= 1;

        $display("\n=== TC5: CRC Correctness ===");
        dll_flit_ack <= 0;

        send_tlp_pair({128{8'h55}}, {128{8'hAA}});
        wait_flit_valid(20);

        crc_first = flit_crc;
        check(crc_first != 24'h0, "TC5: CRC non-zero for first payload");

        dll_flit_ack <= 1;
        @(posedge clk); #1;
        dll_flit_ack <= 0;
        @(posedge clk); #1;

        send_tlp_pair({128{8'h12}}, {128{8'h34}});
        wait_flit_valid(20);

        check(flit_crc != crc_first, "TC5: CRC differs for different payload");

        dll_flit_ack <= 1;
        @(posedge clk); #1;
        dll_flit_ack <= 0;

        $display("\n============================================");
        $display("  RESULTS: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        $display("============================================");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***\n");
        else
            $display("  *** SOME TESTS FAILED - review log ***\n");

        #20;
        $finish;
    end

    always @(posedge clk) begin
        if (flit_valid)
            $display("[FLIT] seq=%0d  crc=0x%06h  retry=%b  overflow=%b  state=%0d",
                     flit_seq, flit_crc, flit_retry_req,
                     flit_overflow_err, dut.state);
    end

endmodule
