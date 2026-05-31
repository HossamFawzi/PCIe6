
module rx_tlp_router (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [4:0]    tlp_type,
    input  wire [2:0]    tlp_fmt,
    input  wire          tlp_fwd_valid,
    input  wire [1023:0] tlp_rx,
    input  wire          ecrc_ok,

    output wire          to_cpl_valid,
    output wire          to_mwr_valid,
    output wire          to_cfg_valid,
    output wire          to_msg_valid,
    output wire          to_atomic_valid,
    output wire [1023:0] routed_tlp
);

    wire is_mem    = (tlp_type == 5'b00000);
    wire is_io     = (tlp_type == 5'b00010);
    wire is_cfg    = (tlp_type == 5'b00100) || (tlp_type == 5'b00101);
    wire is_msg    = (tlp_type[4:3] == 2'b10);
    wire is_cpl    = (tlp_type == 5'b01010);
    wire is_atomic = (tlp_type == 5'b01100) ||
                     (tlp_type == 5'b01101) ||
                     (tlp_type == 5'b01110);

    wire route_en = tlp_fwd_valid && ecrc_ok;

    assign to_cpl_valid    = route_en & is_cpl;

    wire is_mwr = is_mem & tlp_fmt[1];
    assign to_mwr_valid    = route_en & is_mwr;
    assign to_cfg_valid    = route_en & (is_cfg | is_io);
    assign to_msg_valid    = route_en & is_msg;
    assign to_atomic_valid = route_en & is_atomic;

    assign routed_tlp = route_en ? tlp_rx : 1024'b0;

endmodule
