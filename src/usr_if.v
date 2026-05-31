
module usr_if (

    input  wire          clk,
    input  wire          rst_n,

    input  wire [3:0]    req_type,
    input  wire [63:0]   req_addr,
    input  wire [9:0]    req_len,
    input  wire [511:0]  req_data,
    input  wire          req_valid,
    input  wire [2:0]    req_attr,
    input  wire [2:0]    req_tc,
    input  wire [3:0]    req_first_be,
    input  wire [3:0]    req_last_be,
    output wire          req_ready,

    output wire [603:0]  pkt_out,
    output wire          pkt_valid,
    input  wire          pkt_ready,

    input  wire [511:0]  cpl_data,
    input  wire          cpl_valid,
    input  wire [2:0]    cpl_status,
    input  wire [9:0]    cpl_tag,
    output wire [511:0]  usr_cpl_data,
    output wire          usr_cpl_valid,
    output wire [2:0]    usr_cpl_status,
    output wire [9:0]    usr_cpl_tag,

    input  wire [511:0]  mwr_data,
    input  wire          mwr_valid,
    input  wire [63:0]   mwr_addr,
    output wire [511:0]  usr_mwr_data,
    output wire          usr_mwr_valid,
    output wire [63:0]   usr_mwr_addr

);

assign pkt_out = {
    req_type,
    req_addr,
    req_len,
    req_attr,
    req_tc,
    req_first_be,
    req_last_be,
    req_data
};

assign pkt_valid = req_valid;
assign req_ready = pkt_ready;

assign usr_cpl_data   = cpl_data;
assign usr_cpl_valid  = cpl_valid;
assign usr_cpl_status = cpl_status;
assign usr_cpl_tag    = cpl_tag;

assign usr_mwr_data   = mwr_data;
assign usr_mwr_valid  = mwr_valid;
assign usr_mwr_addr   = mwr_addr;

`ifdef SIMULATION
always @(posedge clk) begin
    if (rst_n && req_valid && req_ready) begin
        if (req_type > 4'd5)
            $error("[USR_IF] Unknown req_type=%0d", req_type);
        if (req_len == 10'd0)
            $error("[USR_IF] req_len=0 illegal");
    end
end
`endif

endmodule
