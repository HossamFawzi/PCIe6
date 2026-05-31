
module lane_rev (

    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  ts1_lane_num,
    input  wire [7:0]  local_lane_id,
    input  wire        reversal_det,

    output reg  [3:0]  lane_map,
    output reg         reversal_active
);

reg        reversed_r;

localparam [7:0] MAX_LANE = 8'd15;

wire [7:0] mirror_lane = MAX_LANE - local_lane_id;

wire reversal_indicated = reversal_det |
                          (ts1_lane_num == mirror_lane &&
                           ts1_lane_num != local_lane_id);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        reversed_r <= 1'b0;
    else if (reversal_indicated)
        reversed_r <= 1'b1;

end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        lane_map        <= 4'd0;
        reversal_active <= 1'b0;
    end else begin
        reversal_active <= reversed_r;
        if (reversed_r)
            lane_map <= (MAX_LANE - local_lane_id) & 8'hF;
        else
            lane_map <= local_lane_id[3:0];
    end
end

endmodule
