// =============================================================
//  MODULE : tmo_err_manager
//  TAG    : TMO_ERR
//  LAYER  : Transaction Layer — Support Group
//  DESC   : Tracks outstanding tags and fires completion-timeout
//           errors. Uses a per-tag countdown counter array.
//           On timeout → asserts timeout_valid, routes to AER.
//  SPEC   : PCIe 6.0 Base Spec §2.8 (Completion Timeouts)
// =============================================================
module tmo_err_manager #(
    parameter MAX_TAGS = 1024  // 10-bit tag space
)(
    input  wire         clk,
    input  wire         rst_n,

    // ── Tag lifecycle ────────────────────────────────────────
    input  wire [9:0]   tag_start,        // Tag just allocated
    input  wire         tag_start_valid,  // Pulse: new tag is live
    input  wire         tag_return_valid, // Pulse: tag completed
    input  wire [9:0]   tag_returned,     // Which tag completed

    // ── Timeout threshold (clk cycles) ──────────────────────
    input  wire [15:0]  timeout_limit,    // Programmable limit

    // ── Outputs ──────────────────────────────────────────────
    output reg  [9:0]   timeout_tag,      // Tag that timed out
    output reg          timeout_valid,    // Pulse: timeout fired
    output reg          cpl_timeout_err,  // Sticky error flag
    output reg  [3:0]   err_to_aer        // Error code → AER block
);

    // ── Per-tag countdown timers ──────────────────────────────
    reg [15:0] timer [0:MAX_TAGS-1];
    reg        active[0:MAX_TAGS-1];    // 1 = tag is outstanding

    integer i;

    // ── Activate / deactivate tags ───────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_TAGS; i = i + 1) begin
                timer [i] <= 16'h0;
                active[i] <= 1'b0;
            end
            timeout_valid    <= 1'b0;
            timeout_tag      <= 10'h0;
            cpl_timeout_err  <= 1'b0;
            err_to_aer       <= 4'h0;
        end
        else begin
            // Default: de-assert pulse outputs
            timeout_valid <= 1'b0;

            // Start tracking a new tag
            if (tag_start_valid) begin
                timer [tag_start] <= timeout_limit;
                active[tag_start] <= 1'b1;
            end

            // Retire a completed tag
            if (tag_return_valid) begin
                active[tag_returned] <= 1'b0;
                timer [tag_returned] <= 16'h0;
            end

            // ── Scan all active timers (decrement + detect) ──
            // NOTE: real silicon would pipeline this scan.
            for (i = 0; i < MAX_TAGS; i = i + 1) begin
                if (active[i]) begin
                    if (timer[i] == 16'h1) begin
                        // Timeout!
                        timer[i]        <= 16'h0;
                        active[i]       <= 1'b0;
                        timeout_tag     <= i[9:0];
                        timeout_valid   <= 1'b1;
                        cpl_timeout_err <= 1'b1;
                        err_to_aer      <= 4'h1; // code: CPL_TIMEOUT
                    end
                    else if (timer[i] > 16'h1) begin
                        timer[i] <= timer[i] - 16'h1;
                    end
                end
            end
        end
    end

endmodule
