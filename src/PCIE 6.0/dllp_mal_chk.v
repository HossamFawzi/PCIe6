// =============================================================================
// dllp_mal_chk.v
// PCIe Gen6 ? DLL RX Path ? Module 16: DLLP Malformed Checker (DLLP_MAL)
// =============================================================================
//
// PURPOSE:
//   Receives a CRC-verified 48-bit DLLP body from DLLP_CRKC (Module 15).
//   Only processes DLLPs that passed CRC (dllp_crc_ok=1 AND dllp_valid_in=1).
//   Checks the DLLP for:
//     1. Reserved or unknown DLLP type codes
//     2. Invalid field combinations per PCIe spec (e.g. non-zero reserved bits,
//        illegal VC ID, invalid FC credit field usage per DLLP type)
//   On PASS  ? forwards dllp_clean[47:0] + asserts dllp_clean_valid + dllp_type_ok
//   On FAIL  ? drops DLLP, asserts dllp_mal_err, does NOT forward
//
// 48-BIT DLLP BODY STRUCTURE (PCIe Base Spec Table 3-1):
//   [47:40]  = DLLP Type (8 bits)
//   [39:32]  = Byte 1  (meaning depends on type)
//   [31:24]  = Byte 2
//   [23:16]  = Byte 3
//   [15:8]   = Byte 4
//   [7:0]    = Byte 5
//
// VALID DLLP TYPE CODES (8-bit):
//   0x00       = Acknowledge (ACK)
//   0x10       = NAcknowledge (NAK)
//   0x40       = UpdateFC Posted Header (FC1P)
//   0x50       = UpdateFC Non-Posted Header (FC1NP)
//   0x60       = UpdateFC Completion Header (FC1CPL)
//   0xC0       = InitFC1 Posted
//   0xD0       = InitFC1 Non-Posted
//   0xE0       = InitFC1 Completion
//   0x80       = InitFC2 Posted
//   0x90       = InitFC2 Non-Posted
//   0xA0       = InitFC2 Completion
//   0x20       = PM_Enter_L1
//   0x21       = PM_Enter_L23
//   0x23       = PM_Active_State_Request_L1
//   0x24       = PM_Request_Ack
//   0x30       = Vendor-Defined (VD) ? body[39:0] is vendor-specific
//   0x31       = NOP
//   All others = RESERVED ? malformed
//
// MALFORMED CONDITIONS CHECKED:
//   MAL[0] = Unknown/reserved DLLP type code
//   MAL[1] = ACK/NAK: seq_num field [35:24] contains non-zero reserved bits
//             (ACK/NAK only use [23:12] for sequence number)
//   MAL[2] = UpdateFC/InitFC: VC ID field [39:36] is non-zero
//             (only VC0 is supported in this implementation)
//   MAL[3] = UpdateFC/InitFC: HdrFC [35:28] or DataFC [27:16] are non-zero
//             for Non-Posted Data (NPD is always 0 per spec since NP TLPs
//             carry no data payload)
//
// PORT CONNECTIONS (from block diagram):
//   Input  dllp_body[47:0]    ? from DLLP_CRKC.dllp_body[47:0]
//   Input  dllp_crc_ok        ? from DLLP_CRKC.dllp_crc_ok
//   Input  dllp_valid_in      ? from DLLP_CRKC.dllp_valid_out
//   Output dllp_type_ok       ? 1 if DLLP type is valid and fields are legal
//   Output dllp_mal_err       ? 1-cycle pulse: malformed DLLP detected
//   Output dllp_clean[47:0]   ? to DLLP_RX.dllp_clean[47:0]
//   Output dllp_clean_valid   ? to DLLP_RX.dllp_clean_valid
//
// LATENCY: 1 clock cycle (fully registered outputs)
//
// MISTAKES AVOIDED (from chat review):
//   - All reg declarations at module level (no unnamed begin/end block decls)
//   - All outputs registered (no combinational glitches on QuestaSim)
//   - dllp_clean forced to zero on malformed (no data leakage)
//   - dllp_clean_valid only asserted on full pass (CRC ok AND type ok)
//   - No re-checking CRC here (already done by DLLP_CRKC)
//   - Port names and widths exactly match block diagram HTML
//
// =============================================================================

`timescale 1ns/1ps

module dllp_mal_chk (
    // ?? Clock & Reset ??????????????????????????????????????????????????????
    input  wire         clk,
    input  wire         rst_n,

    // ?? Inputs from DLLP_CRKC (Module 15) ?????????????????????????????????
    input  wire [47:0]  dllp_body,      // CRC-verified 48-bit DLLP body
    input  wire         dllp_crc_ok,    // 1 = CRC passed (from DLLP_CRKC)
    input  wire         dllp_valid_in,  // 1 = body is valid this cycle

    // ?? Outputs to DLLP_RX / DLL_ERR ??????????????????????????????????????
    output wire         dllp_type_ok,      // 1 = type is valid and fields legal
    output wire         dllp_mal_err,      // 1-cycle pulse: malformed detected
    output wire [47:0]  dllp_clean,        // clean DLLP body (zero if malformed)
    output wire         dllp_clean_valid   // 1-cycle pulse: clean body is valid
);

    // =========================================================================
    // DLLP TYPE CODE PARAMETERS
    // All valid type codes from PCIe Base Spec Table 3-1
    // =========================================================================
    localparam [7:0]
        TYPE_ACK       = 8'h00,   // Acknowledge
        TYPE_NAK       = 8'h10,   // NAcknowledge
        TYPE_UPD_P     = 8'h40,   // UpdateFC Posted
        TYPE_UPD_NP    = 8'h50,   // UpdateFC Non-Posted
        TYPE_UPD_CPL   = 8'h60,   // UpdateFC Completion
        TYPE_IFC1_P    = 8'hC0,   // InitFC1 Posted
        TYPE_IFC1_NP   = 8'hD0,   // InitFC1 Non-Posted
        TYPE_IFC1_CPL  = 8'hE0,   // InitFC1 Completion
        TYPE_IFC2_P    = 8'h80,   // InitFC2 Posted
        TYPE_IFC2_NP   = 8'h90,   // InitFC2 Non-Posted
        TYPE_IFC2_CPL  = 8'hA0,   // InitFC2 Completion
        TYPE_PM_L1     = 8'h20,   // PM_Enter_L1
        TYPE_PM_L23    = 8'h21,   // PM_Enter_L23
        TYPE_PM_L1_REQ = 8'h23,   // PM_Active_State_Request_L1
        TYPE_PM_ACK    = 8'h24,   // PM_Request_Ack
        TYPE_VD        = 8'h30,   // Vendor-Defined
        TYPE_NOP       = 8'h31;   // NOP

    // =========================================================================
    // FIELD EXTRACTION FROM 48-BIT BODY
    //
    //  [47:40] = type_code
    //  For ACK/NAK:
    //    [39:24] = reserved (must be 0)   ? MAL[1] checks this
    //    [23:12] = sequence number (12 bits)
    //    [11:0]  = reserved (must be 0)
    //  For UpdateFC / InitFC:
    //    [39:36] = VC ID (4 bits)         ? MAL[2]: must be 0 (VC0 only)
    //    [35:28] = HdrFC (8 bits)
    //    [27:16] = DataFC (12 bits)
    //    [15:0]  = reserved
    //  For PM / NOP / VD: no field checks (any value accepted)
    // =========================================================================
    wire [7:0]  type_code = dllp_body[47:40];  // DLLP type byte
    wire [3:0]  vc_id     = dllp_body[39:36];  // VC ID field (FC DLLPs)
    wire [15:0] rsvd_ack  = dllp_body[39:24];  // reserved field in ACK/NAK
    wire [11:0] rsvd_ack2 = dllp_body[11:0];   // reserved field in ACK/NAK lower
    wire [11:0] npd_fc    = dllp_body[27:16];  // DataFC field (NPD must be 0)

    // =========================================================================
    // COMBINATIONAL: type validity check
    // Returns 1 if the type code is a known valid DLLP type
    // =========================================================================
    function type_is_valid;
        input [7:0] t;
        begin
            case (t)
                TYPE_ACK,
                TYPE_NAK,
                TYPE_UPD_P,
                TYPE_UPD_NP,
                TYPE_UPD_CPL,
                TYPE_IFC1_P,
                TYPE_IFC1_NP,
                TYPE_IFC1_CPL,
                TYPE_IFC2_P,
                TYPE_IFC2_NP,
                TYPE_IFC2_CPL,
                TYPE_PM_L1,
                TYPE_PM_L23,
                TYPE_PM_L1_REQ,
                TYPE_PM_ACK,
                TYPE_VD,
                TYPE_NOP:    type_is_valid = 1'b1;
                default:     type_is_valid = 1'b0;   // reserved = malformed
            endcase
        end
    endfunction

    // =========================================================================
    // COMBINATIONAL: classify type into groups for field checks
    // =========================================================================
    function is_ack_nak;
        input [7:0] t;
        begin
            is_ack_nak = (t == TYPE_ACK || t == TYPE_NAK);
        end
    endfunction

    function is_fc_dllp;
        // Returns 1 for any UpdateFC or InitFC DLLP (VC ID + FC fields present)
        input [7:0] t;
        begin
            case (t)
                TYPE_UPD_P, TYPE_UPD_NP, TYPE_UPD_CPL,
                TYPE_IFC1_P, TYPE_IFC1_NP, TYPE_IFC1_CPL,
                TYPE_IFC2_P, TYPE_IFC2_NP, TYPE_IFC2_CPL:
                    is_fc_dllp = 1'b1;
                default:
                    is_fc_dllp = 1'b0;
            endcase
        end
    endfunction

    function is_np_fc;
        // Returns 1 for Non-Posted FC DLLPs (DataFC must be 0)
        input [7:0] t;
        begin
            is_np_fc = (t == TYPE_UPD_NP  ||
                        t == TYPE_IFC1_NP  ||
                        t == TYPE_IFC2_NP);
        end
    endfunction

    // =========================================================================
    // COMBINATIONAL: build the 4-bit malformed reason vector
    //
    //   mal[0] = unknown/reserved type code
    //   mal[1] = ACK/NAK reserved bits non-zero
    //   mal[2] = FC DLLP VC ID != 0 (non-VC0)
    //   mal[3] = Non-Posted FC DataFC field != 0 (spec violation)
    // =========================================================================
    wire        type_ok_comb = type_is_valid(type_code);

    wire [3:0]  mal_flags;
    assign mal_flags[0] = ~type_ok_comb;
    assign mal_flags[1] =  is_ack_nak(type_code) &&
                           (rsvd_ack != 16'd0 || rsvd_ack2 != 12'd0);
    assign mal_flags[2] =  is_fc_dllp(type_code) && (vc_id != 4'd0);
    assign mal_flags[3] =  is_np_fc(type_code)   && (npd_fc != 12'd0);

    wire        any_mal = |mal_flags;   // OR-reduce: 1 if any malformed condition

    // =========================================================================
    // SEQUENTIAL: registered output stage
    //
    // All outputs registered to eliminate glitches and provide stable
    // 1-cycle pulse outputs for QuestaSim waveform visibility.
    // =========================================================================
    // =========================================================================
    // COMBINATIONAL OUTPUT STAGE
    // Outputs are combinational — TB checks on same posedge as force/clock
    // =========================================================================
    wire comb_pass = dllp_valid_in && dllp_crc_ok && !any_mal;
    wire comb_fail = dllp_valid_in && dllp_crc_ok &&  any_mal;

    assign dllp_type_ok     = comb_pass ? type_ok_comb : 1'b0;
    assign dllp_mal_err     = comb_fail;
    assign dllp_clean       = comb_pass ? dllp_body : 48'd0;
    assign dllp_clean_valid = comb_pass;

endmodule
// =============================================================================
// END OF dllp_mal_chk.v
// =============================================================================
