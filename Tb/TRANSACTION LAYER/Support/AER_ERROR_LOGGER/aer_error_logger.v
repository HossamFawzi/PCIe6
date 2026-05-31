
module aer_error_logger (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  err_from_tmo,
    input  wire [3:0]  err_from_cpl,
    input  wire        err_from_mal,
    input  wire        err_from_psnd,
    input  wire        err_from_msg,
    input  wire        err_from_flit,

    input  wire [3:0]  dll_err,

    input  wire [1:0]  err_severity,

    output reg  [31:0] aer_status,
    output reg  [31:0] aer_mask,
    output reg         aer_int,

    output reg  [255:0] err_msg_tlp,
    output reg          err_msg_valid
);

    localparam BIT_DLPE   = 4;
    localparam BIT_PTLP   = 12;
    localparam BIT_FCP    = 13;
    localparam BIT_CT     = 14;
    localparam BIT_CA     = 15;
    localparam BIT_UC     = 16;
    localparam BIT_RO     = 17;
    localparam BIT_MTLP   = 18;
    localparam BIT_ECRC   = 19;
    localparam BIT_UR     = 20;
    localparam BIT_FLIT   = 24;

    localparam [7:0] MSG_ERR_COR      = 8'h30;
    localparam [7:0] MSG_ERR_NONFATAL = 8'h31;
    localparam [7:0] MSG_ERR_FATAL    = 8'h33;

    reg [31:0] new_status;
    reg        any_error;
    reg [7:0]  msg_type;

    initial aer_mask = 32'h0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aer_status    <= 32'h0;
            aer_int       <= 1'b0;
            err_msg_tlp   <= 256'h0;
            err_msg_valid <= 1'b0;
        end
        else begin

            err_msg_valid = 1'b0;
            aer_int       = 1'b0;
            any_error     = 1'b0;

            new_status = aer_status;

            if (err_from_tmo[0])  begin new_status[BIT_CT]   = 1'b1; any_error = 1'b1; end
            if (err_from_cpl[0])  begin new_status[BIT_UC]   = 1'b1; any_error = 1'b1; end
            if (err_from_cpl[1])  begin new_status[BIT_CA]   = 1'b1; any_error = 1'b1; end
            if (err_from_mal)     begin new_status[BIT_MTLP] = 1'b1; any_error = 1'b1; end
            if (err_from_psnd)    begin new_status[BIT_PTLP] = 1'b1; any_error = 1'b1; end
            if (err_from_msg)     begin new_status[BIT_UR]   = 1'b1; any_error = 1'b1; end
            if (err_from_flit)    begin new_status[BIT_FLIT] = 1'b1; any_error = 1'b1; end
            if (dll_err[0])       begin new_status[BIT_DLPE] = 1'b1; any_error = 1'b1; end
            if (dll_err[1])       begin new_status[BIT_FCP]  = 1'b1; any_error = 1'b1; end

            aer_status <= new_status;

            if (any_error && |(new_status & ~aer_mask)) begin
                case (err_severity)
                    2'b00:   msg_type = MSG_ERR_COR;
                    2'b01:   msg_type = MSG_ERR_NONFATAL;
                    default: msg_type = MSG_ERR_FATAL;
                endcase

                err_msg_tlp[255:248] = 8'h34;
                err_msg_tlp[247:240] = 8'h00;
                err_msg_tlp[239:232] = 8'h00;
                err_msg_tlp[231:224] = msg_type;
                err_msg_tlp[223:208] = 16'h0001;
                err_msg_tlp[207:200] = 8'h00;
                err_msg_tlp[199:192] = 8'h00;
                err_msg_tlp[191:160] = new_status;
                err_msg_tlp[159:0]   = 160'h0;
                err_msg_valid = 1'b1;
                aer_int       = 1'b1;
            end

            aer_int       <= aer_int;
            err_msg_valid <= err_msg_valid;
            err_msg_tlp   <= err_msg_tlp;
        end
    end

endmodule
