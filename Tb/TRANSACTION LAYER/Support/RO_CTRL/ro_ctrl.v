
module ro_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_attr_ro,
    input  wire [3:0]  req_type,
    input  wire [2:0]  req_tc,

    input  wire        ro_en,

    input  wire        ordering_stall,

    output reg         ro_bypass_ok,
    output reg         ordering_override,
    output reg         ro_err
);

    localparam [3:0] TYPE_MWR  = 4'b0000;
    localparam [3:0] TYPE_MRD  = 4'b0001;
    localparam [3:0] TYPE_CPL  = 4'b1010;
    localparam [3:0] TYPE_CPLD = 4'b1011;

    reg valid_for_ro;

    always @(*) begin

        case (req_type)
            TYPE_MWR : valid_for_ro = 1'b1;
            TYPE_MRD : valid_for_ro = 1'b1;
            default  : valid_for_ro = 1'b0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ro_bypass_ok       <= 1'b0;
            ordering_override  <= 1'b0;
            ro_err             <= 1'b0;
        end
        else begin
            ro_err             <= 1'b0;
            ro_bypass_ok       <= 1'b0;
            ordering_override  <= 1'b0;

            if (req_attr_ro) begin
                if (!ro_en) begin

                    ro_err <= 1'b1;
                end
                else if (!valid_for_ro) begin

                    ro_err <= 1'b1;
                end
                else begin

                    ro_bypass_ok      <= 1'b1;
                    ordering_override <= ordering_stall;
                end
            end
        end
    end

endmodule
