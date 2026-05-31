
module ts_det (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [255:0] rx_data,
    input  wire         rx_valid,
    input  wire         block_lock,

    output reg          ts1_detected,
    output reg          ts2_detected,
    output reg  [7:0]   ts1_link_num,
    output reg  [7:0]   ts1_lane_num,
    output reg  [7:0]   ts2_speed_cap,
    output reg          ts_decode_err
);

localparam [7:0] COM_SYMBOL = 8'hBC;
localparam [7:0] TS1_ID     = 8'h4A;
localparam [7:0] TS2_ID     = 8'h45;

wire [7:0] sym0  = rx_data[ 7:  0];
wire [7:0] sym1  = rx_data[15:  8];
wire [7:0] sym2  = rx_data[23: 16];
wire [7:0] sym4  = rx_data[39: 32];
wire [7:0] sym6  = rx_data[55: 48];

wire is_com      = (sym0 == COM_SYMBOL);
wire is_ts1_id   = (sym6 == TS1_ID);
wire is_ts2_id   = (sym6 == TS2_ID);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ts1_detected  <= 1'b0;
        ts2_detected  <= 1'b0;
        ts1_link_num  <= 8'h00;
        ts1_lane_num  <= 8'h00;
        ts2_speed_cap <= 8'h00;
        ts_decode_err <= 1'b0;
    end else begin

        ts1_detected  <= 1'b0;
        ts2_detected  <= 1'b0;
        ts_decode_err <= 1'b0;

        if (rx_valid && block_lock) begin
            if (is_com) begin
                if (is_ts1_id) begin

                    ts1_detected <= 1'b1;
                    ts1_link_num <= sym1;
                    ts1_lane_num <= sym2;
                end else if (is_ts2_id) begin

                    ts2_detected  <= 1'b1;
                    ts2_speed_cap <= sym4;
                end else begin

                    ts_decode_err <= 1'b1;
                end
            end

        end
    end
end

endmodule
