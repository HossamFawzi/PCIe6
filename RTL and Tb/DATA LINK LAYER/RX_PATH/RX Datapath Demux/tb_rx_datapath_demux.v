// =============================================================================
// Testbench : tb_rx_datapath_demux
// DUT       : rx_datapath_demux
// Coverage  :
//   TC1 – FLIT mode: TLP-only input → tlp_rx_valid, dllp stays low
//   TC2 – FLIT mode: DLLP-only input → dllp_rx_valid, tlp stays low
//   TC3 – FLIT mode: both valid → both outputs valid simultaneously
//   TC4 – Legacy mode: STP framing byte → tlp_rx_valid
//   TC5 – Legacy mode: SDP framing byte → dllp_rx_valid
//   TC6 – Legacy mode: unknown framing → rx_parse_err (no data)
//   TC7 – Legacy mode: COM byte (0xBC) → silently ignored, no error
//   TC8 – Mode switch mid-stream: no stale data leaks across mode boundary
// =============================================================================

`timescale 1ns/1ps

module tb_rx_datapath_demux;

    // ── DUT ports ─────────────────────────────────────────────────────────────
    reg          clk;
    reg          rst_n;
    reg [255:0]  rx_data;
    reg          rx_valid;
    reg [1023:0] flit_tlp;
    reg          flit_tlp_valid;
    reg [63:0]   flit_dllp;
    reg          flit_dllp_valid;
    reg          flit_mode_en;

    wire [1055:0] tlp_rx;
    wire          tlp_rx_valid;
    wire [63:0]   dllp_raw;
    wire          dllp_rx_valid;
    wire          rx_parse_err;

    // ── DUT instantiation ─────────────────────────────────────────────────────
    rx_datapath_demux dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .rx_data        (rx_data),
        .rx_valid       (rx_valid),
        .flit_tlp       (flit_tlp),
        .flit_tlp_valid (flit_tlp_valid),
        .flit_dllp      (flit_dllp),
        .flit_dllp_valid(flit_dllp_valid),
        .flit_mode_en   (flit_mode_en),
        .tlp_rx         (tlp_rx),
        .tlp_rx_valid   (tlp_rx_valid),
        .dllp_raw       (dllp_raw),
        .dllp_rx_valid  (dllp_rx_valid),
        .rx_parse_err   (rx_parse_err)
    );

    // ── Clock: 250 MHz ────────────────────────────────────────────────────────
    initial clk = 0;
    always #2 clk = ~clk;

    // ── Scoreboard ────────────────────────────────────────────────────────────
    integer pass_count = 0;
    integer fail_count = 0;

    task check1;
        input [255:0] label;
        input         expected;
        input         actual;
        begin
            if (expected === actual) begin
                $display("[PASS] %s | exp=%b got=%b", label, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %s | exp=%b got=%b  @%0t", label, expected, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ── Reset all inputs ──────────────────────────────────────────────────────
    task reset_inputs;
        begin
            rx_data        <= 256'b0;
            rx_valid       <= 1'b0;
            flit_tlp       <= 1024'b0;
            flit_tlp_valid <= 1'b0;
            flit_dllp      <= 64'b0;
            flit_dllp_valid<= 1'b0;
        end
    endtask

    // ── FLIT mode helpers ─────────────────────────────────────────────────────
    task flit_send_tlp;
        input [1023:0] tlp_data;
        begin
            @(posedge clk);
            flit_tlp       <= tlp_data;
            flit_tlp_valid <= 1'b1;
            flit_dllp_valid<= 1'b0;
            @(posedge clk);
            flit_tlp_valid <= 1'b0;
        end
    endtask

    task flit_send_dllp;
        input [63:0] dllp_data;
        begin
            @(posedge clk);
            flit_dllp       <= dllp_data;
            flit_dllp_valid <= 1'b1;
            flit_tlp_valid  <= 1'b0;
            @(posedge clk);
            flit_dllp_valid <= 1'b0;
        end
    endtask

    task flit_send_mixed;
        input [1023:0] tlp_data;
        input [63:0]   dllp_data;
        begin
            @(posedge clk);
            flit_tlp        <= tlp_data;
            flit_tlp_valid  <= 1'b1;
            flit_dllp       <= dllp_data;
            flit_dllp_valid <= 1'b1;
            @(posedge clk);
            flit_tlp_valid  <= 1'b0;
            flit_dllp_valid <= 1'b0;
        end
    endtask

    // ── Legacy mode helpers ───────────────────────────────────────────────────
    localparam STP = 8'hFB;
    localparam SDP = 8'hFC;
    localparam COM = 8'hBC;

    task legacy_send;
        input [7:0]   framing_byte;
        input [247:0] payload;
        begin
            @(posedge clk);
            rx_data  <= {payload, framing_byte};  // LS byte = framing
            rx_valid <= 1'b1;
            @(posedge clk);
            rx_valid <= 1'b0;
        end
    endtask

    // ── Test sequence ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_rx_datapath_demux.vcd");
        $dumpvars(0, tb_rx_datapath_demux);

        // ── Reset ──────────────────────────────────────────────────────────
        rst_n        = 0;
        flit_mode_en = 0;
        reset_inputs;
        repeat(4) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // ==================================================================
        // FLIT MODE tests
        // ==================================================================
        flit_mode_en = 1;
        $display("\n=== FLIT MODE ===");

        // ── TC1: FLIT mode TLP only ────────────────────────────────────────
        $display("\n--- TC1: FLIT mode TLP only ---");
        flit_send_tlp(1024'hDEADC0DE_CAFE_BABE);
        @(posedge clk);
        check1("TC1 tlp_rx_valid",  1'b1, tlp_rx_valid);
        check1("TC1 dllp_rx_valid", 1'b0, dllp_rx_valid);
        check1("TC1 rx_parse_err",  1'b0, rx_parse_err);
        repeat(2) @(posedge clk);

        // ── TC2: FLIT mode DLLP only ───────────────────────────────────────
        $display("\n--- TC2: FLIT mode DLLP only ---");
        flit_send_dllp(64'hAABBCCDD11223344);
        @(posedge clk);
        check1("TC2 tlp_rx_valid",  1'b0, tlp_rx_valid);
        check1("TC2 dllp_rx_valid", 1'b1, dllp_rx_valid);
        repeat(2) @(posedge clk);

        // ── TC3: FLIT mode mixed ───────────────────────────────────────────
        $display("\n--- TC3: FLIT mode MIXED (both valid simultaneously) ---");
        flit_send_mixed(1024'h1111, 64'h2222_3333_4444_5555);
        @(posedge clk);
        check1("TC3 tlp_rx_valid",  1'b1, tlp_rx_valid);
        check1("TC3 dllp_rx_valid", 1'b1, dllp_rx_valid);
        repeat(2) @(posedge clk);

        // ==================================================================
        // LEGACY MODE tests
        // ==================================================================
        flit_mode_en = 0;
        reset_inputs;
        repeat(2) @(posedge clk);
        $display("\n=== LEGACY MODE ===");

        // ── TC4: STP → TLP ────────────────────────────────────────────────
        $display("\n--- TC4: Legacy STP framing → TLP ---");
        legacy_send(STP, 248'hDEAD_FACE_CAFE);
        @(posedge clk);
        check1("TC4 tlp_rx_valid",  1'b1, tlp_rx_valid);
        check1("TC4 dllp_rx_valid", 1'b0, dllp_rx_valid);
        check1("TC4 rx_parse_err",  1'b0, rx_parse_err);
        repeat(2) @(posedge clk);

        // ── TC5: SDP → DLLP ───────────────────────────────────────────────
        $display("\n--- TC5: Legacy SDP framing → DLLP ---");
        legacy_send(SDP, 248'h4F4F4F4F4F4F);
        @(posedge clk);
        check1("TC5 tlp_rx_valid",  1'b0, tlp_rx_valid);
        check1("TC5 dllp_rx_valid", 1'b1, dllp_rx_valid);
        check1("TC5 rx_parse_err",  1'b0, rx_parse_err);
        repeat(2) @(posedge clk);

        // ── TC6: Unknown framing → rx_parse_err ───────────────────────────
        $display("\n--- TC6: Unknown framing byte → rx_parse_err ---");
        legacy_send(8'hAA /*unknown*/, 248'h0);
        @(posedge clk);
        check1("TC6 rx_parse_err",  1'b1, rx_parse_err);
        check1("TC6 tlp_rx_valid",  1'b0, tlp_rx_valid);
        check1("TC6 dllp_rx_valid", 1'b0, dllp_rx_valid);
        repeat(2) @(posedge clk);

        // ── TC7: COM (0xBC) → silently ignored ────────────────────────────
        $display("\n--- TC7: COM byte (0xBC) → silently ignored ---");
        legacy_send(COM, 248'h0);
        @(posedge clk);
        check1("TC7 rx_parse_err",  1'b0, rx_parse_err);
        check1("TC7 tlp_rx_valid",  1'b0, tlp_rx_valid);
        check1("TC7 dllp_rx_valid", 1'b0, dllp_rx_valid);
        repeat(2) @(posedge clk);

        // ── TC8: Mode switch mid-stream ────────────────────────────────────
        $display("\n--- TC8: Mode switch FLIT→Legacy→FLIT (no stale data) ---");
        // Drive FLIT mode inputs, then switch to legacy and verify no false valid
        flit_mode_en   = 1;
        flit_tlp_valid = 1'b0;
        flit_dllp_valid= 1'b0;
        @(posedge clk);
        flit_mode_en   = 0;  // switch to legacy
        rx_valid       <= 1'b0;
        @(posedge clk);
        check1("TC8 tlp_rx_valid during switch",  1'b0, tlp_rx_valid);
        check1("TC8 dllp_rx_valid during switch",  1'b0, dllp_rx_valid);
        flit_mode_en = 1;  // switch back
        @(posedge clk);
        check1("TC8 tlp_rx_valid after switch back", 1'b0, tlp_rx_valid);
        repeat(2) @(posedge clk);

        // ── Summary ───────────────────────────────────────────────────────
        $display("\n========================================");
        $display("  RX Datapath Demux TB: %0d PASS / %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

    initial begin
        #50000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
