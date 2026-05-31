
module encoder_128b130b (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [127:0] data_in,
    input  wire         is_ordered_set,
    input  wire         data_valid,

    output reg  [129:0] data_out,
    output reg          data_out_valid,
    output reg          enc_err
);

localparam SH_DATA        = 2'b01;
localparam SH_ORDERED_SET = 2'b10;

reg [31:0] block_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out       <= 130'h0;
        data_out_valid <= 1'b0;
        enc_err        <= 1'b0;
        block_cnt      <= 32'h0;
    end else begin
        data_out_valid <= 1'b0;
        enc_err        <= 1'b0;

        if (data_valid) begin

            if (!is_ordered_set) begin

                data_out       <= {SH_DATA, data_in};
                data_out_valid <= 1'b1;
            end else begin

                data_out       <= {SH_ORDERED_SET, data_in};
                data_out_valid <= 1'b1;
            end
            block_cnt <= block_cnt + 1'b1;
        end
    end
end

endmodule
