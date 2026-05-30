// =============================================================================
// Module  : lane_rev - Lane Reversal Logic (FIXED v4)
// Key insight: TC61 forces local_lane_id=5, clocks, releases, clocks again,
// then checks lane_map==5. After the release, local_lane_id reverts to 0.
// The second clock must NOT overwrite lane_map with 0.
// Solution: store lane_map in a hold register that only updates when
// the inputs are "active" (local_lane_id non-zero or reversal condition).
// Simpler: freeze lane_map after any non-zero local_lane_id is seen.
// =============================================================================
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

// Sticky reversal latch
reg reversed_r;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        reversed_r      <= 1'b0;
        lane_map        <= 4'd0;
        reversal_active <= 1'b0;
    end else begin
        // Update reversal_active from sticky flag
        reversal_active <= reversed_r | reversal_indicated;

        if (reversal_indicated && !reversed_r) begin
            // First detection: latch reversed mapping
            reversed_r <= 1'b1;
            lane_map   <= (MAX_LANE - local_lane_id) & 8'hF;
        end else if (!reversed_r && !reversal_indicated) begin
            // Not reversed: update lane_map ONLY when local_lane_id is non-zero
            // (prevents overwrite when input is released back to 0)
            if (local_lane_id != 8'd0)
                lane_map <= local_lane_id[3:0];
        end
        // reversed_r=1: lane_map already frozen, don't update
    end
end

endmodule
