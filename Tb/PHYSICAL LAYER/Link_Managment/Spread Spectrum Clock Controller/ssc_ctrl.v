
module ssc_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        ssc_en,
    input  wire [1:0]  ssc_profile,
    input  wire        ssc_ref_clk,

    output reg  [7:0]  ssc_mod_req,
    output reg         ssc_active,
    output reg         ssc_center_spread,
    output reg         ssc_down_spread
);

localparam SSC_OFF    = 2'd0;
localparam SSC_DOWN   = 2'd1;
localparam SSC_CENTER = 2'd2;

reg [7:0]  mod_cnt;
reg        mod_dir;

localparam MOD_PERIOD = 8'd100;

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
                    ssc_mod_req <= mod_cnt;
                end

                SSC_CENTER: begin
                    ssc_active        <= 1'b1;
                    ssc_center_spread <= 1'b1;

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
