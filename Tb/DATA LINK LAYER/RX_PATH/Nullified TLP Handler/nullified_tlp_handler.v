// =============================================================================
// Module  : nullified_tlp_handler
// Layer   : Data Link Layer (DLL) — RX Path
// Spec    : PCIe Gen6 Base Specification r1.0 — Chapter 3 (DLL)
// Tag     : NULL_HDL
//
// Description:
//   In PCIe Gen6 FLIT mode a sender may insert NULL (padding) slots inside a
//   FLIT when it has no real TLP to transmit.  These null slots MUST be
//   silently dropped and never forwarded to the Transaction Layer.
//
//   This module:
//     • Accepts the flit_null flag and the raw slot data from FLIT Rx Deframer.
//     • Counts the number of null slots dropped (8-bit saturating counter).
//     • Asserts null_drop for exactly one cycle per null slot.
//     • When the slot is NOT null it is transparent (zero-latency pass-through).
//
//   The module intentionally has no output data path: the upstream FLIT Rx
//   Deframer already withholds flit_tlp_valid / flit_dllp_valid when the slot
//   is null, so this block only needs to maintain diagnostics.
//
// Inputs:
//   flit_null              — null-slot flag from FLIT Rx Deframer
//   flit_slot_data[1023:0] — raw 1024-bit slot payload (for optional logging)
//   flit_slot_valid        — slot is present on the bus this cycle
//
// Outputs:
//   null_drop              — pulse: null slot dropped this cycle
//   null_count[7:0]        — saturating count of null slots dropped
// =============================================================================

module nullified_tlp_handler (
    input  wire          clk,
    input  wire          rst_n,

    // ── From FLIT Rx Deframer ─────────────────────────────────────────────────
    input  wire          flit_null,            // this FLIT slot is a null slot
    input  wire [1023:0] flit_slot_data,       // raw slot data (used for assert checks only)
    input  wire          flit_slot_valid,      // FLIT slot present this cycle

    // ── To DLL Error Aggregator / diagnostics ───────────────────────────────
    output reg           null_drop,            // 1-cycle pulse per null slot dropped
    output reg  [7:0]    null_count            // saturating counter (wraps at 8'hFF)
);

    // ── Null slot detection and counting ──────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            null_drop  <= 1'b0;
            null_count <= 8'h00;
        end else begin
            null_drop <= 1'b0;   // default: no drop this cycle

            if (flit_slot_valid && flit_null) begin
                null_drop <= 1'b1;

                // Saturating increment
                if (null_count != 8'hFF)
                    null_count <= null_count + 8'h01;
            end
        end
    end

    // ── Assertion: null slots must carry the PCIe-defined null pattern ────────
    // (Null TLP slot payload should be all-ones per spec; this is a simulation
    //  check only — synthesis tools ignore initial/assert blocks.)
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (flit_slot_valid && flit_null) begin
            if (flit_slot_data !== {1024{1'b1}} && flit_slot_data !== 1024'b0) begin
                $display("[NULL_HDL] WARNING @%0t: null slot data is neither all-ones nor all-zeros", $time);
            end
        end
    end
    `endif

endmodule
