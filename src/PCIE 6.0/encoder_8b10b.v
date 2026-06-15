// =============================================================================
// Module: 8b/10b Encoder
// PCIe Gen1 / Gen2 Physical Layer
// Description: Encodes 8-bit data to 10-bit symbols using running disparity.
//              Implements full 8b/10b lookup including K-codes (control chars).
//              Supports: K28.5 (comma), K27.7, K29.7, K30.7, K23.7, K28.1,
//                        K28.2, K28.3, K28.4, K28.6, K28.7
// =============================================================================
module encoder_8b10b (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,       // 8-bit input data
    input  wire       k_char,        // 1 = K (control) character
    input  wire       data_valid,

    output reg  [9:0] data_out,      // 10-bit encoded symbol
    output reg        data_out_valid,
    output reg        rd_out,        // Running disparity after this symbol
    output reg        enc_err        // Encoding error (invalid K code)
);

// ---------------------------------------------------------------------------
// Running disparity state register
// RD: 0 = negative (RD-), 1 = positive (RD+)
// ---------------------------------------------------------------------------
reg rd_reg;

// ---------------------------------------------------------------------------
// 5b/6b and 3b/4b sub-encoders
// ---------------------------------------------------------------------------
// Split input
wire [4:0] data_5b = data_in[4:0];  // EDCBA
wire [2:0] data_3b = data_in[7:5];  // HGF

reg [5:0] enc_6b;
reg [3:0] enc_4b;
reg       rd_next_after_6b; // RD after 6b
reg       err_6b, err_4b;

// ---------------------------------------------------------------------------
// 5b/6b encoding table (full, with RD consideration)
// Returns: {6b_symbol_for_RD+, 6b_symbol_for_RD-}
// ---------------------------------------------------------------------------
function [11:0] encode_5b6b;
    input [4:0] d;
    input       rd;      // current RD
    // Returns {6b_rdp, 6b_rdn} where rdp = symbol for RD+, rdn = symbol for RD-
    // Convention: [11:6] = RD- symbol, [5:0] = RD+ symbol
    // Running disparity: negative if more 0s than 1s in symbol
    begin
        case (d)
            5'h00: encode_5b6b = 12'b100111_011000; // D.0  RD-=100111 RD+=011000
            5'h01: encode_5b6b = 12'b011101_100010; // D.1
            5'h02: encode_5b6b = 12'b101101_010010; // D.2
            5'h03: encode_5b6b = 12'b110001_110001; // D.3  neutral
            5'h04: encode_5b6b = 12'b110101_001010; // D.4
            5'h05: encode_5b6b = 12'b101001_101001; // D.5  neutral
            5'h06: encode_5b6b = 12'b011001_011001; // D.6  neutral
            5'h07: encode_5b6b = 12'b111000_000111; // D.7
            5'h08: encode_5b6b = 12'b111001_000110; // D.8
            5'h09: encode_5b6b = 12'b100101_100101; // D.9  neutral
            5'h0A: encode_5b6b = 12'b010101_010101; // D.10 neutral
            5'h0B: encode_5b6b = 12'b110100_110100; // D.11 neutral
            5'h0C: encode_5b6b = 12'b001101_001101; // D.12 neutral
            5'h0D: encode_5b6b = 12'b101100_101100; // D.13 neutral
            5'h0E: encode_5b6b = 12'b011100_011100; // D.14 neutral
            5'h0F: encode_5b6b = 12'b010111_101000; // D.15
            5'h10: encode_5b6b = 12'b011011_100100; // D.16
            5'h11: encode_5b6b = 12'b100011_100011; // D.17 neutral
            5'h12: encode_5b6b = 12'b010011_010011; // D.18 neutral
            5'h13: encode_5b6b = 12'b110010_110010; // D.19 neutral
            5'h14: encode_5b6b = 12'b001011_001011; // D.20 neutral
            5'h15: encode_5b6b = 12'b101010_101010; // D.21 neutral
            5'h16: encode_5b6b = 12'b011010_011010; // D.22 neutral
            5'h17: encode_5b6b = 12'b111010_000101; // D.23
            5'h18: encode_5b6b = 12'b110011_001100; // D.24
            5'h19: encode_5b6b = 12'b100110_100110; // D.25 neutral
            5'h1A: encode_5b6b = 12'b010110_010110; // D.26 neutral
            5'h1B: encode_5b6b = 12'b110110_001001; // D.27
            5'h1C: encode_5b6b = 12'b001110_001110; // D.24/K combo
            5'h1D: encode_5b6b = 12'b101110_010001; // D.29
            5'h1E: encode_5b6b = 12'b011110_100001; // D.30
            5'h1F: encode_5b6b = 12'b101011_010100; // D.31
            default: encode_5b6b = 12'hXXX;
        endcase
    end
endfunction

// ---------------------------------------------------------------------------
// 3b/4b encoding table
// ---------------------------------------------------------------------------
function [7:0] encode_3b4b;
    input [2:0] d;
    input       rd;
    input       k;       // K character
    // Returns {4b_rdn, 4b_rdp}
    begin
        if (!k) begin
            case (d)
                3'h0: encode_3b4b = 8'b1011_0100; // D.x.0
                3'h1: encode_3b4b = 8'b1001_1001; // D.x.1 neutral
                3'h2: encode_3b4b = 8'b0101_0101; // D.x.2 neutral
                3'h3: encode_3b4b = 8'b1100_0011; // D.x.3
                3'h4: encode_3b4b = 8'b1101_0010; // D.x.4
                3'h5: encode_3b4b = 8'b1010_1010; // D.x.5 neutral
                3'h6: encode_3b4b = 8'b0110_0110; // D.x.6 neutral
                3'h7: encode_3b4b = 8'b0111_1000; // D.x.7 (alt: 1110/0001)
                default: encode_3b4b = 8'hXX;
            endcase
        end else begin
            // K character 3b/4b
            case (d)
                3'h0: encode_3b4b = 8'b1011_0100; // K.x.0
                3'h1: encode_3b4b = 8'b0110_1001; // K.x.1
                3'h2: encode_3b4b = 8'b1010_0101; // K.x.2
                3'h3: encode_3b4b = 8'b1100_0011; // K.x.3
                3'h4: encode_3b4b = 8'b1101_0010; // K.x.4
                3'h5: encode_3b4b = 8'b0101_1010; // K.x.5
                3'h6: encode_3b4b = 8'b1001_0110; // K.x.6
                3'h7: encode_3b4b = 8'b0001_1110; // K.x.7 (alt: 1110/0001)
                default: encode_3b4b = 8'hXX;
            endcase
        end
    end
endfunction

// ---------------------------------------------------------------------------
// Lookup and disparity logic
// ---------------------------------------------------------------------------
wire [11:0] tbl_6b = encode_5b6b(data_5b, rd_reg);
wire [7:0]  tbl_4b = encode_3b4b(data_3b, rd_reg, k_char);

// Select 6b symbol based on current running disparity
// sym_4b is computed in the two-step block below (sym_4b_final) — not here
wire [5:0] sym_6b = rd_reg ? tbl_6b[5:0] : tbl_6b[11:6]; // RD+→[5:0], RD-→[11:6]

// Compute disparity of 6b symbol: +1 if more 1s, -1 if more 0s, 0 if equal
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

// ---------------------------------------------------------------------------
// Validate K characters
// ---------------------------------------------------------------------------
function is_valid_k;
    input [7:0] d;
    begin
        case (d)
            8'hBC: is_valid_k = 1; // K28.5 - comma
            8'hF7: is_valid_k = 1; // K23.7
            8'hFB: is_valid_k = 1; // K27.7
            8'hFD: is_valid_k = 1; // K29.7
            8'hFE: is_valid_k = 1; // K30.7
            8'h1C: is_valid_k = 1; // K28.0
            8'h3C: is_valid_k = 1; // K28.1
            8'h5C: is_valid_k = 1; // K28.2
            8'h7C: is_valid_k = 1; // K28.3
            8'h9C: is_valid_k = 1; // K28.4
            8'hDC: is_valid_k = 1; // K28.6
            8'hFC: is_valid_k = 1; // K28.7
            default: is_valid_k = 0;
        endcase
    end
endfunction

// ---------------------------------------------------------------------------
// Ones count wires (combinational) — used for documentation/debug only
// Main RD update now uses two-step method below (rd_mid / rd_final)
// ---------------------------------------------------------------------------
wire [3:0] ones_6b = sym_6b[0]+sym_6b[1]+sym_6b[2]+sym_6b[3]+sym_6b[4]+sym_6b[5];

// ---------------------------------------------------------------------------
// Two-step RD update (standard 8b/10b algorithm):
//   Step 1: RD after 6b sub-block
//   Step 2: RD after 4b sub-block  (= final RD for this symbol)
//   rd_out = RD AFTER this symbol (correct value for downstream)
// ---------------------------------------------------------------------------
// RD after the 6b sub-block
wire rd_mid = (ones_6b > 3) ? 1'b1 :
              (ones_6b < 3) ? 1'b0 : rd_reg;

// Re-select 4b symbol using rd_mid (not original rd_reg)
// Table format: encode_3b4b returns {RD- sym [7:4], RD+ sym [3:0]}
// rd_mid=0 (in RD- state) → pick RD- symbol = tbl[7:4]
// rd_mid=1 (in RD+ state) → pick RD+ symbol = tbl[3:0]
wire [7:0]  tbl_4b_mid   = encode_3b4b(data_3b, rd_mid, k_char);
wire [3:0]  sym_4b_final = rd_mid ? tbl_4b_mid[3:0] : tbl_4b_mid[7:4];
wire [2:0]  ones_4b_final = sym_4b_final[0]+sym_4b_final[1]+
                             sym_4b_final[2]+sym_4b_final[3];

// RD after the 4b sub-block = final RD
wire rd_final = (ones_4b_final > 2) ? 1'b1 :
                (ones_4b_final < 2) ? 1'b0 : rd_mid;

// ---------------------------------------------------------------------------
// Sequential encoding
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out       <= 10'h0;
        data_out_valid <= 1'b0;
        rd_reg         <= 1'b0; // Start with RD-
        rd_out         <= 1'b0;
        enc_err        <= 1'b0;
    end else begin
        data_out_valid <= 1'b0;
        enc_err        <= 1'b0;
        if (data_valid) begin
            if (k_char && !is_valid_k(data_in)) begin
                enc_err <= 1'b1;
            end else begin
                // 4b symbol now uses rd_mid for correct two-step selection
                data_out       <= {sym_4b_final, sym_6b};
                data_out_valid <= 1'b1;
                rd_reg         <= rd_final;   // Update state
                rd_out         <= rd_final;   // Output RD AFTER this symbol
            end
        end
    end
end

endmodule
