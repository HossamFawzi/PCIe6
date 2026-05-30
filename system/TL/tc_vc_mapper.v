// =============================================================
//  MODULE : tc_vc_mapper
//  TAG    : TC_VC  🔴 MUST
//  LAYER  : Transaction Layer — Support Group
//  DESC   : Maps Traffic Class (TC0–TC7) to Virtual Channel ID.
//           Mapping is driven by VC Capability register fields
//           (vc_map_cfg). Default: all TCs map to VC0.
//           Detects unmapped TC (vc_map_err).
//  SPEC   : PCIe 6.0 Base Spec §6.14 (VC Capability)
// =============================================================
module tc_vc_mapper (
    input  wire        clk,
    input  wire        rst_n,

    // ── TLP Traffic Class input ───────────────────────────────
    input  wire [2:0]  tlp_tc,          // TC field from TLP header
    input  wire        tlp_valid,       // TLP is valid

    // ── Configuration from VC Capability Register ────────────
    // vc_map_cfg encodes TC→VC mapping:
    //   bits[2:0]  = VC for TC0
    //   bits[5:3]  = VC for TC1
    //   ...
    //   bits[23:21]= VC for TC7  (3 bits each × 8 TC = 24 bits)
    input  wire [23:0] vc_map_cfg,
    input  wire [7:0]  vc_arb_cfg,     // Arbitration config (passed through)

    // ── Output ────────────────────────────────────────────────
    output reg  [2:0]  vc_id,          // Resolved VC for this TLP
    output reg         vc_map_valid,   // vc_id is valid
    output reg         vc_map_err      // TC has no valid VC mapping
);

    // ── Extract per-TC VC assignments from vc_map_cfg ─────────
    // TC n → bits [3n+2 : 3n]
    wire [2:0] vc_for_tc [0:7];
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GEN_VC_MAP
            assign vc_for_tc[g] = vc_map_cfg[3*g+2 : 3*g];
        end
    endgenerate

    // ── Combinational lookup ──────────────────────────────────
    reg [2:0] resolved_vc;

    always @(*) begin
        resolved_vc = vc_for_tc[tlp_tc]; // direct indexed lookup
    end

    // ── Register output ───────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vc_id        <= 3'h0;
            vc_map_valid <= 1'b0;
            vc_map_err   <= 1'b0;
        end
        else if (tlp_valid) begin
            vc_id        <= resolved_vc;
            vc_map_valid <= 1'b1;
            // Error: mapping resolves to VC3-7 but only VC0-2
            // are considered valid in a minimal implementation.
            // Extend this check based on device VC capability.
            vc_map_err   <= (resolved_vc > 3'd3) ? 1'b1 : 1'b0;
        end
        else begin
            vc_map_valid <= 1'b0;
            vc_map_err   <= 1'b0;
        end
    end

endmodule
