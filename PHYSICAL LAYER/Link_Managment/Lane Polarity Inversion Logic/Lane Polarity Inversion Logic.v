// =============================================================================
// Module  : lane_pol  ?  Lane Polarity Inversion Logic
// Standard: PCIe All Generations (tag LANE_POL)
// Source  : pcie_gen6_complete_all_layers_v2.html  (PHY Layer, link group)
//
// Description:
//   Corrects per-lane differential-pair P/N swap (polarity inversion) on the
//   receive datapath.  A swapped pair appears as a bitwise complement of the
//   intended symbol.
//
//   The module maintains a 16-bit polarity_inv register, one bit per lane.
//   When polarity_inv[n] = 1, lane n's 16-bit slice of rx_data is inverted.
//
//   The polarity_det[15:0] input is a one-time indication (edge) from the
//   comma/sync-header detector that a given lane needs inversion.  Once set,
//   the correction is held until reset.
//
// Data path organisation:
//   rx_data[255:0] carries 16 lanes × 16 bits each.
//   Lane n occupies rx_data[16*n +: 16].
//
// Interface (verbatim from HTML):
//   Inputs : rx_data[255:0], polarity_det[15:0], clk, rst_n
//   Outputs: rx_data_pol[255:0], polarity_inv[15:0]
// =============================================================================

module lane_pol (
    // ?? Clock / Reset ??????????????????????????????????????????????????????
    input  wire         clk,
    input  wire         rst_n,

    // ?? Inputs ?????????????????????????????????????????????????????????????
    input  wire [255:0] rx_data,         // Raw RX data, 16 lanes × 16 bits
    input  wire [15:0]  polarity_det,    // Per-lane polarity error detected

    // ?? Outputs ????????????????????????????????????????????????????????????
    output wire [255:0] rx_data_pol,     // Polarity-corrected RX data
    output reg  [15:0]  polarity_inv     // Sticky inversion mask (per lane)
);

// =============================================================================
// polarity_inv register
//   Bits are set by polarity_det and cleared only by reset.
//   This implements a write-once (sticky) latch per lane.
// =============================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        polarity_inv <= 16'h0000;
    else
        polarity_inv <= polarity_inv | polarity_det;  // Bits only set, never cleared
end

// =============================================================================
// Datapath: per-lane conditional inversion
//   For each of the 16 lanes (n = 0..15):
//     rx_data_pol[16*n +: 16] = polarity_inv[n] ? ~rx_data[16*n +: 16]
//                                                :  rx_data[16*n +: 16]
//
//   Implemented as a generate loop for clarity and scalability.
// =============================================================================
genvar n;
generate
    for (n = 0; n < 16; n = n + 1) begin : gen_polarity_invert
        assign rx_data_pol[16*n +: 16] =
            polarity_inv[n] ? ~rx_data[16*n +: 16]
                            :  rx_data[16*n +: 16];
    end
endgenerate

endmodule
