
module seq_num_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        tlp_valid_in,
    input  wire [11:0] ack_seq,
    input  wire [11:0] nak_seq,
    input  wire        retry_req,
    input  wire        link_reset,

    output reg  [11:0] seq_num,
    output reg         seq_valid,
    output reg         seq_wrap
);

    localparam SEQ_MAX = 12'd4095;

    reg [11:0] next_seq;
    reg [11:0] retry_ptr;
    reg        in_retry;

    wire [11:0] incremented = (next_seq == SEQ_MAX) ? 12'd0 : next_seq + 12'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_seq   <= 12'd0;
            retry_ptr  <= 12'd0;
            in_retry   <= 1'b0;
            seq_num    <= 12'd0;
            seq_valid  <= 1'b0;
            seq_wrap   <= 1'b0;
        end else if (link_reset) begin

            next_seq   <= 12'd0;
            retry_ptr  <= 12'd0;
            in_retry   <= 1'b0;
            seq_num    <= 12'd0;
            seq_valid  <= 1'b0;
            seq_wrap   <= 1'b0;
        end else begin
            seq_wrap  <= 1'b0;
            seq_valid <= 1'b0;

            if (retry_req) begin

                retry_ptr <= nak_seq;
                in_retry  <= 1'b1;
            end

            if (tlp_valid_in) begin
                if (in_retry) begin
                    seq_num   <= retry_ptr;
                    seq_valid <= 1'b1;

                    if (retry_ptr == next_seq - 1 || retry_ptr == SEQ_MAX) begin
                        in_retry <= 1'b0;
                    end
                    retry_ptr <= (retry_ptr == SEQ_MAX) ? 12'd0 : retry_ptr + 12'd1;
                end else begin

                    seq_num   <= next_seq;
                    seq_valid <= 1'b1;

                    if (next_seq == SEQ_MAX) begin
                        seq_wrap <= 1'b1;
                        next_seq <= 12'd0;
                    end else begin
                        next_seq <= next_seq + 12'd1;
                    end
                end
            end

            if (1'b0) begin
                if (ack_seq == 12'd0) begin end
            end
        end
    end

endmodule
