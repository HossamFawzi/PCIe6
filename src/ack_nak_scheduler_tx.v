
`timescale 1ns/1ps

module ack_nak_scheduler_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] seq_rx,
    input  wire        crc_ok,
    input  wire        tlp_rx_valid,
    input  wire        ack_timer_exp,
    input  wire [ 7:0] ack_freq,
    output reg  [63:0] ack_dllp,
    output reg  [63:0] nak_dllp,
    output reg         dllp_valid,
    output reg  [ 1:0] dllp_type
);

    localparam [7:0] DLLP_TYPE_ACK = 8'h00;
    localparam [7:0] DLLP_TYPE_NAK = 8'h10;
    localparam [1:0] DTYPE_ACK     = 2'b01;
    localparam [1:0] DTYPE_NAK     = 2'b10;

    reg [11:0] pending_ack_seq;
    reg        ack_pending;
    reg [ 7:0] ack_count;
    reg [11:0] last_acked_seq;

    reg        dllp_hold;
    reg [63:0] ack_dllp_hold;
    reg [63:0] nak_dllp_hold;
    reg [ 1:0] dllp_type_hold;

    function [63:0] build_dllp;
        input [7:0]  dtype;
        input [11:0] seq;
        begin
            build_dllp = {dtype, 12'h000, seq, 32'h0000_0000};
        end
    endfunction

    wire [7:0] ack_count_next = ack_count + 8'h01;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_acked_seq  <= 12'h000;
            pending_ack_seq <= 12'h000;
            ack_pending     <= 1'b0;
            ack_count       <= 8'h00;
            ack_dllp        <= 64'h0;
            nak_dllp        <= 64'h0;
            dllp_valid      <= 1'b0;
            dllp_type       <= 2'b00;
            dllp_hold       <= 1'b0;
            ack_dllp_hold   <= 64'h0;
            nak_dllp_hold   <= 64'h0;
            dllp_type_hold  <= 2'b00;

        end else begin

            if (dllp_hold) begin
                dllp_valid     <= 1'b1;
                dllp_type      <= dllp_type_hold;
                ack_dllp       <= ack_dllp_hold;
                nak_dllp       <= nak_dllp_hold;
                dllp_hold      <= 1'b0;
            end else begin
                dllp_valid     <= 1'b0;
                dllp_type      <= 2'b00;
            end

            if (tlp_rx_valid) begin

                if (!crc_ok) begin

                    nak_dllp      <= build_dllp(DLLP_TYPE_NAK, seq_rx);
                    dllp_valid    <= 1'b1;
                    dllp_type     <= DTYPE_NAK;

                    dllp_hold     <= 1'b1;
                    nak_dllp_hold <= build_dllp(DLLP_TYPE_NAK, seq_rx);
                    ack_dllp_hold <= ack_dllp;
                    dllp_type_hold<= DTYPE_NAK;

                end else begin
                    if (ack_count_next >= ack_freq) begin

                        ack_dllp       <= build_dllp(DLLP_TYPE_ACK, seq_rx);
                        dllp_valid     <= 1'b1;
                        dllp_type      <= DTYPE_ACK;
                        last_acked_seq <= seq_rx;
                        pending_ack_seq<= seq_rx;
                        ack_pending    <= 1'b0;
                        ack_count      <= 8'h00;

                        dllp_hold      <= 1'b1;
                        ack_dllp_hold  <= build_dllp(DLLP_TYPE_ACK, seq_rx);
                        nak_dllp_hold  <= nak_dllp;
                        dllp_type_hold <= DTYPE_ACK;
                    end else begin
                        pending_ack_seq <= seq_rx;
                        ack_pending     <= 1'b1;
                        ack_count       <= ack_count_next;
                    end
                end

            end else begin

                if (ack_pending && ack_timer_exp) begin
                    ack_dllp       <= build_dllp(DLLP_TYPE_ACK, pending_ack_seq);
                    dllp_valid     <= 1'b1;
                    dllp_type      <= DTYPE_ACK;
                    last_acked_seq <= pending_ack_seq;
                    ack_pending    <= 1'b0;
                    ack_count      <= 8'h00;

                    dllp_hold      <= 1'b1;
                    ack_dllp_hold  <= build_dllp(DLLP_TYPE_ACK, pending_ack_seq);
                    nak_dllp_hold  <= nak_dllp;
                    dllp_type_hold <= DTYPE_ACK;
                end
            end
        end
    end

endmodule
