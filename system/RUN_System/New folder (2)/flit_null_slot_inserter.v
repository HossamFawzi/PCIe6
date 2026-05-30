// ============================================================================
// PCIe Gen6 — FLIT Null Slot Inserter (TX)
// Tag: NULL_INS  |  Layer: DLL TX  |  Gen6 MANDATORY (🔴 MUST)
//
// Spec Reference:
//   PCI Express Base Specification Rev 6.0 §4.2.3 — FLIT Mode TX Null Padding
//
// Every transmitted FLIT must be exactly 256 bytes (2048 bits).
// A FLIT contains two 128-byte (1024-bit) slots.
// Any slot not carrying a TLP or DLLP payload MUST be filled with the
// null-slot marker pattern before the FLIT is forwarded to the FEC encoder.
//
// Port Map (matches HTML reference card exactly):
//   Inputs:
//     clk                 – system clock
//     rst_n               – active-low synchronous reset
//     flit_in[2047:0]     – raw 256-byte FLIT from upstream packer
//     flit_valid          – flit_in is valid this cycle
//     flit_slot_used[1:0] – bit[0]=slot0 occupied, bit[1]=slot1 occupied
//     null_pattern[1023:0]– 128-byte null-slot fill pattern (PCIe Gen6 defined)
//   Outputs:
//     flit_out[2047:0]    – padded FLIT (all slots filled) → FEC encoder
//     flit_out_valid      – flit_out is valid
//     null_inserted       – one or more null slots were inserted this cycle
//     null_count[7:0]     – cumulative saturating count of null insertions
//
// Slot layout within the 2048-bit FLIT word:
//   flit[1023:   0]  = slot 0  (lower 128 bytes)
//   flit[2047:1024]  = slot 1  (upper 128 bytes)
//
// Pipeline depth: 1 register stage (inputs -> registered outputs)
// ============================================================================

`timescale 1ns / 1ps

module flit_null_slot_inserter (
    input  wire          clk,
    input  wire          rst_n,

    // Upstream FLIT input
    input  wire [2047:0] flit_in,
    input  wire          flit_valid,
    input  wire [1:0]    flit_slot_used,

    // Null marker (128 bytes = 1024 bits)
    input  wire [1023:0] null_pattern,

    // Padded FLIT output
    output reg  [2047:0] flit_out,
    output reg           flit_out_valid,
    output reg           null_inserted,
    output reg  [7:0]    null_count
);

    // -------------------------------------------------------------------------
    // Combinational null-select mux (zero latency)
    // -------------------------------------------------------------------------
    wire [1023:0] slot0_mux = flit_slot_used[0] ? flit_in[1023:0]    : null_pattern;
    wire [1023:0] slot1_mux = flit_slot_used[1] ? flit_in[2047:1024] : null_pattern;

    // A null insertion event = valid FLIT with at least one unused slot
    wire any_null = flit_valid & (~flit_slot_used[0] | ~flit_slot_used[1]);

    // -------------------------------------------------------------------------
    // Single register stage
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            flit_out       <= {2048{1'b0}};
            flit_out_valid <= 1'b0;
            null_inserted  <= 1'b0;
            null_count     <= 8'h00;
        end else begin
            // Output valid tracks input valid
            flit_out_valid <= flit_valid;

            // Null-insertion flag tracks whether any_null was true this cycle
            null_inserted  <= any_null;

            // Latch padded FLIT when valid
            if (flit_valid)
                flit_out <= {slot1_mux, slot0_mux};

            // Saturating counter: increment once per FLIT that needed padding
            if (any_null)
                null_count <= (null_count == 8'hFF) ? 8'hFF : null_count + 8'h01;
        end
    end

endmodule
