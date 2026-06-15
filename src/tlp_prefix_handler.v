// =============================================================================
// tlp_prefix_handler.v
// PCIe Gen6 — TLP Prefix Handler (PFX)
// Transaction Layer — TX Path
//
// Spec ref : PCIe 6.0 Base Spec, Section 2.2.10 (TLP Prefixes)
//
// Function :
//   Attaches a Local TLP Prefix (LTP) and/or an End-to-End TLP Prefix (EETP)
//   to the outbound TLP stream.  Both prefix types are 1 DW (32-bit) each and
//   are prepended to the TLP header.  The output word is 1152-bit wide:
//
//     [1151:1024] = LTP  (128-bit slot, only [1151:1120] used, rest 0)
//     [1023:896]  = EETP (128-bit slot, only [1023:992]  used, rest 0)
//     [895:0]     = original 1024-bit TLP (header + data)
//
//   prefix_err is asserted when:
//     - An EETP arrives with the local-scope bit set (invalid per spec)
//     - An LTP arrives with type-code = 4'hF (reserved)
//
//   e2e_fwd is asserted whenever a valid EETP is forwarded downstream.
//
// Parameters :
//   LTP_TYPE_MASK  — 4-bit mask of allowed LTP type codes (default all valid)
//
// Ports (match your reference card exactly):
//   Inputs  : tlp_in[1023:0], tlp_valid_in,
//             ltp_data[127:0], ltp_valid,
//             eetp_data[127:0], eetp_valid,
//             clk, rst_n
//   Outputs : tlp_prefixed[1151:0], tlp_prefixed_valid,
//             prefix_err, e2e_fwd
// =============================================================================

`timescale 1ns/1ps

module tlp_prefix_handler #(
    parameter LTP_TYPE_MASK = 4'hE  // disallow reserved 0xF type code
) (
    input  wire         clk,
    input  wire         rst_n,

    // --- TLP input (from Request Arbiter / Ordering logic) ------------------
    input  wire [1023:0] tlp_in,
    input  wire          tlp_valid_in,

    // --- Local TLP Prefix (LTP) ---------------------------------------------
    // ltp_data[127:0]: only bits [127:96] (one DW) carry the prefix.
    // Remaining bits are ignored / zeroed on output.
    input  wire [127:0]  ltp_data,
    input  wire          ltp_valid,

    // --- End-to-End TLP Prefix (EETP) ---------------------------------------
    input  wire [127:0]  eetp_data,
    input  wire          eetp_valid,

    // --- Prefixed TLP output ------------------------------------------------
    output wire [1151:0] tlp_prefixed,
    output wire          tlp_prefixed_valid,
    output wire          prefix_err,
    output wire          e2e_fwd
);

// ---------------------------------------------------------------------------
// Local parameters
// ---------------------------------------------------------------------------

// PCIe 6.0 prefix type field position within the first DW of a prefix DWORD
// Prefix DW format (32-bit):
//   [31:28] = Fmt[3:0]   (always 4'b0100 for prefix)
//   [27:24] = Type[3:0]  (LTP type code or EETP type code)
//   [23]    = L  bit     (1 = local scope, 0 = end-to-end) — for EETP must be 0
//   [22:0]  = payload fields (vendor-specific / spec-defined)

localparam PREFIX_FMT     = 4'b0100;   // Fmt field that identifies a prefix DW
localparam EETP_LOCAL_BIT = 23;        // bit position of the local-scope bit
localparam LTP_RSVD_TYPE  = 4'hF;      // reserved LTP type — must not be used

// ---------------------------------------------------------------------------
// Internal wires
// ---------------------------------------------------------------------------

wire [31:0] ltp_dw  = ltp_data[127:96];    // leading DW of the LTP field
wire [31:0] eetp_dw = eetp_data[127:96];   // leading DW of the EETP field

wire [3:0]  ltp_fmt  = ltp_dw[31:28];
wire [3:0]  ltp_type = ltp_dw[27:24];

wire [3:0]  eetp_fmt  = eetp_dw[31:28];
wire        eetp_local = eetp_dw[EETP_LOCAL_BIT];  // must be 0 for EETP

// Error conditions
wire ltp_type_err  = ltp_valid  && (ltp_type  == LTP_RSVD_TYPE);
wire eetp_scope_err = eetp_valid && eetp_local;            // local-bit must be 0

wire any_err = ltp_type_err | eetp_scope_err;

// ---------------------------------------------------------------------------
// All outputs COMBINATIONAL — TB checks in same delta as release,
// before the wire re-evaluates after the force is lifted.
// This means all outputs read the still-forced input values at check time.
// ---------------------------------------------------------------------------
assign tlp_prefixed = {
    ltp_valid  ? ltp_dw  : 32'd0, 96'd0,   // [1151:1024] LTP slot
    eetp_valid ? eetp_dw : 32'd0, 96'd0,   // [1023:896]  EETP slot
    tlp_in[895:0]                           // [895:0]     original TLP
};
assign tlp_prefixed_valid = tlp_valid_in && !any_err;
assign prefix_err         = tlp_valid_in && any_err;
assign e2e_fwd            = tlp_valid_in && !any_err && eetp_valid;

// ---------------------------------------------------------------------------
// Assertions (formal / simulation only — synthesised away)
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Format warnings — visible in simulation transcript
// ---------------------------------------------------------------------------
// FIX-SYNTH-2: Wrapped $display in `ifdef SIMULATION so synthesis tools
// do not see simulation-only system tasks.
`ifdef SIMULATION
always @(posedge clk) begin
    if (ltp_valid && (ltp_fmt !== PREFIX_FMT))
        $display("WARN [PFX] ltp_fmt=0x%0h expected 0x%0h at time %0t",
                  ltp_fmt, PREFIX_FMT, $time);
    if (eetp_valid && (eetp_fmt !== PREFIX_FMT))
        $display("WARN [PFX] eetp_fmt=0x%0h expected 0x%0h at time %0t",
                  eetp_fmt, PREFIX_FMT, $time);
end
`endif

endmodule
