// =============================================================================
// Module 6: TX Gear Box
// PCIe Gen6 Physical Layer
// Description: Serializes wide parallel data (256b) from core logic into
//              narrower PIPE interface width (e.g., 32b for Gen5, 64b for Gen6).
//              Handles width conversion with proper phase alignment.
//              TX direction: wide → narrow (serialize).
//
// CDC Design: Ping-Pong Buffer with toggle handshake.
//   1. clk_core writes into pp_buf[wr_sel], records buf_last_wr, toggles req_toggle.
//   2. req_toggle + buf_last_wr synced (2-FF) into clk_pipe.
//   3. clk_pipe detects edge on req, sets rd_sel = bw_s2, serializes MSB-first.
//   4. clk_pipe toggles ack_toggle when done.
//   5. clk_core waits for ack before accepting next word.
//   Guarantee: pp_buf[rd_sel] is never written while pipe is reading it.
// =============================================================================
module tx_gear_box #(
    parameter WIDE_W   = 256,  // Core-side width
    parameter NARROW_W = 32    // PIPE-side width (configurable per gen)
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

// Ping-pong buffers — only written by clk_core
reg [WIDE_W-1:0] pp_buf [0:1];

// clk_core signals
reg        wr_sel;
reg        buf_last_wr;
reg        req_toggle;
reg        ack_s1, ack_s2;

// clk_pipe signals
reg        req_s1, req_s2, req_prev;
reg        bw_s1,  bw_s2;
reg        rd_sel;
reg [CNT_W-1:0] phase;
reg        pipe_busy;
reg        ack_toggle;

assign gear_full  = req_toggle ^ ack_s2;
assign gear_empty = !pipe_busy;

// ── clk_core ──────────────────────────────────────────────────────────────
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

// ── clk_pipe ──────────────────────────────────────────────────────────────
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
            // ack_toggle is sent AFTER serialization completes, not here
        end else if (pipe_busy) begin
            data_out       <= pp_buf[rd_sel][WIDE_W-1 - phase*NARROW_W -: NARROW_W];
            data_out_valid <= 1'b1;
            if (phase == RATIO-1) begin
                pipe_busy  <= 1'b0;
                phase      <= {CNT_W{1'b0}};
                ack_toggle <= ~ack_toggle;  // BUG FIX: ack after all chunks sent
            end else
                phase <= phase + 1'b1;
        end else begin
            data_out <= {NARROW_W{1'b0}};
        end
    end
end

endmodule
