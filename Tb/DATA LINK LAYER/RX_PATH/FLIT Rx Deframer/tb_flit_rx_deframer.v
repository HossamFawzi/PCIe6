
`timescale 1ns/1ps

module tb_flit_rx_deframer;

    reg          clk;
    reg          rst_n;
    reg  [2047:0] rx_flit;
    reg          rx_flit_valid;
    reg  [15:0]  fec_syndrome;
    reg          fec_corrected;

    wire [1023:0] flit_tlp;
    wire          flit_tlp_valid;
    wire [63:0]   flit_dllp;
    wire          flit_dllp_valid;
    wire [11:0]   flit_seq;
    wire          flit_crc_err;
    wire          flit_null;
    wire          flit_uncorr_err;

    flit_rx_deframer dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .rx_flit        (rx_flit),
        .rx_flit_valid  (rx_flit_valid),
        .fec_syndrome   (fec_syndrome),
        .fec_corrected  (fec_corrected),
        .flit_tlp       (flit_tlp),
        .flit_tlp_valid (flit_tlp_valid),
        .flit_dllp      (flit_dllp),
        .flit_dllp_valid(flit_dllp_valid),
        .flit_seq       (flit_seq),
        .flit_crc_err   (flit_crc_err),
        .flit_null      (flit_null),
        .flit_uncorr_err(flit_uncorr_err)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [255:0] label;
        input         expected;
        input         actual;
        begin
            if (expected === actual) begin
                $display("[PASS] %s | expected=%b got=%b", label, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %s | expected=%b got=%b  @%0t", label, expected, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    localparam [3:0] TYPE_NULL  = 4'h0;
    localparam [3:0] TYPE_TLP   = 4'h1;
    localparam [3:0] TYPE_DLLP  = 4'h2;
    localparam [3:0] TYPE_MIXED = 4'h3;

    function [23:0] compute_crc24;
        input [2023:0] data_in;
        integer i;
        reg [23:0] c;
        reg [7:0]  b;
        begin
            c = 24'hFFFFFF;
            for (i = 0; i < 253; i = i + 1) begin : crc_loop
                b = data_in[i*8 +: 8];
                c = c ^ {b, 16'h0};
                begin : bit_loop
                    integer k;
                    for (k = 0; k < 8; k = k + 1) begin
                        if (c[23]) c = (c << 1) ^ 24'hC60001;
                        else       c = (c << 1);
                    end
                end
            end
            compute_crc24 = c;
        end
    endfunction

    task send_flit;
        input [3:0]   ftype;
        input [11:0]  seq;
        input [1023:0] tlp_data;
        input [63:0]   dllp_data;
        input          inject_crc_err;
        input [15:0]   fec_syn;
        input          fec_corr;
        reg [2047:0]  flit_word;
        reg [23:0]    crc_val;
        begin

            flit_word = 2048'b0;
            flit_word[1023:0]    = tlp_data;
            flit_word[2007:1944] = dllp_data;
            flit_word[2011:2008] = ftype;
            flit_word[2023:2012] = seq;

            crc_val = compute_crc24(flit_word[2023:0]);
            if (inject_crc_err)
                crc_val = ~crc_val;
            flit_word[2047:2024] = crc_val;

            @(posedge clk);
            rx_flit       <= flit_word;
            rx_flit_valid <= 1'b1;
            fec_syndrome  <= fec_syn;
            fec_corrected <= fec_corr;
            @(posedge clk);
            rx_flit_valid <= 1'b0;
            fec_syndrome  <= 16'h0;
            fec_corrected <= 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_flit_rx_deframer.vcd");
        $dumpvars(0, tb_flit_rx_deframer);

        rst_n         = 0;
        rx_flit       = 2048'b0;
        rx_flit_valid = 1'b0;
        fec_syndrome  = 16'h0;
        fec_corrected = 1'b0;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n--- TC1: NULL FLIT ---");
        send_flit(TYPE_NULL, 12'h001, 1024'hDEAD, 64'hBEEF, 0, 16'h0, 0);
        @(posedge clk);
        check("TC1 flit_null",       1'b1, flit_null);
        check("TC1 flit_tlp_valid",  1'b0, flit_tlp_valid);
        check("TC1 flit_dllp_valid", 1'b0, flit_dllp_valid);
        check("TC1 flit_crc_err",    1'b0, flit_crc_err);
        repeat(2) @(posedge clk);

        $display("\n--- TC2: TLP-only FLIT ---");
        send_flit(TYPE_TLP, 12'h042, 1024'hCAFE_BABE, 64'h0, 0, 16'h0, 0);
        @(posedge clk);
        check("TC2 flit_tlp_valid",  1'b1, flit_tlp_valid);
        check("TC2 flit_dllp_valid", 1'b0, flit_dllp_valid);
        check("TC2 flit_null",       1'b0, flit_null);
        check("TC2 flit_seq==0x042", 1'b1, (flit_seq === 12'h042));
        repeat(2) @(posedge clk);

        $display("\n--- TC3: DLLP-only FLIT ---");
        send_flit(TYPE_DLLP, 12'h007, 1024'h0, 64'hDEAD_BEEF_1234_5678, 0, 16'h0, 0);
        @(posedge clk);
        check("TC3 flit_dllp_valid", 1'b1, flit_dllp_valid);
        check("TC3 flit_tlp_valid",  1'b0, flit_tlp_valid);
        check("TC3 flit_seq==0x007", 1'b1, (flit_seq === 12'h007));
        repeat(2) @(posedge clk);

        $display("\n--- TC4: MIXED (TLP+DLLP) FLIT ---");
        send_flit(TYPE_MIXED, 12'hFFF, 1024'hAA55, 64'h12345678AABBCCDD, 0, 16'h0, 0);
        @(posedge clk);
        check("TC4 flit_tlp_valid",  1'b1, flit_tlp_valid);
        check("TC4 flit_dllp_valid", 1'b1, flit_dllp_valid);
        check("TC4 flit_seq==0xFFF", 1'b1, (flit_seq === 12'hFFF));
        repeat(2) @(posedge clk);

        $display("\n--- TC5: CRC error injection ---");
        send_flit(TYPE_TLP, 12'h100, 1024'h5A5A, 64'h0, 1, 16'h0, 0);
        @(posedge clk);
        check("TC5 flit_crc_err",   1'b1, flit_crc_err);
        check("TC5 flit_tlp_valid", 1'b0, flit_tlp_valid);
        repeat(2) @(posedge clk);

        $display("\n--- TC6: FEC uncorrectable error ---");
        send_flit(TYPE_TLP, 12'h200, 1024'h1234, 64'h0, 0, 16'hABCD, 0);
        @(posedge clk);
        check("TC6 flit_uncorr_err", 1'b1, flit_uncorr_err);
        check("TC6 flit_tlp_valid",  1'b0, flit_tlp_valid);
        repeat(2) @(posedge clk);

        $display("\n--- TC7: FEC corrected (data valid) ---");
        send_flit(TYPE_TLP, 12'h300, 1024'hFEED, 64'h0, 0, 16'hABCD, 1);
        @(posedge clk);
        check("TC7 flit_uncorr_err", 1'b0, flit_uncorr_err);
        check("TC7 flit_tlp_valid",  1'b1, flit_tlp_valid);
        repeat(2) @(posedge clk);

        $display("\n--- TC8: Back-to-back FLITs ---");
        begin : bb
            integer i;
            for (i = 0; i < 4; i = i + 1) begin
                send_flit(TYPE_TLP, i[11:0], {1008'h0, i[15:0]}, 64'h0, 0, 16'h0, 0);
            end
        end
        @(posedge clk);
        $display("TC8: back-to-back complete (visual inspection of waveform)");
        repeat(4) @(posedge clk);

        $display("\n========================================");
        $display("  FLIT Rx Deframer TB: %0d PASS / %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED — review above");

        $finish;
    end

    initial begin
        #100000;
        $display("[TIMEOUT] Testbench exceeded 100 us — aborting");
        $finish;
    end

endmodule
