module link_speed_neg (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  ts1_speed_cap,
    input  wire [7:0]  ts2_speed_cap,
    input  wire [7:0]  local_speed_cap,
    input  wire        speed_change_req,
    input  wire [5:0]  ltssm_state,
    output reg  [3:0]  target_speed,
    output reg         speed_change_en,
    output reg  [7:0]  adv_speed_cap,
    output reg         speed_neg_done
);

    localparam ST_DETECT     = 6'h00;
    localparam ST_POLLING    = 6'h01;
    localparam ST_CONFIG     = 6'h02;
    localparam ST_RECOVERY   = 6'h03;
    localparam ST_L0         = 6'h04;
    localparam ST_L0S        = 6'h05;
    localparam ST_L1         = 6'h06;
    localparam ST_L2         = 6'h07;
    localparam ST_HOT_RESET  = 6'h08;
    localparam ST_LOOPBACK   = 6'h09;
    localparam ST_DISABLED   = 6'h0A;

    localparam GEN1_BIT = 0;
    localparam GEN2_BIT = 1;
    localparam GEN3_BIT = 2;
    localparam GEN4_BIT = 3;
    localparam GEN5_BIT = 4;
    localparam GEN6_BIT = 5;

    localparam SPD_GEN1 = 4'h1;
    localparam SPD_GEN2 = 4'h2;
    localparam SPD_GEN3 = 4'h3;
    localparam SPD_GEN4 = 4'h4;
    localparam SPD_GEN5 = 4'h5;
    localparam SPD_GEN6 = 4'h6;

    wire [7:0] common_cap;
    reg  [3:0] neg_speed;
    reg        neg_done_reg;
    reg        change_en_reg;

    assign common_cap = ts1_speed_cap & ts2_speed_cap & local_speed_cap;

    always @(*) begin
        if      (common_cap[GEN6_BIT]) neg_speed = SPD_GEN6;
        else if (common_cap[GEN5_BIT]) neg_speed = SPD_GEN5;
        else if (common_cap[GEN4_BIT]) neg_speed = SPD_GEN4;
        else if (common_cap[GEN3_BIT]) neg_speed = SPD_GEN3;
        else if (common_cap[GEN2_BIT]) neg_speed = SPD_GEN2;
        else                            neg_speed = SPD_GEN1;
    end

    always @(*) begin
        case (neg_speed)
            SPD_GEN1: neg_done_reg = ts1_speed_cap[GEN1_BIT] & ts2_speed_cap[GEN1_BIT];
            SPD_GEN2: neg_done_reg = ts1_speed_cap[GEN2_BIT] & ts2_speed_cap[GEN2_BIT];
            SPD_GEN3: neg_done_reg = ts1_speed_cap[GEN3_BIT] & ts2_speed_cap[GEN3_BIT];
            SPD_GEN4: neg_done_reg = ts1_speed_cap[GEN4_BIT] & ts2_speed_cap[GEN4_BIT];
            SPD_GEN5: neg_done_reg = ts1_speed_cap[GEN5_BIT] & ts2_speed_cap[GEN5_BIT];
            SPD_GEN6: neg_done_reg = ts1_speed_cap[GEN6_BIT] & ts2_speed_cap[GEN6_BIT];
            default:  neg_done_reg = 1'b0;
        endcase
    end

    always @(*) begin
        change_en_reg = speed_change_req &&
                        (ltssm_state == ST_RECOVERY) &&
                        neg_done_reg;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_speed    <= SPD_GEN1;
            speed_change_en <= 1'b0;
            adv_speed_cap   <= 8'h00;
            speed_neg_done  <= 1'b0;
        end else begin

            adv_speed_cap <= local_speed_cap;

            if (ltssm_state == ST_RECOVERY || ltssm_state == ST_CONFIG) begin
                target_speed    <= neg_speed;
                speed_change_en <= change_en_reg;
                speed_neg_done  <= neg_done_reg;
            end else begin
                speed_change_en <= 1'b0;
                speed_neg_done  <= 1'b0;

            end
        end
    end

endmodule
