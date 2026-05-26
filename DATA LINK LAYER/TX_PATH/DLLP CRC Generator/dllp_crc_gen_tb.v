// ============================================================
//  Testbench : dllp_crc_gen_tb
//  DUT       : dllp_crc_gen  (DLLP_CRCG)
//
//  Test cases covered:
//    TC1  – Reset / power-on state
//    TC2  – Single valid DLLP (known CRC-16/CCITT reference)
//    TC3  – Back-to-back DLLPs (verify pipeline clearing)
//    TC4  – dllp_valid_in de-asserted mid-stream (no output)
//    TC5  – All-zeros DLLP body
//    TC6  – All-ones DLLP body
//    TC7  – dllp_full field packing check [47:0]=body, [15:0]=CRC
//    TC8  – Reset in-flight assertion (output must clear)
//    TC9  – ACK-type DLLP (type field = 4'h0)
//    TC10 – UpdateFC-type DLLP (type field = 4'h4)
// ============================================================
`timescale 1ns/1ps

module dllp_crc_gen_tb;

    // ── DUT Ports ──────────────────────────────────────────
    reg         clk;
    reg         rst_n;
    reg  [47:0] dllp_in;
    reg         dllp_valid_in;

    wire [15:0] dllp_crc;
    wire        dllp_crc_valid;
    wire [63:0] dllp_full;

    // ── DUT instantiation ──────────────────────────────────
    dllp_crc_gen uDUT (
        .clk           (clk),
        .rst_n         (rst_n),
        .dllp_in       (dllp_in),
        .dllp_valid_in (dllp_valid_in),
        .dllp_crc      (dllp_crc),
        .dllp_crc_valid(dllp_crc_valid),
        .dllp_full     (dllp_full)
    );

    // ── Clock: 1 GHz (period = 1 ns) ─────────────────────
    initial clk = 0;
    always #0.5 clk = ~clk;

    // ── Housekeeping ────────────────────────────────────────
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // Reference CRC (matches the function in the DUT)
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

    // ── Stimulus ────────────────────────────────────────────
    initial begin
        $dumpfile("dllp_crc_gen_tb.vcd");
        $dumpvars(0, dllp_crc_gen_tb);

        // ---- Reset ----
        rst_n         = 0;
        dllp_in       = 48'h0;
        dllp_valid_in = 0;
        @(posedge clk); #0.1;
        @(posedge clk); #0.1;

        // TC1 – Check reset state
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

        // TC2 – Known DLLP body: ACK (type=0x00), sequence=12'hABC
        dllp_in       = 48'h00_0ABC_0000_00;  // [47:44]=type, [43:32]=seq, rest=0
        dllp_valid_in = 1;
        @(posedge clk); #0.1;  // output latches here
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'h00_0ABC_0000_00, "TC2_KNOWN_ACK");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        // TC3 – Back-to-back: two different DLLPs
        dllp_in       = 48'hAA_BB_CC_DD_EE_FF;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        dllp_in       = 48'h11_22_33_44_55_66;
        @(posedge clk); #0.1;  // second DLLP latched here
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'h11_22_33_44_55_66, "TC3_B2B_DLLP2");
        dllp_valid_in = 0;
        // check second result
        @(posedge clk); #0.1;

        // TC4 – valid de-asserted: output should NOT update
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

        // TC5 – All-zeros body
        dllp_in       = 48'h000000000000;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'h000000000000, "TC5_ALL_ZEROS");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        // TC6 – All-ones body
        dllp_in       = 48'hFFFFFFFFFFFF;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, 48'hFFFFFFFFFFFF, "TC6_ALL_ONES");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        // TC7 – Packing: upper 48 bits = body, lower 16 bits = CRC
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

        // TC8 – Assert reset mid-flight
        dllp_in       = 48'hCAFEBABEDEAD;
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        rst_n = 0;               // reset while valid is high
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

        // TC9 – ACK-type: type[7:4]=4'h0, seq[11:0]=12'h123
        //   DLLP format: [47:40]=type_byte [39:28]=seq [27:0]=reserved
        dllp_in       = {8'h00, 12'h123, 28'h0};
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, {8'h00, 12'h123, 28'h0}, "TC9_ACK_TYPE");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        // TC10 – UpdateFC-type: type=8'h40 (InitFC1-P), value fields
        dllp_in       = {8'h40, 12'h001, 8'hFF, 12'hABC, 8'h00};
        dllp_valid_in = 1;
        @(posedge clk); #0.1;
        check(dllp_full, dllp_crc, dllp_crc_valid, {8'h40, 12'h001, 8'hFF, 12'hABC, 8'h00}, "TC10_UPDATEFC");
        dllp_valid_in = 0;
        @(posedge clk); #0.1;

        // ── Summary ────────────────────────────────────────
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

    // ── Timeout guard ──────────────────────────────────────
    initial begin
        #10000;
        $display("TIMEOUT — simulation ran too long");
        $finish;
    end

endmodule
