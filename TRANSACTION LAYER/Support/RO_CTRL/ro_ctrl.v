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
    output reg         ro_bypass_ok,    // This TLP may skip ordering
    output reg         ordering_override,// Override strict order
    output reg         ro_err           // RO misuse detected
);

    // ── TLP type encoding (PCIe §2.2.1) ──────────────────────
    // Only non-posted writes (MWr) and reads (MRd) are relevant.
    // Completions must NOT have RO set.
    localparam [3:0] TYPE_MWR  = 4'b0000; // Memory Write (posted)
    localparam [3:0] TYPE_MRD  = 4'b0001; // Memory Read
    localparam [3:0] TYPE_CPL  = 4'b1010; // Completion (no RO allowed)
    localparam [3:0] TYPE_CPLD = 4'b1011; // Completion with data

    reg valid_for_ro;

    always @(*) begin
        // RO is valid only on MWr and MRd TLPs
        // Setting RO on a Completion is a protocol error
        case (req_type)
            TYPE_MWR : valid_for_ro = 1'b1;
            TYPE_MRD : valid_for_ro = 1'b1;
            default  : valid_for_ro = 1'b0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ro_bypass_ok       <= 1'b0;
            ordering_override  <= 1'b0;
            ro_err             <= 1'b0;
        end
        else begin
            ro_err             <= 1'b0;
            ro_bypass_ok       <= 1'b0;
            ordering_override  <= 1'b0;

            if (req_attr_ro) begin
                if (!ro_en) begin
                    // RO attribute set but globally disabled → error
                    ro_err <= 1'b1;
                end
                else if (!valid_for_ro) begin
                    // RO on Completion or unsupported type → error
                    ro_err <= 1'b1;
                end
                else begin
                    // Legal RO TLP — allow bypass
                    ro_bypass_ok      <= 1'b1;
                    ordering_override <= ordering_stall; // override if stalled
                end
            end
        end
    end

endmodule
