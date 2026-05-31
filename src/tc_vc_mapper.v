
module tc_vc_mapper (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [2:0]  tlp_tc,
    input  wire        tlp_valid,

    input  wire [23:0] vc_map_cfg,
    input  wire [7:0]  vc_arb_cfg,

    output reg  [2:0]  vc_id,
    output reg         vc_map_valid,
    output reg         vc_map_err
);

    wire [2:0] vc_for_tc [0:7];
    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GEN_VC_MAP
            assign vc_for_tc[g] = vc_map_cfg[3*g+2 : 3*g];
        end
    endgenerate

    reg [2:0] resolved_vc;

    always @(*) begin
        resolved_vc = vc_for_tc[tlp_tc];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vc_id        <= 3'h0;
            vc_map_valid <= 1'b0;
            vc_map_err   <= 1'b0;
        end
        else if (tlp_valid) begin
            vc_id        <= resolved_vc;
            vc_map_valid <= 1'b1;

            vc_map_err   <= (resolved_vc > 3'd3) ? 1'b1 : 1'b0;
        end
        else begin
            vc_map_valid <= 1'b0;
            vc_map_err   <= 1'b0;
        end
    end

endmodule
