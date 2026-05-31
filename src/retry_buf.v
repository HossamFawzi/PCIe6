
`timescale 1ns/1ps

module retry_buf #(
    parameter BUF_DEPTH = 4096,
    parameter TLP_WIDTH = 1056,
    parameter PTR_W     = 12
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [TLP_WIDTH-1:0]  tlp_in,
    input  wire                  tlp_write_en,
    input  wire [11:0]           seq_num_in,

    input  wire [11:0]           ack_seq,
    input  wire [11:0]           nak_seq,
    input  wire                  retry_req,

    output reg  [TLP_WIDTH-1:0]  retry_tlp,
    output reg                   retry_valid,
    output reg  [11:0]           retry_seq,

    output wire                  buf_full,
    output reg  [11:0]           buf_occ,
    output reg                   purge_done
);

    reg [TLP_WIDTH-1:0] mem_data [0:BUF_DEPTH-1];
    reg [11:0]          mem_seq  [0:BUF_DEPTH-1];

    reg [PTR_W-1:0] head_ptr;
    reg [PTR_W-1:0] tail_ptr;
    reg [PTR_W-1:0] replay_ptr;

    localparam ST_IDLE    = 2'b00;
    localparam ST_REPLAY  = 2'b01;

    reg [1:0] state;

    wire [PTR_W-1:0] occ_w = head_ptr - tail_ptr;

    localparam [11:0] BUF_FULL_THR = 12'd4095;
    assign buf_full = (occ_w == BUF_FULL_THR);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) buf_occ <= 12'h0;

        else        buf_occ <= occ_w[11:0];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= {PTR_W{1'b0}};
        end else if (tlp_write_en && !buf_full) begin
            mem_data[head_ptr] <= tlp_in;
            mem_seq [head_ptr] <= seq_num_in;
            head_ptr           <= head_ptr + 1'b1;
        end
    end

    function automatic seq_in_window;
        input [11:0] base;
        input [11:0] seq;
        input [11:0] top;
        begin
            seq_in_window = (((seq - base) & 12'hFFF) <=
                             ((top - base) & 12'hFFF));
        end
    endfunction

    wire [PTR_W-1:0] last_ptr  = head_ptr - 1'b1;
    wire [11:0]      top_seq   = mem_seq[last_ptr];

    wire do_purge = (occ_w > 0) &&
                    seq_in_window(mem_seq[tail_ptr], ack_seq, top_seq);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tail_ptr    <= {PTR_W{1'b0}};
            replay_ptr  <= {PTR_W{1'b0}};
            retry_tlp   <= {TLP_WIDTH{1'b0}};
            retry_valid <= 1'b0;
            retry_seq   <= 12'h0;
            purge_done  <= 1'b0;
            state       <= ST_IDLE;
        end else begin
            purge_done  <= 1'b0;
            retry_valid <= 1'b0;

            case (state)

                ST_IDLE: begin

                    if (do_purge) begin
                        tail_ptr   <= tail_ptr + 1'b1;
                        purge_done <= 1'b1;
                    end

                    if (retry_req) begin
                        replay_ptr <= tail_ptr;
                        state      <= ST_REPLAY;
                    end
                end

                ST_REPLAY: begin
                    if (replay_ptr != head_ptr) begin
                        retry_tlp   <= mem_data[replay_ptr];
                        retry_seq   <= mem_seq [replay_ptr];
                        retry_valid <= 1'b1;
                        replay_ptr  <= replay_ptr + 1'b1;
                    end else begin

                        retry_valid <= 1'b0;
                        state       <= ST_IDLE;
                    end

                    if (do_purge) begin
                        tail_ptr   <= tail_ptr + 1'b1;
                        purge_done <= 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
