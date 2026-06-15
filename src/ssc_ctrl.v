// ============================================================
// Module 51 : Spread Spectrum Clock Controller (SSC_CTRL)
// PCIe Gen6 Physical Layer
// Controls spread-spectrum clocking modulation.
// Required for EMI compliance. Down-spread or center-spread.
// ============================================================
module ssc_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        ssc_en,             // Enable SSC
    input  wire [1:0]  ssc_profile,        // 00=off, 01=down-spread, 10=center-spread
    input  wire        ssc_ref_clk,        // Reference clock input

    // Outputs
    output reg  [7:0]  ssc_mod_req,        // Modulation request value to PLL
    output reg         ssc_active,         // SSC is active
    output reg         ssc_center_spread,  // Center spread mode active
    output reg         ssc_down_spread     // Down spread mode active
);

// SSC parameters
// Down-spread: frequency modulates from nominal DOWN to -0.5%
// Center-spread: frequency modulates ±0.25%

localparam SSC_OFF    = 2'd0;
localparam SSC_DOWN   = 2'd1;
localparam SSC_CENTER = 2'd2;

// Modulation counter — triangle wave for SSC
reg [7:0]  mod_cnt;
reg        mod_dir;     // 0 = counting up, 1 = counting down

// Modulation period (cycles)
localparam MOD_PERIOD = 8'd100;  // Simplified; real = ~33kHz modulation

// Modulation amplitude
// Down-spread: 0 to -50 steps out of 100 = 0 to -0.5%
// Center:     -25 to +25 steps = ±0.25%

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ssc_mod_req     <= 8'd0;
        ssc_active      <= 1'b0;
        ssc_center_spread <= 1'b0;
        ssc_down_spread <= 1'b0;
        mod_cnt         <= 8'd0;
        mod_dir         <= 1'b0;
    end else begin
        ssc_center_spread <= 1'b0;
        ssc_down_spread   <= 1'b0;
        ssc_active        <= 1'b0;

        if (ssc_en) begin
            case (ssc_profile)
                SSC_OFF: begin
                    ssc_mod_req <= 8'd0;
                    mod_cnt     <= 8'd0;
                    mod_dir     <= 1'b0;
                end

                SSC_DOWN: begin
                    ssc_active      <= 1'b1;
                    ssc_down_spread <= 1'b1;
                    // Triangle wave: 0 to MOD_PERIOD
                    if (!mod_dir) begin
                        if (mod_cnt < MOD_PERIOD)
                            mod_cnt <= mod_cnt + 8'd1;
                        else
                            mod_dir <= 1'b1;
                    end else begin
                        if (mod_cnt > 8'd0)
                            mod_cnt <= mod_cnt - 8'd1;
                        else
                            mod_dir <= 1'b0;
                    end
                    ssc_mod_req <= mod_cnt;  // 0 = nominal, max = -0.5%
                end

                SSC_CENTER: begin
                    ssc_active        <= 1'b1;
                    ssc_center_spread <= 1'b1;
                    // Triangle wave: 0 to MOD_PERIOD, centered at half
                    if (!mod_dir) begin
                        if (mod_cnt < MOD_PERIOD)
                            mod_cnt <= mod_cnt + 8'd1;
                        else
                            mod_dir <= 1'b1;
                    end else begin
                        if (mod_cnt > 8'd0)
                            mod_cnt <= mod_cnt - 8'd1;
                        else
                            mod_dir <= 1'b0;
                    end
                    // Output signed-like: subtract half period to center
                    ssc_mod_req <= mod_cnt - (MOD_PERIOD >> 1);
                end

                default: begin
                    ssc_mod_req <= 8'd0;
                end
            endcase
        end else begin
            ssc_mod_req <= 8'd0;
            mod_cnt     <= 8'd0;
            mod_dir     <= 1'b0;
        end
    end
end

endmodule
