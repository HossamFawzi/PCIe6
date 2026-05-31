// =============================================================
//  MODULE : cpl_timeout_logic
//  TAG    : CPL_TMO  🔴 MUST
//  LAYER  : Transaction Layer — Support Group
//  DESC   : Per-tag completion timeout. PCIe spec mandates that
//           every Non-Posted Request has an independent countdown.
//           When counter hits zero before a Completion is seen,
//           the tag is aborted and an error is logged.
//           Supports 1024 outstanding tags (10-bit tag space).
//  SPEC   : PCIe 6.0 Base Spec §2.8.2 (Completion Timeout)
// =============================================================
module cpl_timeout_logic #(
    parameter MAX_TAGS = 1024
)(
    input  wire         clk,
    input  wire         rst_n,

    // ── Tag alloc (from Tag Manager) ─────────────────────────
    input  wire [9:0]   tag_alloc,          // New tag allocated
    input  wire         tag_alloc_valid,    // Pulse

    // ── Tag return (from Completion Handler) ─────────────────
    input  wire [9:0]   tag_return,         // Tag completed
    input  wire         tag_return_valid,   // Pulse

    // ── Timeout threshold (programmable via CFG) ─────────────
    input  wire [19:0]  cpl_timeout_val,    // Cycles until timeout

    // ── Outputs ──────────────────────────────────────────────
    output reg  [9:0]   timeout_tag,        // Tag that timed out
    output reg          timeout_fired,      // Pulse: timeout occurred
    output reg          cpl_abort_req,      // Request tag abort
    output reg  [3:0]   err_to_aer          // Error code → AER
);

    // ── Per-tag storage ───────────────────────────────────────
    reg [19:0] cnt  [0:MAX_TAGS-1]; // Countdown timer
    reg        live [0:MAX_TAGS-1]; // Tag is outstanding

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_TAGS; i = i + 1) begin
                cnt [i] <= 20'h0;
                live[i] <= 1'b0;
            end
            timeout_tag   <= 10'h0;
            timeout_fired <= 1'b0;
            cpl_abort_req <= 1'b0;
            err_to_aer    <= 4'h0;
        end
        else begin
            // Deassert pulses
            timeout_fired <= 1'b0;
            cpl_abort_req <= 1'b0;
            err_to_aer    <= 4'h0;

            // ── Allocate new tag ─────────────────────────────
            if (tag_alloc_valid) begin
                cnt [tag_alloc] <= cpl_timeout_val;
                live[tag_alloc] <= 1'b1;
            end

            // ── Retire completed tag ─────────────────────────
            if (tag_return_valid) begin
                live[tag_return] <= 1'b0;
                cnt [tag_return] <= 20'h0;
            end

            // ── Scan & decrement ─────────────────────────────
            for (i = 0; i < MAX_TAGS; i = i + 1) begin
                // Skip tag being allocated this cycle
                if (live[i] && !(tag_alloc_valid && tag_alloc == i[9:0])
                             && !(tag_return_valid && tag_return == i[9:0])) begin
                    if (cnt[i] == 20'h1) begin
                        // Timeout expired!
                        cnt[i]        <= 20'h0;
                        live[i]       <= 1'b0;
                        timeout_tag   <= i[9:0];
                        timeout_fired <= 1'b1;
                        cpl_abort_req <= 1'b1;
                        err_to_aer    <= 4'hE;  // code: CPL_TIMEOUT (0xE)
                    end
                    else begin
                        cnt[i] <= cnt[i] - 20'h1;
                    end
                end
            end
        end
    end

endmodule
