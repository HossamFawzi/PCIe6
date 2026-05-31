
`timescale 1ns/1ps

module dllp_mal_chk (

    input  wire         clk,
    input  wire         rst_n,

    input  wire [47:0]  dllp_body,
    input  wire         dllp_crc_ok,
    input  wire         dllp_valid_in,

    output wire         dllp_type_ok,
    output wire         dllp_mal_err,
    output wire [47:0]  dllp_clean,
    output wire         dllp_clean_valid
);

    localparam [7:0]
        TYPE_ACK       = 8'h00,
        TYPE_NAK       = 8'h10,
        TYPE_UPD_P     = 8'h40,
        TYPE_UPD_NP    = 8'h50,
        TYPE_UPD_CPL   = 8'h60,
        TYPE_IFC1_P    = 8'hC0,
        TYPE_IFC1_NP   = 8'hD0,
        TYPE_IFC1_CPL  = 8'hE0,
        TYPE_IFC2_P    = 8'h80,
        TYPE_IFC2_NP   = 8'h90,
        TYPE_IFC2_CPL  = 8'hA0,
        TYPE_PM_L1     = 8'h20,
        TYPE_PM_L23    = 8'h21,
        TYPE_PM_L1_REQ = 8'h23,
        TYPE_PM_ACK    = 8'h24,
        TYPE_VD        = 8'h30,
        TYPE_NOP       = 8'h31;

    wire [7:0]  type_code = dllp_body[47:40];
    wire [3:0]  vc_id     = dllp_body[39:36];
    wire [15:0] rsvd_ack  = dllp_body[39:24];
    wire [11:0] rsvd_ack2 = dllp_body[11:0];
    wire [11:0] npd_fc    = dllp_body[27:16];

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
                default:     type_is_valid = 1'b0;
            endcase
        end
    endfunction

    function is_ack_nak;
        input [7:0] t;
        begin
            is_ack_nak = (t == TYPE_ACK || t == TYPE_NAK);
        end
    endfunction

    function is_fc_dllp;

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

        input [7:0] t;
        begin
            is_np_fc = (t == TYPE_UPD_NP  ||
                        t == TYPE_IFC1_NP  ||
                        t == TYPE_IFC2_NP);
        end
    endfunction

    wire        type_ok_comb = type_is_valid(type_code);

    wire [3:0]  mal_flags;
    assign mal_flags[0] = ~type_ok_comb;
    assign mal_flags[1] =  is_ack_nak(type_code) &&
                           (rsvd_ack != 16'd0 || rsvd_ack2 != 12'd0);
    assign mal_flags[2] =  is_fc_dllp(type_code) && (vc_id != 4'd0);
    assign mal_flags[3] =  is_np_fc(type_code)   && (npd_fc != 12'd0);

    wire        any_mal = |mal_flags;

    wire comb_pass = dllp_valid_in && dllp_crc_ok && !any_mal;
    wire comb_fail = dllp_valid_in && dllp_crc_ok &&  any_mal;

    assign dllp_type_ok     = comb_pass ? type_ok_comb : 1'b0;
    assign dllp_mal_err     = comb_fail;
    assign dllp_clean       = comb_pass ? dllp_body : 48'd0;
    assign dllp_clean_valid = comb_pass;

endmodule
