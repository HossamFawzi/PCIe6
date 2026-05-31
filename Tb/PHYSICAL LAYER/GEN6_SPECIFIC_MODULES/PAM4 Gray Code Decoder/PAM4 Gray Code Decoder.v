
module pam4_gray_code_decoder (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [127:0] pam4_symbols_in,
    input  wire         pam4_valid,
    input  wire         pam4_en,

    output reg  [255:0] data_out,
    output reg          data_valid,
    output reg          decode_err
);

    localparam NUM_SYMBOLS = 64;

    reg [127:0] decoded_128;
    reg         any_err;

    integer     dec_idx;
    reg [1:0]   gray_sym;
    reg [1:0]   bin_sym;
    reg         sym_err;

    always @(*) begin
        decoded_128 = 128'b0;
        any_err     = 1'b0;

        for (dec_idx = 0; dec_idx < NUM_SYMBOLS; dec_idx = dec_idx + 1) begin
            gray_sym = pam4_symbols_in[dec_idx*2 +: 2];

            case (gray_sym)
                2'b00: begin bin_sym = 2'b00; sym_err = 1'b0; end
                2'b01: begin bin_sym = 2'b01; sym_err = 1'b0; end
                2'b11: begin bin_sym = 2'b10; sym_err = 1'b0; end
                2'b10: begin bin_sym = 2'b11; sym_err = 1'b0; end

                default: begin bin_sym = 2'b00; sym_err = 1'b1; end
            endcase

            decoded_128[dec_idx*2 +: 2] = bin_sym;
            any_err = any_err | sym_err;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            data_out   <= 256'b0;
            data_valid <= 1'b0;
            decode_err <= 1'b0;
        end else begin
            data_valid <= pam4_valid;

            if (pam4_valid) begin
                if (pam4_en) begin

                    data_out   <= {128'b0, decoded_128};
                    decode_err <= any_err;
                end else begin

                    data_out   <= {128'b0, pam4_symbols_in};
                    decode_err <= 1'b0;
                end
            end else begin
                data_out   <= 256'b0;
                decode_err <= 1'b0;
            end
        end
    end

endmodule
