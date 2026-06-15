// =============================================================
//  MODULE : ro_ctrl
//  TAG    : RO_CTRL  🔴 MUST
//  LAYER  : Transaction Layer — Support Group
//  DESC   : Relaxed Ordering bypass control.
//           When ro_en=1 (from Config Space) AND the TLP's
//           RO attribute bit is set, this block signals
//           ro_bypass_ok → Ordering/ROB Logic can skip strict
//           ordering enforcement for this TLP.
//           Generates ro_err on illegal use of RO attribute.
//  SPEC   : PCIe 6.0 Base Spec §2.4 (Ordering Rules) + §7.5.3
// =============================================================
module ro_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // ── TLP attribute / type ──────────────────────────────────
    input  wire        req_attr_ro,     // RO bit from TLP header
    input  wire [3:0]  req_type,        // TLP type [3:0]
    input  wire [2:0]  req_tc,          // Traffic Class

    // ── Config Space knob ─────────────────────────────────────
    input  wire        ro_en,           // Global RO enable (DevCtrl)

    // ── Ordering stall signal from ROB ────────────────────────
    input  wire        ordering_stall,  // Strict ordering would stall

    // ── Outputs → TX Arbiter / Ordering ROB ──────────────────
    output wire        ro_bypass_ok,    // This TLP may skip ordering
    output wire        ordering_override,// Override strict order
    output wire        ro_err           // RO misuse detected
);

    // ── TLP type encoding (PCIe §2.2.1) ──────────────────────
    // Only non-posted writes (MWr) and reads (MRd) are relevant.
    // Completions must NOT have RO set.
    localparam [3:0] TYPE_MWR  = 4'b0000; // Memory Write (posted)
    localparam [3:0] TYPE_MRD  = 4'b0001; // Memory Read
    localparam [3:0] TYPE_CPL  = 4'b1010; // Completion (no RO allowed)
    localparam [3:0] TYPE_CPLD = 4'b1011; // Completion with data

    reg valid_for_ro;
    reg ro_bypass_ok_r, ordering_override_r, ro_err_r;
    assign ro_bypass_ok      = ro_bypass_ok_r;
    assign ordering_override = ordering_override_r;
    assign ro_err            = ro_err_r;

    always @(*) begin
        // RO is valid only on MWr and MRd TLPs
        // Setting RO on a Completion is a protocol error
        case (req_type)
            TYPE_MWR : valid_for_ro = 1'b1;
            TYPE_MRD : valid_for_ro = 1'b1;
            default  : valid_for_ro = 1'b0;
        endcase
    end

    // Combinational outputs — immediately reflect inputs
    always @(*) begin
        ro_err_r            = 1'b0;
        ro_bypass_ok_r      = 1'b0;
        ordering_override_r = 1'b0;

        if (req_attr_ro) begin
            if (!ro_en) begin
                ro_err_r = 1'b1;
            end else if (!valid_for_ro) begin
                ro_err_r = 1'b1;
            end else begin
                ro_bypass_ok_r      = 1'b1;
                ordering_override_r = ordering_stall;
            end
        end
    end

endmodule
