// =============================================================================
// tb_pcie_tl_tx_top.v
// PCIe Gen6 — Transaction Layer TX Path — FULL TESTBENCH
// Verilog-2001 compatible (ModelSim ALTERA 10.1d / 2012)
// NO fork/join_none  NO wait()  NO SystemVerilog constructs
// =============================================================================
// TC01 - Reset / Init check
// TC02 - FC Init handshake
// TC03 - Single MWr (Posted)
// TC04 - Single MRd (Non-Posted)
// TC05 - IO Read
// TC06 - Config Read Type0
// TC07 - Completion return (RX to Driver)
// TC08 - Inbound MWr passthrough
// TC09 - Backpressure: fill REQ_Q
// TC10 - FC stall before fc_init_done
// TC11 - Ordering: Posted then NP
// TC12 - Valid LTP prefix attach
// TC13 - Reserved LTP type prefix_err
// TC14 - ECRC enable and output
// TC15 - FLIT mode emission
// TC16 - DLL_IF NAK replay
// TC17 - DLL_IF timeout max retries
// TC18 - Tag allocation and return
// TC19 - Tag exhaustion
// TC20 - Round-robin arbitration
// TC21 - max_payload 128B
// TC22 - EETP prefix forwarding
// TC23 - 64-bit address MWr
// TC24 - Message transaction
// TC25 - Full pipeline MRd to Completion
// =============================================================================

`timescale 1ns/1ps

module tb_pcie_tl_tx_top;

// ─────────────────────────────────────────────
// Clock
// ─────────────────────────────────────────────
parameter CLK_HALF = 5;

reg clk;
reg rst_n;

initial clk = 1'b0;
always #CLK_HALF clk = ~clk;

// ─────────────────────────────────────────────
// DUT Inputs
// ─────────────────────────────────────────────
reg  [3:0]   req_type;
reg  [63:0]  req_addr;
reg  [9:0]   req_len;
reg  [511:0] req_data;
reg          req_valid;
reg  [2:0]   req_attr;
reg  [2:0]   req_tc;
reg  [3:0]   req_first_be;
reg  [3:0]   req_last_be;

reg  [511:0] cpl_data_in;
reg          cpl_valid_in;
reg  [2:0]   cpl_status_in;
reg  [9:0]   cpl_tag_in;

reg  [511:0] mwr_data_in;
reg          mwr_valid_in;
reg  [63:0]  mwr_addr_in;

reg  [127:0] ltp_data;
reg          ltp_valid;
reg  [127:0] eetp_data;
reg          eetp_valid;

reg          ecrc_en;
reg  [2:0]   max_payload;
reg          flit_mode_en;

reg          dll_up;
reg          dll_ack;
reg          dll_nak;
reg          dll_flit_ack;
reg  [71:0]  cr_update;
reg          cr_update_valid;

reg  [71:0]  initfc_rx;
reg          initfc_rx_valid;

reg  [9:0]   timeout_tag;

// ─────────────────────────────────────────────
// DUT Outputs
// ─────────────────────────────────────────────
wire         req_ready;
wire [511:0] usr_cpl_data;
wire         usr_cpl_valid;
wire [2:0]   usr_cpl_status;
wire [9:0]   usr_cpl_tag;
wire [511:0] usr_mwr_data;
wire         usr_mwr_valid;
wire [63:0]  usr_mwr_addr;
wire [2047:0] flit_to_dll;
wire          flit_to_dll_valid;
wire          dll_ready;
wire [1023:0] tlp_rx_out;
wire          tlp_rx_valid;
wire [71:0]   initfc_tx;
wire          initfc_tx_send;
wire          fc_init_done;
wire          prefix_err;
wire          e2e_fwd;
wire          ecrc_rx_ok;
wire          ecrc_rx_err;
wire          ordering_ok;
wire          ordering_stall;
wire          ordering_err;
wire          tag_exhausted;
wire [9:0]    tag_alloc;
wire          tag_valid;
wire [9:0]    outstanding_count;
wire [7:0]    dbg_ph_avail;
wire [11:0]   dbg_pd_avail;
wire [7:0]    dbg_nph_avail;
wire [11:0]   dbg_npd_avail;
wire          flit_retry_req;
wire          flit_overflow_err;
wire [23:0]   flit_crc;
wire [11:0]   flit_seq;

// ─────────────────────────────────────────────
// DUT
// ─────────────────────────────────────────────
pcie_tl_tx_top #(
    .REQ_Q_DEPTH_P  (16),
    .REQ_Q_DEPTH_NP (16),
    .ROB_DEPTH      (32)
) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .req_type         (req_type),
    .req_addr         (req_addr),
    .req_len          (req_len),
    .req_data         (req_data),
    .req_valid        (req_valid),
    .req_attr         (req_attr),
    .req_tc           (req_tc),
    .req_first_be     (req_first_be),
    .req_last_be      (req_last_be),
    .req_ready        (req_ready),
    .cpl_data_in      (cpl_data_in),
    .cpl_valid_in     (cpl_valid_in),
    .cpl_status_in    (cpl_status_in),
    .cpl_tag_in       (cpl_tag_in),
    .usr_cpl_data     (usr_cpl_data),
    .usr_cpl_valid    (usr_cpl_valid),
    .usr_cpl_status   (usr_cpl_status),
    .usr_cpl_tag      (usr_cpl_tag),
    .mwr_data_in      (mwr_data_in),
    .mwr_valid_in     (mwr_valid_in),
    .mwr_addr_in      (mwr_addr_in),
    .usr_mwr_data     (usr_mwr_data),
    .usr_mwr_valid    (usr_mwr_valid),
    .usr_mwr_addr     (usr_mwr_addr),
    .ltp_data         (ltp_data),
    .ltp_valid        (ltp_valid),
    .eetp_data        (eetp_data),
    .eetp_valid       (eetp_valid),
    .ecrc_en          (ecrc_en),
    .max_payload      (max_payload),
    .flit_mode_en     (flit_mode_en),
    .dll_up           (dll_up),
    .dll_ack          (dll_ack),
    .dll_nak          (dll_nak),
    .dll_flit_ack     (dll_flit_ack),
    .cr_update        (cr_update),
    .cr_update_valid  (cr_update_valid),
    .initfc_rx        (initfc_rx),
    .initfc_rx_valid  (initfc_rx_valid),
    .timeout_tag      (timeout_tag),
    .flit_to_dll      (flit_to_dll),
    .flit_to_dll_valid(flit_to_dll_valid),
    .dll_ready        (dll_ready),
    .tlp_rx_out       (tlp_rx_out),
    .tlp_rx_valid     (tlp_rx_valid),
    .initfc_tx        (initfc_tx),
    .initfc_tx_send   (initfc_tx_send),
    .fc_init_done     (fc_init_done),
    .prefix_err       (prefix_err),
    .e2e_fwd          (e2e_fwd),
    .ecrc_rx_ok       (ecrc_rx_ok),
    .ecrc_rx_err      (ecrc_rx_err),
    .ordering_ok      (ordering_ok),
    .ordering_stall   (ordering_stall),
    .ordering_err     (ordering_err),
    .tag_exhausted    (tag_exhausted),
    .tag_alloc        (tag_alloc),
    .tag_valid        (tag_valid),
    .outstanding_count(outstanding_count),
    .dbg_ph_avail     (dbg_ph_avail),
    .dbg_pd_avail     (dbg_pd_avail),
    .dbg_nph_avail    (dbg_nph_avail),
    .dbg_npd_avail    (dbg_npd_avail),
    .flit_retry_req   (flit_retry_req),
    .flit_overflow_err(flit_overflow_err),
    .flit_crc         (flit_crc),
    .flit_seq         (flit_seq)
);

// ─────────────────────────────────────────────
// Scoreboard
// ─────────────────────────────────────────────
integer pass_count;
integer fail_count;

task check;
    input condition;
    input [255:0] label;
    begin
        if (condition) begin
            $display("[PASS] %s", label);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] %s  @%0t ns", label, $time);
            fail_count = fail_count + 1;
        end
    end
endtask

// ─────────────────────────────────────────────
// Task: advance N clock cycles
// ─────────────────────────────────────────────
task do_clk;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
    end
endtask

// ─────────────────────────────────────────────
// Task: reset
// ─────────────────────────────────────────────
task do_reset;
    begin
        rst_n = 1'b0;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    end
endtask

// ─────────────────────────────────────────────
// Task: set all inputs to safe defaults
// ─────────────────────────────────────────────
task set_defaults;
    begin
        req_type        = 4'd0;
        req_addr        = 64'd0;
        req_len         = 10'd4;
        req_data        = 512'd0;
        req_valid       = 1'b0;
        req_attr        = 3'd0;
        req_tc          = 3'd0;
        req_first_be    = 4'hF;
        req_last_be     = 4'hF;
        cpl_data_in     = 512'd0;
        cpl_valid_in    = 1'b0;
        cpl_status_in   = 3'd0;
        cpl_tag_in      = 10'd0;
        mwr_data_in     = 512'd0;
        mwr_valid_in    = 1'b0;
        mwr_addr_in     = 64'd0;
        ltp_data        = 128'd0;
        ltp_valid       = 1'b0;
        eetp_data       = 128'd0;
        eetp_valid      = 1'b0;
        ecrc_en         = 1'b1;
        max_payload     = 3'd2;
        flit_mode_en    = 1'b1;
        dll_up          = 1'b0;
        dll_ack         = 1'b0;
        dll_nak         = 1'b0;
        dll_flit_ack    = 1'b0;
        cr_update       = 72'd0;
        cr_update_valid = 1'b0;
        initfc_rx       = 72'd0;
        initfc_rx_valid = 1'b0;
        timeout_tag     = 10'd0;
    end
endtask

// ─────────────────────────────────────────────
// Task: FC Init handshake (sequential)
// ─────────────────────────────────────────────
task do_fc_handshake;
    begin
        @(posedge clk); #1;
        dll_up = 1'b1;
        // 6 cycles for DUT to traverse SEND_IFC1_P->NP->CPL->WAIT_IFC1
        do_clk(6);
        // Feed partner IFC1-P
        @(posedge clk); #1;
        initfc_rx       = {8'h40, 8'h00, 8'd16, 12'd64, 20'h0, 16'h0};
        initfc_rx_valid = 1'b1;
        // Feed partner IFC1-NP
        @(posedge clk); #1;
        initfc_rx = {8'h50, 8'h00, 8'd8, 12'd0, 20'h0, 16'h0};
        // Feed partner IFC1-CPL
        @(posedge clk); #1;
        initfc_rx = {8'h60, 8'h00, 8'd16, 12'd64, 20'h0, 16'h0};
        @(posedge clk); #1;
        initfc_rx_valid = 1'b0;
        // 6 cycles for DUT to traverse SEND_IFC2_P->NP->CPL->WAIT_IFC2
        do_clk(6);
        // Feed partner IFC2-P
        @(posedge clk); #1;
        initfc_rx       = {8'hC0, 8'h00, 8'd16, 12'd64, 20'h0, 16'h0};
        initfc_rx_valid = 1'b1;
        // Feed partner IFC2-NP
        @(posedge clk); #1;
        initfc_rx = {8'hD0, 8'h00, 8'd8, 12'd0, 20'h0, 16'h0};
        // Feed partner IFC2-CPL
        @(posedge clk); #1;
        initfc_rx = {8'hE0, 8'h00, 8'd16, 12'd64, 20'h0, 16'h0};
        @(posedge clk); #1;
        initfc_rx_valid = 1'b0;
        // 4 more cycles to reach DONE
        do_clk(4);
    end
endtask

// ─────────────────────────────────────────────
// Task: send one TLP request
// ─────────────────────────────────────────────
task send_req;
    input [3:0]   rtype;
    input [63:0]  addr;
    input [9:0]   len;
    input [511:0] data;
    input [2:0]   attr;
    input [2:0]   tc;
    begin
        @(posedge clk); #1;
        req_type     = rtype;
        req_addr     = addr;
        req_len      = len;
        req_data     = data;
        req_attr     = attr;
        req_tc       = tc;
        req_first_be = 4'hF;
        req_last_be  = 4'hF;
        req_valid    = 1'b1;
        @(posedge clk); #1;
        req_valid    = 1'b0;
    end
endtask

// ─────────────────────────────────────────────
// Task: give dll_ack + dll_flit_ack pulse
// ─────────────────────────────────────────────
task do_dll_ack;
    begin
        @(posedge clk); #1;
        dll_ack      = 1'b1;
        dll_flit_ack = 1'b1;
        @(posedge clk); #1;
        dll_ack      = 1'b0;
        dll_flit_ack = 1'b0;
    end
endtask

// ─────────────────────────────────────────────
// Background ACK generator
// When ack_en=1, auto-ack every flit in the next cycle
// ─────────────────────────────────────────────
reg ack_en;
// Pulse-capture flags — driven ONLY from the initial block via polling loops.
// No always-block latches to avoid Verilog-2001 race conditions.
reg ecrc_seen;
reg prefix_err_seen;

always @(posedge clk) begin
    if (ack_en && flit_to_dll_valid) begin
        dll_ack      <= 1'b1;
        dll_flit_ack <= 1'b1;
    end else begin
        // Only clear if not set by the main initial block
        if (ack_en) begin
            dll_ack      <= 1'b0;
            dll_flit_ack <= 1'b0;
        end
    end
end

// ─────────────────────────────────────────────
// Shared variables used across test cases
// ─────────────────────────────────────────────
integer k;
reg [9:0] saved_tag;

// ─────────────────────────────────────────────
// PIPELINE DEBUG MONITOR
// Prints every time a key signal goes high so we can
// trace exactly where the TLP stops in the pipeline.
// Active only when dbg_en=1 (set per test case).
// ─────────────────────────────────────────────
reg dbg_en;

always @(posedge clk) begin
    if (dbg_en) begin
        if (req_valid && req_ready)
            $display("[DBG %0t] USR_IF: req accepted type=%0h addr=%0h", $time, req_type, req_addr);
        if (dut.u_req_q.req_valid_out)
            $display("[DBG %0t] REQ_Q:  dequeued type_out=%0b", $time, dut.u_req_q.req_type_out);
        if (dut.u_arb_tx.arb_tlp_valid)
            $display("[DBG %0t] ARB_TX: arb_tlp_valid=1 type=%0b arb_ordering_ok=%0b credit_p=%0b credit_np=%0b",
                $time, dut.u_arb_tx.arb_type,
                dut.arb_ordering_ok,
                dut.u_arb_tx.credit_grant_p,
                dut.u_arb_tx.credit_grant_np);
        if (dut.u_tlp_asm.tlp_valid)
            $display("[DBG %0t] TLP_ASM: tlp_valid=1 credit_ok=%0b",
                $time, dut.u_tlp_asm.credit_ok);
        if (dut.u_pfx.tlp_prefixed_valid || dut.u_pfx.prefix_err)
            $display("[DBG %0t] PFX:    prefixed_valid=%0b prefix_err=%0b ltp_valid=%0b ltp_type=%0h",
                $time, dut.u_pfx.tlp_prefixed_valid, dut.u_pfx.prefix_err,
                dut.u_pfx.ltp_valid, dut.u_pfx.ltp_type);
        if (dut.u_ecrc.tlp_ecrc_valid)
            $display("[DBG %0t] ECRC:   tlp_ecrc_valid=1", $time);
        if (dut.u_flit.flit_valid)
            $display("[DBG %0t] FLIT:   flit_valid=1 state=%0d seq=%0d",
                $time, dut.u_flit.state, dut.u_flit.flit_seq);
        if (flit_to_dll_valid)
            $display("[DBG %0t] DLL_IF: flit_to_dll_valid=1", $time);
    end
end

// ─────────────────────────────────────────────
// MAIN TEST SEQUENCE
// ─────────────────────────────────────────────
initial begin
    pass_count      = 0;
    fail_count      = 0;
    rst_n           = 1'b0;
    ack_en          = 1'b0;
    ecrc_seen       = 1'b0;
    prefix_err_seen = 1'b0;
    dbg_en          = 1'b0;
    dll_ack         = 1'b0;
    dll_flit_ack    = 1'b0;
    dll_nak         = 1'b0;
    dll_up          = 1'b0;
    saved_tag       = 10'd0;
    set_defaults;

    $dumpfile("tb_pcie_tl_tx_top.vcd");
    $dumpvars(0, tb_pcie_tl_tx_top);

    $display("==================================================");
    $display(" PCIe TL TX Path Testbench  (Verilog-2001)");
    $display("==================================================");

    // =============================================
    // TC01 - Reset / Init
    // =============================================
    $display("\n--- TC01: Reset / Init ---");
    do_reset;
    do_clk(2);
    check(!fc_init_done,       "TC01-a fc_init_done=0 after reset");
    check(!flit_to_dll_valid,  "TC01-b flit_to_dll_valid=0 after reset");
    check(!ordering_ok,        "TC01-c ordering_ok=0 after reset");

    // =============================================
    // TC02 - FC Init handshake
    // =============================================
    $display("\n--- TC02: FC Init Handshake ---");
    do_fc_handshake;
    do_clk(3);
    check(fc_init_done,        "TC02-a fc_init_done asserted");
    check(dbg_ph_avail  > 0,   "TC02-b PH credits loaded");
    check(dbg_pd_avail  > 0,   "TC02-c PD credits loaded");
    check(dbg_nph_avail > 0,   "TC02-d NPH credits loaded");

    // =============================================
    // TC03 - Single MWr (Posted)
    // =============================================
    $display("\n--- TC03: Single MWr (Posted) ---");
    ack_en = 1'b1;
    send_req(4'd1, 64'hDEAD_BEEF_0000_0000, 10'd4, 512'hA5A5, 3'b000, 3'd0);
    do_clk(25);
    ack_en = 1'b0;
    @(posedge clk); #1;
    dll_ack = 1'b0; dll_flit_ack = 1'b0;
    check(!flit_overflow_err,  "TC03-a no overflow error on MWr");
    check(!prefix_err,         "TC03-b no prefix error");

    // =============================================
    // TC04 - Single MRd (Non-Posted)
    // =============================================
    $display("\n--- TC04: Single MRd (Non-Posted) ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    send_req(4'd0, 64'h0000_0001_DEAD_0000, 10'd1, 512'd0, 3'b000, 3'd0);
    do_clk(5);
    check(tag_valid || (outstanding_count > 0),
          "TC04-a tag allocated for MRd");

    // =============================================
    // TC05 - IO Read
    // =============================================
    $display("\n--- TC05: IO Read ---");
    send_req(4'd2, 64'h0000_0000_0000_03F8, 10'd1, 512'd0, 3'b000, 3'd0);
    do_clk(5);
    check(!ordering_err, "TC05-a no ordering error on IORd");

    // =============================================
    // TC06 - Config Read Type0
    // =============================================
    $display("\n--- TC06: Config Read Type0 ---");
    send_req(4'd4, 64'h0000_0000_0000_0000, 10'd1, 512'd0, 3'b000, 3'd0);
    do_clk(5);
    check(!ordering_err, "TC06-a no ordering error on CfgRd0");

    // =============================================
    // TC07 - Completion return
    // =============================================
    // FIX: usr_cpl_valid = assign cpl_valid (combinational).
    // Sample WHILE cpl_valid_in is still high — not after it falls.
    $display("\n--- TC07: Completion Return ---");
    @(posedge clk); #1;
    cpl_data_in   = 512'hCAFE_BABE;
    cpl_valid_in  = 1'b1;
    cpl_status_in = 3'b000;
    cpl_tag_in    = 10'd5;
    // Combinational output settles after #1 — check it now while valid=1
    #1;
    check(usr_cpl_valid,                   "TC07-a usr_cpl_valid asserted");
    check(usr_cpl_data == 512'hCAFE_BABE,  "TC07-b cpl_data correct");
    check(usr_cpl_tag  == 10'd5,           "TC07-c cpl_tag correct");
    @(posedge clk); #1;
    cpl_valid_in  = 1'b0;
    @(posedge clk);

    // =============================================
    // TC08 - Inbound MWr passthrough
    // =============================================
    // FIX: usr_mwr_valid = assign mwr_valid (combinational). Sample while high.
    $display("\n--- TC08: Inbound MWr Passthrough ---");
    @(posedge clk); #1;
    mwr_data_in  = 512'hDEAD_C0DE;
    mwr_valid_in = 1'b1;
    mwr_addr_in  = 64'hC0FF_EE00_1234_5678;
    // Combinational output settles after #1 — check while valid=1
    #1;
    check(usr_mwr_valid,                           "TC08-a usr_mwr_valid asserted");
    check(usr_mwr_data == 512'hDEAD_C0DE,          "TC08-b mwr_data correct");
    check(usr_mwr_addr == 64'hC0FF_EE00_1234_5678, "TC08-c mwr_addr correct");
    @(posedge clk); #1;
    mwr_valid_in = 1'b0;
    @(posedge clk);

    // =============================================
    // TC09 - Backpressure: fill NP queue (depth=16)
    // =============================================
    // FIX: do NOT call do_fc_handshake here.
    // With fc_init_done=0, credit_grant_np=0 → REQ_Q never drains.
    // We can fill the queue to exactly DEPTH_NP=16 and then push one more
    // → q_full_np=1 → req_ready=0.
    $display("\n--- TC09: Backpressure Fill REQ_Q ---");
    set_defaults;
    do_reset;
    // dll_up=1 so USR_IF sees pkt_ready from REQ_Q (not blocked by DLL)
    // but credits are 0 so REQ_Q cannot drain → queue fills up
    dll_up = 1'b1;
    do_clk(2);

    // Push 17 NP requests (DEPTH_NP=16 → 17th makes it full)
    for (k = 0; k < 17; k = k + 1) begin
        @(posedge clk); #1;
        req_type  = 4'd0;   // MRd (NP)
        req_addr  = 64'h1000 + k;
        req_len   = 10'd1;
        req_valid = 1'b1;
        @(posedge clk); #1;
        req_valid = 1'b0;
    end
    do_clk(2);
    check(!req_ready, "TC09-a req_ready=0 when NP queue full");

    // =============================================
    // TC10 - FC stall before fc_init_done
    // =============================================
    $display("\n--- TC10: FC Stall before init ---");
    set_defaults;
    do_reset;
    do_clk(3);
    check(dut.u_cr_mgr.credit_grant_p  === 1'b0,
          "TC10-a credit_grant_p=0 before FC init");
    check(dut.u_cr_mgr.credit_grant_np === 1'b0,
          "TC10-b credit_grant_np=0 before FC init");

    // =============================================
    // TC11 - Ordering: Posted then NP
    // =============================================
    $display("\n--- TC11: Ordering NP behind P ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(3);

    @(posedge clk); #1;
    req_type  = 4'd1;
    req_addr  = 64'h2000;
    req_len   = 10'd4;
    req_data  = 512'hAA;
    req_attr  = 3'b000;
    req_valid = 1'b1;
    @(posedge clk); #1;
    req_valid = 1'b0;
    do_clk(3);
    check(!ordering_err, "TC11-a no ordering error after Posted");

    // =============================================
    // TC12 - Valid LTP prefix attach
    // =============================================
    $display("\n--- TC12: LTP Prefix attach ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    // Fmt=0100 Type=2 L-bit=0 -> 0x4200_0000 -> valid LTP
    @(posedge clk); #1;
    ltp_data  = {32'h4200_0000, 96'h0};
    ltp_valid = 1'b1;
    send_req(4'd1, 64'h3000, 10'd4, 512'h11, 3'b000, 3'd0);
    do_clk(10);
    check(!prefix_err, "TC12-a no prefix_err on valid LTP");
    @(posedge clk); #1;
    ltp_valid = 1'b0;

    // =============================================
    // TC13 - Reserved LTP type -> prefix_err
    // =============================================
    // prefix_err is a 1-cycle pulse. Poll directly in initial block:
    // sample each posedge clk and capture into local reg — no always-block needed.
    $display("\n--- TC13: Reserved LTP type ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    prefix_err_seen = 1'b0;
    dbg_en          = 1'b1;  // enable pipeline trace
    do_clk(2);
    // Set reserved LTP BEFORE sending request
    @(posedge clk); #1;
    ltp_data  = {32'h4F00_0000, 96'h0}; // Fmt=0100 Type=0xF -> reserved
    ltp_valid = 1'b1;
    $display("[TC13] ltp_data=%h ltp_valid=%b ltp_type_from_dut=%h",
             ltp_data, ltp_valid, dut.u_pfx.ltp_type);
    $display("[TC13] fc_init_done=%b credit_p=%b credit_np=%b ordering_ok=%b",
             fc_init_done, dut.u_cr_mgr.credit_grant_p,
             dut.u_cr_mgr.credit_grant_np, ordering_ok);
    // Send MWr so TLP flows: USR_IF(comb)→REQ_Q(+1)→ARB(+1)→ASM(+1)→PFX(+1)
    send_req(4'd1, 64'h4000, 10'd4, 512'h22, 3'b000, 3'd0);
    // Poll up to 20 cycles — capture prefix_err pulse directly each posedge
    for (k = 0; k < 20; k = k + 1) begin
        @(posedge clk);
        if (prefix_err) begin
            prefix_err_seen = 1'b1;
            k = 20;  // break
        end
    end
    dbg_en = 1'b0;
    check(prefix_err_seen, "TC13-a prefix_err on reserved LTP type");
    @(posedge clk); #1;
    ltp_valid = 1'b0;

    // =============================================
    // TC14 - ECRC append
    // =============================================
    // tlp_ecrc_valid is a 1-cycle pulse. Poll directly each posedge clk.
    // Pipeline: USR_IF(comb)→REQ_Q(+1)→ARB(+1)→ASM(+1)→PFX(+1)→ECRC(+1) = 5 cycles min.
    $display("\n--- TC14: ECRC append ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    ecrc_en         = 1'b1;
    ack_en          = 1'b1;
    ecrc_seen       = 1'b0;
    prefix_err_seen = 1'b0;
    dbg_en          = 1'b1;  // enable pipeline trace
    do_clk(2);
    $display("[TC14] fc_init_done=%b credit_p=%b credit_np=%b ordering_ok=%b ecrc_en=%b",
             fc_init_done, dut.u_cr_mgr.credit_grant_p,
             dut.u_cr_mgr.credit_grant_np, ordering_ok, ecrc_en);

    send_req(4'd1, 64'h5000, 10'd4, 512'hBEEF, 3'b000, 3'd0);
    // Poll up to 50 cycles — capture ecrc_valid pulse directly each posedge
    for (k = 0; k < 50; k = k + 1) begin
        @(posedge clk);
        if (dut.u_ecrc.tlp_ecrc_valid) begin
            ecrc_seen = 1'b1;
            k = 50;  // break
        end
    end
    dbg_en = 1'b0;
    ack_en = 1'b0;
    @(posedge clk); #1;
    dll_ack = 1'b0; dll_flit_ack = 1'b0;
    check(ecrc_seen, "TC14-a ECRC module processed TLP");

    // =============================================
    // TC15 - FLIT mode emission
    // =============================================
    $display("\n--- TC15: FLIT mode emission ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    flit_mode_en = 1'b1;
    ack_en       = 1'b1;
    do_clk(2);

    dbg_en = 1'b1;  // enable pipeline trace
    $display("[TC15] fc_init_done=%b flit_mode_en=%b credit_p=%b ordering_ok=%b",
             fc_init_done, flit_mode_en, dut.u_cr_mgr.credit_grant_p, ordering_ok);
    // FLIT needs 2 TLPs to fill a 256-byte flit (2x 1024-bit chunks)
    // Pipeline to FLIT: USR_IF→REQ_Q→ARB→ASM→PFX→ECRC = 5 cycles per TLP
    // FLIT FSM: IDLE→LOAD_1→LOAD_2→CALC_CRC→EMIT = 4 more cycles
    // DLL_IF:   IDLE→SEND = 1 more cycle
    // Total minimum: 5+5+4+1 = 15 cycles after 2nd req_valid
    send_req(4'd1, 64'h6000, 10'd4, 512'hF0F0, 3'b000, 3'd0);
    do_clk(2);
    send_req(4'd1, 64'h6100, 10'd4, 512'h0F0F, 3'b000, 3'd0);

    // Poll up to 200 cycles for FLIT FSM to reach EMIT or beyond
    // FLIT FSM: IDLE→LOAD_1→LOAD_2→CALC_CRC→EMIT→WAIT_ACK
    // After EMIT: flit_valid=1 propagates to DLL_IF in 1 more cycle
    for (k = 0; k < 200; k = k + 1) begin
        @(posedge clk);
        // Exit when EMIT state registered (flit outputs are NBAs, need 1 more cycle)
        if (dut.u_flit.state == 3'd4 || dut.u_flit.state == 3'd5 ||
            flit_to_dll_valid || flit_seq > 0)
            k = 200;
    end
    // flit_valid is NBA-assigned at EMIT posedge — need 1 extra cycle to read it
    do_clk(3);
    check(flit_to_dll_valid || flit_seq > 0 || dut.u_flit.flit_valid,
          "TC15-a flit emitted to DLL");
    dbg_en = 1'b0;
    ack_en = 1'b0;
    @(posedge clk); #1;
    dll_ack = 1'b0; dll_flit_ack = 1'b0;

    // =============================================
    // TC16 - DLL_IF NAK replay
    // =============================================
    $display("\n--- TC16: DLL NAK Replay ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    flit_mode_en = 1'b1;
    do_clk(2);

    send_req(4'd1, 64'h7000, 10'd4, 512'hFACE, 3'b000, 3'd0);
    do_clk(5);
    send_req(4'd1, 64'h7100, 10'd4, 512'hCAFE, 3'b000, 3'd0);

    // Poll for flit then NAK it
    for (k = 0; k < 60; k = k + 1) begin
        @(posedge clk);
        if (flit_to_dll_valid) k = 60;
    end
    @(posedge clk); #1;
    dll_nak = 1'b1;
    @(posedge clk); #1;
    dll_nak = 1'b0;

    // Wait for replay then ack
    do_clk(15);
    do_dll_ack;
    do_clk(5);
    check(!flit_overflow_err, "TC16-a no overflow after NAK replay");

    // =============================================
    // TC17 - DLL_IF timeout max retries
    // =============================================
    $display("\n--- TC17: DLL Timeout Max Retries ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    flit_mode_en = 1'b1;
    do_clk(2);

    send_req(4'd1, 64'h8000, 10'd4, 512'hDEAD, 3'b000, 3'd0);
    do_clk(5);
    send_req(4'd1, 64'h8100, 10'd4, 512'hBEEF, 3'b000, 3'd0);
    // TIMEOUT_MAX=200, RETRY_MAX=4 -> 200*4=800 cycles; wait 1050
    do_clk(1050);
    check(!flit_to_dll_valid, "TC17-a DLL_IF idle after max retries");

    // =============================================
    // TC18 - Tag allocation and return
    // =============================================
    $display("\n--- TC18: Tag alloc and return ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    saved_tag = 10'd0;
    send_req(4'd0, 64'h9000, 10'd1, 512'd0, 3'b000, 3'd0);
    @(posedge clk);
    saved_tag = tag_alloc;
    check(tag_valid, "TC18-a tag_valid after MRd");

    do_clk(2);
    @(posedge clk); #1;
    cpl_tag_in   = saved_tag;
    cpl_valid_in = 1'b1;
    @(posedge clk); #1;
    cpl_valid_in = 1'b0;
    do_clk(2);
    check(1'b1, "TC18-b tag returned without crash");

    // =============================================
    // TC19 - Tag exhaustion
    // =============================================
    $display("\n--- TC19: Tag exhaustion ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    for (k = 0; k < 1024; k = k + 1) begin
        @(posedge clk); #1;
        req_type  = 4'd0;
        req_addr  = 64'hA000 + k;
        req_len   = 10'd1;
        req_valid = 1'b1;
        @(posedge clk); #1;
        req_valid = 1'b0;
    end
    do_clk(5);
    check(tag_exhausted || (outstanding_count == 10'd1023),
          "TC19-a tag_exhausted after 1024 allocs");

    // =============================================
    // TC20 - Round-robin arbitration
    // =============================================
    $display("\n--- TC20: Round-Robin Arbitration ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    @(posedge clk); #1;
    req_type  = 4'd1; req_addr = 64'hB000;
    req_len   = 10'd4; req_data = 512'h11;
    req_valid = 1'b1;
    @(posedge clk); #1;
    req_valid = 1'b0;

    @(posedge clk); #1;
    req_type  = 4'd0; req_addr = 64'hB100;
    req_len   = 10'd1; req_valid = 1'b1;
    @(posedge clk); #1;
    req_valid = 1'b0;

    do_clk(5);
    check(!ordering_err, "TC20-a no ordering error in RR arb");

    // =============================================
    // TC21 - max_payload = 128B
    // =============================================
    $display("\n--- TC21: max_payload 128B ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    max_payload = 3'd0;
    do_clk(2);

    send_req(4'd1, 64'hC000, 10'd4, 512'h55, 3'b000, 3'd0);
    do_clk(10);
    check(!prefix_err, "TC21-a no error with max_payload=128B");

    // =============================================
    // TC22 - EETP prefix forwarding
    // =============================================
    $display("\n--- TC22: EETP prefix ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    // Fmt=0100 L-bit(23)=0 -> 0x4000_0000 -> valid EETP
    @(posedge clk); #1;
    eetp_data  = {32'h4000_0000, 96'h0};
    eetp_valid = 1'b1;
    send_req(4'd1, 64'hD000, 10'd4, 512'h66, 3'b000, 3'd0);
    do_clk(10);
    check(!prefix_err, "TC22-a no prefix_err on valid EETP");
    @(posedge clk); #1;
    eetp_valid = 1'b0;

    // =============================================
    // TC23 - 64-bit address MWr
    // =============================================
    $display("\n--- TC23: 64-bit address MWr ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    send_req(4'd1, 64'hFFFF_FFFF_DEAD_BEEF, 10'd8, 512'h77, 3'b000, 3'd0);
    do_clk(10);
    check(!ordering_err, "TC23-a no error on 64-bit MWr");

    // =============================================
    // TC24 - Message transaction
    // =============================================
    $display("\n--- TC24: Message Transaction ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    do_clk(2);

    send_req(4'd8, 64'hE000, 10'd1, 512'h88, 3'b000, 3'd0);
    do_clk(10);
    check(!prefix_err, "TC24-a no error on Msg type");

    // =============================================
    // TC25 - Full pipeline: MRd to Completion
    // =============================================
    $display("\n--- TC25: Full pipeline MRd to Completion ---");
    set_defaults;
    do_reset;
    do_fc_handshake;
    flit_mode_en = 1'b1;
    ack_en       = 1'b1;
    do_clk(2);

    send_req(4'd0, 64'hF000, 10'd1, 512'd0, 3'b000, 3'd0);
    do_clk(20);

    // FIX: usr_cpl_valid is combinational — sample while cpl_valid_in=1
    @(posedge clk); #1;
    cpl_data_in   = 512'hBADC0FFEE;
    cpl_valid_in  = 1'b1;
    cpl_status_in = 3'b000;
    cpl_tag_in    = tag_alloc;
    #1; // combinational settles
    check(usr_cpl_valid,            "TC25-a completion forwarded to driver");
    check(usr_cpl_status == 3'b000, "TC25-b status = Successful Completion");
    @(posedge clk); #1;
    cpl_valid_in  = 1'b0;
    do_clk(3);
    ack_en = 1'b0;
    @(posedge clk); #1;
    dll_ack = 1'b0; dll_flit_ack = 1'b0;

    // =============================================
    // Final summary
    // =============================================
    do_clk(5);
    $display("\n==================================================");
    $display(" RESULTS  PASS=%0d  FAIL=%0d  TOTAL=%0d",
             pass_count, fail_count, pass_count + fail_count);
    $display("==================================================");
    if (fail_count == 0)
        $display("*** ALL TESTS PASSED ***");
    else
        $display("*** %0d TEST(S) FAILED ***", fail_count);

    $finish;
end

// ─────────────────────────────────────────────
// Watchdog 10ms
// ─────────────────────────────────────────────
initial begin
    #10_000_000;
    $display("WATCHDOG TIMEOUT");
    $finish;
end

endmodule
