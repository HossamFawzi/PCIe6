
`timescale 1ns/1ps

module dllp_crc_gen_tb;

    reg         clk;
    reg         rst_n;
    reg  [47:0] dllp_in;
    reg         dllp_valid_in;

    wire [15:0] dllp_crc;
    wire        dllp_crc_valid;
    wire [63:0] dllp_full;

    dllp_crc_gen uDUT (
        .clk           (clk),
        .rst_n         (rst_n),
        .dllp_in       (dllp_in),
        .dllp_valid_in (dllp_valid_in),
        .dllp_crc      (dllp_crc),
        .dllp_crc_valid(dllp_crc_valid),
        .dllp_full     (dllp_full)
    );

    initial clk = 0;
    always #0.5 clk = ~clk;

    integer pass_cnt = 0;
    integer fail_cnt = 0;

    function [15:0] ref_crc16;
        input [47:0] data;
        integer      i;
        reg   [15:0] c;
        begin
            c = 16'hFFFF;
            for (i = 47; i >= 0; i = i - 1) begin
                if (c[15] ^ data[i])
                    c = {c[14:0], 1'b0} ^ 16'h1021;
                else
                    c = {c[14:0], 1'b0};
            end
            ref_crc16 = c;
        end
    endfunction

    task check;
        input [63:0] got_full;
        input [15:0] got_crc;
        input        got_valid;
        input [47:0] body;
        input [8*32-1:0] tc_name;
        reg   [15:0] exp_crc;
        begin
            exp_crc = ref_crc16(body);
            if (got_valid && got_crc === exp_crc && got_full === {body, exp_crc}) begin
                $display("PASS  %0s  | CRC=0x%04h  full=0x%016h", tc_name, got_crc, got_full);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  %0s  | got_valid=%b got_crc=0x%04h exp_crc=0x%04h",
                         tc_name, got_valid, got_crc, exp_crc);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask
	reg [15:0] exp ;

    initial begin
        $dumpfile("dllp_crc_gen_tb.vcd");
        $dumpvars(0, dllp_crc_gen_tb);

        rst_n         = 0;
        dllp_in       = 48'h0;
        dllp_valid_in = 0;
        @(posedge clk); #0.1;
        @(posedge clk); #0.1;

        if (dllp_crc === 16'h0 && dllp_crc_valid === 0 && dllp_full === 64'h0) begin
            $display("PASS  TC1_RESET | outputs zeroed in reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  TC1_RESET | crc=%h valid=%b full=%h",
                     dllp_crc, dllp_crc_valid, dllp_full);
            fail_cnt = fail_cnt + 1;
        end

        rst_n = 1;
        @(posedge clk); #0.1;

        dllp_in       = 48'h00_0ABC_0000_00;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'h00_0ABC_0000_00, "TC2_KNOWN_ACK");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        dllp_in       = 48'hAA_BB_CC_DD_EE_FF;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        dllp_in       = 48'h11_22_33_44_55_66;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'h11_22_33_44_55_66, "TC3_B2B_DLLP2");
        dllp_valid_in = 0;

        @(posedge clk); #0.1;

        @(posedge clk); #0.1;
        dllp_in       = 48'hDEAD_BEEF_0000;
        dllp_valid_in = 0;
        @(posedge clk); #0.1;
        @(posedge clk); #0.1;
        if (dllp_crc_valid === 0) begin
            $display("PASS  TC4_NO_VALID | dllp_crc_valid correctly deasserted");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  TC4_NO_VALID | dllp_crc_valid still high when valid=0");
            fail_cnt = fail_cnt + 1;
        end

        dllp_in       = 48'h000000000000;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'h000000000000, "TC5_ALL_ZEROS");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        dllp_in       = 48'hFFFFFFFFFFFF;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'hFFFFFFFFFFFF, "TC6_ALL_ONES");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        dllp_in       = 48'h1A2B3C4D5E6F;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        dllp_valid_in = 0;
        begin

            exp = ref_crc16(48'h1A2B3C4D5E6F);
            if (dllp_full[63:16] === 48'h1A2B3C4D5E6F &&
                dllp_full[15:0]  === exp) begin
                $display("PASS  TC7_PACKING  | body in [63:16], CRC in [15:0]");
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("FAIL  TC7_PACKING  | full=%h exp_body=1A2B3C4D5E6F exp_crc=%h",
                         dllp_full, exp);
                fail_cnt = fail_cnt + 1;
            end
        end

        dllp_in       = 48'hCAFEBABEDEAD;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        rst_n = 0;
        @(posedge clk); #0.1;
        if (dllp_crc_valid === 0 && dllp_crc === 16'h0 && dllp_full === 64'h0) begin
            $display("PASS  TC8_RST_INFLIGHT | outputs cleared on reset");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL  TC8_RST_INFLIGHT | crc=%h valid=%b full=%h",
                     dllp_crc, dllp_crc_valid, dllp_full);
            fail_cnt = fail_cnt + 1;
        end
        rst_n         = 1;
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        dllp_in       = {8'h00, 12'h123, 28'h0};
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, {8'h00, 12'h123, 28'h0}, "TC9_ACK_TYPE");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        dllp_in       = {8'h40, 12'h001, 8'hFF, 12'hABC, 8'h00};
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, {8'h40, 12'h001, 8'hFF, 12'hABC, 8'h00}, "TC10_UPDATEFC");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        #5;
        $display("--------------------------------------------");
        $display("  dllp_crc_gen TB: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
        $display("--------------------------------------------");
        if (fail_cnt == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** FAILURES DETECTED ***");
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT — simulation ran too long");
        $finish;
    end

endmodule
