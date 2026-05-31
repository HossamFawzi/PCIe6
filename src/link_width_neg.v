module link_width_neg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  ts1_lane_num,
    input  wire [5:0]  local_width_cap,
    input  wire        upcfg_req,
    input  wire [5:0]  ltssm_state,
    output reg  [5:0]  negotiated_width,
    output reg         width_neg_done,
    output reg  [15:0] active_lanes,
    output reg         width_change_req
);

    localparam ST_DETECT    = 6'h00;
    localparam ST_POLLING   = 6'h01;
    localparam ST_CONFIG    = 6'h02;
    localparam ST_RECOVERY  = 6'h03;
    localparam ST_L0        = 6'h04;
    localparam ST_L0S       = 6'h05;
    localparam ST_L1        = 6'h06;
    localparam ST_L2        = 6'h07;
    localparam ST_DISABLED  = 6'h08;
    localparam ST_HOTRESET  = 6'h09;
    localparam ST_LOOPBACK  = 6'h0A;

    localparam W1_BIT  = 0;
    localparam W2_BIT  = 1;
    localparam W4_BIT  = 2;
    localparam W8_BIT  = 3;
    localparam W16_BIT = 4;

    wire [4:0] common_cap;
    assign common_cap = ts1_lane_num[4:0] & local_width_cap[4:0];

    reg [5:0]  neg_w;
    reg [15:0] act_lanes;
    reg        neg_valid;

    always @(*) begin
        if (common_cap[W16_BIT]) begin
            neg_w     = 6'd16;
            act_lanes = 16'hFFFF;
            neg_valid = 1'b1;
        end else if (common_cap[W8_BIT]) begin
            neg_w     = 6'd8;
            act_lanes = 16'h00FF;
            neg_valid = 1'b1;
        end else if (common_cap[W4_BIT]) begin
            neg_w     = 6'd4;
            act_lanes = 16'h000F;
            neg_valid = 1'b1;
        end else if (common_cap[W2_BIT]) begin
            neg_w     = 6'd2;
            act_lanes = 16'h0003;
            neg_valid = 1'b1;
        end else if (common_cap[W1_BIT]) begin
            neg_w     = 6'd1;
            act_lanes = 16'h0001;
            neg_valid = 1'b1;
        end else begin
            neg_w     = 6'd1;
            act_lanes = 16'h0001;
            neg_valid = 1'b0;
        end
    end

    reg upcfg_possible;

    always @(*) begin
        if (!upcfg_req) begin
            upcfg_possible = 1'b0;
        end else begin

            upcfg_possible = (common_cap[W16_BIT] | common_cap[W8_BIT] |
                              common_cap[W4_BIT]  | common_cap[W2_BIT]);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            negotiated_width <= 6'd1;
            width_neg_done   <= 1'b0;
            active_lanes     <= 16'h0001;
            width_change_req <= 1'b0;
        end else begin
            if (ltssm_state == ST_CONFIG || ltssm_state == ST_RECOVERY) begin
                negotiated_width <= neg_w;
                active_lanes     <= act_lanes;
                width_neg_done   <= neg_valid;
                width_change_req <= upcfg_possible;
            end else begin

                width_neg_done   <= 1'b0;
                width_change_req <= 1'b0;
            end
        end
    end

endmodule
