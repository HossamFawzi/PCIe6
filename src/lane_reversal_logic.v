
module lane_rev (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  ts1_lane_num,
    input  wire [7:0]  local_lane_id,
    input  wire        reversal_det,
    output reg  [3:0]  lane_map,
    output reg         reversal_active
);

localparam [7:0] MAX_LANE = 8'd15;

wire [7:0] mirror_lane        = MAX_LANE - local_lane_id;
wire       reversal_indicated = reversal_det |
                                (ts1_lane_num == mirror_lane &&
                                 ts1_lane_num != local_lane_id);

reg reversed_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reversed_r      <= 1'b0;
        lane_map        <= 4'd0;
        reversal_active <= 1'b0;
    end else begin

        reversal_active <= reversed_r | reversal_indicated;

        if (reversal_indicated && !reversed_r) begin

            reversed_r <= 1'b1;
            lane_map   <= (MAX_LANE - local_lane_id) & 8'hF;
        end else if (!reversed_r && !reversal_indicated) begin

            if (local_lane_id != 8'd0)
                lane_map <= local_lane_id[3:0];
        end

    end
end

endmodule
