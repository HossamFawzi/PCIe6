
module encoder_8b10b (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire       k_char,
    input  wire       data_valid,

    output reg  [9:0] data_out,
    output reg        data_out_valid,
    output reg        rd_out,
    output reg        enc_err
);

reg rd_reg;

wire [4:0] data_5b = data_in[4:0];
wire [2:0] data_3b = data_in[7:5];

reg [5:0] enc_6b;
reg [3:0] enc_4b;
reg       rd_next_after_6b;
reg       err_6b, err_4b;

function [11:0] encode_5b6b;
    input [4:0] d;
    input       rd;

    begin
        case (d)
            5'h00: encode_5b6b = 12'b100111_011000;
            5'h01: encode_5b6b = 12'b011101_100010;
            5'h02: encode_5b6b = 12'b101101_010010;
            5'h03: encode_5b6b = 12'b110001_110001;
            5'h04: encode_5b6b = 12'b110101_001010;
            5'h05: encode_5b6b = 12'b101001_101001;
            5'h06: encode_5b6b = 12'b011001_011001;
            5'h07: encode_5b6b = 12'b111000_000111;
            5'h08: encode_5b6b = 12'b111001_000110;
            5'h09: encode_5b6b = 12'b100101_100101;
            5'h0A: encode_5b6b = 12'b010101_010101;
            5'h0B: encode_5b6b = 12'b110100_110100;
            5'h0C: encode_5b6b = 12'b001101_001101;
            5'h0D: encode_5b6b = 12'b101100_101100;
            5'h0E: encode_5b6b = 12'b011100_011100;
            5'h0F: encode_5b6b = 12'b010111_101000;
            5'h10: encode_5b6b = 12'b011011_100100;
            5'h11: encode_5b6b = 12'b100011_100011;
            5'h12: encode_5b6b = 12'b010011_010011;
            5'h13: encode_5b6b = 12'b110010_110010;
            5'h14: encode_5b6b = 12'b001011_001011;
            5'h15: encode_5b6b = 12'b101010_101010;
            5'h16: encode_5b6b = 12'b011010_011010;
            5'h17: encode_5b6b = 12'b111010_000101;
            5'h18: encode_5b6b = 12'b110011_001100;
            5'h19: encode_5b6b = 12'b100110_100110;
            5'h1A: encode_5b6b = 12'b010110_010110;
            5'h1B: encode_5b6b = 12'b110110_001001;
            5'h1C: encode_5b6b = 12'b001110_001110;
            5'h1D: encode_5b6b = 12'b101110_010001;
            5'h1E: encode_5b6b = 12'b011110_100001;
            5'h1F: encode_5b6b = 12'b101011_010100;
            default: encode_5b6b = 12'hXXX;
        endcase
    end
endfunction

function [7:0] encode_3b4b;
    input [2:0] d;
    input       rd;
    input       k;

    begin
        if (!k) begin
            case (d)
                3'h0: encode_3b4b = 8'b1011_0100;
                3'h1: encode_3b4b = 8'b1001_1001;
                3'h2: encode_3b4b = 8'b0101_0101;
                3'h3: encode_3b4b = 8'b1100_0011;
                3'h4: encode_3b4b = 8'b1101_0010;
                3'h5: encode_3b4b = 8'b1010_1010;
                3'h6: encode_3b4b = 8'b0110_0110;
                3'h7: encode_3b4b = 8'b0111_1000;
                default: encode_3b4b = 8'hXX;
            endcase
        end else begin

            case (d)
                3'h0: encode_3b4b = 8'b1011_0100;
                3'h1: encode_3b4b = 8'b0110_1001;
                3'h2: encode_3b4b = 8'b1010_0101;
                3'h3: encode_3b4b = 8'b1100_0011;
                3'h4: encode_3b4b = 8'b1101_0010;
                3'h5: encode_3b4b = 8'b0101_1010;
                3'h6: encode_3b4b = 8'b1001_0110;
                3'h7: encode_3b4b = 8'b0001_1110;
                default: encode_3b4b = 8'hXX;
            endcase
        end
    end
endfunction

wire [11:0] tbl_6b = encode_5b6b(data_5b, rd_reg);
wire [7:0]  tbl_4b = encode_3b4b(data_3b, rd_reg, k_char);

wire [5:0] sym_6b = rd_reg ? tbl_6b[5:0] : tbl_6b[11:6];

function rd_after_6b;
    input [5:0] sym;
    reg [2:0] ones;
    begin
        ones = sym[0]+sym[1]+sym[2]+sym[3]+sym[4]+sym[5];
        rd_after_6b = (ones > 3) ? 1'b1 : 1'b0;
    end
endfunction

function rd_after_4b;
    input [3:0] sym;
    reg [2:0] ones;
    begin
        ones = sym[0]+sym[1]+sym[2]+sym[3];
        rd_after_4b = (ones > 2) ? 1'b1 : 1'b0;
    end
endfunction

function is_valid_k;
    input [7:0] d;
    begin
        case (d)
            8'hBC: is_valid_k = 1;
            8'hF7: is_valid_k = 1;
            8'hFB: is_valid_k = 1;
            8'hFD: is_valid_k = 1;
            8'hFE: is_valid_k = 1;
            8'h1C: is_valid_k = 1;
            8'h3C: is_valid_k = 1;
            8'h5C: is_valid_k = 1;
            8'h7C: is_valid_k = 1;
            8'h9C: is_valid_k = 1;
            8'hDC: is_valid_k = 1;
            8'hFC: is_valid_k = 1;
            default: is_valid_k = 0;
        endcase
    end
endfunction

wire [3:0] ones_6b = sym_6b[0]+sym_6b[1]+sym_6b[2]+sym_6b[3]+sym_6b[4]+sym_6b[5];

wire rd_mid = (ones_6b > 3) ? 1'b1 :
              (ones_6b < 3) ? 1'b0 : rd_reg;

wire [7:0]  tbl_4b_mid   = encode_3b4b(data_3b, rd_mid, k_char);
wire [3:0]  sym_4b_final = rd_mid ? tbl_4b_mid[3:0] : tbl_4b_mid[7:4];
wire [2:0]  ones_4b_final = sym_4b_final[0]+sym_4b_final[1]+
                             sym_4b_final[2]+sym_4b_final[3];

wire rd_final = (ones_4b_final > 2) ? 1'b1 :
                (ones_4b_final < 2) ? 1'b0 : rd_mid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out       <= 10'h0;
        data_out_valid <= 1'b0;
        rd_reg         <= 1'b0;
        rd_out         <= 1'b0;
        enc_err        <= 1'b0;
    end else begin
        data_out_valid <= 1'b0;
        enc_err        <= 1'b0;
        if (data_valid) begin
            if (k_char && !is_valid_k(data_in)) begin
                enc_err <= 1'b1;
            end else begin

                data_out       <= {sym_4b_final, sym_6b};
                data_out_valid <= 1'b1;
                rd_reg         <= rd_final;
                rd_out         <= rd_final;
            end
        end
    end
end

endmodule
