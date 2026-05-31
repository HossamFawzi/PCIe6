
module ts2_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  link_num,
    input  wire [7:0]  lane_num,
    input  wire [7:0]  speed_cap,
    input  wire [7:0]  fts_count,
    input  wire        ts2_send,

    output reg  [255:0] ts2_data,
    output reg          ts2_valid,
    output reg          ts2_done
);

localparam [7:0] COM_SYMBOL = 8'hBC;
localparam [7:0] PAD_SYMBOL = 8'hF7;
localparam [7:0] TS2_ID     = 8'h45;

reg [1:0] state;
localparam S_IDLE  = 2'd0;
localparam S_BUILD = 2'd1;
localparam S_VALID = 2'd2;
localparam S_DONE  = 2'd3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ts2_data  <= 256'd0;
        ts2_valid <= 1'b0;
        ts2_done  <= 1'b0;
        state     <= S_IDLE;
    end else begin
        ts2_done <= 1'b0;

        case (state)
            S_IDLE: begin
                ts2_valid <= 1'b0;
                if (ts2_send)
                    state <= S_BUILD;
            end

            S_BUILD: begin

                ts2_data[  7:  0] <= COM_SYMBOL;
                ts2_data[ 15:  8] <= link_num;
                ts2_data[ 23: 16] <= lane_num;
                ts2_data[ 31: 24] <= fts_count;
                ts2_data[ 39: 32] <= speed_cap;
                ts2_data[ 47: 40] <= 8'h00;
                ts2_data[ 55: 48] <= TS2_ID;
                ts2_data[ 63: 56] <= PAD_SYMBOL;
                ts2_data[ 71: 64] <= PAD_SYMBOL;
                ts2_data[ 79: 72] <= PAD_SYMBOL;
                ts2_data[ 87: 80] <= PAD_SYMBOL;
                ts2_data[ 95: 88] <= PAD_SYMBOL;
                ts2_data[103: 96] <= PAD_SYMBOL;
                ts2_data[111:104] <= PAD_SYMBOL;
                ts2_data[119:112] <= PAD_SYMBOL;
                ts2_data[127:120] <= PAD_SYMBOL;
                ts2_data[135:128] <= PAD_SYMBOL;
                ts2_data[143:136] <= PAD_SYMBOL;
                ts2_data[151:144] <= PAD_SYMBOL;
                ts2_data[159:152] <= PAD_SYMBOL;
                ts2_data[167:160] <= PAD_SYMBOL;
                ts2_data[175:168] <= PAD_SYMBOL;
                ts2_data[183:176] <= PAD_SYMBOL;
                ts2_data[191:184] <= PAD_SYMBOL;
                ts2_data[199:192] <= PAD_SYMBOL;
                ts2_data[207:200] <= PAD_SYMBOL;
                ts2_data[215:208] <= PAD_SYMBOL;
                ts2_data[223:216] <= PAD_SYMBOL;
                ts2_data[231:224] <= PAD_SYMBOL;
                ts2_data[239:232] <= PAD_SYMBOL;
                ts2_data[247:240] <= PAD_SYMBOL;
                ts2_data[255:248] <= PAD_SYMBOL;
                state <= S_VALID;
            end

            S_VALID: begin
                ts2_valid <= 1'b1;
                state     <= S_DONE;
            end

            S_DONE: begin
                ts2_done  <= 1'b1;
                ts2_valid <= 1'b0;
                state     <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
