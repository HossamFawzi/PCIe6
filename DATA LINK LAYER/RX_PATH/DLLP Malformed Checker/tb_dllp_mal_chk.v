// =============================================================================
// tb_dllp_mal_chk.v  — FINAL VERSION (timing fixed)
// PCIe Gen6 — Module 16: DLLP Malformed Checker Testbench
// =============================================================================
//
// TIMING RULE (applied everywhere):
//   @(negedge clk)  drive inputs + assert valid
//   @(posedge clk)  DUT captures
//   #1              sample outputs (registered, settled)
//   -- checks here --
//   @(negedge clk)  deassert valid
//
// ALL reg declarations at MODULE LEVEL — no unnamed begin/end errors.
// =============================================================================

`timescale 1ns/1ps

module tb_dllp_mal_chk;

    // ── DUT ports ─────────────────────────────────────────────────────────────
    reg         clk;
    reg         rst_n;
    reg  [47:0] dllp_body;
    reg         dllp_crc_ok;
    reg         dllp_valid_in;

    wire        dllp_type_ok;
    wire        dllp_mal_err;
    wire [47:0] dllp_clean;
    wire        dllp_clean_valid;

    // ── Test infrastructure — ALL at module level ─────────────────────────────
    integer pass_count;
    integer fail_count;
    integer test_num;
    integer burst_pass;
    integer burst_err;
    integer i;
    reg [47:0] burst_bodies [0:4];

    // ── DUT instantiation ─────────────────────────────────────────────────────
    dllp_mal_chk u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .dllp_body       (dllp_body),
        .dllp_crc_ok     (dllp_crc_ok),
        .dllp_valid_in   (dllp_valid_in),
        .dllp_type_ok    (dllp_type_ok),
        .dllp_mal_err    (dllp_mal_err),
        .dllp_clean      (dllp_clean),
        .dllp_clean_valid(dllp_clean_valid)
    );

    // ── Clock: 100 MHz ────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ── Waveform dump ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("dllp_mal_chk.vcd");
        $dumpvars(0, tb_dllp_mal_chk);
    end

    // =========================================================================
    // HELPER: check()
    // =========================================================================
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
                $display("         type_ok=%b mal_err=%b clean_valid=%b clean=%h",
                         dllp_type_ok, dllp_mal_err, dllp_clean_valid, dllp_clean);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // =========================================================================
    // HELPER: idle(n)
    // =========================================================================
    task idle;
        input integer n;
        begin repeat(n) @(posedge clk); end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        pass_count    = 0;
        fail_count    = 0;
        test_num      = 0;
        burst_pass    = 0;
        burst_err     = 0;
        i             = 0;
        rst_n         = 1'b0;
        dllp_body     = 48'd0;
        dllp_crc_ok   = 1'b0;
        dllp_valid_in = 1'b0;

        $display("\n================================================================");
        $display("  PCIe Gen6 DLL RX - Module 16: DLLP Malformed Checker TB");
        $display("================================================================\n");

        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[RESET] Released.\n");

        // =====================================================================
        // TC1: ACK (0x00) valid — all reserved bits zero
        // =====================================================================
        $display("--- TC1: ACK (0x00) valid ---");
        @(negedge clk);
        dllp_body     = {8'h00, 16'h0000, 12'hABC, 12'h000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "ACK: type_ok");
        check(dllp_clean_valid=== 1'b1, "ACK: clean_valid");
        check(dllp_mal_err    === 1'b0, "ACK: no mal_err");
        check(dllp_clean      === {8'h00, 16'h0000, 12'hABC, 12'h000}, "ACK: body forwarded");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC2: NAK (0x10) valid
        // =====================================================================
        $display("\n--- TC2: NAK (0x10) valid ---");
        @(negedge clk);
        dllp_body     = {8'h10, 16'h0000, 12'h123, 12'h000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "NAK: type_ok");
        check(dllp_clean_valid=== 1'b1, "NAK: clean_valid");
        check(dllp_mal_err    === 1'b0, "NAK: no mal_err");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC3: UpdateFC Posted (0x40) VC0 valid
        // =====================================================================
        $display("\n--- TC3: UpdateFC Posted (0x40) valid ---");
        @(negedge clk);
        dllp_body     = {8'h40, 4'h0, 8'h10, 12'h080, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "UPD_P: type_ok");
        check(dllp_clean_valid=== 1'b1, "UPD_P: clean_valid");
        check(dllp_mal_err    === 1'b0, "UPD_P: no mal_err");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC4: UpdateFC NP (0x50) NPD=0 valid
        // =====================================================================
        $display("\n--- TC4: UpdateFC NP (0x50) NPD=0 valid ---");
        @(negedge clk);
        dllp_body     = {8'h50, 4'h0, 8'h08, 12'h000, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "UPD_NP: type_ok");
        check(dllp_clean_valid=== 1'b1, "UPD_NP: clean_valid");
        check(dllp_mal_err    === 1'b0, "UPD_NP: no mal_err");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC5: UpdateFC CPL (0x60) valid
        // =====================================================================
        $display("\n--- TC5: UpdateFC CPL (0x60) valid ---");
        @(negedge clk);
        dllp_body     = {8'h60, 4'h0, 8'h20, 12'h100, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "UPD_CPL: type_ok");
        check(dllp_clean_valid=== 1'b1, "UPD_CPL: clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC6: InitFC1 Posted (0xC0) valid
        // =====================================================================
        $display("\n--- TC6: InitFC1 Posted (0xC0) valid ---");
        @(negedge clk);
        dllp_body     = {8'hC0, 4'h0, 8'h20, 12'h080, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "IFC1_P: type_ok");
        check(dllp_clean_valid=== 1'b1, "IFC1_P: clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC7: InitFC1 NP (0xD0) NPD=0 valid
        // =====================================================================
        $display("\n--- TC7: InitFC1 NP (0xD0) valid ---");
        @(negedge clk);
        dllp_body     = {8'hD0, 4'h0, 8'h08, 12'h000, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "IFC1_NP: type_ok");
        check(dllp_clean_valid=== 1'b1, "IFC1_NP: clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC8: InitFC1 CPL (0xE0) valid
        // =====================================================================
        $display("\n--- TC8: InitFC1 CPL (0xE0) valid ---");
        @(negedge clk);
        dllp_body     = {8'hE0, 4'h0, 8'h20, 12'h080, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "IFC1_CPL: type_ok");
        check(dllp_clean_valid=== 1'b1, "IFC1_CPL: clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC9: InitFC2 Posted (0x80) valid
        // =====================================================================
        $display("\n--- TC9: InitFC2 Posted (0x80) valid ---");
        @(negedge clk);
        dllp_body     = {8'h80, 4'h0, 8'h20, 12'h080, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "IFC2_P: type_ok");
        check(dllp_clean_valid=== 1'b1, "IFC2_P: clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC10: InitFC2 NP (0x90) NPD=0 valid
        // =====================================================================
        $display("\n--- TC10: InitFC2 NP (0x90) valid ---");
        @(negedge clk);
        dllp_body     = {8'h90, 4'h0, 8'h08, 12'h000, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "IFC2_NP: type_ok");
        check(dllp_clean_valid=== 1'b1, "IFC2_NP: clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC11: InitFC2 CPL (0xA0) valid
        // =====================================================================
        $display("\n--- TC11: InitFC2 CPL (0xA0) valid ---");
        @(negedge clk);
        dllp_body     = {8'hA0, 4'h0, 8'h20, 12'h080, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "IFC2_CPL: type_ok");
        check(dllp_clean_valid=== 1'b1, "IFC2_CPL: clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC12: PM_Enter_L1 (0x20) valid
        // =====================================================================
        $display("\n--- TC12: PM_Enter_L1 (0x20) valid ---");
        @(negedge clk);
        dllp_body     = {8'h20, 40'h00_00_00_00_00};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "PM_L1: type_ok");
        check(dllp_clean_valid=== 1'b1, "PM_L1: clean_valid");
        check(dllp_mal_err    === 1'b0, "PM_L1: no mal_err");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC13: NOP (0x31) valid
        // =====================================================================
        $display("\n--- TC13: NOP (0x31) valid ---");
        @(negedge clk);
        dllp_body     = {8'h31, 40'h00_00_00_00_00};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "NOP: type_ok");
        check(dllp_clean_valid=== 1'b1, "NOP: clean_valid");
        check(dllp_mal_err    === 1'b0, "NOP: no mal_err");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC14: Vendor-Defined (0x30) valid
        // =====================================================================
        $display("\n--- TC14: Vendor-Defined (0x30) valid ---");
        @(negedge clk);
        dllp_body     = {8'h30, 40'hDE_AD_BE_EF_CA};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "VD: type_ok");
        check(dllp_clean_valid=== 1'b1, "VD: clean_valid");
        check(dllp_mal_err    === 1'b0, "VD: no mal_err");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC15: Reserved type 0xFF → malformed
        // =====================================================================
        $display("\n--- TC15: Reserved 0xFF → malformed ---");
        @(negedge clk);
        dllp_body     = {8'hFF, 40'h00_00_00_00_00};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1,  "RSVD_FF: mal_err");
        check(dllp_type_ok    === 1'b0,  "RSVD_FF: no type_ok");
        check(dllp_clean_valid=== 1'b0,  "RSVD_FF: no clean_valid");
        check(dllp_clean      === 48'd0, "RSVD_FF: clean=0 (no leak)");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC16: Reserved type 0x01 → malformed
        // =====================================================================
        $display("\n--- TC16: Reserved 0x01 → malformed ---");
        @(negedge clk);
        dllp_body     = {8'h01, 40'h00_00_00_00_00};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "RSVD_01: mal_err");
        check(dllp_clean_valid=== 1'b0, "RSVD_01: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC17: Reserved type 0x05 → malformed
        // =====================================================================
        $display("\n--- TC17: Reserved 0x05 → malformed ---");
        @(negedge clk);
        dllp_body     = {8'h05, 40'h00_00_00_00_00};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "RSVD_05: mal_err");
        check(dllp_clean_valid=== 1'b0, "RSVD_05: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC18: ACK with non-zero reserved upper bits → malformed (MAL[1])
        // =====================================================================
        $display("\n--- TC18: ACK reserved bits non-zero → malformed ---");
        @(negedge clk);
        dllp_body     = {8'h00, 16'hDEAD, 12'h001, 12'h000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "ACK_RSVD: mal_err");
        check(dllp_clean_valid=== 1'b0, "ACK_RSVD: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC19: NAK with non-zero reserved lower bits → malformed (MAL[1])
        // =====================================================================
        $display("\n--- TC19: NAK lower reserved bits non-zero → malformed ---");
        @(negedge clk);
        dllp_body     = {8'h10, 16'h0000, 12'h001, 12'hFFF};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "NAK_RSVD: mal_err");
        check(dllp_clean_valid=== 1'b0, "NAK_RSVD: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC20: UpdateFC Posted VC ID=1 → malformed (MAL[2])
        // =====================================================================
        $display("\n--- TC20: UpdateFC Posted VC=1 → malformed ---");
        @(negedge clk);
        dllp_body     = {8'h40, 4'h1, 8'h10, 12'h080, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "UPD_P_VC1: mal_err");
        check(dllp_clean_valid=== 1'b0, "UPD_P_VC1: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC21: InitFC1 NP VC=3 → malformed (MAL[2])
        // =====================================================================
        $display("\n--- TC21: InitFC1 NP VC=3 → malformed ---");
        @(negedge clk);
        dllp_body     = {8'hD0, 4'h3, 8'h08, 12'h000, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "IFC1_NP_VC3: mal_err");
        check(dllp_clean_valid=== 1'b0, "IFC1_NP_VC3: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC22: UpdateFC NP non-zero DataFC → malformed (MAL[3])
        // =====================================================================
        $display("\n--- TC22: UpdateFC NP non-zero DataFC → malformed ---");
        @(negedge clk);
        dllp_body     = {8'h50, 4'h0, 8'h08, 12'hFFF, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "UPD_NP_NPD: mal_err");
        check(dllp_clean_valid=== 1'b0, "UPD_NP_NPD: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC23: InitFC1 NP non-zero DataFC → malformed (MAL[3])
        // =====================================================================
        $display("\n--- TC23: InitFC1 NP non-zero DataFC → malformed ---");
        @(negedge clk);
        dllp_body     = {8'hD0, 4'h0, 8'h08, 12'h100, 16'h0000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "IFC1_NP_NPD: mal_err");
        check(dllp_clean_valid=== 1'b0, "IFC1_NP_NPD: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC24: crc_ok=0 → module must NOT process
        // =====================================================================
        $display("\n--- TC24: crc_ok=0 → no processing ---");
        @(negedge clk);
        dllp_body     = {8'h00, 16'h0000, 12'hABC, 12'h000};
        dllp_crc_ok   = 1'b0;   // CRC failed
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b0, "CRC_FAIL: no type_ok");
        check(dllp_clean_valid=== 1'b0, "CRC_FAIL: no clean_valid");
        check(dllp_mal_err    === 1'b0, "CRC_FAIL: no mal_err");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC25: valid_in=0 → no processing
        // =====================================================================
        $display("\n--- TC25: valid_in=0 → no processing ---");
        @(negedge clk);
        dllp_body     = {8'hFF, 40'hFF_FF_FF_FF_FF};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b0;   // valid LOW
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b0, "VALID_LOW: no type_ok");
        check(dllp_clean_valid=== 1'b0, "VALID_LOW: no clean_valid");
        check(dllp_mal_err    === 1'b0, "VALID_LOW: no mal_err");
        @(negedge clk);
        dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC26: 1-cycle pulse check
        // =====================================================================
        $display("\n--- TC26: 1-cycle pulse check ---");
        @(negedge clk);
        dllp_body     = {8'h00, 16'h0000, 12'h001, 12'h000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b1, "PULSE: type_ok HIGH N+1");
        check(dllp_clean_valid=== 1'b1, "PULSE: clean_valid HIGH N+1");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b0, "PULSE: type_ok cleared N+2");
        check(dllp_clean_valid=== 1'b0, "PULSE: clean_valid cleared N+2");
        idle(2);

        // =====================================================================
        // TC27: Back-to-back valid ACK then reserved type
        // =====================================================================
        $display("\n--- TC27: back-to-back valid then malformed ---");
        // Packet 1: valid ACK
        @(negedge clk);
        dllp_body     = {8'h00, 16'h0000, 12'h005, 12'h000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_clean_valid=== 1'b1, "BB: ACK clean_valid");
        check(dllp_mal_err    === 1'b0, "BB: ACK no mal_err");
        // Packet 2: reserved type
        @(negedge clk);
        dllp_body     = {8'hAA, 40'h00_00_00_00_00};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1, "BB: reserved mal_err");
        check(dllp_clean_valid=== 1'b0, "BB: reserved no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC28: dllp_clean=0 on malformed (no data leak)
        // =====================================================================
        $display("\n--- TC28: dllp_clean=0 on malformed ---");
        @(negedge clk);
        dllp_body     = {8'hBB, 40'hDE_AD_BE_EF_CA};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(posedge clk); #1;
        check(dllp_mal_err    === 1'b1,  "LEAK: mal_err");
        check(dllp_clean      === 48'd0, "LEAK: clean=0 (no leak)");
        check(dllp_clean_valid=== 1'b0,  "LEAK: no clean_valid");
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        idle(2);

        // =====================================================================
        // TC29: Reset during operation
        // =====================================================================
        $display("\n--- TC29: Reset during operation ---");
        @(negedge clk);
        dllp_body     = {8'h00, 16'h0000, 12'h007, 12'h000};
        dllp_crc_ok   = 1'b1;
        dllp_valid_in = 1'b1;
        @(negedge clk);
        rst_n         = 1'b0;
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        @(posedge clk); #1;
        check(dllp_type_ok    === 1'b0,  "RST: type_ok=0");
        check(dllp_mal_err    === 1'b0,  "RST: mal_err=0");
        check(dllp_clean_valid=== 1'b0,  "RST: clean_valid=0");
        check(dllp_clean      === 48'd0, "RST: clean=0");
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        $display("[INFO] Reset released.");
        idle(2);

        // =====================================================================
        // TC30: Burst of 5 valid DLLPs — all pass
        // =====================================================================
        $display("\n--- TC30: Burst of 5 valid DLLPs ---");
        burst_bodies[0] = {8'h00, 16'h0000, 12'h001, 12'h000};
        burst_bodies[1] = {8'h10, 16'h0000, 12'h002, 12'h000};
        burst_bodies[2] = {8'h40, 4'h0, 8'h10, 12'h080, 16'h0000};
        burst_bodies[3] = {8'h60, 4'h0, 8'h20, 12'h100, 16'h0000};
        burst_bodies[4] = {8'h31, 40'h00_00_00_00_00};
        burst_pass = 0;
        burst_err  = 0;

        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            dllp_body     = burst_bodies[i];
            dllp_crc_ok   = 1'b1;
            dllp_valid_in = 1'b1;
            @(posedge clk); #1;
            if (dllp_clean_valid && dllp_type_ok) burst_pass = burst_pass + 1;
            if (dllp_mal_err)                     burst_err  = burst_err  + 1;
        end
        @(negedge clk);
        dllp_valid_in = 1'b0; dllp_crc_ok = 1'b0; dllp_body = 48'd0;
        check(burst_pass === 5, "BURST: all 5 passed");
        check(burst_err  === 0, "BURST: zero mal_err");
        idle(3);

        // =====================================================================
        // FINAL RESULTS
        // =====================================================================
        $display("\n================================================================");
        $display("  DLLP Malformed Checker - Final Result");
        $display("  PASS = %0d  |  FAIL = %0d  |  TOTAL = %0d",
                 pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** %0d TESTS FAILED ***", fail_count);
        $display("================================================================\n");
        $finish;
    end

    // ── Watchdog ──────────────────────────────────────────────────────────────
    initial begin
        #200000;
        $display("[WATCHDOG] 200us — force finish.");
        $finish;
    end

endmodule
