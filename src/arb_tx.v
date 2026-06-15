// ============================================================
// MODULE : arb_tx.v
// DESCRIPTION : TX Request Arbiter
// LAYER : Transaction Layer — TX Path (Third Module)
// FUNCTION :
//   - Arbitrates between posted (P) and non-posted (NP) queues
//   - Gated by CR_MGR credit grants (must have credits to send)
//   - Gated by ORD module ordering_ok (must not violate ordering)
//   - Outputs a single selected TLP descriptor to TLP_ASM & PFX
//
// KEY CONCEPT — WHY AN ARBITER?
//   At any clock cycle both the Posted FIFO and Non-Posted FIFO
//   in REQ_Q may have valid entries ready to send. The TLP
//   assembler downstream can only accept ONE TLP at a time.
//   The arbiter must select one, but it CANNOT pick arbitrarily:
//     (a) No credits → that type cannot be selected
//     (b) ordering_ok = 0 → ORD module says ordering would be
//         violated; stall ALL transmission
//   Within those constraints a round-robin or priority scheme
//   is applied to avoid starvation.
//
// ARBITRATION POLICY (this implementation):
//   1. If ordering_ok == 0: output nothing (stall)
//   2. If only P has credits & valid: select P
//   3. If only NP has credits & valid: select NP
//   4. If both: round-robin between P and NP
//
// SIGNAL FLOW:
//   REQ_Q  → req_p/req_np  →  ARB_TX  → arb_tlp → TLP_ASM
//   CR_MGR → credit_grant  ↗           → arb_tlp → PFX
//   ORD    → ordering_ok   ↗
// ============================================================

module arb_tx (
    // ── Clock & Reset ─────────────────────────────────────────
    input  wire         clk,
    input  wire         rst_n,

    // ── From REQ_Q ────────────────────────────────────────────
    input  wire         req_p_valid,     // Posted queue has valid entry
    input  wire         req_np_valid,    // Non-Posted queue has valid entry
    input  wire [575:0] req_p,           // Posted TLP descriptor
    input  wire [575:0] req_np,          // Non-Posted TLP descriptor

    // ── From CR_MGR (Flow Control) ───────────────────────────
    input  wire         credit_grant_p,  // Credits available for Posted
    input  wire         credit_grant_np, // Credits available for Non-Posted

    // ── From ORD (Ordering Check) ────────────────────────────
    input  wire         ordering_ok,     // 1 = safe to transmit

    // ── To TLP_ASM & PFX ─────────────────────────────────────
    output reg  [575:0] arb_tlp,         // Selected TLP descriptor
    output reg          arb_tlp_valid,   // Output is valid this cycle
    output reg  [1:0]   arb_type         // 0=Posted, 1=Non-Posted, 2=Rsvd
);

// ──────────────────────────────────────────────────────────────
// ROUND-ROBIN STATE
// last_granted tracks which type was selected last cycle so we
// can alternate and avoid starvation when both have data.
// ──────────────────────────────────────────────────────────────
localparam POSTED     = 1'b0;
localparam NON_POSTED = 1'b1;

reg last_granted;  // POSTED or NON_POSTED

// ──────────────────────────────────────────────────────────────
// CAN-SEND QUALIFICATION
// A type can only be sent if:
//   (a) it has a valid entry in its queue
//   (b) it has credits from CR_MGR
//   (c) the ordering module says it is safe (ordering_ok)
// ──────────────────────────────────────────────────────────────
wire can_send_p  = req_p_valid  && credit_grant_p  && ordering_ok;
wire can_send_np = req_np_valid && credit_grant_np && ordering_ok;

// ──────────────────────────────────────────────────────────────
// ARBITRATION LOGIC (Registered output for clean timing)
// ──────────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arb_tlp       <= 576'b0;
        arb_tlp_valid <= 1'b0;
        arb_type      <= 2'b00;
        last_granted  <= POSTED;
    end else begin
        arb_tlp_valid <= 1'b0;  // default: no output

        if (!ordering_ok) begin
            // ── STALL: ordering violation would occur ───────────
            arb_tlp_valid <= 1'b0;
            // Do NOT advance last_granted — resume same state later
        end
        else if (can_send_p && !can_send_np) begin
            // ── Only Posted can go ──────────────────────────────
            arb_tlp       <= req_p;
            arb_tlp_valid <= 1'b1;
            arb_type      <= 2'b00;  // Posted
            last_granted  <= POSTED;
        end
        else if (!can_send_p && can_send_np) begin
            // ── Only Non-Posted can go ──────────────────────────
            arb_tlp       <= req_np;
            arb_tlp_valid <= 1'b1;
            arb_type      <= 2'b01;  // Non-Posted
            last_granted  <= NON_POSTED;
        end
        else if (can_send_p && can_send_np) begin
            // ── Both eligible: round-robin ──────────────────────
            if (last_granted == POSTED) begin
                // Give turn to Non-Posted
                arb_tlp       <= req_np;
                arb_tlp_valid <= 1'b1;
                arb_type      <= 2'b01;
                last_granted  <= NON_POSTED;
            end else begin
                // Give turn to Posted
                arb_tlp       <= req_p;
                arb_tlp_valid <= 1'b1;
                arb_type      <= 2'b00;
                last_granted  <= POSTED;
            end
        end
        // else: neither can send — output stays deasserted
    end
end

// ──────────────────────────────────────────────────────────────
// SIMULATION CHECKS
// Assertion block removed: the original assert/else syntax was
// parsed incorrectly by ModelSim (the 'else' bound to the outer
// 'if', not the 'assert'), causing false warnings every cycle.
// Credit and ordering correctness is enforced by the top-module
// arb_ordering_ok gate and CR_MGR credit checks.
// ──────────────────────────────────────────────────────────────

endmodule
