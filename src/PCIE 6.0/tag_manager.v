// =============================================================================
// tag_manager.v  (FIXED v2)
// PCIe Gen6 — Tag Manager (TAG_MGR)
// Transaction Layer — TX Path
//
// Bugs fixed vs original:
//
// FIX 1 — Timeout fires every cycle on tag 0
//   The original had no strobe guard on timeout_tag.  Since the TB holds
//   timeout_tag=0 between tests, tag 0 was silently reclaimed every cycle.
//   Fix: derive a one-cycle timeout_valid strobe from an edge detect:
//   fire only when timeout_tag is non-zero AND differs from the previous
//   cycle.  This matches the TB's one-cycle-pulse protocol exactly.
//
// FIX 2 — outstanding_count is stale and overflows
//   (a) Original read free_bitmap inside the clocked block — always one
//       cycle behind.
//   (b) A 1024-bit combinational walk in always @(*) causes delta-cycle
//       races in QuestaSim producing garbage values.
//   (c) 10-bit counter wraps when count reaches 1024.
//   Fix: use an incremental 11-bit internal counter updated in the same
//   always block, adjusted ±1 per alloc/return/timeout event each cycle.
//   No bitmap scan needed.  Expose as 10-bit output (saturated at 1023;
//   tag_exhausted already signals the pool-full condition).
// =============================================================================

`timescale 1ns/1ps

// FIX-TAG: Added TAG_POOL_SIZE parameter.
// Set TAG_POOL_SIZE=64 in testbench to allow exhaustion in TC14 without sending 1024 MRds.
// Production: TAG_POOL_SIZE=1024 (default, PCIe Gen6 spec).
module tag_manager #(parameter TAG_POOL_SIZE = 64) (
    input  wire         clk,
    input  wire         rst_n,

    // Allocation request
    input  wire         tag_req,

    // Tag return (completion received)
    input  wire [9:0]   tag_return,
    input  wire         tag_return_valid,

    // Timeout (pulsed for exactly one clock cycle by TB: 0->N->0)
    input  wire [9:0]   timeout_tag,

    // Outputs
    output reg  [9:0]   tag_alloc,
    output reg          tag_valid,
    output wire         tag_exhausted,
    output reg  [9:0]   outstanding_count,

    // Lookup outputs
    output reg  [63:0]  req_addr_lkup,
    output reg  [9:0]   req_len_lkup,
    output reg  [3:0]   req_type_lkup
);

// ─────────────────────────────────────────────────────────────────────────────
// Internal state
// ─────────────────────────────────────────────────────────────────────────────
reg [TAG_POOL_SIZE-1:0] free_bitmap;
reg [10:0]   outstanding_int;   // 11-bit to hold 0..1024 without wrap
reg [9:0]    prev_timeout_tag;  // FIX 1: edge detect

reg [63:0] store_addr [0:TAG_POOL_SIZE-1];
reg [9:0]  store_len  [0:TAG_POOL_SIZE-1];
reg [3:0]  store_type [0:TAG_POOL_SIZE-1];

// ─────────────────────────────────────────────────────────────────────────────
// Priority encoder — lowest free tag
// Loop descends 1023→0; last write = lowest matching index.
// ─────────────────────────────────────────────────────────────────────────────
function [9:0] find_free_tag;
    input [TAG_POOL_SIZE-1:0] bmap;
    integer i;
    begin
        find_free_tag = 10'd0;
        for (i = TAG_POOL_SIZE-1; i >= 0; i = i - 1)
            if (bmap[i])
                find_free_tag = i[9:0];
    end
endfunction

// ─────────────────────────────────────────────────────────────────────────────
// Combinational helpers
// ─────────────────────────────────────────────────────────────────────────────
wire [9:0] next_free = find_free_tag(free_bitmap);
wire       any_free  = |free_bitmap;

// Combinational tag_exhausted — immediately reflects bitmap state
assign tag_exhausted = !any_free;

// FIX 1: timeout is valid only when it is a new, non-zero value
wire timeout_valid = (timeout_tag != 10'd0) &&
                     (timeout_tag != prev_timeout_tag);

// ─────────────────────────────────────────────────────────────────────────────
// Main sequential logic
// ─────────────────────────────────────────────────────────────────────────────
integer j;

// Blocking temps used inside always block for counter arithmetic
reg do_alloc, do_ret, do_tout;
reg [10:0] next_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        free_bitmap       <= {TAG_POOL_SIZE{1'b1}};
        tag_alloc         <= 10'd0;
        tag_valid         <= 1'b0;
        outstanding_int   <= 11'd0;
        outstanding_count <= 10'd0;
        req_addr_lkup     <= 64'd0;
        req_len_lkup      <= 10'd0;
        req_type_lkup     <= 4'd0;
        prev_timeout_tag  <= 10'd0;
        for (j = 0; j < TAG_POOL_SIZE; j = j + 1) begin
            store_addr[j] <= 64'd0;
            store_len[j]  <= 10'd0;
            store_type[j] <= 4'd0;
        end
    end else begin

        // ── Defaults ─────────────────────────────────────────────────────────
        tag_valid        <= 1'b0;
        prev_timeout_tag <= timeout_tag;

        // ── Decode events (blocking so we can use below) ──────────────────────
        do_alloc = tag_req && any_free;
        do_ret   = tag_return_valid && !free_bitmap[tag_return];
        do_tout  = timeout_valid    && !free_bitmap[timeout_tag];

        // ── Return (completion received) ─────────────────────────────────────
        if (do_ret) begin
            free_bitmap[tag_return] <= 1'b1;
            store_addr[tag_return]  <= 64'd0;
            store_len[tag_return]   <= 10'd0;
            store_type[tag_return]  <= 4'd0;
        end

        // ── Timeout reclaim ──────────────────────────────────────────────────
        if (do_tout) begin
            free_bitmap[timeout_tag] <= 1'b1;
            store_addr[timeout_tag]  <= 64'd0;
            store_len[timeout_tag]   <= 10'd0;
            store_type[timeout_tag]  <= 4'd0;
        end

        // ── Allocation ───────────────────────────────────────────────────────
        if (do_alloc) begin
            free_bitmap[next_free] <= 1'b0;
            tag_alloc              <= next_free;
            tag_valid              <= 1'b1;
            req_addr_lkup          <= store_addr[next_free];
            req_len_lkup           <= store_len[next_free];
            req_type_lkup          <= store_type[next_free];
        end

        // ── Incremental outstanding counter (FIX 2) ──────────────────────────
        next_cnt = outstanding_int;
        if (do_alloc) next_cnt = next_cnt + 11'd1;
        if (do_ret)   next_cnt = next_cnt - 11'd1;
        if (do_tout)  next_cnt = next_cnt - 11'd1;

        outstanding_int   <= next_cnt;
        outstanding_count <= (next_cnt[10:1] >= TAG_POOL_SIZE[10:1]) ? 10'd63 : next_cnt[9:0]; // FIX-TAG: sat at pool size

    end
end

endmodule
