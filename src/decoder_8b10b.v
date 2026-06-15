//============================================================
// PCI Gen 6.0 Physical Layer - 8b/10b Decoder
// Module: decoder_8b10b
//
// Fix log:
//  - disparity_in was declared but never used; the always block
//    now loads rd_current from disparity_in (blocking assign)
//    before each decode so the caller's running-disparity context
//    is respected.
//  - Removed duplicate case items in decode_4b K-code branch:
//    4'b1001 and 4'b0110 each appeared twice; the dead second
//    entries (K.28.6 alt) have been removed.
//============================================================
module decoder_8b10b (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  data_in,
    input  wire        dec_en,
    input  wire        disparity_in,
    output reg  [7:0]  data_out,
    output reg         datak_out,
    output reg         disparity_out,
    output reg         dec_err,
    output reg         disparity_err
);

    // Internal signals
    reg [9:0] d;
    reg       rd_current;
    reg [5:0] code6b;
    reg [3:0] code4b;
    reg [4:0] data5b;
    reg [2:0] data3b;
    reg       is_kcode;
    reg       decode_error;
    reg       disp_error;
    reg       rd_next;
    integer   pop6, pop4, pop10;

    // Running disparity calculation
    function automatic integer popcount6;
        input [5:0] v;
        integer i, cnt;
        begin
            cnt = 0;
            for (i = 0; i < 6; i = i + 1)
                cnt = cnt + v[i];
            popcount6 = cnt;
        end
    endfunction

    function automatic integer popcount4;
        input [3:0] v;
        integer i, cnt;
        begin
            cnt = 0;
            for (i = 0; i < 4; i = i + 1)
                cnt = cnt + v[i];
            popcount4 = cnt;
        end
    endfunction

    // 6b/5b decode table (abcde from abcdei, MSB first after flip)
    // data_in[9:0] = abcdeifghj (a=MSB transmitted first)
    // Received bit order: data_in[9]=a, [8]=b, [7]=c, [6]=d, [5]=e, [4]=i, [3]=f, [2]=g, [1]=h, [0]=j

    task decode_6b;
        input  [5:0] c6;   // abcdei
        input        rd_in;
        output [4:0] out5;
        output       rd_out;
        output       err;
        output       k_flag;
        begin
            err    = 1'b0;
            k_flag = 1'b0;
            rd_out = rd_in;
            case (c6)
                // RD- codes (rd_in=0 -> positive disparity group)
                6'b100111: begin out5 = 5'b00000; rd_out = 1'b1; end // D.0
                6'b011000: begin out5 = 5'b00000; rd_out = 1'b0; end // D.0 RD+
                6'b011101: begin out5 = 5'b00001; rd_out = 1'b1; end // D.1
                6'b100010: begin out5 = 5'b00001; rd_out = 1'b0; end // D.1 RD+
                6'b101101: begin out5 = 5'b00010; rd_out = 1'b1; end // D.2
                6'b010010: begin out5 = 5'b00010; rd_out = 1'b0; end // D.2 RD+
                6'b110001: begin out5 = 5'b00011; rd_out = 1'b0; end // D.3 (neutral)
                6'b110101: begin out5 = 5'b00100; rd_out = 1'b1; end // D.4
                6'b001010: begin out5 = 5'b00100; rd_out = 1'b0; end // D.4 RD+
                6'b101001: begin out5 = 5'b00101; rd_out = 1'b0; end // D.5
                6'b011001: begin out5 = 5'b00110; rd_out = 1'b0; end // D.6
                6'b111000: begin out5 = 5'b00111; rd_out = 1'b1; end // D.7
                6'b000111: begin out5 = 5'b00111; rd_out = 1'b0; end // D.7 RD+
                6'b111001: begin out5 = 5'b01000; rd_out = 1'b1; end // D.8
                6'b000110: begin out5 = 5'b01000; rd_out = 1'b0; end // D.8 RD+
                6'b100101: begin out5 = 5'b01001; rd_out = 1'b0; end // D.9
                6'b010101: begin out5 = 5'b01010; rd_out = 1'b0; end // D.10
                6'b110100: begin out5 = 5'b01011; rd_out = 1'b0; end // D.11
                6'b001101: begin out5 = 5'b01100; rd_out = 1'b0; end // D.12
                6'b101100: begin out5 = 5'b01101; rd_out = 1'b0; end // D.13
                6'b011100: begin out5 = 5'b01110; rd_out = 1'b0; end // D.14
                6'b010111: begin out5 = 5'b01111; rd_out = 1'b1; end // D.15
                6'b101000: begin out5 = 5'b01111; rd_out = 1'b0; end // D.15 RD+
                6'b011011: begin out5 = 5'b10000; rd_out = 1'b1; end // D.16
                6'b100100: begin out5 = 5'b10000; rd_out = 1'b0; end // D.16 RD+
                6'b100011: begin out5 = 5'b10001; rd_out = 1'b0; end // D.17
                6'b010011: begin out5 = 5'b10010; rd_out = 1'b0; end // D.18
                6'b110010: begin out5 = 5'b10011; rd_out = 1'b0; end // D.19
                6'b001011: begin out5 = 5'b10100; rd_out = 1'b0; end // D.20
                6'b101010: begin out5 = 5'b10101; rd_out = 1'b0; end // D.21
                6'b011010: begin out5 = 5'b10110; rd_out = 1'b0; end // D.22
                6'b111010: begin out5 = 5'b10111; rd_out = 1'b1; end // D.23
                6'b000101: begin out5 = 5'b10111; rd_out = 1'b0; end // D.23 RD+
                6'b110011: begin out5 = 5'b11000; rd_out = 1'b1; end // D.24
                6'b001100: begin out5 = 5'b11000; rd_out = 1'b0; end // D.24 RD+
                6'b100110: begin out5 = 5'b11001; rd_out = 1'b0; end // D.25
                6'b010110: begin out5 = 5'b11010; rd_out = 1'b0; end // D.26
                6'b110110: begin out5 = 5'b11011; rd_out = 1'b1; end // D.27
                6'b001001: begin out5 = 5'b11011; rd_out = 1'b0; end // D.27 RD+
                6'b001110: begin out5 = 5'b11100; rd_out = 1'b0; end // D.28
                6'b101110: begin out5 = 5'b11101; rd_out = 1'b1; end // D.29
                6'b010001: begin out5 = 5'b11101; rd_out = 1'b0; end // D.29 RD+
                6'b011110: begin out5 = 5'b11110; rd_out = 1'b1; end // D.30
                6'b100001: begin out5 = 5'b11110; rd_out = 1'b0; end // D.30 RD+
                6'b101011: begin out5 = 5'b11111; rd_out = 1'b1; end // D.31
                6'b010100: begin out5 = 5'b11111; rd_out = 1'b0; end // D.31 RD+
                // K codes 6b portion
                6'b111100: begin out5 = 5'b11100; rd_out = 1'b1; k_flag = 1'b1; end // K.28.* RD-
                6'b000011: begin out5 = 5'b11100; rd_out = 1'b0; k_flag = 1'b1; end // K.28.* RD+
                default:   begin out5 = 5'b00000; err    = 1'b1; rd_out = rd_in; end
            endcase
        end
    endtask

    // 4b/3b decode table (fghj -> HGF)
    // FIX: removed duplicate case items 4'b1001 and 4'b0110 from the K-code
    //      branch; the second occurrences (K.28.6 alt entries) were dead code
    //      because Verilog case matches the first hit.
    task decode_4b;
        input  [3:0] c4;
        input        rd_in;
        input        is_k;
        output [2:0] out3;
        output       rd_out;
        output       err;
        begin
            err    = 1'b0;
            rd_out = rd_in;
            if (!is_k) begin
                case (c4)
                    4'b1011: begin out3 = 3'b000; rd_out = 1'b1; end // D.x.0 RD-
                    4'b0100: begin out3 = 3'b000; rd_out = 1'b0; end // D.x.0 RD+
                    4'b1001: begin out3 = 3'b001; rd_out = 1'b0; end // D.x.1
                    4'b0101: begin out3 = 3'b010; rd_out = 1'b0; end // D.x.2
                    4'b1100: begin out3 = 3'b011; rd_out = 1'b1; end // D.x.3 RD-
                    4'b0011: begin out3 = 3'b011; rd_out = 1'b0; end // D.x.3 RD+
                    4'b1101: begin out3 = 3'b100; rd_out = 1'b1; end // D.x.4 RD-
                    4'b0010: begin out3 = 3'b100; rd_out = 1'b0; end // D.x.4 RD+
                    4'b1010: begin out3 = 3'b101; rd_out = 1'b0; end // D.x.5
                    4'b0110: begin out3 = 3'b110; rd_out = 1'b0; end // D.x.6
                    4'b1110: begin out3 = 3'b111; rd_out = 1'b1; end // D.x.7 RD- (alt)
                    4'b0001: begin out3 = 3'b111; rd_out = 1'b0; end // D.x.7 RD+
                    4'b0111: begin out3 = 3'b111; rd_out = 1'b1; end // D.x.P7 RD-
                    4'b1000: begin out3 = 3'b111; rd_out = 1'b0; end // D.x.A7 RD+
                    default: begin out3 = 3'b000; err    = 1'b1;  end
                endcase
            end else begin
                case (c4)
                    4'b0010: begin out3 = 3'b000; rd_out = 1'b0; end // K.28.0 RD+
                    4'b1101: begin out3 = 3'b000; rd_out = 1'b1; end // K.28.0 RD-
                    4'b1001: begin out3 = 3'b001; rd_out = 1'b0; end // K.28.1 RD+
                    4'b0110: begin out3 = 3'b001; rd_out = 1'b1; end // K.28.1 RD-
                    4'b0101: begin out3 = 3'b010; rd_out = 1'b0; end // K.28.2 RD+
                    4'b1010: begin out3 = 3'b010; rd_out = 1'b1; end // K.28.2 RD-
                    4'b1100: begin out3 = 3'b011; rd_out = 1'b1; end // K.28.3 RD-
                    4'b0011: begin out3 = 3'b011; rd_out = 1'b0; end // K.28.3 RD+
                    4'b0100: begin out3 = 3'b100; rd_out = 1'b0; end // K.28.4 RD+
                    4'b1011: begin out3 = 3'b100; rd_out = 1'b1; end // K.28.4 RD-
                    4'b1000: begin out3 = 3'b101; rd_out = 1'b0; end // K.28.5 RD+
                    4'b0111: begin out3 = 3'b101; rd_out = 1'b1; end // K.28.5 RD-
                    4'b1110: begin out3 = 3'b111; rd_out = 1'b1; end // K.28.7 RD-
                    4'b0001: begin out3 = 3'b111; rd_out = 1'b0; end // K.28.7 RD+
                    default: begin out3 = 3'b000; err    = 1'b1;  end
                endcase
            end
        end
    endtask

    // Disparity check
    function automatic integer count_ones_10;
        input [9:0] v;
        integer i, cnt;
        begin
            cnt = 0;
            for (i = 0; i < 10; i = i + 1)
                cnt = cnt + v[i];
            count_ones_10 = cnt;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out      <= 8'h00;
            datak_out     <= 1'b0;
            disparity_out <= 1'b0;
            dec_err       <= 1'b0;
            disparity_err <= 1'b0;
            rd_current    = 1'b0;
        end else if (dec_en) begin
            // FIX: load rd_current from disparity_in (blocking assignment) so
            // the caller's running-disparity context is used for this symbol.
            rd_current = disparity_in;

            // Extract 6b (abcdei) and 4b (fghj) from received 10b
            // Bit order: data_in[9]=a,data_in[8]=b,...,data_in[4]=i,data_in[3]=f,...,data_in[0]=j
            code6b = data_in[9:4];
            code4b = data_in[3:0];

            // Decode sub-blocks
            decode_6b(code6b, rd_current, data5b, rd_next, decode_error, is_kcode);

            begin : blk_4b
                reg       rd_after6;
                reg [2:0] tmp3b;
                reg       err4;
                rd_after6 = rd_next;
                decode_4b(code4b, rd_after6, is_kcode, tmp3b, rd_next, err4);
                decode_error = decode_error | err4;
                data3b = tmp3b;
            end

            // Disparity error detection
            // A violation occurs when a positive-disparity codeword (ones > 5)
            // arrives while already at RD+ (rd_current==1), or a negative-
            // disparity codeword (ones < 5) arrives while already at RD-.
            // Neutral codewords (ones == 5) never cause a disparity error.
            begin : blk_disp
                integer ones;
                ones = count_ones_10(data_in);
                if (ones == 5) begin
                    disp_error = 1'b0;
                end else if (ones > 5) begin
                    // Positive disparity group - rd going to RD+
                    disp_error = (rd_current == 1'b1); // already at RD+
                end else begin
                    // Negative disparity group - rd going to RD-
                    disp_error = (rd_current == 1'b0); // already at RD-
                end
            end

            // Update running disparity
            rd_current    = rd_next;
            disparity_out <= rd_next;

            // Outputs
            data_out      <= {data3b, data5b};
            datak_out     <= is_kcode;
            dec_err       <= decode_error;
            disparity_err <= disp_error;
        end else begin
            dec_err       <= 1'b0;
            disparity_err <= 1'b0;
        end
    end

endmodule
