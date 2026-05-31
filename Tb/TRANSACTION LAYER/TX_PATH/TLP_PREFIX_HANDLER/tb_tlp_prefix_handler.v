`timescale 1ns/1ps

`define ASSERT(cond, msg) \
    if (!(cond)) begin $display("FAIL  %s  @ %0t", msg, $time); fail_count = fail_count + 1; end \
    else         begin $display("PASS  %s", msg); end

module tb_tlp_prefix_handler;

reg          clk;
reg          rst_n;
reg  [1023:0] tlp_in;
reg           tlp_valid_in;
reg  [127:0]  ltp_data;
reg           ltp_valid;
reg  [127:0]  eetp_data;
reg           eetp_valid;

wire [1151:0] tlp_prefixed;
wire          tlp_prefixed_valid;
wire          prefix_err;
wire          e2e_fwd;

tlp_prefix_handler #(
    .LTP_TYPE_MASK(4'hE)
) dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .tlp_in            (tlp_in),
    .tlp_valid_in      (tlp_valid_in),
    .ltp_data          (ltp_data),
    .ltp_valid         (ltp_valid),
    .eetp_data         (eetp_data),
    .eetp_valid        (eetp_valid),
    .tlp_prefixed      (tlp_prefixed),
    .tlp_prefixed_valid(tlp_prefixed_valid),
    .prefix_err        (prefix_err),
    .e2e_fwd           (e2e_fwd)
);

initial clk = 0;
always  #5 clk = ~clk;

integer fail_count;

function [31:0] make_prefix_dw;
    input [3:0] ptype;
    input       local_bit;
    begin
        make_prefix_dw = {4'b0100, ptype, local_bit, 23'd0};
    end
endfunction

function [127:0] pack_prefix;
    input [31:0] dw;
    begin
        pack_prefix = {dw, 96'd0};
    end
endfunction

task drive_tlp;
    input [1023:0] tdata;
    begin
        @(negedge clk);
        tlp_in       = tdata;
        tlp_valid_in = 1'b1;
        @(negedge clk);
        tlp_valid_in = 1'b0;
    end
endtask

initial begin
    fail_count   = 0;
    rst_n        = 0;
    tlp_in       = 1024'd0;
    tlp_valid_in = 1'b0;
    ltp_data     = 128'd0;
    ltp_valid    = 1'b0;
    eetp_data    = 128'd0;
    eetp_valid   = 1'b0;

    repeat(3) @(posedge clk);
    @(negedge clk); rst_n = 1;

    $display("\n--- TC1: No prefix (passthrough) ---");
    ltp_valid  = 1'b0;
    eetp_valid = 1'b0;
    drive_tlp({32'h40000000, 992'hABCD_1234});
    #1;
    `ASSERT(tlp_prefixed_valid === 1'b1, "TC1: tlp_prefixed_valid")
    `ASSERT(prefix_err         === 1'b0, "TC1: no prefix_err")
    `ASSERT(e2e_fwd            === 1'b0, "TC1: no e2e_fwd")
    `ASSERT(tlp_prefixed[1023:0] === {32'h40000000, 992'hABCD_1234}, "TC1: TLP data intact")
    `ASSERT(tlp_prefixed[1151:1024] === 128'd0,                        "TC1: prefix slots zeroed")

    $display("\n--- TC2: LTP only ---");
    ltp_data   = pack_prefix(make_prefix_dw(4'h1, 1'b1));
    ltp_valid  = 1'b1;
    eetp_valid = 1'b0;
    drive_tlp(1024'hDEAD_BEEF);
    #1;
    `ASSERT(tlp_prefixed_valid            === 1'b1, "TC2: valid")
    `ASSERT(prefix_err                    === 1'b0, "TC2: no error")
    `ASSERT(e2e_fwd                       === 1'b0, "TC2: no e2e_fwd")
    `ASSERT(tlp_prefixed[1151:1120]       === make_prefix_dw(4'h1, 1'b1), "TC2: LTP DW correct")
    `ASSERT(tlp_prefixed[1119:1088]       === 32'd0, "TC2: EETP slot zeroed")
    `ASSERT(tlp_prefixed[1023:0]          === 1024'hDEAD_BEEF, "TC2: TLP data intact")
    ltp_valid  = 1'b0;

    $display("\n--- TC3: EETP only ---");
    eetp_data  = pack_prefix(make_prefix_dw(4'h2, 1'b0));
    eetp_valid = 1'b1;
    ltp_valid  = 1'b0;
    drive_tlp(1024'hCAFEBABE);
    #1;
    `ASSERT(tlp_prefixed_valid     === 1'b1, "TC3: valid")
    `ASSERT(prefix_err             === 1'b0, "TC3: no error")
    `ASSERT(e2e_fwd                === 1'b1, "TC3: e2e_fwd asserted")
    `ASSERT(tlp_prefixed[1151:1120]=== 32'd0, "TC3: LTP slot zeroed")
    `ASSERT(tlp_prefixed[1119:1088]=== make_prefix_dw(4'h2, 1'b0), "TC3: EETP DW correct")
    eetp_valid = 1'b0;

    $display("\n--- TC4: LTP + EETP ---");
    ltp_data   = pack_prefix(make_prefix_dw(4'h3, 1'b1));
    eetp_data  = pack_prefix(make_prefix_dw(4'h4, 1'b0));
    ltp_valid  = 1'b1;
    eetp_valid = 1'b1;
    drive_tlp(1024'h12345678);
    #1;
    `ASSERT(tlp_prefixed_valid     === 1'b1, "TC4: valid")
    `ASSERT(prefix_err             === 1'b0, "TC4: no error")
    `ASSERT(e2e_fwd                === 1'b1, "TC4: e2e_fwd asserted")
    `ASSERT(tlp_prefixed[1151:1120]=== make_prefix_dw(4'h3, 1'b1), "TC4: LTP DW correct")
    `ASSERT(tlp_prefixed[1119:1088]=== make_prefix_dw(4'h4, 1'b0), "TC4: EETP DW correct")
    `ASSERT(tlp_prefixed[1023:0]   === 1024'h12345678,               "TC4: TLP data intact")
    ltp_valid  = 1'b0;
    eetp_valid = 1'b0;

    $display("\n--- TC5: Reserved LTP type (4'hF) -> error ---");
    ltp_data   = pack_prefix(make_prefix_dw(4'hF, 1'b1));
    ltp_valid  = 1'b1;
    eetp_valid = 1'b0;
    drive_tlp(1024'hBAD0_BAD0);
    #1;
    `ASSERT(prefix_err         === 1'b1, "TC5: prefix_err asserted")
    `ASSERT(tlp_prefixed_valid === 1'b0, "TC5: TLP NOT forwarded")
    `ASSERT(e2e_fwd            === 1'b0, "TC5: no e2e_fwd")
    ltp_valid  = 1'b0;

    $display("\n--- TC6: EETP with local-scope bit set -> error ---");
    eetp_data  = pack_prefix(make_prefix_dw(4'h2, 1'b1));
    eetp_valid = 1'b1;
    ltp_valid  = 1'b0;
    drive_tlp(1024'hBAD1_BAD1);
    #1;
    `ASSERT(prefix_err         === 1'b1, "TC6: prefix_err asserted")
    `ASSERT(tlp_prefixed_valid === 1'b0, "TC6: TLP NOT forwarded")
    eetp_valid = 1'b0;

    $display("\n--- TC7: Back-to-back TLPs ---");
    begin : bb
        integer i;
        reg [1023:0] tlp_pat;
        for (i = 0; i < 4; i = i + 1) begin
            tlp_pat    = $random;
            ltp_valid  = (i % 2 == 0);
            eetp_valid = (i % 2 == 1);
            ltp_data   = pack_prefix(make_prefix_dw(4'h1, 1'b1));
            eetp_data  = pack_prefix(make_prefix_dw(4'h2, 1'b0));

            @(negedge clk);
            tlp_in       = tlp_pat;
            tlp_valid_in = 1'b1;
            @(negedge clk);
            tlp_valid_in = 1'b0;

            #1;
            `ASSERT(tlp_prefixed_valid === 1'b1, "TC7: each TLP forwarded")
            `ASSERT(prefix_err         === 1'b0, "TC7: no error")
        end
    end
    ltp_valid  = 1'b0;
    eetp_valid = 1'b0;

    repeat(4) @(posedge clk);
    $display("\n========================================");
    if (fail_count == 0)
        $display("ALL TESTS PASSED");
    else
        $display("%0d TEST(S) FAILED", fail_count);
    $display("========================================\n");
    $finish;
end

endmodule