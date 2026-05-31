
module beacon_ei_logic (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        beacon_req,
    input  wire        ei_req,
    input  wire        pipe_rx_elec_idle,
    input  wire [2:0]  pm_state,

    output reg         pipe_tx_elec_idle,
    output reg         beacon_detect,
    output reg         ei_detect,
    output reg         wakeup_req
);

    localparam PM_L0   = 3'b000;
    localparam PM_L0S  = 3'b001;
    localparam PM_L1   = 3'b010;
    localparam PM_L2   = 3'b011;
    localparam PM_L3   = 3'b100;

    localparam BEACON_DETECT_THRESHOLD = 16'd500;
    localparam EI_DETECT_THRESHOLD     = 8'd8;

    localparam BCN_IDLE      = 2'b00;
    localparam BCN_ASSERT    = 2'b01;
    localparam BCN_DEASSERT  = 2'b10;
    localparam BCN_DONE      = 2'b11;

    reg [1:0]  bcn_state;
    reg [15:0] bcn_on_cnt;
    reg [15:0] bcn_off_cnt;
    reg [3:0]  bcn_pulse_cnt;

    localparam BCN_ON_CYCLES  = 16'd250;
    localparam BCN_OFF_CYCLES = 16'd250;
    localparam BCN_MIN_PULSES = 4'd4;

    reg [15:0] beacon_cnt;
    reg [7:0]  ei_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            bcn_state     <= BCN_IDLE;
            bcn_on_cnt    <= 16'd0;
            bcn_off_cnt   <= 16'd0;
            bcn_pulse_cnt <= 4'd0;
        end else begin
            case (bcn_state)

                BCN_IDLE : begin
                    bcn_on_cnt    <= 16'd0;
                    bcn_off_cnt   <= 16'd0;
                    bcn_pulse_cnt <= 4'd0;

                    if (beacon_req &&
                        (pm_state == PM_L2 || pm_state == PM_L3)) begin
                        bcn_state <= BCN_ASSERT;
                    end
                end

                BCN_ASSERT : begin
                    if (bcn_on_cnt == BCN_ON_CYCLES - 1) begin
                        bcn_on_cnt    <= 16'd0;
                        bcn_pulse_cnt <= bcn_pulse_cnt + 1'b1;
                        bcn_state     <= BCN_DEASSERT;
                    end else begin
                        bcn_on_cnt <= bcn_on_cnt + 1'b1;
                    end
                end

                BCN_DEASSERT : begin
                    if (bcn_off_cnt == BCN_OFF_CYCLES - 1) begin
                        bcn_off_cnt <= 16'd0;
                        if (bcn_pulse_cnt >= BCN_MIN_PULSES && !beacon_req) begin
                            bcn_state <= BCN_DONE;
                        end else begin
                            bcn_state <= BCN_ASSERT;
                        end
                    end else begin
                        bcn_off_cnt <= bcn_off_cnt + 1'b1;
                    end
                end

                BCN_DONE : begin

                    if (!beacon_req)
                        bcn_state <= BCN_IDLE;
                end

                default : bcn_state <= BCN_IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_tx_elec_idle <= 1'b1;
        end else begin
            if (ei_req) begin

                pipe_tx_elec_idle <= 1'b1;
            end else if (bcn_state == BCN_ASSERT) begin

                pipe_tx_elec_idle <= 1'b0;
            end else begin

                pipe_tx_elec_idle <= 1'b1;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ei_cnt    <= 8'd0;
            ei_detect <= 1'b0;
        end else begin
            if (pipe_rx_elec_idle) begin
                if (ei_cnt < EI_DETECT_THRESHOLD) begin
                    ei_cnt <= ei_cnt + 1'b1;
                end
                ei_detect <= (ei_cnt >= EI_DETECT_THRESHOLD - 1);
            end else begin
                ei_cnt    <= 8'd0;
                ei_detect <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            beacon_cnt    <= 16'd0;
            beacon_detect <= 1'b0;
        end else begin
            if (pm_state == PM_L2 || pm_state == PM_L3) begin

                if (!pipe_rx_elec_idle) begin
                    if (beacon_cnt < BEACON_DETECT_THRESHOLD) begin
                        beacon_cnt <= beacon_cnt + 1'b1;
                    end
                    beacon_detect <=
                        (beacon_cnt >= BEACON_DETECT_THRESHOLD - 1);
                end else begin
                    beacon_cnt    <= 16'd0;
                    beacon_detect <= 1'b0;
                end
            end else begin
                beacon_cnt    <= 16'd0;
                beacon_detect <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wakeup_req <= 1'b0;
        end else begin
            if (beacon_detect) begin

                wakeup_req <= 1'b1;
            end else if (pm_state == PM_L0 || pm_state == PM_L0S) begin

                wakeup_req <= 1'b0;
            end

        end
    end

endmodule
