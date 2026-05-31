
module eios (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        eios_send,
    input  wire        eieos_send,

    input  wire [255:0] rx_data,
    input  wire         rx_valid,

    output reg  [255:0] eios_data,
    output reg          eios_tx_valid,

    output reg          eios_detected,
    output reg          eieos_detected
);

localparam [7:0] COM_SYMBOL  = 8'hBC;
localparam [7:0] IDL_SYMBOL  = 8'hBC;
localparam [7:0] EIOS_SYM0   = 8'hBC;
localparam [7:0] EIOS_SYM1   = 8'h7C;

wire [255:0] eios_word;
genvar gi;
generate
    for (gi = 0; gi < 8; gi = gi + 1) begin : EIOS_BUILD
        assign eios_word[gi*32 + 0  +: 8] = EIOS_SYM0;
        assign eios_word[gi*32 + 8  +: 8] = EIOS_SYM1;
        assign eios_word[gi*32 + 16 +: 8] = EIOS_SYM1;
        assign eios_word[gi*32 + 24 +: 8] = EIOS_SYM1;
    end
endgenerate

wire [255:0] eieos_word;
generate
    for (gi = 0; gi < 16; gi = gi + 1) begin : EIEOS_BUILD
        assign eieos_word[gi*16 + 0 +: 8] = 8'h00;
        assign eieos_word[gi*16 + 8 +: 8] = 8'hFF;
    end
endgenerate

reg [1:0] tx_state;
localparam TX_IDLE  = 2'd0;
localparam TX_SEND  = 2'd1;
localparam TX_DONE  = 2'd2;

reg is_eieos_pending;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        eios_data        <= 256'd0;
        eios_tx_valid    <= 1'b0;
        tx_state         <= TX_IDLE;
        is_eieos_pending <= 1'b0;
    end else begin
        case (tx_state)
            TX_IDLE: begin
                eios_tx_valid <= 1'b0;
                if (eios_send) begin
                    eios_data        <= eios_word;
                    is_eieos_pending <= 1'b0;
                    tx_state         <= TX_SEND;
                end else if (eieos_send) begin
                    eios_data        <= eieos_word;
                    is_eieos_pending <= 1'b1;
                    tx_state         <= TX_SEND;
                end
            end

            TX_SEND: begin
                eios_tx_valid <= 1'b1;
                tx_state      <= TX_DONE;
            end

            TX_DONE: begin
                eios_tx_valid <= 1'b0;
                tx_state      <= TX_IDLE;
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

wire rx_is_eios  = (rx_data[7:0] == EIOS_SYM0) && (rx_data[15:8] == EIOS_SYM1);
wire rx_is_eieos = (rx_data[7:0] == 8'h00)     && (rx_data[15:8] == 8'hFF);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        eios_detected  <= 1'b0;
        eieos_detected <= 1'b0;
    end else begin
        eios_detected  <= 1'b0;
        eieos_detected <= 1'b0;
        if (rx_valid) begin
            if (rx_is_eios)  eios_detected  <= 1'b1;
            if (rx_is_eieos) eieos_detected <= 1'b1;
        end
    end
end

endmodule
