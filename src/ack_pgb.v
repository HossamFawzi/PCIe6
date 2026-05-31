
module ack_pgb (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] ack_pending_seq,
    input  wire        ack_pending,
    input  wire        nop_send_req,
    input  wire [15:0] ack_lat_limit,
    output reg  [11:0] ack_piggyback_seq,
    output reg         ack_piggyback_valid,
    output reg         ack_sent
);
    reg [15:0] lat_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lat_cnt <= 16'd0;
        end else if (!ack_pending || ack_sent) begin
            lat_cnt <= 16'd0;
        end else begin
            lat_cnt <= lat_cnt + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_piggyback_seq   <= 12'd0;
            ack_piggyback_valid <= 1'b0;
            ack_sent            <= 1'b0;
        end else begin
            ack_piggyback_valid <= 1'b0;
            ack_sent            <= 1'b0;

            if (ack_pending) begin
                if (nop_send_req || (lat_cnt >= ack_lat_limit)) begin
                    ack_piggyback_seq   <= ack_pending_seq;
                    ack_piggyback_valid <= 1'b1;
                    ack_sent            <= 1'b1;
                end
            end
        end
    end
endmodule
