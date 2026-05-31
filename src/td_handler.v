
module td_handler (
    input  wire           clk,
    input  wire           rst_n,

    input  wire [1183:0]  tlp_tx,
    input  wire           tlp_tx_valid,
    input  wire           tlp_td_bit,
    input  wire [31:0]    ecrc_val,
    input  wire           ecrc_en,

    output reg [1215:0]   tlp_with_digest,
    output reg            digest_valid,

    output reg            td_strip_ok,
    output reg            td_err
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_with_digest <= 1216'h0;
            digest_valid    <= 1'b0;
            td_strip_ok     <= 1'b0;
            td_err          <= 1'b0;
        end
        else begin

            digest_valid <= 1'b0;
            td_strip_ok  <= 1'b0;
            td_err       <= 1'b0;

            if (tlp_tx_valid) begin
                if (ecrc_en && tlp_td_bit) begin

                    tlp_with_digest[1215:32] <= tlp_tx[1183:0];
                    tlp_with_digest[31:0]    <= ecrc_val;
                    digest_valid             <= 1'b1;
                    td_strip_ok              <= 1'b0;
                end
                else if (!ecrc_en && tlp_td_bit) begin

                    if (tlp_tx[31:0] == ecrc_val) begin

                        tlp_with_digest[1215:1184] <= 32'h0;
                        tlp_with_digest[1183:0]    <= tlp_tx[1183:0];
                        td_strip_ok                <= 1'b1;
                    end
                    else begin
                        tlp_with_digest <= 1216'h0;
                        td_err          <= 1'b1;
                    end
                end
                else begin

                    tlp_with_digest[1215:32] <= tlp_tx;
                    tlp_with_digest[31:0]    <= 32'h0;
                    digest_valid             <= 1'b1;
                end
            end
        end
    end

endmodule
