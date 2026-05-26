// ============================================================
// MODULE : req_q.v
// DESCRIPTION : Posted / Non-Posted Request Queue (Dual FIFO)
// LAYER : Transaction Layer — TX Path (Second Module)
// FUNCTION :
//   - Buffers outbound requests from USR_IF into two separate FIFOs
//       • Posted FIFO     : MWr, Msg
//       • Non-Posted FIFO : MRd, IORd/Wr, CfgRd/Wr
//   - Gates FIFO output on Flow Control credit grants from CR_MGR
//   - Provides queue occupancy and full flags back to USR_IF
//
// KEY CONCEPT — WHY TWO SEPARATE FIFOs?
//   PCIe spec requires posted and non-posted transactions to be
//   tracked independently because they consume different credit
//   classes (PH/PD vs NPH/NPD) and must obey ordering rules
//   separately. Posted requests cannot be stalled by non-posted
//   credit exhaustion and vice versa.
//
// SIGNAL FLOW:
//   USR_IF → req_in → [P-FIFO | NP-FIFO] → req_out → ARB_TX
//                                   ↑
//                          credit_grant from CR_MGR
// ============================================================

module req_q #(
    parameter DEPTH_P  = 16,   // Depth of Posted FIFO (power of 2)
    parameter DEPTH_NP = 16,   // Depth of Non-Posted FIFO (power of 2)
    parameter WIDTH    = 576   // TLP descriptor width (matches ARB_TX input)
)(
    // ── Clock & Reset ─────────────────────────────────────────
    input  wire             clk,
    input  wire             rst_n,

    // ── From USR_IF (Inbound Requests) ───────────────────────
    input  wire [WIDTH-1:0] req_in,         // Packed request word
    input  wire             req_valid_in,   // Request is valid
    // req_type embedded in req_in[575:572] — used to route to P or NP FIFO

    // ── From CR_MGR (Flow Control Gates) ─────────────────────
    input  wire             credit_grant_p,   // OK to dequeue Posted
    input  wire             credit_grant_np,  // OK to dequeue Non-Posted

    // ── To ARB_TX (Downstream) ───────────────────────────────
    output reg  [WIDTH-1:0] req_out,          // Selected TLP descriptor
    output reg              req_valid_out,    // Output is valid
    output reg  [1:0]       req_type_out,     // 0=Posted, 1=Non-Posted (for ARB_TX)

    // ── Status back to USR_IF ─────────────────────────────────
    output wire             q_full_p,         // Posted queue full
    output wire             q_full_np,        // Non-Posted queue full
    output wire [7:0]       q_occ_p,          // Posted queue occupancy
    output wire [7:0]       q_occ_np          // Non-Posted queue occupancy
);

// ──────────────────────────────────────────────────────────────
// FIFO STORAGE — Simple synchronous FIFO using arrays
// In a real design you would replace this with SRAM macros.
// ──────────────────────────────────────────────────────────────

// Posted FIFO
reg [WIDTH-1:0] p_mem  [0:DEPTH_P-1];
reg [$clog2(DEPTH_P):0] p_wptr, p_rptr;
wire p_empty  = (p_wptr == p_rptr);
wire p_full_w = ((p_wptr - p_rptr) == DEPTH_P);
assign q_full_p  = p_full_w;
assign q_occ_p   = p_wptr - p_rptr;

// Non-Posted FIFO
reg [WIDTH-1:0] np_mem [0:DEPTH_NP-1];
reg [$clog2(DEPTH_NP):0] np_wptr, np_rptr;
wire np_empty  = (np_wptr == np_rptr);
wire np_full_w = ((np_wptr - np_rptr) == DEPTH_NP);
assign q_full_np = np_full_w;
assign q_occ_np  = np_wptr - np_rptr;

// ──────────────────────────────────────────────────────────────
// ROUTING LOGIC
// Extract req_type from packed input to decide which FIFO to write.
// req_type[3:0] is stored in req_in[575:572].
// Posted types: MWr = 4'd1. All others are Non-Posted.
// ──────────────────────────────────────────────────────────────
wire [3:0] in_type   = req_in[575:572];
wire       is_posted = (in_type == 4'd1);  // Extend for Msg types as needed

// ──────────────────────────────────────────────────────────────
// WRITE SIDE — Push incoming requests into correct FIFO
// ──────────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p_wptr  <= 0;
        np_wptr <= 0;
    end else if (req_valid_in) begin
        if (is_posted && !p_full_w) begin
            p_mem[p_wptr[$clog2(DEPTH_P)-1:0]] <= req_in;
            p_wptr <= p_wptr + 1;
        end else if (!is_posted && !np_full_w) begin
            np_mem[np_wptr[$clog2(DEPTH_NP)-1:0]] <= req_in;
            np_wptr <= np_wptr + 1;
        end
        // If full: drop with error (in real design: assert backpressure upstream)
    end
end

// ──────────────────────────────────────────────────────────────
// READ SIDE — Dequeue when credit is granted
// Priority: Non-Posted first (conservative — can be changed to
// round-robin or posted-first depending on your latency goals)
// ARB_TX will arbitrate further, but we need to present one entry
// ──────────────────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p_rptr       <= 0;
        np_rptr      <= 0;
        req_out      <= {WIDTH{1'b0}};
        req_valid_out<= 1'b0;
        req_type_out <= 2'b00;
    end else begin
        req_valid_out <= 1'b0;

        // Prefer Non-Posted when credit available and queue non-empty
        if (!np_empty && credit_grant_np) begin
            req_out       <= np_mem[np_rptr[$clog2(DEPTH_NP)-1:0]];
            req_valid_out <= 1'b1;
            req_type_out  <= 2'b01;  // Non-Posted
            np_rptr       <= np_rptr + 1;
        end
        // Fall back to Posted
        else if (!p_empty && credit_grant_p) begin
            req_out       <= p_mem[p_rptr[$clog2(DEPTH_P)-1:0]];
            req_valid_out <= 1'b1;
            req_type_out  <= 2'b00;  // Posted
            p_rptr        <= p_rptr + 1;
        end
    end
end

// ──────────────────────────────────────────────────────────────
// SIMULATION CHECKS
// ──────────────────────────────────────────────────────────────
// synthesis translate_off
always @(posedge clk) begin
    if (rst_n && req_valid_in && is_posted && p_full_w)
        $warning("REQ_Q: Posted FIFO overflow — request dropped!");
    if (rst_n && req_valid_in && !is_posted && np_full_w)
        $warning("REQ_Q: Non-Posted FIFO overflow — request dropped!");
end
// synthesis translate_on

endmodule
