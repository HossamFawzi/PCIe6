
module lane_pol (

    input  wire         clk,
    input  wire         rst_n,

    input  wire [255:0] rx_data,
    input  wire [15:0]  polarity_det,

    output wire [255:0] rx_data_pol,
    output reg  [15:0]  polarity_inv
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        polarity_inv <= 16'h0000;
    else
        polarity_inv <= polarity_inv | polarity_det;
end

genvar n;
generate
    for (n = 0; n < 16; n = n + 1) begin : gen_polarity_invert
        assign rx_data_pol[16*n +: 16] =
            polarity_inv[n] ? ~rx_data[16*n +: 16]
                            :  rx_data[16*n +: 16];
    end
endgenerate

endmodule
