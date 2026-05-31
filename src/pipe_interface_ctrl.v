
module pipe_interface_ctrl (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        pipe_phystatus,
    input  wire        pipe_rxvalid,
    input  wire [2:0]  pipe_rxstatus,

    input  wire [5:0]  ltssm_state,
    input  wire [1:0]  power_down_req,

    output reg  [1:0]  pipe_powerdown,
    output reg  [3:0]  pipe_rate,
    output reg         pipe_txdetectrx,
    output reg         pipe_txelecidle,
    output reg         pipe_txcompliance,
    output reg         pipe_pclkchangeack,
    output reg  [1:0]  pipe_width
);

    localparam LTSSM_DETECT_QUIET     = 6'h00;
    localparam LTSSM_DETECT_ACTIVE    = 6'h01;
    localparam LTSSM_POLLING_ACTIVE   = 6'h02;
    localparam LTSSM_POLLING_COMPL    = 6'h03;
    localparam LTSSM_POLLING_CONFIG   = 6'h04;
    localparam LTSSM_CONFIG_LWIDTH    = 6'h05;
    localparam LTSSM_CONFIG_LWIDTH_A  = 6'h06;
    localparam LTSSM_CONFIG_LANE_NUM  = 6'h07;
    localparam LTSSM_CONFIG_LANE_A    = 6'h08;
    localparam LTSSM_CONFIG_COMPLETE  = 6'h09;
    localparam LTSSM_CONFIG_IDLE      = 6'h0A;
    localparam LTSSM_L0               = 6'h10;
    localparam LTSSM_L0S_TX           = 6'h11;
    localparam LTSSM_L0S_RX           = 6'h12;
    localparam LTSSM_L1_ENTRY         = 6'h13;
    localparam LTSSM_L1_IDLE          = 6'h14;
    localparam LTSSM_L2_IDLE          = 6'h15;
    localparam LTSSM_L2_TX_WAKE       = 6'h16;
    localparam LTSSM_RECOVERY_RCVRL0  = 6'h20;
    localparam LTSSM_RECOVERY_RCVRCFG= 6'h21;
    localparam LTSSM_RECOVERY_IDLE    = 6'h22;
    localparam LTSSM_RECOVERY_SPEED   = 6'h23;
    localparam LTSSM_HOT_RESET        = 6'h30;
    localparam LTSSM_DISABLED         = 6'h31;
    localparam LTSSM_LOOPBACK_ENTRY   = 6'h32;
    localparam LTSSM_LOOPBACK_ACTIVE  = 6'h33;
    localparam LTSSM_LOOPBACK_EXIT    = 6'h34;

    localparam PIPE_P0   = 2'b00;
    localparam PIPE_P0S  = 2'b01;
    localparam PIPE_P1   = 2'b10;
    localparam PIPE_P2   = 2'b11;

    localparam RATE_GEN1 = 4'b0001;
    localparam RATE_GEN2 = 4'b0010;
    localparam RATE_GEN3 = 4'b0100;
    localparam RATE_GEN4 = 4'b1000;
    localparam RATE_GEN5 = 4'b1001;
    localparam RATE_GEN6 = 4'b1010;

    localparam WIDTH_8   = 2'b00;
    localparam WIDTH_16  = 2'b01;
    localparam WIDTH_32  = 2'b10;

    localparam RXST_OK         = 3'b000;
    localparam RXST_SKP_ADD    = 3'b001;
    localparam RXST_SKP_REMOVE = 3'b010;
    localparam RXST_DETECT_OK  = 3'b011;
    localparam RXST_DETECT_NOK = 3'b100;
    localparam RXST_EI         = 3'b101;
    localparam RXST_DISPERR    = 3'b110;
    localparam RXST_SYMBERR    = 3'b111;

    reg        phystatus_prev;
    reg        pclk_change_pending;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_powerdown <= PIPE_P0;
        end else begin

            case (ltssm_state)
                LTSSM_L0,
                LTSSM_POLLING_ACTIVE,
                LTSSM_POLLING_CONFIG,
                LTSSM_CONFIG_LWIDTH,
                LTSSM_CONFIG_LWIDTH_A,
                LTSSM_CONFIG_LANE_NUM,
                LTSSM_CONFIG_LANE_A,
                LTSSM_CONFIG_COMPLETE,
                LTSSM_CONFIG_IDLE,
                LTSSM_RECOVERY_RCVRL0,
                LTSSM_RECOVERY_RCVRCFG,
                LTSSM_RECOVERY_IDLE,
                LTSSM_RECOVERY_SPEED   : pipe_powerdown <= PIPE_P0;

                LTSSM_DETECT_QUIET,
                LTSSM_DETECT_ACTIVE    : pipe_powerdown <= PIPE_P0S;

                LTSSM_L0S_TX,
                LTSSM_L0S_RX          : pipe_powerdown <= PIPE_P0S;

                LTSSM_L1_ENTRY,
                LTSSM_L1_IDLE         : pipe_powerdown <= PIPE_P1;

                LTSSM_L2_IDLE,
                LTSSM_L2_TX_WAKE,
                LTSSM_HOT_RESET,
                LTSSM_DISABLED        : pipe_powerdown <= PIPE_P2;

                default               : pipe_powerdown <= power_down_req;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_rate <= RATE_GEN1;
        end else begin

            if (ltssm_state == LTSSM_RECOVERY_SPEED) begin

                pipe_rate <= pipe_rate;
            end

        end
    end

    reg detect_triggered;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_txdetectrx  <= 1'b0;
            detect_triggered <= 1'b0;
        end else begin
            if (ltssm_state == LTSSM_DETECT_ACTIVE && !detect_triggered) begin
                pipe_txdetectrx  <= 1'b1;
                detect_triggered <= 1'b1;
            end else if (ltssm_state != LTSSM_DETECT_ACTIVE) begin
                pipe_txdetectrx  <= 1'b0;
                detect_triggered <= 1'b0;
            end else begin
                pipe_txdetectrx <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_txelecidle <= 1'b1;
        end else begin
            case (ltssm_state)
                LTSSM_L0,
                LTSSM_POLLING_ACTIVE,
                LTSSM_POLLING_COMPL,
                LTSSM_POLLING_CONFIG,
                LTSSM_CONFIG_LWIDTH,
                LTSSM_CONFIG_LWIDTH_A,
                LTSSM_CONFIG_LANE_NUM,
                LTSSM_CONFIG_LANE_A,
                LTSSM_CONFIG_COMPLETE,
                LTSSM_CONFIG_IDLE,
                LTSSM_RECOVERY_RCVRL0,
                LTSSM_RECOVERY_RCVRCFG,
                LTSSM_RECOVERY_IDLE,
                LTSSM_RECOVERY_SPEED,
                LTSSM_LOOPBACK_ACTIVE  : pipe_txelecidle <= 1'b0;

                default                : pipe_txelecidle <= 1'b1;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_txcompliance <= 1'b0;
        end else begin
            pipe_txcompliance <=
                (ltssm_state == LTSSM_POLLING_COMPL) ? 1'b1 : 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            phystatus_prev       <= 1'b0;
            pclk_change_pending  <= 1'b0;
            pipe_pclkchangeack   <= 1'b0;
        end else begin
            phystatus_prev <= pipe_phystatus;

            if (pipe_phystatus && !phystatus_prev &&
                ltssm_state == LTSSM_RECOVERY_SPEED) begin
                pclk_change_pending <= 1'b1;
            end

            if (pclk_change_pending) begin
                pipe_pclkchangeack  <= 1'b1;
                pclk_change_pending <= 1'b0;
            end else begin
                pipe_pclkchangeack  <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_width <= WIDTH_16;
        end else begin
            case (pipe_rate)
                RATE_GEN1,
                RATE_GEN2              : pipe_width <= WIDTH_16;
                RATE_GEN3,
                RATE_GEN4,
                RATE_GEN5,
                RATE_GEN6              : pipe_width <= WIDTH_32;
                default                : pipe_width <= WIDTH_32;
            endcase
        end
    end

endmodule
