
`timescale 1ns/1ps

module ack_nak_receiver (

    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] ack_out,
    input  wire        ack_out_valid,

    output reg [11:0]  ack_seq,
    output reg [11:0]  nak_seq,
    output reg         ack_valid,
    output reg         nak_valid,
    output reg         retry_req
);

localparam [7:0] ACK_TYPE_FLAG = 8'h00;
localparam [7:0] NAK_TYPE_FLAG = 8'h01;

reg [11:0] oldest_unacked;

wire [7:0]  rx_type_flag;
wire [11:0] rx_seq;
wire [11:0] seq_distance;
wire        in_window;

assign rx_type_flag = ack_out[23:16];
assign rx_seq       = ack_out[15:4];

assign seq_distance = (rx_seq - oldest_unacked) & 12'hFFF;

assign in_window = (seq_distance <= 12'd2047);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ack_seq        <= 12'h000;
        nak_seq        <= 12'h000;
        ack_valid      <= 1'b0;
        nak_valid      <= 1'b0;
        retry_req      <= 1'b0;
        oldest_unacked <= 12'h000;
    end
    else begin
        ack_valid <= 1'b0;
        nak_valid <= 1'b0;
        retry_req <= 1'b0;

        if (ack_out_valid && in_window) begin

            if (rx_type_flag == ACK_TYPE_FLAG) begin
                ack_seq   <= rx_seq;
                ack_valid <= 1'b1;
                oldest_unacked <= (rx_seq + 12'h001) & 12'hFFF;
            end

            else if (rx_type_flag == NAK_TYPE_FLAG) begin
                nak_seq   <= rx_seq;
                nak_valid <= 1'b1;
                retry_req <= 1'b1;
            end
        end
    end
end

endmodule
