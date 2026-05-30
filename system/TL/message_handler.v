// ============================================================
//  Module  : pcie_msg_hdl
//  Purpose : PCIe Gen6 - Message Handler (RX)
//
//  ARCHITECTURE FIX: All outputs are now COMBINATORIAL.
//  The testbench checks message outputs (intx_assert, pme_msg,
//  err_msg_valid, vdm_valid, msg_to_aer) at the SAME clock edge
//  at which tlp_msg_valid asserts (cy1 after SOP), before
//  deasserting tlp_rx_valid.  A registered implementation
//  would produce outputs at cy2, missing the check window.
//  Combinatorial decode from tlp_msg_valid + msg_code gives
//  zero-latency outputs that are valid for the full cy1 period.
//
//  Supported message types:
//    INTx Assert / Deassert  (msg_code 0x20-0x27)
//    PME                     (msg_code 0x18)
//    ERR_COR                 (msg_code 0x30)
//    ERR_NONFATAL            (msg_code 0x31)
//    ERR_FATAL               (msg_code 0x33)
//    VDM (no data)           (msg_code 0x7E)
//    VDM (with data)         (msg_code 0x7F)
//    Slot Power Limit        (msg_code 0x50)
//    All others -> msg_to_aer
// ============================================================

module pcie_msg_hdl (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [1023:0] tlp_msg,
    input  wire          tlp_msg_valid,
    input  wire [7:0]    msg_code,

    output wire [3:0]    intx_assert,
    output wire [3:0]    intx_deassert,
    output wire          pme_msg,
    output wire [2:0]    err_msg_type,
    output wire          err_msg_valid,
    output wire [511:0]  vdm_data,
    output wire          vdm_valid,
    output wire          msg_to_aer
);

    localparam MSG_INTA_ASSERT   = 8'h20;
    localparam MSG_INTB_ASSERT   = 8'h21;
    localparam MSG_INTC_ASSERT   = 8'h22;
    localparam MSG_INTD_ASSERT   = 8'h23;
    localparam MSG_INTA_DEASSERT = 8'h24;
    localparam MSG_INTB_DEASSERT = 8'h25;
    localparam MSG_INTC_DEASSERT = 8'h26;
    localparam MSG_INTD_DEASSERT = 8'h27;
    localparam MSG_PME           = 8'h18;
    localparam MSG_ERR_COR       = 8'h30;
    localparam MSG_ERR_NONFATAL  = 8'h31;
    localparam MSG_ERR_FATAL     = 8'h33;
    localparam MSG_VDM_NODATA    = 8'h7E;
    localparam MSG_VDM_DATA      = 8'h7F;
    localparam MSG_SPL           = 8'h50;

    localparam [2:0] ERR_TYPE_COR      = 3'd0;
    localparam [2:0] ERR_TYPE_NONFATAL = 3'd1;
    localparam [2:0] ERR_TYPE_FATAL    = 3'd2;

    // ----------------------------------------------------------
    // Combinatorial decode
    // ----------------------------------------------------------
    reg [3:0]   c_intx_assert;
    reg [3:0]   c_intx_deassert;
    reg         c_pme_msg;
    reg [2:0]   c_err_msg_type;
    reg         c_err_msg_valid;
    reg [511:0] c_vdm_data;
    reg         c_vdm_valid;
    reg         c_msg_to_aer;

    always @(*) begin
        c_intx_assert   = 4'b0000;
        c_intx_deassert = 4'b0000;
        c_pme_msg       = 1'b0;
        c_err_msg_type  = 3'b000;
        c_err_msg_valid = 1'b0;
        c_vdm_data      = 512'h0;
        c_vdm_valid     = 1'b0;
        c_msg_to_aer    = 1'b0;

        if (tlp_msg_valid) begin
            case (msg_code)
                MSG_INTA_ASSERT   : c_intx_assert = 4'b0001;
                MSG_INTB_ASSERT   : c_intx_assert = 4'b0010;
                MSG_INTC_ASSERT   : c_intx_assert = 4'b0100;
                MSG_INTD_ASSERT   : c_intx_assert = 4'b1000;

                MSG_INTA_DEASSERT : c_intx_deassert = 4'b0001;
                MSG_INTB_DEASSERT : c_intx_deassert = 4'b0010;
                MSG_INTC_DEASSERT : c_intx_deassert = 4'b0100;
                MSG_INTD_DEASSERT : c_intx_deassert = 4'b1000;

                MSG_PME           : c_pme_msg = 1'b1;

                MSG_ERR_COR: begin
                    c_err_msg_type  = ERR_TYPE_COR;
                    c_err_msg_valid = 1'b1;
                    c_msg_to_aer    = 1'b1;
                end
                MSG_ERR_NONFATAL: begin
                    c_err_msg_type  = ERR_TYPE_NONFATAL;
                    c_err_msg_valid = 1'b1;
                    c_msg_to_aer    = 1'b1;
                end
                MSG_ERR_FATAL: begin
                    c_err_msg_type  = ERR_TYPE_FATAL;
                    c_err_msg_valid = 1'b1;
                    c_msg_to_aer    = 1'b1;
                end

                MSG_VDM_NODATA: begin
                    c_vdm_data  = 512'h0;
                    c_vdm_valid = 1'b1;
                end
                MSG_VDM_DATA: begin
                    c_vdm_data  = tlp_msg[895:384];
                    c_vdm_valid = 1'b1;
                end

                MSG_SPL    : c_msg_to_aer = 1'b1;
                default    : c_msg_to_aer = 1'b1;
            endcase
        end
    end

    assign intx_assert   = c_intx_assert;
    assign intx_deassert = c_intx_deassert;
    assign pme_msg       = c_pme_msg;
    assign err_msg_type  = c_err_msg_type;
    assign err_msg_valid = c_err_msg_valid;
    assign vdm_data      = c_vdm_data;
    assign vdm_valid     = c_vdm_valid;
    assign msg_to_aer    = c_msg_to_aer;

endmodule
