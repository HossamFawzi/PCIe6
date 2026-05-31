
module tx_gear_box #(
    parameter WIDE_W   = 256,
    parameter NARROW_W = 32
)(
    input  wire                clk_core,
    input  wire                clk_pipe,
    input  wire                rst_n,

    input  wire [WIDE_W-1:0]   data_in,
    input  wire                data_in_valid,

    output reg  [NARROW_W-1:0] data_out,
    output reg                 data_out_valid,
    output wire                gear_full,
    output wire                gear_empty
);

localparam RATIO = WIDE_W / NARROW_W;
localparam CNT_W = $clog2(RATIO);

reg [WIDE_W-1:0] pp_buf [0:1];

reg        wr_sel;
reg        buf_last_wr;
reg        req_toggle;
reg        ack_s1, ack_s2;

reg        req_s1, req_s2, req_prev;
reg        bw_s1,  bw_s2;
reg        rd_sel;
reg [CNT_W-1:0] phase;
reg        pipe_busy;
reg        ack_toggle;

assign gear_full  = req_toggle ^ ack_s2;
assign gear_empty = !pipe_busy;

always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        pp_buf[0]   <= {WIDE_W{1'b0}};
        pp_buf[1]   <= {WIDE_W{1'b0}};
        wr_sel      <= 1'b0;
        buf_last_wr <= 1'b0;
        req_toggle  <= 1'b0;
        ack_s1      <= 1'b0;
        ack_s2      <= 1'b0;
    end else begin
        ack_s1 <= ack_toggle;
        ack_s2 <= ack_s1;
        if (data_in_valid && !(req_toggle ^ ack_s2)) begin
            pp_buf[wr_sel] <= data_in;
            buf_last_wr    <= wr_sel;
            wr_sel         <= ~wr_sel;
            req_toggle     <= ~req_toggle;
        end
    end
end

always @(posedge clk_pipe or negedge rst_n) begin
    if (!rst_n) begin
        req_s1         <= 1'b0;
        req_s2         <= 1'b0;
        req_prev       <= 1'b0;
        bw_s1          <= 1'b0;
        bw_s2          <= 1'b0;
        rd_sel         <= 1'b0;
        phase          <= {CNT_W{1'b0}};
        pipe_busy      <= 1'b0;
        data_out       <= {NARROW_W{1'b0}};
        data_out_valid <= 1'b0;
        ack_toggle     <= 1'b0;
    end else begin
        req_s1 <= req_toggle;  req_s2 <= req_s1;  req_prev <= req_s2;
        bw_s1  <= buf_last_wr; bw_s2  <= bw_s1;

        data_out_valid <= 1'b0;

        if ((req_s2 != req_prev) && !pipe_busy) begin
            rd_sel    <= bw_s2;
            pipe_busy <= 1'b1;
            phase     <= {CNT_W{1'b0}};

        end else if (pipe_busy) begin
            data_out       <= pp_buf[rd_sel][WIDE_W-1 - phase*NARROW_W -: NARROW_W];
            data_out_valid <= 1'b1;
            if (phase == RATIO-1) begin
                pipe_busy  <= 1'b0;
                phase      <= {CNT_W{1'b0}};
                ack_toggle <= ~ack_toggle;
            end else
                phase <= phase + 1'b1;
        end else begin
            data_out <= {NARROW_W{1'b0}};
        end
    end
end

endmodule
