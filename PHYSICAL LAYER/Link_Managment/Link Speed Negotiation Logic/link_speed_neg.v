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

    // -----------------------------------------------------------------------
    // LTSSM state encoding
    // -----------------------------------------------------------------------
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

    // -----------------------------------------------------------------------
    // Speed capability bit positions (PCIe Data Rate Identifier)
    // -----------------------------------------------------------------------
    localparam GEN1_BIT = 0;   // 2.5  GT/s
    localparam GEN2_BIT = 1;   // 5.0  GT/s
    localparam GEN3_BIT = 2;   // 8.0  GT/s
    localparam GEN4_BIT = 3;   // 16.0 GT/s
    localparam GEN5_BIT = 4;   // 32.0 GT/s
    localparam GEN6_BIT = 5;   // 64.0 GT/s  (PCIe 6.0)

    // -----------------------------------------------------------------------
    // Target speed encoding
    // -----------------------------------------------------------------------
    localparam SPD_GEN1 = 4'h1;
    localparam SPD_GEN2 = 4'h2;
    localparam SPD_GEN3 = 4'h3;
    localparam SPD_GEN4 = 4'h4;
    localparam SPD_GEN5 = 4'h5;
    localparam SPD_GEN6 = 4'h6;

    // -----------------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------------
    wire [7:0] common_cap;
    reg  [3:0] neg_speed;
    reg        neg_done_reg;
    reg        change_en_reg;

    // Common capabilities: intersection of all three participants
    assign common_cap = ts1_speed_cap & ts2_speed_cap & local_speed_cap;

    // -----------------------------------------------------------------------
    // Priority encoder: pick highest supported common speed
    // -----------------------------------------------------------------------
    always @(*) begin
        if      (common_cap[GEN6_BIT]) neg_speed = SPD_GEN6;
        else if (common_cap[GEN5_BIT]) neg_speed = SPD_GEN5;
        else if (common_cap[GEN4_BIT]) neg_speed = SPD_GEN4;
        else if (common_cap[GEN3_BIT]) neg_speed = SPD_GEN3;
        else if (common_cap[GEN2_BIT]) neg_speed = SPD_GEN2;
        else                            neg_speed = SPD_GEN1;
    end

    // -----------------------------------------------------------------------
    // Negotiation done: TS1 and TS2 both advertise the resolved speed bit,
    // AND we are in the Recovery or Configuration state.
    // -----------------------------------------------------------------------
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

    // Speed change is enabled when: in Recovery, change requested, and
    // negotiation resolved a valid target.
    always @(*) begin
        change_en_reg = speed_change_req &&
                        (ltssm_state == ST_RECOVERY) &&
                        neg_done_reg;
    end

    // -----------------------------------------------------------------------
    // Registered outputs
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_speed    <= SPD_GEN1;
            speed_change_en <= 1'b0;
            adv_speed_cap   <= 8'h00;
            speed_neg_done  <= 1'b0;
        end else begin
            // Always advertise local capability in TS1/TS2
            adv_speed_cap <= local_speed_cap;

            // Only update target and done status in Config or Recovery
            if (ltssm_state == ST_RECOVERY || ltssm_state == ST_CONFIG) begin
                target_speed    <= neg_speed;
                speed_change_en <= change_en_reg;
                speed_neg_done  <= neg_done_reg;
            end else begin
                speed_change_en <= 1'b0;
                speed_neg_done  <= 1'b0;
                // Hold last negotiated target_speed
            end
        end
    end

endmodule
