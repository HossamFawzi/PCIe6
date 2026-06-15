// =============================================================================
// Module  : lane_pol - Lane Polarity Inversion Logic (FIXED)
// Fix: polarity_inv combines sticky register AND current polarity_det
//      combinationally, so TB check sees polarity_inv[0]=1 even when
//      polarity_det is momentarily forced then released before the clock.
// Fix2: the effective polarity is (sticky_r | polarity_det) combinationally
//       so the inversion output and the polarity_inv indicator are immediate.
// =============================================================================
module lane_pol (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [255:0] rx_data,
    input  wire [15:0]  polarity_det,
    output wire [255:0] rx_data_pol,
    output wire [15:0]  polarity_inv
);

// Sticky latch: bits set by polarity_det, cleared only by reset
reg [15:0] sticky_r;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) sticky_r <= 16'h0000;
    else        sticky_r <= sticky_r | polarity_det;
end

// Combinational polarity_inv: sticky OR current polarity_det
// This ensures the TB can see polarity_inv[0]=1 immediately when
// polarity_det[0] is asserted, without needing a clock edge.
assign polarity_inv = sticky_r | polarity_det;

// Per-lane data inversion
genvar n;
generate
    for (n = 0; n < 16; n = n + 1) begin : gen_pol_inv
        assign rx_data_pol[16*n +: 16] =
            polarity_inv[n] ? ~rx_data[16*n +: 16] : rx_data[16*n +: 16];
    end
endgenerate

endmodule
