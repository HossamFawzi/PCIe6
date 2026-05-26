//============================================================
// Testbench: flit_deframer_rx_tb
// PCIe 6.0 Physical Link Layer - FLIT Deframer RX
// Compatible with ModelSim / QuestaSim / Icarus Verilog
//============================================================
`timescale 1ns/1ps

module flit_deframer_rx_tb;

    // -------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------
    reg           clk;
    reg           rst_n;
    reg  [2303:0] flit_in;
    reg           flit_valid;
    reg           fec_corrected;
    reg  [255:0]  fec_syndrome;
    reg           flit_mode_en;

    wire [1023:0] tlp_out;
    wire          tlp_valid;
    wire [63:0]   dllp_out;
    wire          dllp_valid;
    wire [11:0]   flit_seq;
    wire          flit_crc_err;
    wire          flit_null;
    wire          flit_sync_err;

    // -------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------
    flit_deframer_rx DUT (
        .clk          (clk),
        .rst_n        (rst_n),
        .flit_in      (flit_in),
        .flit_valid   (flit_valid),
        .fec_corrected(fec_corrected),
        .fec_syndrome (fec_syndrome),
        .flit_mode_en (flit_mode_en),
        .tlp_out      (tlp_out),
        .tlp_valid    (tlp_valid),
        .dllp_out     (dllp_out),
        .dllp_valid   (dllp_valid),
        .flit_seq     (flit_seq),
        .flit_crc_err (flit_crc_err),
        .flit_null    (flit_null),
        .flit_sync_err(flit_sync_err)
    );

    // -------------------------------------------------------
    // Clock: 1 GHz (1 ns period)
    // -------------------------------------------------------
    initial clk = 0;
    always #0.5 clk = ~clk;

    // -------------------------------------------------------
    // Test counters
    // -------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;
    integer test_num;

    // -------------------------------------------------------
    // CRC-32/MPEG-2 reference function (identical to DUT)
    // Poly=0x04C11DB7, Init=0xFFFFFFFF, no reflection, no final XOR
    // -------------------------------------------------------
    function [31:0] crc32_ref;
        input [2015:0] data;
        reg   [31:0]   crc;
        integer        i;
        begin
            crc = 32'hFFFF_FFFF;
            for (i = 2015; i >= 0; i = i - 1) begin
                if (crc[31] ^ data[i])
                    crc = {crc[30:0], 1'b0} ^ 32'h04C1_1DB7;
                else
                    crc = {crc[30:0], 1'b0};
            end
            crc32_ref = crc;
        end
    endfunction

    // -------------------------------------------------------
    // Task: assemble a valid 2304-bit FLIT block
    //   flit_in = { fec[255:0], crc[31:0],
    //               seq[11:0], ftype[3:0],
    //               dllp[63:0], tlp[1023:0], rsvd[911:0] }
    // -------------------------------------------------------
    task build_flit;
        input [3:0]    ftype;
        input [11:0]   seq;
        input [1023:0] tlp;
        input [63:0]   dllp;
        input [911:0]  rsvd;
        input [255:0]  fec;
        input          corrupt_crc;    // 1 = flip one CRC bit
        output [2303:0] flit_out;
        reg [2015:0] content;
        reg [31:0]   crc;
        begin
            content  = {seq, ftype, dllp, tlp, rsvd};
            crc      = crc32_ref(content);
            if (corrupt_crc) crc = crc ^ 32'hDEAD_BEEF;
            flit_out = {fec, crc, content};
        end
    endtask

    // -------------------------------------------------------
    // Task: apply one FLIT and check all outputs
    // -------------------------------------------------------
    task apply_and_check;
        input [2303:0] fin;
        input          fv;
        input          fecc;
        input [255:0]  fecs;
        input          fme;
        input [1023:0] exp_tlp;
        input          exp_tv;
        input [63:0]   exp_dllp;
        input          exp_dv;
        input [11:0]   exp_seq;
        input          exp_crc_err;
        input          exp_null;
        input          exp_sync_err;
        input [127:0]  label;
        begin
            @(negedge clk);
            flit_in      = fin;
            flit_valid   = fv;
            fec_corrected= fecc;
            fec_syndrome = fecs;
            flit_mode_en = fme;
            @(posedge clk);
            #0.2;
            test_num = test_num + 1;
            if (fv && fme) begin
                if ((tlp_out      === exp_tlp)      &&
                    (tlp_valid    === exp_tv)        &&
                    (dllp_out     === exp_dllp)      &&
                    (dllp_valid   === exp_dv)        &&
                    (flit_seq     === exp_seq)       &&
                    (flit_crc_err === exp_crc_err)   &&
                    (flit_null    === exp_null)      &&
                    (flit_sync_err=== exp_sync_err)) begin
                    $display("[PASS] Test %0d (%s): tlp_v=%b dllp_v=%b seq=%03h crc_err=%b null=%b sync_err=%b",
                             test_num, label, tlp_valid, dllp_valid,
                             flit_seq, flit_crc_err, flit_null, flit_sync_err);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (%s):", test_num, label);
                    $display("  Exp: tlp_v=%b dllp_v=%b seq=%03h crc_err=%b null=%b sync_err=%b",
                             exp_tv, exp_dv, exp_seq, exp_crc_err, exp_null, exp_sync_err);
                    $display("  Got: tlp_v=%b dllp_v=%b seq=%03h crc_err=%b null=%b sync_err=%b",
                             tlp_valid, dllp_valid, flit_seq, flit_crc_err, flit_null, flit_sync_err);
                    if (tlp_out !== exp_tlp)
                        $display("  TLP mismatch: exp=0x%0h got=0x%0h", exp_tlp, tlp_out);
                    if (dllp_out !== exp_dllp)
                        $display("  DLLP mismatch: exp=0x%016h got=0x%016h", exp_dllp, dllp_out);
                    fail_cnt = fail_cnt + 1;
                end
            end else begin
                // When disabled: check error flags are suppressed
                if (flit_crc_err === 1'b0 && flit_sync_err === 1'b0 &&
                    tlp_valid    === 1'b0 && dllp_valid    === 1'b0) begin
                    $display("[PASS] Test %0d (%s): disabled - no spurious outputs", test_num, label);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (%s): disabled but spurious outputs tlp_v=%b dllp_v=%b crc_err=%b sync_err=%b",
                             test_num, label, tlp_valid, dllp_valid, flit_crc_err, flit_sync_err);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end
    endtask

    // -------------------------------------------------------
    // Reset task
    // -------------------------------------------------------
    task do_reset;
        begin
            rst_n        = 1'b0;
            flit_in      = 2304'h0;
            flit_valid   = 1'b0;
            fec_corrected= 1'b0;
            fec_syndrome = 256'h0;
            flit_mode_en = 1'b1;
            repeat(4) @(posedge clk);
            #0.1;
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------
    // Test data constants
    // -------------------------------------------------------
    localparam [1023:0] TLP_A = 1024'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0_DEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
    localparam [1023:0] TLP_B = 1024'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999;
    localparam [63:0]   DLLP_A = 64'hFEDC_BA98_7654_3210;
    localparam [63:0]   DLLP_B = 64'h1122_3344_5566_7788;
    localparam [255:0]  FEC_ZERO = 256'h0;
    localparam [255:0]  FEC_ERR  = 256'hDEAD_BEEF_CAFE_BABE_DEAD_BEEF_CAFE_BABE_DEAD_BEEF_CAFE_BABE_DEAD_BEEF_CAFE_BABE;
    localparam [911:0]  RSVD_0 = 912'h0;

    reg [2303:0] flit_vec;

    // -------------------------------------------------------
    // Main test body
    // -------------------------------------------------------
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        test_num = 0;

        $display("========================================================");
        $display(" PCIe 6.0 PHY - FLIT Deframer RX Testbench");
        $display(" ModelSim / QuestaSim / Icarus Compatible");
        $display("========================================================");

        do_reset;
        $display("\n--- Reset Complete ---\n");

        // ============================================================
        // GROUP 1: Data FLIT (type=1, TLP+DLLP)
        // ============================================================
        $display("--- Group 1: Data FLIT (type=1, TLP+DLLP) ---");

        build_flit(4'h1, 12'h001, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        TLP_A,1, DLLP_A,1, 12'h001, 0,0,0,
                        "DATA_seq001");

        build_flit(4'h1, 12'h002, TLP_B, DLLP_B, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        TLP_B,1, DLLP_B,1, 12'h002, 0,0,0,
                        "DATA_seq002");

        build_flit(4'h1, 12'hFFF, 1024'h0, 64'h0, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,1, 64'h0,1, 12'hFFF, 0,0,0,
                        "DATA_seq_FFF_zeros");

        // ============================================================
        // GROUP 2: TLP-only FLIT (type=2)
        // ============================================================
        $display("\n--- Group 2: TLP-only FLIT (type=2) ---");

        build_flit(4'h2, 12'h010, TLP_A, 64'hDEAD, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        TLP_A,1, 64'h0,0, 12'h010, 0,0,0,
                        "TLP_ONLY_seq010");

        build_flit(4'h2, 12'h011, TLP_B, 64'h0, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        TLP_B,1, 64'h0,0, 12'h011, 0,0,0,
                        "TLP_ONLY_seq011");

        // ============================================================
        // GROUP 3: DLLP-only FLIT (type=3)
        // ============================================================
        $display("\n--- Group 3: DLLP-only FLIT (type=3) ---");

        build_flit(4'h3, 12'h020, 1024'hBEEF, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, DLLP_A,1, 12'h020, 0,0,0,
                        "DLLP_ONLY_seq020");

        build_flit(4'h3, 12'h021, 1024'h0, DLLP_B, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, DLLP_B,1, 12'h021, 0,0,0,
                        "DLLP_ONLY_seq021");

        // ============================================================
        // GROUP 4: Null FLIT (type=0)
        // ============================================================
        $display("\n--- Group 4: Null FLIT (type=0) ---");

        build_flit(4'h0, 12'h030, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h030, 0,1,0,
                        "NULL_seq030");

        build_flit(4'h0, 12'h031, 1024'h0, 64'h0, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h031, 0,1,0,
                        "NULL_seq031");

        // ============================================================
        // GROUP 5: CRC Error
        // ============================================================
        $display("\n--- Group 5: CRC Error (flit_crc_err=1) ---");

        build_flit(4'h1, 12'h040, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 1, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h040, 1,0,0,
                        "CRC_ERR_type1");

        build_flit(4'h2, 12'h041, TLP_B, 64'h0, RSVD_0, FEC_ZERO, 1, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h041, 1,0,0,
                        "CRC_ERR_type2");

        build_flit(4'h3, 12'h042, 1024'h0, DLLP_B, RSVD_0, FEC_ZERO, 1, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h042, 1,0,0,
                        "CRC_ERR_type3");

        // ============================================================
        // GROUP 6: Invalid FLIT type -> flit_sync_err=1
        // ============================================================
        $display("\n--- Group 6: Invalid FLIT Type (flit_sync_err=1) ---");

        build_flit(4'hA, 12'h050, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h050, 0,0,1,
                        "INV_TYPE_0xA");

        build_flit(4'hF, 12'h051, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h051, 0,0,1,
                        "INV_TYPE_0xF");

        build_flit(4'h8, 12'h052, 1024'h0, 64'h0, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h052, 0,0,1,
                        "INV_TYPE_0x8");

        // ============================================================
        // GROUP 7: FEC Uncorrectable Error (fec_syndrome!=0, fec_corrected=0)
        // ============================================================
        $display("\n--- Group 7: FEC Uncorrectable Error (flit_sync_err=1) ---");

        build_flit(4'h1, 12'h060, TLP_A, DLLP_A, RSVD_0, FEC_ERR, 0, flit_vec);
        apply_and_check(flit_vec, 1, 0, FEC_ERR, 1,
                        1024'h0,0, 64'h0,0, 12'h060, 0,0,1,
                        "FEC_UNCORR");

        build_flit(4'h2, 12'h061, TLP_B, 64'h0, RSVD_0, FEC_ERR, 0, flit_vec);
        apply_and_check(flit_vec, 1, 0, FEC_ERR, 1,
                        1024'h0,0, 64'h0,0, 12'h061, 0,0,1,
                        "FEC_UNCORR_type2");

        // ============================================================
        // GROUP 8: FEC Corrected (fec_syndrome!=0, fec_corrected=1)
        //          sync_err must NOT be asserted
        // ============================================================
        $display("\n--- Group 8: FEC Corrected (no flit_sync_err) ---");

        build_flit(4'h1, 12'h070, TLP_A, DLLP_A, RSVD_0, FEC_ERR, 0, flit_vec);
        apply_and_check(flit_vec, 1, 1, FEC_ERR, 1,
                        TLP_A,1, DLLP_A,1, 12'h070, 0,0,0,
                        "FEC_CORR_type1");

        build_flit(4'h3, 12'h071, 1024'h0, DLLP_B, RSVD_0, FEC_ERR, 0, flit_vec);
        apply_and_check(flit_vec, 1, 1, FEC_ERR, 1,
                        1024'h0,0, DLLP_B,1, 12'h071, 0,0,0,
                        "FEC_CORR_type3");

        // ============================================================
        // GROUP 9: flit_valid=0 (no decode)
        // ============================================================
        $display("\n--- Group 9: flit_valid=0 (decoder idle) ---");

        build_flit(4'h1, 12'h080, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 0,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h000, 0,0,0,
                        "FLIT_VALID_0");

        build_flit(4'h0, 12'h081, 1024'h0, 64'h0, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 0,0,FEC_ZERO,1,
                        1024'h0,0, 64'h0,0, 12'h000, 0,0,0,
                        "FLIT_VALID_0_NULL");

        // ============================================================
        // GROUP 10: flit_mode_en=0 (FLIT mode disabled)
        // ============================================================
        $display("\n--- Group 10: flit_mode_en=0 (FLIT mode disabled) ---");

        build_flit(4'h1, 12'h090, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,0,
                        1024'h0,0, 64'h0,0, 12'h000, 0,0,0,
                        "MODE_EN_0");

        build_flit(4'hA, 12'h091, 1024'h0, 64'h0, RSVD_0, FEC_ZERO, 0, flit_vec);
        apply_and_check(flit_vec, 1,0,FEC_ZERO,0,
                        1024'h0,0, 64'h0,0, 12'h000, 0,0,0,
                        "MODE_EN_0_INV_TYPE");

        // ============================================================
        // GROUP 11: Reset during operation
        // ============================================================
        $display("\n--- Group 11: Reset During Operation ---");

        build_flit(4'h1, 12'h0A0, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, flit_vec);
        @(negedge clk);
        flit_in      = flit_vec;
        flit_valid   = 1'b1;
        flit_mode_en = 1'b1;
        fec_syndrome = FEC_ZERO;
        fec_corrected= 1'b0;
        @(posedge clk);
        #0.1;
        rst_n = 1'b0;
        @(posedge clk);
        #0.2;
        test_num = test_num + 1;
        if (tlp_out      === 1024'h0 && tlp_valid   === 1'b0 &&
            dllp_out     === 64'h0   && dllp_valid  === 1'b0 &&
            flit_seq     === 12'h0   && flit_crc_err=== 1'b0 &&
            flit_null    === 1'b0    && flit_sync_err=== 1'b0) begin
            $display("[PASS] Test %0d (RESET): All outputs cleared", test_num);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("[FAIL] Test %0d (RESET): tlp_v=%b dllp_v=%b seq=%03h crc_err=%b null=%b sync_err=%b",
                     test_num, tlp_valid, dllp_valid, flit_seq,
                     flit_crc_err, flit_null, flit_sync_err);
            fail_cnt = fail_cnt + 1;
        end
        rst_n = 1'b1;
        @(posedge clk);

        // ============================================================
        // GROUP 12: Sequence number tracking (check flit_seq monotonicity)
        // ============================================================
        $display("\n--- Group 12: Sequence Number Tracking ---");

        begin : seq_blk
            integer k;
            reg [2303:0] sv;
            reg [11:0]   exp_s;
            for (k = 0; k < 8; k = k + 1) begin
                exp_s = 12'h100 + k;
                build_flit(4'h1, exp_s, TLP_A, DLLP_A, RSVD_0, FEC_ZERO, 0, sv);
                @(negedge clk);
                flit_in      = sv;
                flit_valid   = 1'b1;
                flit_mode_en = 1'b1;
                fec_syndrome = FEC_ZERO;
                fec_corrected= 1'b0;
                @(posedge clk);
                #0.2;
                test_num = test_num + 1;
                if (flit_seq === exp_s && flit_crc_err === 1'b0 &&
                    tlp_valid === 1'b1 && dllp_valid  === 1'b1) begin
                    $display("[PASS] Test %0d (SEQ[%0d]): flit_seq=0x%03h tlp_v=1 dllp_v=1",
                             test_num, k, flit_seq);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (SEQ[%0d]): exp_seq=0x%03h got=0x%03h crc_err=%b tlp_v=%b dllp_v=%b",
                             test_num, k, exp_s, flit_seq, flit_crc_err, tlp_valid, dllp_valid);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end

        // ============================================================
        // GROUP 13: Continuous streaming - interleaved types
        // ============================================================
        $display("\n--- Group 13: Continuous Streaming (interleaved types) ---");

        begin : stream_blk
            integer m;
            reg [2303:0]  sc;
            reg [3:0]     st  [0:5];
            reg [11:0]    ss  [0:5];
            reg [1023:0]  stlp[0:5];
            reg [63:0]    sdl [0:5];
            reg           etv [0:5];
            reg           edv [0:5];

            st[0]=4'h1; ss[0]=12'h200; stlp[0]=TLP_A; sdl[0]=DLLP_A; etv[0]=1; edv[0]=1;
            st[1]=4'h2; ss[1]=12'h201; stlp[1]=TLP_B; sdl[1]=64'h0;  etv[1]=1; edv[1]=0;
            st[2]=4'h3; ss[2]=12'h202; stlp[2]=1024'h0; sdl[2]=DLLP_B; etv[2]=0; edv[2]=1;
            st[3]=4'h0; ss[3]=12'h203; stlp[3]=TLP_A; sdl[3]=DLLP_A; etv[3]=0; edv[3]=0;
            st[4]=4'h1; ss[4]=12'h204; stlp[4]=TLP_B; sdl[4]=DLLP_B; etv[4]=1; edv[4]=1;
            st[5]=4'h2; ss[5]=12'h205; stlp[5]=TLP_A; sdl[5]=64'h0;  etv[5]=1; edv[5]=0;

            for (m = 0; m < 6; m = m + 1) begin
                build_flit(st[m], ss[m], stlp[m], sdl[m], RSVD_0, FEC_ZERO, 0, sc);
                @(negedge clk);
                flit_in      = sc;
                flit_valid   = 1'b1;
                flit_mode_en = 1'b1;
                fec_syndrome = FEC_ZERO;
                fec_corrected= 1'b0;
                @(posedge clk);
                #0.2;
                test_num = test_num + 1;
                if (tlp_valid   === etv[m]  &&
                    dllp_valid  === edv[m]  &&
                    flit_seq    === ss[m]   &&
                    flit_crc_err=== 1'b0    &&
                    flit_null   === (st[m]==4'h0 ? 1'b1 : 1'b0) &&
                    flit_sync_err=== 1'b0) begin
                    $display("[PASS] Test %0d (STREAM[%0d] type=%0h seq=%03h): tlp_v=%b dllp_v=%b null=%b",
                             test_num, m, st[m], flit_seq, tlp_valid, dllp_valid, flit_null);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("[FAIL] Test %0d (STREAM[%0d] type=%0h seq=%03h): tlp_v=%b(%b) dllp_v=%b(%b) null=%b crc_err=%b sync_err=%b",
                             test_num, m, st[m], flit_seq,
                             tlp_valid, etv[m], dllp_valid, edv[m],
                             flit_null, flit_crc_err, flit_sync_err);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end

        // ============================================================
        // SUMMARY
        // ============================================================
        $display("\n========================================================");
        $display(" SIMULATION COMPLETE");
        $display(" Total Tests : %0d", test_num);
        $display(" PASSED      : %0d", pass_cnt);
        $display(" FAILED      : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display(" STATUS      : ALL TESTS PASSED");
        else
            $display(" STATUS      : SOME TESTS FAILED");
        $display("========================================================\n");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #200000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("flit_deframer_rx_waves.vcd");
        $dumpvars(0, flit_deframer_rx_tb);
    end

endmodule
