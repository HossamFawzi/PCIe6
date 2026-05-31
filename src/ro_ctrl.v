
module ro_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_attr_ro,
    input  wire [3:0]  req_type,
    input  wire [2:0]  req_tc,

    input  wire        ro_en,

    input  wire        ordering_stall,

    output wire        ro_bypass_ok,
    output wire        ordering_override,
    output wire        ro_err
);

    localparam [3:0] TYPE_MWR  = 4'b0000;
    localparam [3:0] TYPE_MRD  = 4'b0001;
    localparam [3:0] TYPE_CPL  = 4'b1010;
    localparam [3:0] TYPE_CPLD = 4'b1011;

    reg valid_for_ro;
    reg ro_bypass_ok_r, ordering_override_r, ro_err_r;
    assign ro_bypass_ok      = ro_bypass_ok_r;
    assign ordering_override = ordering_override_r;
    assign ro_err            = ro_err_r;

    always @(*) begin

        case (req_type)
            TYPE_MWR : valid_for_ro = 1'b1;
            TYPE_MRD : valid_for_ro = 1'b1;
            default  : valid_for_ro = 1'b0;
        endcase
    end

    always @(*) begin
        ro_err_r            = 1'b0;
        ro_bypass_ok_r      = 1'b0;
        ordering_override_r = 1'b0;

        if (req_attr_ro) begin
            if (!ro_en) begin
                ro_err_r = 1'b1;
            end else if (!valid_for_ro) begin
                ro_err_r = 1'b1;
            end else begin
                ro_bypass_ok_r      = 1'b1;
                ordering_override_r = ordering_stall;
            end
        end
    end

endmodule
