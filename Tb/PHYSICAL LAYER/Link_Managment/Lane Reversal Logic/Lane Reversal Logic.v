// =============================================================================
// Module  : lane_rev  ?  Lane Reversal Logic
// Standard: PCIe All Generations (tag LANE_REV)
// Source  : pcie_gen6_complete_all_layers_v2.html  (PHY Layer, link group)
//
// Description:
//   Detects when the PCIe connector is physically flipped (e.g. M.2 reversed)
//   and remaps logical lane IDs to physical lane IDs accordingly.
//
//   Lane reversal is detected when:
//     reversal_det is asserted  OR
//     ts1_lane_num != local_lane_id  (for a single-lane ordered set check)
//
//   The mapping output lane_map[3:0] encodes the offset to apply:
//     lane_map = (negotiated_width - 1 - local_lane_id) when reversed
//     lane_map = local_lane_id                           when normal
//
//   A 4-bit output supports up to x16 links (indices 0-15).
//
// Interface (verbatim from HTML):
//   Inputs : ts1_lane_num[7:0], local_lane_id[7:0], reversal_det,
//            clk, rst_n
//   Outputs: lane_map[3:0], reversal_active
// =============================================================================

module lane_rev (
    // ?? Clock / Reset ??????????????????????????????????????????????????????
    input  wire        clk,
    input  wire        rst_n,

    // ?? Inputs ?????????????????????????????????????????????????????????????
    input  wire [7:0]  ts1_lane_num,    // Lane number field from received TS1
    input  wire [7:0]  local_lane_id,   // This lane's physical ID (0-15)
    input  wire        reversal_det,    // External reversal indication

    // ?? Outputs ????????????????????????????????????????????????????????????
    output reg  [3:0]  lane_map,        // Remapped logical lane index
    output reg         reversal_active  // 1 = reversal correction in effect
);

// =============================================================================
// Internal registers
// =============================================================================
reg        reversed_r;      // Latched reversal decision

// Maximum logical lane ID for a x16 link (width - 1 = 15)
localparam [7:0] MAX_LANE = 8'd15;

// =============================================================================
// Reversal Detection
//
// Reversal is declared when:
//   (a) The external block asserts reversal_det, OR
//   (b) The TS1 lane number received on this physical lane doesn't match the
//       local_lane_id, but DOES match the mirrored position.
//
// Mirrored position: mirror = MAX_LANE - local_lane_id
// If ts1_lane_num == mirror, the connector is reversed.
// =============================================================================
wire [7:0] mirror_lane = MAX_LANE - local_lane_id;

// Combinational reversal test
wire reversal_indicated = reversal_det |
                          (ts1_lane_num == mirror_lane &&
                           ts1_lane_num != local_lane_id);

// =============================================================================
// Sequential latch ? reversal decision is sticky until reset
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        reversed_r <= 1'b0;
    else if (reversal_indicated)
        reversed_r <= 1'b1;
    // Once reversed, stay reversed for the duration of the link session.
    // A new training sequence (reset) clears the state.
end

// =============================================================================
// Lane map output
//   Normal  : logical_lane = local_lane_id
//   Reversed: logical_lane = MAX_LANE - local_lane_id
// The output is 4 bits (max index = 15).
// =============================================================================
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
