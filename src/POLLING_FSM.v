
`timescale 1ns / 1ps

module polling_fsm #(
    parameter POLL_ACTIVE_TIMEOUT  = 6_000_000,
    parameter POLL_CONFIG_TIMEOUT  = 12_000_000,
    parameter TS2_REQUIRED_COUNT   = 8,
    parameter TS1_TX_COUNT         = 1024
) (

    input  wire        clk,
    input  wire        rst_n,

    input  wire        polling_req,
    input  wire [15:0] lanes_detected,

    input  wire        rx_valid,
    input  wire        rx_datak,
    input  wire [31:0] rx_data,
    input  wire        rx_elec_idle,

    input  wire        ts1_det_in,
    input  wire        ts2_det_in,

    input  wire        compliance_req,

    output reg         tx_elec_idle,
    output reg         send_ts1,
    output reg         send_ts2,
    output reg         enter_compliance,
    output reg         rx_polarity,

    output reg         polling_done,
    output reg         polling_success,
    output reg         polling_timeout
);

    localparam [2:0]
        ST_IDLE             = 3'd0,
        ST_POLLING_ACTIVE   = 3'd1,
        ST_POLARITY_CHECK   = 3'd2,
        ST_COMPLIANCE       = 3'd3,
        ST_POLLING_CONFIG   = 3'd4,
        ST_DONE             = 3'd5,
        ST_TIMEOUT          = 3'd6;

    localparam [7:0] K28_5 = 8'hBC;
    localparam [7:0] TS1_IDENT = 8'h4A;
    localparam [7:0] TS2_IDENT = 8'hB5;

    wire rx_com_det  = rx_valid && rx_datak && (rx_data[7:0] == K28_5);
    wire rx_ts1_raw  = ts1_det_in;
    wire rx_ts2_raw  = ts2_det_in;

    localparam [7:0] K28_5_INV = 8'h43;
    wire rx_inv_ts1  = rx_valid && rx_datak && (rx_data[7:0] == K28_5_INV);

    reg [2:0]  state,       next_state;

    reg [26:0] timer;
    wire       active_timeout = (timer == POLL_ACTIVE_TIMEOUT[26:0] - 1);
    wire       config_timeout = (timer == POLL_CONFIG_TIMEOUT[26:0] - 1);

    reg [19:0] ts1_tx_cnt;
    wire       ts1_tx_done = (ts1_tx_cnt >= TS1_TX_COUNT[19:0]);

    reg [3:0]  ts2_rx_cnt;
    wire       ts2_rx_done = (ts2_rx_cnt >= TS2_REQUIRED_COUNT[3:0]);

    reg [3:0]  ts2_tx_cnt;
    wire       ts2_tx_done = (ts2_tx_cnt >= TS2_REQUIRED_COUNT[3:0]);

    reg        inv_detected;

    reg        bit_lock;
    reg        symbol_lock;

    reg [4:0]  lane_count;
    integer    lc_i;
    always @(*) begin
        lane_count = 5'd0;
        for (lc_i = 0; lc_i < 16; lc_i = lc_i + 1)
            lane_count = lane_count + {4'd0, lanes_detected[lc_i]};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            timer <= 27'd0;
        end else begin
            case (state)
                ST_POLLING_ACTIVE,
                ST_POLARITY_CHECK,
                ST_POLLING_CONFIG : timer <= timer + 27'd1;
                default           : timer <= 27'd0;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ts1_tx_cnt <= 20'd0;
        end else begin
            if ((state == ST_POLLING_ACTIVE || state == ST_POLARITY_CHECK) && send_ts1)
                ts1_tx_cnt <= ts1_tx_cnt + 20'd1;
            else if (state != ST_POLLING_ACTIVE && state != ST_POLARITY_CHECK)
                ts1_tx_cnt <= 20'd0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ts2_rx_cnt <= 4'd0;
        end else begin
            if (state == ST_POLLING_CONFIG) begin
                if (rx_ts2_raw)
                    ts2_rx_cnt <= ts2_rx_cnt + 4'd1;
                else if (rx_valid && !rx_ts2_raw)
                    ts2_rx_cnt <= 4'd0;
            end else begin
                ts2_rx_cnt <= 4'd0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ts2_tx_cnt <= 4'd0;
        end else begin
            if (state == ST_POLLING_CONFIG && ts2_rx_done && send_ts2)
                ts2_tx_cnt <= ts2_tx_cnt + 4'd1;
            else if (state != ST_POLLING_CONFIG)
                ts2_tx_cnt <= 4'd0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            inv_detected <= 1'b0;
        end else begin
            if (state == ST_POLLING_ACTIVE && rx_inv_ts1)
                inv_detected <= 1'b1;
            else if (state == ST_IDLE)
                inv_detected <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            bit_lock    <= 1'b0;
            symbol_lock <= 1'b0;
        end else begin
            if (state == ST_POLLING_ACTIVE || state == ST_POLARITY_CHECK) begin
                if (rx_com_det || rx_inv_ts1)
                    bit_lock <= 1'b1;
                if (rx_ts1_raw && bit_lock)
                    symbol_lock <= 1'b1;
            end else if (state == ST_IDLE) begin
                bit_lock    <= 1'b0;
                symbol_lock <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;

        case (state)

            ST_IDLE: begin
                if (polling_req && (lanes_detected != 16'd0))
                    next_state = ST_POLLING_ACTIVE;
            end

            ST_POLLING_ACTIVE: begin
                if (active_timeout)
                    next_state = ST_TIMEOUT;
                else if (compliance_req)
                    next_state = ST_COMPLIANCE;
                else if (rx_inv_ts1 && !inv_detected)
                    next_state = ST_POLARITY_CHECK;
                else if (symbol_lock && ts1_tx_done)
                    next_state = ST_POLLING_CONFIG;
            end

            ST_POLARITY_CHECK: begin
                if (active_timeout)
                    next_state = ST_TIMEOUT;
                else if (symbol_lock && ts1_tx_done)
                    next_state = ST_POLLING_CONFIG;
            end

            ST_COMPLIANCE: begin
                if (!compliance_req)
                    next_state = ST_POLLING_ACTIVE;
            end

            ST_POLLING_CONFIG: begin
                if (config_timeout)
                    next_state = ST_TIMEOUT;
                else if (ts2_rx_done && ts2_tx_done)
                    next_state = ST_DONE;
            end

            ST_DONE: begin
                next_state = ST_IDLE;
            end

            ST_TIMEOUT: begin
                next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_elec_idle    <= 1'b1;
            send_ts1        <= 1'b0;
            send_ts2        <= 1'b0;
            enter_compliance<= 1'b0;
            rx_polarity     <= 1'b0;
            polling_done    <= 1'b0;
            polling_success <= 1'b0;
            polling_timeout <= 1'b0;
        end else begin

            send_ts1        <= 1'b0;
            send_ts2        <= 1'b0;
            polling_done    <= 1'b0;
            polling_success <= 1'b0;
            polling_timeout <= 1'b0;
            enter_compliance<= 1'b0;

            case (state)
                ST_IDLE: begin
                    tx_elec_idle <= 1'b1;
                    rx_polarity  <= 1'b0;
                end

                ST_POLLING_ACTIVE: begin
                    tx_elec_idle <= 1'b0;
                    send_ts1     <= 1'b1;
                end

                ST_POLARITY_CHECK: begin
                    tx_elec_idle <= 1'b0;
                    send_ts1     <= 1'b1;
                    rx_polarity  <= 1'b1;
                end

                ST_COMPLIANCE: begin
                    tx_elec_idle    <= 1'b0;
                    enter_compliance<= 1'b1;
                end

                ST_POLLING_CONFIG: begin
                    tx_elec_idle <= 1'b0;
                    if (!ts2_rx_done)
                        send_ts1 <= 1'b1;
                    else
                        send_ts2 <= 1'b1;
                end

                ST_DONE: begin
                    tx_elec_idle    <= 1'b1;
                    polling_done    <= 1'b1;
                    polling_success <= 1'b1;
                end

                ST_TIMEOUT: begin
                    tx_elec_idle    <= 1'b1;
                    polling_done    <= 1'b1;
                    polling_timeout <= 1'b1;
                end

                default: begin
                    tx_elec_idle <= 1'b1;
                end
            endcase
        end
    end

endmodule
