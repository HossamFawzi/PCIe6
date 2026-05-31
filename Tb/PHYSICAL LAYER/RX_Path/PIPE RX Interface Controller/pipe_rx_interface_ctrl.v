
module pipe_rx_interface_ctrl (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [255:0]  pipe_rxd,
    input  wire [31:0]   pipe_rxdatak,
    input  wire          pipe_rx_valid,
    input  wire [2:0]    pipe_rx_status,
    input  wire          pipe_rx_elec_idle,
    input  wire          pipe_clk,
    input  wire          pipe_phystatus,

    input  wire [1:0]    power_down_req,
    input  wire [3:0]    pipe_rate_req,
    input  wire          tx_detect_rx_req,
    input  wire          tx_elec_idle_req,
    input  wire          tx_compliance_req,
    input  wire          pclk_change_req,
    input  wire [1:0]    pipe_width_req,

    output reg  [1:0]    pipe_powerdown,
    output reg  [3:0]    pipe_rate,
    output reg           pipe_txdetectrx,
    output reg           pipe_txelecidle,
    output reg           pipe_txcompliance,
    output reg           pipe_pclkchangeack,
    output reg  [1:0]    pipe_width,

    output reg  [255:0]  rx_data,
    output reg  [31:0]   rx_datak,
    output reg           rx_valid,
    output reg           rx_elec_idle,
    output reg  [2:0]    rx_status,
    output reg           phystatus_sync,

    output reg           pipe_up,
    output reg           rate_change_busy
);

reg pipe_phystatus_s1, pipe_phystatus_s2;
reg pipe_rxvalid_s1,   pipe_rxvalid_s2;
reg pipe_rxei_s1,      pipe_rxei_s2;
reg [2:0] pipe_rxst_s1, pipe_rxst_s2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_phystatus_s1 <= 1'b0; pipe_phystatus_s2 <= 1'b0;
        pipe_rxvalid_s1   <= 1'b0; pipe_rxvalid_s2   <= 1'b0;
        pipe_rxei_s1      <= 1'b1; pipe_rxei_s2      <= 1'b1;
        pipe_rxst_s1      <= 3'h0; pipe_rxst_s2      <= 3'h0;
    end else begin
        pipe_phystatus_s1 <= pipe_phystatus;    pipe_phystatus_s2 <= pipe_phystatus_s1;
        pipe_rxvalid_s1   <= pipe_rx_valid;     pipe_rxvalid_s2   <= pipe_rxvalid_s1;
        pipe_rxei_s1      <= pipe_rx_elec_idle; pipe_rxei_s2      <= pipe_rxei_s1;
        pipe_rxst_s1      <= pipe_rx_status;    pipe_rxst_s2      <= pipe_rxst_s1;
    end
end

reg [255:0] rxd_latch;
reg [31:0]  rxdk_latch;
reg         rxv_latch;

always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        rxd_latch  <= {256{1'b0}};
        rxdk_latch <= {32{1'b0}};
        rxv_latch  <= 1'b0;
    end else begin
        rxd_latch  <= pipe_rxd;
        rxdk_latch <= pipe_rxdatak;
        rxv_latch  <= pipe_rx_valid;
    end
end

localparam RC_IDLE  = 2'd0;
localparam RC_WAIT  = 2'd1;
localparam RC_ACK   = 2'd2;
localparam RC_DONE  = 2'd3;

reg [1:0] rc_state;
reg [7:0] rc_timer;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_powerdown    <= 2'h0;
        pipe_rate         <= 4'h0;
        pipe_txdetectrx   <= 1'b0;
        pipe_txelecidle   <= 1'b0;
        pipe_txcompliance <= 1'b0;
        pipe_pclkchangeack<= 1'b0;
        pipe_width        <= 2'h2;
        rx_data           <= {256{1'b0}};
        rx_datak          <= {32{1'b0}};
        rx_valid          <= 1'b0;
        rx_elec_idle      <= 1'b1;
        rx_status         <= 3'h0;
        phystatus_sync    <= 1'b0;
        pipe_up           <= 1'b0;
        rate_change_busy  <= 1'b0;
        rc_state          <= RC_IDLE;
        rc_timer          <= 8'h0;
    end else begin

        pipe_powerdown    <= power_down_req;
        pipe_txdetectrx   <= tx_detect_rx_req;
        pipe_txelecidle   <= tx_elec_idle_req;
        pipe_txcompliance <= tx_compliance_req;
        pipe_width        <= pipe_width_req;

        rx_data      <= rxd_latch;
        rx_datak     <= rxdk_latch;
        rx_valid     <= pipe_rxvalid_s2;
        rx_elec_idle <= pipe_rxei_s2;
        rx_status    <= pipe_rxst_s2;
        phystatus_sync <= pipe_phystatus_s2;

        pipe_up <= pipe_rxvalid_s2 && !pipe_rxei_s2;

        case (rc_state)
            RC_IDLE: begin
                pipe_pclkchangeack <= 1'b0;
                rate_change_busy   <= 1'b0;
                if (pclk_change_req) begin
                    pipe_rate       <= pipe_rate_req;
                    rate_change_busy<= 1'b1;
                    rc_timer        <= 8'hFF;
                    rc_state        <= RC_WAIT;
                end else begin
                    pipe_rate <= pipe_rate_req;
                end
            end
            RC_WAIT: begin

                if (pipe_phystatus_s2) begin
                    pipe_pclkchangeack <= 1'b1;
                    rc_state           <= RC_ACK;
                end else if (rc_timer == 8'h0) begin

                    rc_state <= RC_IDLE;
                end else begin
                    rc_timer <= rc_timer - 1'b1;
                end
            end
            RC_ACK: begin

                if (!pipe_phystatus_s2) begin
                    pipe_pclkchangeack <= 1'b0;
                    rc_state           <= RC_DONE;
                end
            end
            RC_DONE: begin
                rate_change_busy <= 1'b0;
                rc_state         <= RC_IDLE;
            end
            default: rc_state <= RC_IDLE;
        endcase
    end
end

endmodule
