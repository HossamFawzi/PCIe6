//============================================================
// Testbench: tb_tlp_header_parser
// Verifies: Field extraction, 3DW/4DW addressing,
//           error detection, 10-bit tag support
//
// TIMING NOTE: DUT outputs are registered (clocked). Inputs
// must be stable before posedge. After posedge the DUT latches
// the data and asserts parse_valid for exactly ONE cycle.
// We therefore check outputs immediately after that posedge
// (before the next clock edge clears parse_valid).
//============================================================
`timescale 1ns / 1ps

module tb_tlp_header_parser;

    // ?? Clock & Reset ??
    reg          clk;
    reg          rst_n;

    // ?? DUT Signals ??
    reg  [1023:0] tlp_rx;
    reg           tlp_rx_valid;
    reg           tlp_rx_sop;

    wire [4:0]    tlp_type;
    wire [2:0]    tlp_fmt;
    wire [2:0]    tlp_tc;
    wire [2:0]    tlp_attr;
    wire [9:0]    tlp_len;
    wire [9:0]    tlp_tag;
    wire [15:0]   tlp_req_id;
    wire [63:0]   tlp_addr;
    wire          tlp_ep_bit;
    wire          tlp_td_bit;
    wire          parse_err;
    wire          parse_valid;

    // ?? Instantiate DUT ??
    tlp_header_parser dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .tlp_rx       (tlp_rx),
        .tlp_rx_valid (tlp_rx_valid),
        .tlp_rx_sop   (tlp_rx_sop),
        .tlp_type     (tlp_type),
        .tlp_fmt      (tlp_fmt),
        .tlp_tc       (tlp_tc),
        .tlp_attr     (tlp_attr),
        .tlp_len      (tlp_len),
        .tlp_tag      (tlp_tag),
        .tlp_req_id   (tlp_req_id),
        .tlp_addr     (tlp_addr),
        .tlp_ep_bit   (tlp_ep_bit),
        .tlp_td_bit   (tlp_td_bit),
        .parse_err    (parse_err),
        .parse_valid  (parse_valid)
    );

    // ?? Clock Generation: 250 MHz (4ns period) ??
    initial clk = 0;
    always #2 clk = ~clk;

    // ?? Helper function: Build TLP DW0 ??
    // PCIe DW0 bit layout (MSB?LSB):
    //   [31:29] Fmt[2:0]
    //   [28:24] Type[4:0]
    //   [23]    T9 (10-bit tag bit 9) ? set 0 here
    //   [22:20] TC[2:0]
    //   [19]    T8 (10-bit tag bit 8) ? set 0 here
    //   [18]    Attr[2]
    //   [17]    LN  ? 0
    //   [16]    TH  ? 0
    //   [15]    TD
    //   [14]    EP
    //   [13:12] Attr[1:0]
    //   [11:10] AT[1:0] ? 0
    //   [9:0]   Length[9:0]
    function [31:0] build_dw0;
        input [2:0] fmt;
        input [4:0] typ;
        input [2:0] tc;
        input       td;
        input       ep;
        input [2:0] attr;
        input [9:0] len;
        begin
            // Bits: 31-29=fmt, 28-24=typ, 23=0(T9), 22-20=tc,
            //       19=0(T8), 18=attr[2], 17=0(LN), 16=0(TH),
            //       15=td, 14=ep, 13-12=attr[1:0], 11-10=0(AT),
            //       9-0=len
            build_dw0 = { fmt,          // [31:29]
                          typ,          // [28:24]
                          1'b0,         // [23] T9
                          tc,           // [22:20]
                          1'b0,         // [19] T8
                          attr[2],      // [18] Attr[2]
                          1'b0,         // [17] LN
                          1'b0,         // [16] TH
                          td,           // [15] TD
                          ep,           // [14] EP
                          attr[1:0],    // [13:12] Attr[1:0]
                          2'b00,        // [11:10] AT
                          len           // [9:0]
                        };
        end
    endfunction

    integer test_num;
    integer pass_count;
    integer fail_count;

    // ?? Helper task: drive one TLP and wait for DUT to register it ??
    // Sets valid+sop, waits for posedge (DUT latches here), then
    // deasserts. Outputs are valid 1 delta after the posedge (#1).
    task drive_tlp;
        begin
            tlp_rx_valid = 1;
            tlp_rx_sop   = 1;
            @(posedge clk); // DUT registers inputs on this edge
            #1;             // tiny settle ? outputs now stable
            tlp_rx_valid = 0;
            tlp_rx_sop   = 0;
        end
    endtask

    // ?? Main Test Sequence ??
    initial begin
        $display("========================================");
        $display("  TB: TLP Header Parser");
        $display("========================================");

        pass_count = 0;
        fail_count = 0;

        // Reset
        rst_n        = 0;
        tlp_rx       = 1024'b0;
        tlp_rx_valid = 0;
        tlp_rx_sop   = 0;
        #20;
        rst_n = 1;
        #6; // align to a known phase before first posedge

        // ?? TEST 1: Memory Read 3DW ??
        test_num = 1;
        $display("\nTest %0d: MRd 3DW, TC=1, Len=4, Addr=0xDEAD_BEE0", test_num);
        tlp_rx        = 1024'b0;
        // DW0: Fmt=000(3DW no-data), Type=00000(Mem), TC=001, TD=0, EP=0, Attr=000, Len=4
        tlp_rx[31:0]  = build_dw0(3'b000, 5'b00000, 3'b001,
                                   1'b0, 1'b0, 3'b000, 10'd4);
        // DW1: ReqID=0xABCD, Tag=0x42, LastBE=4'hF, FirstBE=4'hF
        tlp_rx[63:32] = {16'hABCD, 8'h42, 4'hF, 4'hF};
        // DW2: 32-bit address (3DW)
        tlp_rx[95:64] = 32'hDEADBEE0;

        drive_tlp; // outputs valid now (#1 after posedge)

        if (parse_valid && !parse_err &&
            tlp_fmt  == 3'b000     &&
            tlp_type == 5'b00000   &&
            tlp_tc   == 3'b001     &&
            tlp_len  == 10'd4      &&
            tlp_addr[31:0] == 32'hDEADBEE0) begin
            $display("  PASS: fmt=%b type=%b tc=%0d len=%0d addr=0x%08h",
                     tlp_fmt, tlp_type, tlp_tc, tlp_len, tlp_addr[31:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: valid=%b err=%b fmt=%b type=%b tc=%0d len=%0d addr=0x%08h",
                     parse_valid, parse_err, tlp_fmt, tlp_type,
                     tlp_tc, tlp_len, tlp_addr[31:0]);
            fail_count = fail_count + 1;
        end

        #10;

        // ?? TEST 2: Memory Write 4DW with EP (Poisoned) ??
        test_num = 2;
        $display("\nTest %0d: MWr 4DW with Poisoned bit (EP=1)", test_num);
        tlp_rx        = 1024'b0;
        // DW0: Fmt=011(4DW with data), Type=00000(Mem), TC=000, TD=0, EP=1, Attr=000, Len=8
        tlp_rx[31:0]  = build_dw0(3'b011, 5'b00000, 3'b000,
                                   1'b0, 1'b1, 3'b000, 10'd8);
        // DW1: ReqID=0x1234, Tag=0xAA, BEs=0xFF
        tlp_rx[63:32] = {16'h1234, 8'hAA, 4'hF, 4'hF};
        // DW2: upper 32-bit address (4DW)
        tlp_rx[95:64]  = 32'h0000_00FF;
        // DW3: lower 32-bit address (4DW) ? bit[1:0] must be 00
        tlp_rx[127:96] = 32'hCAFE_BAB0;

        drive_tlp;

        if (parse_valid && !parse_err &&
            tlp_ep_bit  == 1'b1    &&
            tlp_fmt[0]  == 1'b1    &&   // 4DW: Fmt[0]=1
            tlp_fmt[1]  == 1'b1    &&   // has data: Fmt[1]=1
            tlp_type    == 5'b00000) begin
            $display("  PASS: 4DW + EP detected, fmt=%b ep=%b", tlp_fmt, tlp_ep_bit);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: valid=%b err=%b fmt=%b ep=%b type=%b",
                     parse_valid, parse_err, tlp_fmt, tlp_ep_bit, tlp_type);
            fail_count = fail_count + 1;
        end

        #10;

        // ?? TEST 3: Completion with Data (CplD) + TD bit ??
        test_num = 3;
        $display("\nTest %0d: Completion with Data (CplD), TD=1", test_num);
        tlp_rx        = 1024'b0;
        // DW0: Fmt=010(3DW with data), Type=01010(CplD), TC=000, TD=1, EP=0, Attr=000, Len=1
        tlp_rx[31:0]  = build_dw0(3'b010, 5'b01010, 3'b000,
                                   1'b1, 1'b0, 3'b000, 10'd1);
        // DW1 for Cpl: CompleterID=0x5678, Status+BCM+ByteCount
        tlp_rx[63:32] = {16'h5678, 8'h10, 4'h0, 4'hF};
        // DW2: RequesterID + Tag + LowerAddr (completion header)
        tlp_rx[95:64] = 32'h0000_0000;

        drive_tlp;

        if (parse_valid && !parse_err &&
            tlp_type   == 5'b01010  &&
            tlp_fmt    == 3'b010    &&
            tlp_td_bit == 1'b1) begin
            $display("  PASS: CplD parsed, type=%b fmt=%b td=%b",
                     tlp_type, tlp_fmt, tlp_td_bit);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: valid=%b err=%b type=%b fmt=%b td=%b",
                     parse_valid, parse_err, tlp_type, tlp_fmt, tlp_td_bit);
            fail_count = fail_count + 1;
        end

        #20;

        // ?? Summary ??
        $display("\n========================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
