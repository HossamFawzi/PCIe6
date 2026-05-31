`timescale 1ns/1ps

module tlp_prefix_handler #(
    parameter LTP_TYPE_MASK = 4'hE
) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [1023:0] tlp_in,
    input  wire          tlp_valid_in,

    input  wire [127:0]  ltp_data,
    input  wire          ltp_valid,

    input  wire [127:0]  eetp_data,
    input  wire          eetp_valid,

    output reg  [1151:0] tlp_prefixed,
    output reg           tlp_prefixed_valid,
    output reg           prefix_err,
    output reg           e2e_fwd
);

localparam PREFIX_FMT     = 4'b0100;
localparam EETP_LOCAL_BIT = 23;
localparam LTP_RSVD_TYPE  = 4'hF;

wire [31:0] ltp_dw  = ltp_data[127:96];
wire [31:0] eetp_dw = eetp_data[127:96];

wire [3:0]  ltp_fmt  = ltp_dw[31:28];
wire [3:0]  ltp_type = ltp_dw[27:24];

wire [3:0]  eetp_fmt  = eetp_dw[31:28];
wire        eetp_local = eetp_dw[EETP_LOCAL_BIT];

wire ltp_type_err   = ltp_valid  && (ltp_type  == LTP_RSVD_TYPE);
wire eetp_scope_err = eetp_valid && eetp_local;

wire any_err = ltp_type_err | eetp_scope_err;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tlp_prefixed       <= 1152'd0;
        tlp_prefixed_valid <= 1'b0;
        prefix_err         <= 1'b0;
        e2e_fwd            <= 1'b0;
    end else begin

        tlp_prefixed_valid <= 1'b0;
        prefix_err         <= 1'b0;
        e2e_fwd            <= 1'b0;

        if (tlp_valid_in) begin
            if (any_err) begin
                prefix_err         <= 1'b1;
                tlp_prefixed_valid <= 1'b0;
            end else begin

                tlp_prefixed[1151:1120] <= ltp_valid  ? ltp_dw  : 32'd0;
                tlp_prefixed[1119:1088] <= eetp_valid ? eetp_dw : 32'd0;
                tlp_prefixed[1087:1024] <= 64'd0;

                tlp_prefixed[1023:0]    <= tlp_in;

                tlp_prefixed_valid      <= 1'b1;
                e2e_fwd                 <= eetp_valid;
            end
        end
    end
end

always @(posedge clk) begin
    if (ltp_valid && (ltp_fmt !== PREFIX_FMT))
        $display("WARN [PFX] ltp_fmt=0x%0h expected 0x%0h at time %0t", ltp_fmt, PREFIX_FMT, $time);
    if (eetp_valid && (eetp_fmt !== PREFIX_FMT))
        $display("WARN [PFX] eetp_fmt=0x%0h expected 0x%0h at time %0t", eetp_fmt, PREFIX_FMT, $time);
end

endmodule