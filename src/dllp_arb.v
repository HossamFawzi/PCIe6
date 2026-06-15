// ============================================================
//  PCIe Gen6 — Data Link Layer
//  Module  : DLLP Arbiter  (DLLP_ARB)
//  Tag     : DLLP_ARB
//  Group   : TX Path  |  Gen6 New
//
//  Function:
//    Arbitrates between five competing DLLP sources and
//    presents exactly one DLLP per cycle to the TX Datapath
//    MUX (TX_MUX).  Priority order (high → low) as defined
//    by the PCIe Gen6 specification:
//
//      1. ACK / NAK  (ack_dllp / ack_dllp_valid)
//      2. UpdateFC   (fc_dllp  / fc_dllp_valid)
//      3. PM         (pm_dllp  / pm_dllp_valid)
//      4. BW Notif   (bw_dllp_valid) — data taken from fc_dllp
//         port (same 64-bit bus, type differentiates)
//      5. NOP        (nop_valid)
//
//  Latency optimisation:
//    • Purely combinational select + 1 output register.
//      Total latency = 1 clock cycle.
//    • No round-robin / credit counter — static priority is
//      spec-compliant AND gives minimum latency for the
//      highest-priority ACK/NAK path (critical for retransmit
//      avoidance).
//    • dllp_type[3:0] encoding is driven combinationally from
//      the winning source's DLLP type field [63:60].
//
//  Port list (matches reference HTML exactly):
//    Inputs : ack_dllp[63:0], ack_dllp_valid,
//             fc_dllp[63:0],  fc_dllp_valid,
//             pm_dllp[63:0],  pm_dllp_valid,
//             nop_valid,      bw_dllp_valid,
//             clk, rst_n
//    Outputs: dllp_out[63:0], dllp_out_valid, dllp_type[3:0]
//
//  dllp_type encoding (matches PCIe DL spec):
//    4'h0 = ACK
//    4'h1 = NAK
//    4'h2 = UpdateFC
//    4'h3 = PM_Enter_L1 / PM_Active_Req / PM_Request_Ack
//    4'h4 = BW Notification
//    4'h5 = NOP
//    4'hF = none (idle)
// ============================================================
`timescale 1ns/1ps

module dllp_arb (
    input  wire        clk,
    input  wire        rst_n,

    // Source 1 – ACK / NAK  (highest priority)
    input  wire [63:0] ack_dllp,
    input  wire        ack_dllp_valid,

    // Source 2 – UpdateFC
    input  wire [63:0] fc_dllp,
    input  wire        fc_dllp_valid,

    // Source 3 – Power Management
    input  wire [63:0] pm_dllp,
    input  wire        pm_dllp_valid,

    // Source 4 – NOP  (lowest named source)
    input  wire        nop_valid,

    // Source 5 – BW Notification (uses separate data register)
    input  wire        bw_dllp_valid,

    // Outputs
    output reg  [63:0] dllp_out,
    output reg         dllp_out_valid,
    output reg  [3:0]  dllp_type
);

    // ----------------------------------------------------------
    // NOP DLLP constant (PCIe spec Sect 3.5.2.2: type=0x00 NOP)
    // Full 64-bit DLLP frame: [63:56]=type [55:0]=reserved/zero
    // ----------------------------------------------------------
    localparam [63:0] NOP_DLLP = {8'h31, 56'h00_0000_0000_0000}; // BUG FIX: NOP=0x31 per spec

    // BW Notification DLLP: type byte = 0x03 (Link Bandwidth Management)
    // When bw_dllp_valid is asserted we build the DLLP here.
    // The bandwidth status bits are embedded in bits [55:48] by the
    // LBW_FSM; since DLLP_ARB receives only a valid flag (no separate
    // data bus per the HTML spec), we construct a type-only frame.
    // Downstream consumers decode the type from the output type field.
    localparam [63:0] BW_DLLP_TEMPLATE = {8'h03, 56'h00_0000_0000_0000};

    // ----------------------------------------------------------
    // Combinational priority select
    // ----------------------------------------------------------
    reg  [63:0] sel_data;
    reg  [3:0]  sel_type;
    reg         sel_valid;

    // Extract ACK vs NAK from DLLP type field [63:56]
    // PCIe ACK type byte = 0x00, NAK = 0x10
    wire is_nak = (ack_dllp[63:56] == 8'h10);

    always @(*) begin
        if (ack_dllp_valid) begin
            sel_data  = ack_dllp;
            sel_type  = is_nak ? 4'h1 : 4'h0;
            sel_valid = 1'b1;
        end else if (fc_dllp_valid) begin
            sel_data  = fc_dllp;
            sel_type  = 4'h2;
            sel_valid = 1'b1;
        end else if (pm_dllp_valid) begin
            sel_data  = pm_dllp;
            sel_type  = 4'h3;
            sel_valid = 1'b1;
        end else if (bw_dllp_valid) begin
            sel_data  = BW_DLLP_TEMPLATE;
            sel_type  = 4'h4;
            sel_valid = 1'b1;
        end else if (nop_valid) begin
            sel_data  = NOP_DLLP;
            sel_type  = 4'h5;
            sel_valid = 1'b1;
        end else begin
            sel_data  = 64'h0;
            sel_type  = 4'hF;
            sel_valid = 1'b0;
        end
    end

    // ----------------------------------------------------------
    // Output register — 1-cycle latency
    // ----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dllp_out       <= 64'h0;
            dllp_out_valid <= 1'b0;
            dllp_type      <= 4'hF;
        end else begin
            dllp_out       <= sel_data;
            dllp_out_valid <= sel_valid;
            dllp_type      <= sel_type;
        end
    end

endmodule
