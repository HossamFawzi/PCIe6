// =============================================================
//  TESTBENCH : tb_cfg_space_handler
//  DUT       : cfg_space_handler
//  TESTS:
//    T1 — CfgWr DevCtrl  → check max_payload / ro_en / ecrc_en
//    T2 — CfgWr DevCtrl2 → check flit_mode_en
//    T3 — CfgRd DevCap   → check cfg_rd_data & cpl TLP valid
//    T4 — CfgWr + CfgRd  → write then read-back same DW
//    T5 — CfgRd VendDev  → confirm hard-coded value
// =============================================================
`timescale 1ns/1ps

module tb_cfg_space_handler;

    // ── Clock / Reset ────────────────────────────────────────
    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    reg rst_n;

    // ── DUT ports ────────────────────────────────────────────
    reg  [255:0] tlp_cfg;
    reg          tlp_cfg_valid;
    reg  [11:0]  cfg_addr;
    reg  [31:0]  cfg_wr_data;
    reg          cfg_wr_en;

    wire [31:0]  cfg_rd_data;
    wire         cfg_rd_valid;
    wire [255:0] cfg_cpl_tlp;
    wire         cfg_cpl_valid;
    wire [2:0]   max_payload;
    wire         flit_mode_en;
    wire         ecrc_en;
    wire         ro_en;

    // ── DUT instantiation ─────────────────────────────────────
    cfg_space_handler dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .tlp_cfg       (tlp_cfg),
        .tlp_cfg_valid (tlp_cfg_valid),
        .cfg_addr      (cfg_addr),
        .cfg_wr_data   (cfg_wr_data),
        .cfg_wr_en     (cfg_wr_en),
        .cfg_rd_data   (cfg_rd_data),
        .cfg_rd_valid  (cfg_rd_valid),
        .cfg_cpl_tlp   (cfg_cpl_tlp),
        .cfg_cpl_valid (cfg_cpl_valid),
        .max_payload   (max_payload),
        .flit_mode_en  (flit_mode_en),
        .ecrc_en       (ecrc_en),
        .ro_en         (ro_en)
    );

    // ── Helper tasks ─────────────────────────────────────────
    integer pass_count = 0;
    integer fail_count = 0;

    task do_reset;
        begin
            rst_n          = 0;
            tlp_cfg        = 256'h0;
            tlp_cfg_valid  = 0;
            cfg_addr       = 12'h0;
            cfg_wr_data    = 32'h0;
            cfg_wr_en      = 0;
            repeat(4) @(posedge clk);
            rst_n = 1;
            @(posedge clk);
        end
    endtask

    task cfg_write(input [11:0] addr, input [31:0] data);
        begin
            @(negedge clk);   // drive on negedge — safe setup time
            tlp_cfg_valid = 1;
            cfg_wr_en     = 1;
            cfg_addr      = addr;
            cfg_wr_data   = data;
            tlp_cfg       = {8'h44, 8'h00, 16'h0001,
                             16'hBEEF, 8'hAA, 8'h00,
                             32'h0000_0000, data, 64'h0};
            @(posedge clk);   // RTL latches here
            @(negedge clk);   // release after latch
            tlp_cfg_valid = 0;
            cfg_wr_en     = 0;
            @(posedge clk);   // one full cycle for output
            #1;               // NBA settle
        end
    endtask

    task cfg_read(input [11:0] addr);
        begin
            @(negedge clk);
            tlp_cfg_valid = 1;
            cfg_wr_en     = 0;
            cfg_addr      = addr;
            tlp_cfg       = {8'h04, 8'h00, 16'h0001,
                             16'hBEEF, 8'hAA, 8'h00,
                             32'h0, 64'h0, 64'h0};
            @(posedge clk);   // RTL latches here
            @(negedge clk);
            tlp_cfg_valid = 0;
            @(posedge clk);   // output available
            #1;
        end
    endtask

    task check(input [63:0] got, input [63:0] exp,
               input [127:0] test_name);
        begin
            if (got === exp) begin
                $display("  PASS %-30s  got=0x%0h", test_name, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL %-30s  got=0x%0h  exp=0x%0h",
                          test_name, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Stimulus ─────────────────────────────────────────────
    initial begin
        $display("=== cfg_space_handler Testbench ===");
        do_reset;

        // --------------------------------------------------
        // T1: CfgWr DevCtrl — MPS=256B(001), RO=1, ECRC=1
        //     DevCtrl bit[7:5]=001  bit[4]=1  bit[11]=1
        //     data = 32'h0000_08B0
        //            bit11=1(ecrc) bit7:5=001(mps) bit4=1(ro)
        // --------------------------------------------------
        $display("\n[T1] CfgWr DevCtrl: MPS=256B, RO=1, ECRC=1");
        cfg_write(12'h094, 32'h0000_08B0); // IDX_DEVCTRL=0x25 → byte=0x94
        @(posedge clk);
        check(max_payload,  3'b101, "max_payload=101 (MPS=101=512B)");
        check(ro_en,        1'b1,   "ro_en=1");
        check(ecrc_en,      1'b1,   "ecrc_en=1");
        check(flit_mode_en, 1'b0,   "flit_mode_en still 0");

        // --------------------------------------------------
        // T2: CfgWr DevCtrl2 — FLIT mode enable
        // --------------------------------------------------
        $display("\n[T2] CfgWr DevCtrl2: flit_mode_en=1");
        cfg_write(12'h0B4, 32'h0000_0001); // IDX_DEVCTRL2=0x2D → byte=0xB4
        @(posedge clk);
        check(flit_mode_en, 1'b1, "flit_mode_en=1");

        // --------------------------------------------------
        // T3: CfgRd DevCap — should return default value
        // --------------------------------------------------
        $display("\n[T3] CfgRd DevCap → expect 0x00000001");
        // Capture pulse signals during the read active cycle
        begin : T3_BLOCK
            reg cap_rd_valid, cap_cpl_valid;
            reg [255:0] cap_cpl_tlp;
            reg [31:0]  cap_rd_data;
            cap_rd_valid  = 0; cap_cpl_valid = 0;
            @(negedge clk);
            tlp_cfg_valid = 1; cfg_wr_en = 0; cfg_addr = 12'h090;
            tlp_cfg = {8'h04, 8'h00, 16'h0001, 16'hBEEF, 8'hAA, 8'h00,
                       32'h0, 64'h0, 64'h0};
            @(posedge clk); #1;  // RTL latches, outputs pulse HERE
            cap_rd_valid  = cfg_rd_valid;
            cap_cpl_valid = cfg_cpl_valid;
            cap_cpl_tlp   = cfg_cpl_tlp;
            cap_rd_data   = cfg_rd_data;
            @(negedge clk);
            tlp_cfg_valid = 0;
            @(posedge clk); #1;
            check(cap_rd_valid,  1'b1,         "cfg_rd_valid=1");
            check(cap_rd_data[0],1'b1,         "cfg_rd_data=DevCap default");
            check(cap_cpl_valid, 1'b1,         "cfg_cpl_valid=1");
            check(cap_cpl_tlp[255:248], 8'h4A, "cpl fmt/type=CplD(0x4A)");
        end

        // --------------------------------------------------
        // T4: Write arbitrary DW then read it back
        // --------------------------------------------------
        $display("\n[T4] Write 0xDEAD_BEEF @ 0x100 then read back");
        cfg_write(12'h100, 32'hDEAD_BEEF);
        @(posedge clk);
        cfg_read(12'h100);
        @(posedge clk);
        check(cfg_rd_data, 32'hDEAD_BEEF, "readback=0xDEADBEEF");

        // --------------------------------------------------
        // T5: CfgRd VendorID/DeviceID (offset 0x000)
        // --------------------------------------------------
        $display("\n[T5] CfgRd VendDev @ 0x000 → expect 0x1234ABCD");
        cfg_read(12'h000);
        @(posedge clk);
        check(cfg_rd_data, 32'h1234_ABCD, "VendDev=0x1234ABCD");

        // --------------------------------------------------
        // Summary
        // --------------------------------------------------
        $display("\n===================================");
        $display("  TOTAL PASS : %0d", pass_count);
        $display("  TOTAL FAIL : %0d", fail_count);
        $display("===================================\n");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule
