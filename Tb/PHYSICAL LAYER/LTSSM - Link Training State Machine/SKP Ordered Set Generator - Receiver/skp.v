
module skp (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        skp_send_req,
    input  wire [11:0] skp_interval,

    input  wire [255:0] rx_data,
    input  wire         rx_valid,

    output reg  [255:0] skp_data,
    output reg          skp_tx_valid,

    output reg          skp_detected,
    output reg          skp_removed,
    output reg          skp_err
);

localparam [7:0] COM_SYMBOL = 8'hBC;
localparam [7:0] SKP_SYMBOL = 8'h1C;

wire [255:0] skp_tx_word;
genvar gi;
generate
    for (gi = 0; gi < 8; gi = gi + 1) begin : SKP_BUILD
        assign skp_tx_word[gi*32 +  0 +: 8] = COM_SYMBOL;
        assign skp_tx_word[gi*32 +  8 +: 8] = SKP_SYMBOL;
        assign skp_tx_word[gi*32 + 16 +: 8] = SKP_SYMBOL;
        assign skp_tx_word[gi*32 + 24 +: 8] = SKP_SYMBOL;
    end
endgenerate

reg [11:0] interval_cnt;
reg        auto_send;

reg [1:0] tx_state;
localparam TX_IDLE = 2'd0;
localparam TX_SEND = 2'd1;
localparam TX_DONE = 2'd2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        skp_data      <= 256'd0;
        skp_tx_valid  <= 1'b0;
        tx_state      <= TX_IDLE;
        interval_cnt  <= 12'd0;
        auto_send     <= 1'b0;
    end else begin
        auto_send <= 1'b0;

        if (skp_interval > 12'd0) begin
            if (interval_cnt >= skp_interval - 12'd1) begin
                interval_cnt <= 12'd0;
                auto_send    <= 1'b1;
            end else begin
                interval_cnt <= interval_cnt + 12'd1;
            end
        end

        case (tx_state)
            TX_IDLE: begin
                skp_tx_valid <= 1'b0;
                if (skp_send_req || auto_send) begin
                    skp_data <= skp_tx_word;
                    tx_state <= TX_SEND;
                end
            end

            TX_SEND: begin
                skp_tx_valid <= 1'b1;
                tx_state     <= TX_DONE;
            end

            TX_DONE: begin
                skp_tx_valid <= 1'b0;
                tx_state     <= TX_IDLE;
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

wire is_skp_os = (rx_data[ 7: 0] == COM_SYMBOL) &&
                 (rx_data[15: 8] == SKP_SYMBOL) &&
                 (rx_data[23:16] == SKP_SYMBOL) &&
                 (rx_data[31:24] == SKP_SYMBOL);

wire is_bad_com = (rx_data[7:0] == COM_SYMBOL) &&
                  (rx_data[15:8] != SKP_SYMBOL) &&
                  (rx_data[15:8] != 8'h7C)  &&
                  (rx_data[55:48] != 8'h4A) &&
                  (rx_data[55:48] != 8'h45) &&
                  (rx_data[7:0]  != 8'h3C);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        skp_detected <= 1'b0;
        skp_removed  <= 1'b0;
        skp_err      <= 1'b0;
    end else begin
        skp_detected <= 1'b0;
        skp_removed  <= 1'b0;
        skp_err      <= 1'b0;

        if (rx_valid) begin
            if (is_skp_os) begin
                skp_detected <= 1'b1;
                skp_removed  <= 1'b1;
            end
        end
    end
end

endmodule
