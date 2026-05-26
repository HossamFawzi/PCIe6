// =============================================================================
// Module  : fc_init_fsm
// Layer   : Transaction Layer (TL)  TX Path
// Tag     : FC_INIT
// Spec    : PCIe 6.0  Flow Control Initialization Handshake
//
// Runs the FC Init handshake at link bring-up.
// Separate from the steady-state Credit Manager.
//
// InitFC DLLP format used here (72-bit):
//   [71:64] = DLLP type  (8-bit)
//   [63:56] = VC ID      (8-bit, fixed 0 for VC0)
//   [55:48] = HdrFC[7:0]  (advertised header credits)
//   [47:36] = DataFC[11:0] (advertised data credits)
//   [35:16] = reserved / pad
//   [15: 0] = CRC-16 placeholder (filled by DLL layer)
//
// Handshake sequence (PCIe spec §3.4):
//   IDLE
//    SEND_IFC1_P / NP / CPL   (send our InitFC1 for all credit types)
//    WAIT_IFC1                 (wait for partner's InitFC1 for all types)
//    SEND_IFC2_P / NP / CPL   (send our InitFC2 for all credit types)
//    WAIT_IFC2                 (wait for partner's InitFC2 for all types)
//    DONE                      (fc_init_done asserted, stays high)
// =============================================================================

module fc_init_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // From DLL: physical link is up, start FC init
    input  wire        dll_up,

    // From DLL: received InitFC DLLP from link partner
    input  wire [71:0] initfc_rx,
    input  wire        initfc_rx_valid,

    // To DLL: InitFC DLLP to transmit
    output reg  [71:0] initfc_tx,
    output reg         initfc_tx_send,     // 1-cycle pulse per DLLP

    // Handshake complete released to Credit Manager
    output reg         fc_init_done,

    // Advertised credits output (latched on DONE)
    output reg  [ 7:0] adv_ph,
    output reg  [11:0] adv_pd,
    output reg  [ 7:0] adv_nph,
    output reg  [ 7:0] adv_cplh,
    output reg  [11:0] adv_cpld
);

// ---------------------------------------------------------------------------
// DLLP type codes (PCIe Base Spec Table 3-1)
// ---------------------------------------------------------------------------
localparam [7:0] TYPE_IFC1_P   = 8'h40;
localparam [7:0] TYPE_IFC1_NP  = 8'h50;
localparam [7:0] TYPE_IFC1_CPL = 8'h60;
localparam [7:0] TYPE_IFC2_P   = 8'hC0;
localparam [7:0] TYPE_IFC2_NP  = 8'hD0;
localparam [7:0] TYPE_IFC2_CPL = 8'hE0;

// ---------------------------------------------------------------------------
// Static advertised credit values
// (Real design: from config registers)
// ---------------------------------------------------------------------------
localparam [7:0]  K_PH   = 8'd32;
localparam [11:0] K_PD   = 12'd128;
localparam [7:0]  K_NPH  = 8'd8;
localparam [7:0]  K_CPLH = 8'd32;
localparam [11:0] K_CPLD = 12'd128;

// ---------------------------------------------------------------------------
// FSM states
// ---------------------------------------------------------------------------
localparam [3:0]
    S_IDLE          = 4'd0,
    S_SEND_IFC1_P   = 4'd1,
    S_SEND_IFC1_NP  = 4'd2,
    S_SEND_IFC1_CPL = 4'd3,
    S_WAIT_IFC1     = 4'd4,
    S_SEND_IFC2_P   = 4'd5,
    S_SEND_IFC2_NP  = 4'd6,
    S_SEND_IFC2_CPL = 4'd7,
    S_WAIT_IFC2     = 4'd8,
    S_DONE          = 4'd9;

reg [3:0] state, next_state;

// ---------------------------------------------------------------------------
// Track which InitFC DLLPs we have received from the partner
// ---------------------------------------------------------------------------
reg got_ifc1_p, got_ifc1_np, got_ifc1_cpl;
reg got_ifc2_p, got_ifc2_np, got_ifc2_cpl;

wire all_ifc1 = got_ifc1_p & got_ifc1_np & got_ifc1_cpl;
wire all_ifc2 = got_ifc2_p & got_ifc2_np & got_ifc2_cpl;

wire [7:0] rx_type = initfc_rx[71:64];

// ---------------------------------------------------------------------------
// Build a 72-bit InitFC DLLP word
// ---------------------------------------------------------------------------
function [71:0] make_dllp;
    input [7:0]  dtype;
    input [7:0]  hdr;
    input [11:0] dat;
    begin
        make_dllp = { dtype,   // [71:64] DLLP type
                      8'h00,   // [63:56] VC ID = 0
                      hdr,     // [55:48] HdrFC
                      dat,     // [47:36] DataFC
                      20'h0,   // [35:16] reserved
                      16'h0 }; // [15: 0] CRC placeholder
    end
endfunction

// ---------------------------------------------------------------------------
// Sequential: state + receive flags
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= S_IDLE;
        got_ifc1_p   <= 1'b0;  got_ifc1_np  <= 1'b0;  got_ifc1_cpl <= 1'b0;
        got_ifc2_p   <= 1'b0;  got_ifc2_np  <= 1'b0;  got_ifc2_cpl <= 1'b0;
    end else begin
        state <= next_state;

        if (initfc_rx_valid) begin
            case (rx_type)
                TYPE_IFC1_P  : got_ifc1_p   <= 1'b1;
                TYPE_IFC1_NP : got_ifc1_np  <= 1'b1;
                TYPE_IFC1_CPL: got_ifc1_cpl <= 1'b1;
                TYPE_IFC2_P  : got_ifc2_p   <= 1'b1;
                TYPE_IFC2_NP : got_ifc2_np  <= 1'b1;
                TYPE_IFC2_CPL: got_ifc2_cpl <= 1'b1;
                default:;
            endcase
        end
    end
end

// ---------------------------------------------------------------------------
// Combinational: next-state logic
// ---------------------------------------------------------------------------
always @(*) begin
    next_state = state;
    case (state)
        S_IDLE         : if (dll_up)    next_state = S_SEND_IFC1_P;
        S_SEND_IFC1_P  :                next_state = S_SEND_IFC1_NP;
        S_SEND_IFC1_NP :                next_state = S_SEND_IFC1_CPL;
        S_SEND_IFC1_CPL:                next_state = S_WAIT_IFC1;
        S_WAIT_IFC1    : if (all_ifc1)  next_state = S_SEND_IFC2_P;
        S_SEND_IFC2_P  :                next_state = S_SEND_IFC2_NP;
        S_SEND_IFC2_NP :                next_state = S_SEND_IFC2_CPL;
        S_SEND_IFC2_CPL:                next_state = S_WAIT_IFC2;
        S_WAIT_IFC2    : if (all_ifc2)  next_state = S_DONE;
        S_DONE         :                next_state = S_DONE;
        default        :                next_state = S_IDLE;
    endcase
end

// ---------------------------------------------------------------------------
// Sequential: output logic
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        initfc_tx      <= 72'h0;
        initfc_tx_send <= 1'b0;
        fc_init_done   <= 1'b0;
        adv_ph         <= 8'h0;
        adv_pd         <= 12'h0;
        adv_nph        <= 8'h0;
        adv_cplh       <= 8'h0;
        adv_cpld       <= 12'h0;
    end else begin
        initfc_tx_send <= 1'b0;          // default: de-assert
        fc_init_done   <= (state == S_DONE);

        case (next_state)
            S_SEND_IFC1_P: begin
                initfc_tx      <= make_dllp(TYPE_IFC1_P,   K_PH,   K_PD);
                initfc_tx_send <= 1'b1;
            end
            S_SEND_IFC1_NP: begin
                initfc_tx      <= make_dllp(TYPE_IFC1_NP,  K_NPH,  12'h0);
                initfc_tx_send <= 1'b1;
            end
            S_SEND_IFC1_CPL: begin
                initfc_tx      <= make_dllp(TYPE_IFC1_CPL, K_CPLH, K_CPLD);
                initfc_tx_send <= 1'b1;
            end
            S_SEND_IFC2_P: begin
                initfc_tx      <= make_dllp(TYPE_IFC2_P,   K_PH,   K_PD);
                initfc_tx_send <= 1'b1;
            end
            S_SEND_IFC2_NP: begin
                initfc_tx      <= make_dllp(TYPE_IFC2_NP,  K_NPH,  12'h0);
                initfc_tx_send <= 1'b1;
            end
            S_SEND_IFC2_CPL: begin
                initfc_tx      <= make_dllp(TYPE_IFC2_CPL, K_CPLH, K_CPLD);
                initfc_tx_send <= 1'b1;
            end
            S_DONE: begin
                adv_ph   <= K_PH;
                adv_pd   <= K_PD;
                adv_nph  <= K_NPH;
                adv_cplh <= K_CPLH;
                adv_cpld <= K_CPLD;
            end
            default:;
        endcase
    end
end

endmodule
