`timescale 1ns/1ps

module rx_gear_box_tb;

    reg         clk_ser;
    reg         clk_par;
    reg         rst_n;
    reg  [63:0] ser_data_in;
    reg         ser_valid;
    reg  [2:0]  gear_ratio;

    wire [255:0] par_data_out;
    wire         par_valid;

    rx_gear_box dut (
        .clk_ser    (clk_ser),
        .clk_par    (clk_par),
        .rst_n      (rst_n),
        .ser_data_in(ser_data_in),
        .ser_valid  (ser_valid),
        .gear_ratio (gear_ratio),
        .par_data_out(par_data_out),
        .par_valid  (par_valid)
    );

    initial clk_ser = 1'b0;
    always  #2 clk_ser = ~clk_ser;

    initial clk_par = 1'b0;
    always  #8 clk_par = ~clk_par;

    integer      fail_count;
    integer      i;

    reg [255:0]  captured_data;
    reg          captured_valid;
    integer      par_valid_count;

    always @(posedge clk_par) begin
        if (par_valid) begin
            captured_data  <= par_data_out;
            captured_valid <= 1'b1;
            par_valid_count = par_valid_count + 1;
        end else begin
            captured_valid <= 1'b0;
        end
    end

    task wait_par_valid;
        input integer n_pulses;
        input integer timeout_cycles;
        integer cnt;
        integer tmo;
        begin
            cnt = 0;
            tmo = 0;
            while (cnt < n_pulses && tmo < timeout_cycles) begin
                @(posedge clk_par);
                if (par_valid) cnt = cnt + 1;
                tmo = tmo + 1;
            end
            if (tmo >= timeout_cycles)
                $display("  WARNING: wait_par_valid timed out waiting for %0d pulses", n_pulses);
        end
    endtask

    task drive_ser_word;
        input [63:0] data;
        begin
            @(negedge clk_ser);
            ser_data_in = data;
            ser_valid   = 1'b1;
            @(posedge clk_ser); #0.1;
        end
    endtask

    task ser_idle;
        input integer n;
        integer k;
        begin
            @(negedge clk_ser);
            ser_valid = 1'b0;
            for (k = 0; k < n; k = k + 1) @(posedge clk_ser);
        end
    endtask

    task do_reset;
        begin
            @(negedge clk_ser);
            rst_n       = 1'b0;
            ser_valid   = 1'b0;
            ser_data_in = 64'd0;
            gear_ratio  = 3'd4;
            repeat(4) @(posedge clk_ser);
            repeat(4) @(posedge clk_par);
            rst_n = 1'b1;
            @(posedge clk_ser);
            @(posedge clk_par);
        end
    endtask

    initial begin
        $dumpfile("rx_gear_box_tb.vcd");
        $dumpvars(0, rx_gear_box_tb);

        fail_count     = 0;
        par_valid_count = 0;
        rst_n          = 1'b0;
        ser_valid      = 1'b0;
        ser_data_in    = 64'd0;
        gear_ratio     = 3'd4;

        repeat(6) @(posedge clk_ser);
        repeat(4) @(posedge clk_par);
        rst_n = 1'b1;
        @(posedge clk_par);

        gear_ratio = 3'd4;
        drive_ser_word(64'hAAAA_AAAA_AAAA_AAAA);
        drive_ser_word(64'hBBBB_BBBB_BBBB_BBBB);
        drive_ser_word(64'hCCCC_CCCC_CCCC_CCCC);
        drive_ser_word(64'hDDDD_DDDD_DDDD_DDDD);
        ser_idle(1);

        wait_par_valid(1, 60);
        if (par_data_out === 256'hAAAAAAAAAAAAAAAA_BBBBBBBBBBBBBBBB_CCCCCCCCCCCCCCCC_DDDDDDDDDDDDDDDD)
            $display("PASS TEST 1: ratio=4, par_data_out correct");
        else begin
            $display("FAIL TEST 1: ratio=4, par_data_out=%h", par_data_out);
            fail_count = fail_count + 1;
        end

        do_reset;
        gear_ratio = 3'd4;
        drive_ser_word(64'h1111_1111_1111_1111);
        drive_ser_word(64'h2222_2222_2222_2222);
        drive_ser_word(64'h3333_3333_3333_3333);
        drive_ser_word(64'h4444_4444_4444_4444);
        ser_idle(1);

        wait_par_valid(1, 60);
        if (par_data_out === 256'h1111111111111111_2222222222222222_3333333333333333_4444444444444444)
            $display("PASS TEST 2: ratio=4 second pack correct");
        else begin
            $display("FAIL TEST 2: ratio=4 second pack=%h", par_data_out);
            fail_count = fail_count + 1;
        end

        do_reset;
        gear_ratio = 3'd2;
        drive_ser_word(64'hFACE_CAFE_BABE_DEAD);
        drive_ser_word(64'hBEEF_1234_5678_ABCD);
        ser_idle(1);

        wait_par_valid(1, 60);
        if (par_data_out === {128'd0, 64'hFACECAFEBABEDEAD, 64'hBEEF12345678ABCD})
            $display("PASS TEST 3: ratio=2, par_data_out correct");
        else begin
            $display("FAIL TEST 3: ratio=2, par_data_out=%h", par_data_out);
            fail_count = fail_count + 1;
        end

        do_reset;
        gear_ratio = 3'd1;
        drive_ser_word(64'hDEAD_BEEF_CAFE_BABE);
        ser_idle(1);

        wait_par_valid(1, 60);
        if (par_data_out === {192'd0, 64'hDEADBEEFCAFEBABE})
            $display("PASS TEST 4: ratio=1, par_data_out correct");
        else begin
            $display("FAIL TEST 4: ratio=1, par_data_out=%h", par_data_out);
            fail_count = fail_count + 1;
        end

        do_reset;
        gear_ratio = 3'd4;
        par_valid_count = 0;

        drive_ser_word(64'hAAAA_0000_0000_0001);
        drive_ser_word(64'hAAAA_0000_0000_0002);
        drive_ser_word(64'hAAAA_0000_0000_0003);
        ser_idle(4);

        repeat(8) @(posedge clk_par);
        if (par_valid_count === 0)
            $display("PASS TEST 5a: no spurious par_valid during idle gap");
        else begin
            $display("FAIL TEST 5a: unexpected par_valid during gap, count=%0d", par_valid_count);
            fail_count = fail_count + 1;
        end

        par_valid_count = 0;
        drive_ser_word(64'hAAAA_0000_0000_0004);
        ser_idle(1);
        wait_par_valid(1, 60);

        if (par_valid_count === 1)
            $display("PASS TEST 5b: par_valid fires after completing 4th word");
        else begin
            $display("FAIL TEST 5b: par_valid_count=%0d after completing 4th word",
                      par_valid_count);
            fail_count = fail_count + 1;
        end

        do_reset;
        gear_ratio = 3'd4;
        par_valid_count = 0;

        drive_ser_word(64'hAAAA_0001_0001_0001);
        drive_ser_word(64'hAAAA_0001_0001_0002);
        drive_ser_word(64'hAAAA_0001_0001_0003);
        drive_ser_word(64'hAAAA_0001_0001_0004);
        drive_ser_word(64'hBBBB_0002_0002_0001);
        drive_ser_word(64'hBBBB_0002_0002_0002);
        drive_ser_word(64'hBBBB_0002_0002_0003);
        drive_ser_word(64'hBBBB_0002_0002_0004);
        ser_idle(1);

        wait_par_valid(2, 120);
        if (par_valid_count >= 2)
            $display("PASS TEST 6: back-to-back packs, par_valid_count=%0d", par_valid_count);
        else begin
            $display("FAIL TEST 6: expected 2 par_valid pulses, got %0d", par_valid_count);
            fail_count = fail_count + 1;
        end

        do_reset;
        gear_ratio = 3'd4;

        drive_ser_word(64'hDEAD_1111_1111_1111);
        drive_ser_word(64'hDEAD_2222_2222_2222);

        @(negedge clk_ser);
        rst_n = 1'b0;
        repeat(3) @(posedge clk_par); #0.5;

        if (par_data_out === 256'd0 && par_valid === 1'b0)
            $display("PASS TEST 7: reset clears outputs mid-stream");
        else begin
            $display("FAIL TEST 7: reset did not clear outputs par_valid=%b par_data_out=%h",
                      par_valid, par_data_out);
            fail_count = fail_count + 1;
        end
        rst_n = 1'b1;

        do_reset;
        gear_ratio = 3'd0;
        drive_ser_word(64'hCAFE_BABE_1234_5678);
        ser_idle(1);

        wait_par_valid(1, 60);
        if (par_data_out[63:0] === 64'hCAFEBABE12345678)
            $display("PASS TEST 8: ratio=0 defaults to 1, data[63:0]=%h", par_data_out[63:0]);
        else begin
            $display("FAIL TEST 8: ratio=0 default, par_data_out=%h", par_data_out);
            fail_count = fail_count + 1;
        end

        do_reset;
        gear_ratio = 3'd4;
        drive_ser_word(64'h1234_5678_9ABC_DEF0);
        drive_ser_word(64'h1234_5678_9ABC_DEF1);
        drive_ser_word(64'h1234_5678_9ABC_DEF2);
        drive_ser_word(64'h1234_5678_9ABC_DEF3);
        ser_idle(1);

        wait_par_valid(1, 60);

        @(posedge clk_par); #0.5;
        if (par_valid === 1'b0)
            $display("PASS TEST 9: par_valid de-asserts after one clk_par cycle");
        else begin
            $display("FAIL TEST 9: par_valid still high after one extra clk_par cycle");
            fail_count = fail_count + 1;
        end

        repeat(8) @(posedge clk_par);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SIMULATION DONE — %0d TEST(S) FAILED", fail_count);

        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
