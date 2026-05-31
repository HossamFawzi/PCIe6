
`timescale 1ns/1ps

module tb_lcrc_flit_crc_chk;

    reg           clk;
    reg           rst_n;
    reg  [1055:0] tlp_rx;
    reg           tlp_rx_valid;
    reg           flit_mode_en;

    wire          crc_ok;
    wire          crc_err;
    wire [1023:0] tlp_clean;
    wire          tlp_clean_valid;
    wire [11:0]   seq_rx;

    integer pass_count;
    integer fail_count;
    integer test_num;

    reg [11:0]   b_seq;
    reg [991:0]  b_body;
    reg [31:0]   b_crc;
    reg [1055:0] b_pkt;

    reg [1055:0] pkt_bb1;
    reg [1055:0] pkt_bb2;
    reg [1055:0] pkt_mix_g1;
    reg [1055:0] pkt_mix_bad;
    reg [1055:0] pkt_mix_g2;

    integer burst_ok;
    integer burst_err_cnt;
    integer mix_ok;
    integer mix_err;
    integer i;

    lcrc_flit_crc_chk u_dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_rx         (tlp_rx),
        .tlp_rx_valid   (tlp_rx_valid),
        .flit_mode_en   (flit_mode_en),
        .crc_ok         (crc_ok),
        .crc_err        (crc_err),
        .tlp_clean      (tlp_clean),
        .tlp_clean_valid(tlp_clean_valid),
        .seq_rx         (seq_rx)
    );

    initial clk = 1'b0;
    always  #5  clk = ~clk;

    initial begin
        $dumpfile("lcrc_flit_crc_chk.vcd");
        $dumpvars(0, tb_lcrc_flit_crc_chk);
    end

    function [31:0] ref_crc32;
        input [991:0] data;
        integer       byte_idx;
        integer       bit_idx;
        reg [31:0]    crc;
        reg           data_bit;
        reg           xor_flag;
        reg [7:0]     cur_byte;
        begin
            crc = 32'hFFFF_FFFF;
            for (byte_idx = 123; byte_idx >= 0; byte_idx = byte_idx - 1) begin
                cur_byte = data[(byte_idx * 8) +: 8];
                for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    data_bit = cur_byte[bit_idx];
                    xor_flag = crc[31] ^ data_bit;
                    crc      = crc << 1;
                    if (xor_flag) crc = crc ^ 32'h04C1_1DB7;
                end
            end
            ref_crc32 = crc;
        end
    endfunction

    task build_pkt;
        input [11:0]  seq;
        input [991:0] body;
        input         corrupt;
        begin
            b_seq  = seq;
            b_body = body;
            b_crc  = ref_crc32(body);
            if (corrupt) b_crc = b_crc ^ 32'hDEAD_BEEF;

            b_pkt = {seq, 20'd0, body, b_crc};
        end
    endtask

    task check;
        input        condition;
        input [255:0] label;
        begin
            test_num = test_num + 1;
            if (condition) begin
                $display("  [PASS] TC%0d: %s  (t=%0t)", test_num, label, $time);
                pass_count = pass_count + 1;
            end else begin
                $display("  [FAIL] TC%0d: %s  (t=%0t) *** FAIL ***",
                         test_num, label, $time);
                $display("         crc_ok=%b crc_err=%b clean_valid=%b seq_rx=%h",
                         crc_ok, crc_err, tlp_clean_valid, seq_rx);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task drive_pkt;
        input [1055:0] pkt;
        begin
            @(negedge clk);
            tlp_rx       = pkt;
            tlp_rx_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            tlp_rx_valid = 1'b0;
            tlp_rx       = 1056'd0;
        end
    endtask

    task idle;
        input integer n;
        begin repeat(n) @(posedge clk); end
    endtask

    initial begin

        pass_count    = 0;
        fail_count    = 0;
        test_num      = 0;
        burst_ok      = 0;
        burst_err_cnt = 0;
        mix_ok        = 0;
        mix_err       = 0;
        i             = 0;
        rst_n         = 1'b0;
        tlp_rx        = 1056'd0;
        tlp_rx_valid  = 1'b0;
        flit_mode_en  = 1'b0;
        b_seq         = 12'd0;
        b_body        = 992'd0;
        b_crc         = 32'd0;
        b_pkt         = 1056'd0;
        pkt_bb1       = 1056'd0;
        pkt_bb2       = 1056'd0;
        pkt_mix_g1    = 1056'd0;
        pkt_mix_bad   = 1056'd0;
        pkt_mix_g2    = 1056'd0;

        $display("\n================================================================");
        $display("  PCIe Gen6 DLL RX — Module 17: LCRC/FLIT CRC Checker TB");
        $display("================================================================\n");

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[RESET] Released.\n");

        $display("--- TC1: Basic correct packet ---");
        build_pkt(12'h001,
                  {32'h60000010, 32'h00000001, 32'hDEADBEEF, 32'hCAFE0000, 928'hA5A5A5A5},
                  1'b0);
        drive_pkt(b_pkt);

        #1;
        check(crc_ok          === 1'b1,       "TC1: crc_ok");
        check(tlp_clean_valid === 1'b1,       "TC1: tlp_clean_valid");
        check(crc_err         === 1'b0,       "TC1: no crc_err");
        check(seq_rx          === 12'h001,    "TC1: seq_rx=0x001");
        idle(2);

        $display("\n--- TC2: Body bit flip → crc_err ---");
        build_pkt(12'h002, 992'hB1B2B3B4B5B6B7B8, 1'b0);
        b_pkt[132] = ~b_pkt[132];
        drive_pkt(b_pkt);
        #1;
        check(crc_err         === 1'b1,    "TC2: crc_err on body flip");
        check(crc_ok          === 1'b0,    "TC2: no crc_ok");
        check(tlp_clean_valid === 1'b0,    "TC2: no clean_valid");
        check(tlp_clean       === 1024'd0, "TC2: tlp_clean=0 (no leak)");
        idle(2);

        $display("\n--- TC3: Corrupted CRC field → crc_err ---");
        build_pkt(12'h003, 992'hC1C2C3C4C5C6C7C8, 1'b1);
        drive_pkt(b_pkt);
        #1;
        check(crc_err         === 1'b1, "TC3: crc_err on bad CRC field");
        check(crc_ok          === 1'b0, "TC3: no crc_ok");
        check(tlp_clean_valid === 1'b0, "TC3: no clean_valid");
        idle(2);

        $display("\n--- TC4: valid=0 → outputs stay zero ---");
        @(negedge clk);
        tlp_rx       = 1056'hDEAD;
        tlp_rx_valid = 1'b0;
        @(posedge clk); #1;
        check(crc_ok          === 1'b0, "TC4: no crc_ok");
        check(crc_err         === 1'b0, "TC4: no crc_err");
        check(tlp_clean_valid === 1'b0, "TC4: no clean_valid");
        check(seq_rx          === 12'd0,"TC4: seq_rx=0");
        @(negedge clk);
        tlp_rx = 1056'd0;
        idle(2);

        $display("\n--- TC5: SEQ extracted on pass ---");
        build_pkt(12'hABC, 992'h12345678ABCDEF, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok  === 1'b1,    "TC5: crc_ok");
        check(seq_rx  === 12'hABC, "TC5: seq_rx=0xABC");
        idle(2);

        $display("\n--- TC6: SEQ extracted on CRC fail ---");
        build_pkt(12'hDEF, 992'hABCDEF01, 1'b1);
        drive_pkt(b_pkt);
        #1;
        check(crc_err === 1'b1,    "TC6: crc_err asserted");
        check(seq_rx  === 12'hDEF, "TC6: seq_rx=0xDEF despite fail");
        idle(2);

        $display("\n--- TC7: tlp_clean body matches input ---");
        build_pkt(12'h007, 992'hFEDCBA9876543210, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok             === 1'b1,  "TC7: crc_ok");
        check(tlp_clean[1023:32] === b_body,"TC7: tlp_clean body correct");
        idle(2);

        $display("\n--- TC8: tlp_clean[31:0]=0 (CRC stripped) ---");
        build_pkt(12'h008, 992'h1111222233334444, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1,  "TC8: crc_ok");
        check(tlp_clean[31:0] === 32'd0, "TC8: CRC stripped lower 32b=0");
        idle(2);

        $display("\n--- TC9: flit_mode_en=1 ---");
        flit_mode_en = 1'b1;
        build_pkt(12'h009, 992'hCAFEBABEDEADBEEF, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1, "TC9: flit mode crc_ok");
        check(tlp_clean_valid === 1'b1, "TC9: flit mode clean_valid");
        check(crc_err         === 1'b0, "TC9: flit mode no crc_err");
        flit_mode_en = 1'b0;
        idle(2);

        $display("\n--- TC10: Mode switch 0→1 ---");
        flit_mode_en = 1'b0;
        build_pkt(12'h010, 992'hAAAABBBBCCCCDDDD, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok === 1'b1, "TC10: legacy mode crc_ok");

        flit_mode_en = 1'b1;
        build_pkt(12'h011, 992'hEEEEFFFF00001111, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok === 1'b1, "TC10: flit mode crc_ok after switch");
        flit_mode_en = 1'b0;
        idle(2);

        $display("\n--- TC11: All-zero body ---");
        build_pkt(12'h011, 992'd0, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1, "TC11: all-zero crc_ok");
        check(tlp_clean_valid === 1'b1, "TC11: all-zero clean_valid");
        idle(2);

        $display("\n--- TC12: All-ones body ---");
        build_pkt(12'h012, {992{1'b1}}, 1'b0);
        drive_pkt(b_pkt);
        #1;
        check(crc_ok          === 1'b1, "TC12: all-ones crc_ok");
        check(tlp_clean_valid === 1'b1, "TC12: all-ones clean_valid");
        idle(2);

        $display("\n--- TC13: MSB of body flipped ---");
        build_pkt(12'h013, 992'h80000000, 1'b0);
        b_pkt[1023] = ~b_pkt[1023];
        drive_pkt(b_pkt);
        #1;
        check(crc_err === 1'b1, "TC13: MSB flip crc_err");
        check(crc_ok  === 1'b0, "TC13: MSB flip no crc_ok");
        idle(2);

        $display("\n--- TC14: LSB of body flipped ---");
        build_pkt(12'h014, 992'h00000001, 1'b0);
        b_pkt[32] = ~b_pkt[32];
        drive_pkt(b_pkt);
        #1;
        check(crc_err === 1'b1, "TC14: LSB flip crc_err");
        check(crc_ok  === 1'b0, "TC14: LSB flip no crc_ok");
        idle(2);

        $display("\n--- TC15: Back-to-back two correct packets ---");
        build_pkt(12'h015, 992'hAAAA1111, 1'b0);
        pkt_bb1 = b_pkt;
        build_pkt(12'h016, 992'hBBBB2222, 1'b0);
        pkt_bb2 = b_pkt;

        @(negedge clk);
        tlp_rx       = pkt_bb1;
        tlp_rx_valid = 1'b1;
        @(posedge clk);
        #1;
        check(crc_ok       === 1'b1,    "TC15: pkt1 crc_ok");
        check(tlp_clean_valid=== 1'b1,  "TC15: pkt1 clean_valid");
        check(seq_rx       === 12'h015, "TC15: pkt1 seq=0x015");

        @(negedge clk);
        tlp_rx       = pkt_bb2;
        tlp_rx_valid = 1'b1;
        @(posedge clk);
        #1;
        check(crc_ok       === 1'b1,    "TC15: pkt2 crc_ok");
        check(tlp_clean_valid=== 1'b1,  "TC15: pkt2 clean_valid");
        check(seq_rx       === 12'h016, "TC15: pkt2 seq=0x016");

        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        idle(2);

        $display("\n--- TC16: 1-cycle pulse check ---");
        build_pkt(12'h017, 992'hC3C3C3C3, 1'b0);

        @(negedge clk);
        tlp_rx       = b_pkt;
        tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        check(crc_ok          === 1'b1, "TC16: crc_ok HIGH at N+1");
        check(tlp_clean_valid === 1'b1, "TC16: clean_valid HIGH at N+1");

        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        @(posedge clk); #1;
        check(crc_ok          === 1'b0, "TC16: crc_ok cleared N+2 (pulse)");
        check(tlp_clean_valid === 1'b0, "TC16: clean_valid cleared N+2 (pulse)");
        idle(2);

        $display("\n--- TC17: Reset during operation ---");
        build_pkt(12'h018, 992'hD4D4D4D4, 1'b0);
        @(negedge clk);
        tlp_rx       = b_pkt;
        tlp_rx_valid = 1'b1;
        @(negedge clk);
        rst_n        = 1'b0;
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        @(posedge clk); #1;
        check(crc_ok          === 1'b0,    "TC17: crc_ok=0 in reset");
        check(crc_err         === 1'b0,    "TC17: crc_err=0 in reset");
        check(tlp_clean_valid === 1'b0,    "TC17: clean_valid=0 in reset");
        check(tlp_clean       === 1024'd0, "TC17: tlp_clean=0 in reset");
        check(seq_rx          === 12'd0,   "TC17: seq_rx=0 in reset");
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[INFO] Reset released.");
        idle(2);

        $display("\n--- TC18: tlp_clean=0 on fail (no leak) ---");
        build_pkt(12'h019, 992'hE5E5E5E5DEADBEEF, 1'b1);
        drive_pkt(b_pkt);
        #1;
        check(crc_err         === 1'b1,    "TC18: crc_err");
        check(tlp_clean       === 1024'd0, "TC18: tlp_clean=0 (no leak)");
        check(tlp_clean_valid === 1'b0,    "TC18: no clean_valid");
        idle(2);

        $display("\n--- TC19: Burst of 6 correct packets ---");
        burst_ok      = 0;
        burst_err_cnt = 0;
        for (i = 0; i < 6; i = i + 1) begin
            b_body = {i[7:0], 8'hAA, 8'hBB, 8'hCC, {956{1'b0}}};
            build_pkt(i[11:0], b_body, 1'b0);
            @(negedge clk);
            tlp_rx       = b_pkt;
            tlp_rx_valid = 1'b1;
            @(posedge clk); #1;
            if (crc_ok && tlp_clean_valid) burst_ok      = burst_ok + 1;
            if (crc_err)                   burst_err_cnt = burst_err_cnt + 1;
        end
        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;
        check(burst_ok      === 6, "TC19: all 6 burst packets passed");
        check(burst_err_cnt === 0, "TC19: zero crc_err in burst");
        idle(3);

        $display("\n--- TC20: Mixed burst correct/bad/correct ---");
        build_pkt(12'h020, 992'hF1F1F1F1, 1'b0);
        pkt_mix_g1 = b_pkt;
        build_pkt(12'h021, 992'h22223333, 1'b1);
        pkt_mix_bad = b_pkt;
        build_pkt(12'h022, 992'h44445555, 1'b0);
        pkt_mix_g2 = b_pkt;
        mix_ok  = 0;
        mix_err = 0;

        @(negedge clk); tlp_rx = pkt_mix_g1; tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (crc_ok)  mix_ok  = mix_ok  + 1;

        @(negedge clk); tlp_rx = pkt_mix_bad; tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (crc_err) mix_err = mix_err + 1;

        @(negedge clk); tlp_rx = pkt_mix_g2; tlp_rx_valid = 1'b1;
        @(posedge clk); #1;
        if (crc_ok)  mix_ok  = mix_ok  + 1;

        @(negedge clk);
        tlp_rx_valid = 1'b0;
        tlp_rx       = 1056'd0;

        check(mix_ok  === 2, "TC20: exactly 2 crc_ok");
        check(mix_err === 1, "TC20: exactly 1 crc_err");
        idle(3);

        $display("\n================================================================");
        $display("  LCRC / FLIT CRC Checker — Final Result");
        $display("  PASS = %0d  |  FAIL = %0d  |  TOTAL = %0d",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TESTS FAILED ***", fail_count);
        $display("================================================================\n");
        $finish;
    end

    initial begin
        #500000;
        $display("[WATCHDOG] 500us — force finish.");
        $finish;
    end

endmodule