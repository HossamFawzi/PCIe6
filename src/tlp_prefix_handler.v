
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

    output wire [1151:0] tlp_prefixed,
    output wire          tlp_prefixed_valid,
    output wire          prefix_err,
    output wire          e2e_fwd
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

wire ltp_type_err  = ltp_valid  && (ltp_type  == LTP_RSVD_TYPE);
wire eetp_scope_err = eetp_valid && eetp_local;

wire any_err = ltp_type_err | eetp_scope_err;

assign tlp_prefixed = {
    ltp_valid  ? ltp_dw  : 32'd0, 96'd0,
    eetp_valid ? eetp_dw : 32'd0, 96'd0,
    tlp_in[895:0]
};
assign tlp_prefixed_valid = tlp_valid_in && !any_err;
assign prefix_err         = tlp_valid_in && any_err;
assign e2e_fwd            = tlp_valid_in && !any_err && eetp_valid;

`ifdef SIMULATION
always @(posedge clk) begin
    if (ltp_valid && (ltp_fmt !== PREFIX_FMT))
        $display("WARN [PFX] ltp_fmt=0x%0h expected 0x%0h at time %0t",
                  ltp_fmt, PREFIX_FMT, $time);
    if (eetp_valid && (eetp_fmt !== PREFIX_FMT))
        $display("WARN [PFX] eetp_fmt=0x%0h expected 0x%0h at time %0t",
                  eetp_fmt, PREFIX_FMT, $time);
end
`endif

endmodule
