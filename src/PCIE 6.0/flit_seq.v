// =============================================================================
// PCIe Gen6 DLL Support Block: FLIT Sequence Tracker (FLIT_SEQ)
// FIX-FLIT_SEQ: Removed incorrect RX out-of-order check that compared
//   flit_rx_seq (received from peer) against flit_tx_seq (our own TX counter).
//   These are independent counters — the condition flit_rx_seq != flit_tx_seq
//   is ALWAYS true in normal operation, causing seq_err to fire every cycle.
//   Correct behavior: seq_err fires only when NAK points behind oldest unacked.
//   Out-of-order RX detection is handled by seq_num_checker_rx (tlp_seq_err).
// =============================================================================
module flit_seq (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] flit_tx_seq,
    input  wire [11:0] flit_rx_seq,
    input  wire [11:0] ack_seq,
    input  wire [11:0] nak_seq,
    input  wire        link_reset,
    output reg  [11:0] oldest_unacked_seq,
    output reg         seq_window_full,
    output reg         seq_wrap_det,
    output reg         seq_err
);
    localparam SEQ_WINDOW = 12'd2048;

    reg [11:0] last_acked;
    reg [11:0] prev_tx_seq;

    wire [11:0] unacked_count = flit_tx_seq - last_acked;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            oldest_unacked_seq <= 12'd0;
            seq_window_full    <= 1'b0;
            seq_wrap_det       <= 1'b0;
            seq_err            <= 1'b0;
            last_acked         <= 12'd0;
            prev_tx_seq        <= 12'd0;
        end else begin
            // FIX ELAB-303: link_reset handled synchronously (highest priority)
            if (link_reset) begin
                oldest_unacked_seq <= 12'd0;
                seq_window_full    <= 1'b0;
                seq_wrap_det       <= 1'b0;
                seq_err            <= 1'b0;
                last_acked         <= 12'd0;
                prev_tx_seq        <= 12'd0;
            end else begin
            seq_err      <= 1'b0;
            seq_wrap_det <= 1'b0;

            // Detect TX sequence wrap: 4095 -> 0
            if (prev_tx_seq == 12'd4095 && flit_tx_seq == 12'd0)
                seq_wrap_det <= 1'b1;
            prev_tx_seq <= flit_tx_seq;

            // Track oldest unacked: advance when new ACK arrives
            if (ack_seq != last_acked) begin
                last_acked         <= ack_seq;
                oldest_unacked_seq <= ack_seq + 1'b1;
            end

            // Window full check
            seq_window_full <= (unacked_count >= SEQ_WINDOW);

            // FIX: seq_err only when NAK points BEHIND the oldest unacked seq.
            // (i.e. peer is requesting retransmit of an already-ACKed FLIT —
            // that's a protocol error. Normal NAK within the window is handled
            // by replay_fsm and is NOT an error.)
            // The old RX out-of-order check (flit_rx_seq != flit_tx_seq) was
            // incorrect because TX and RX sequence counters are independent.
            if (nak_seq == (oldest_unacked_seq - 1'b1))
                seq_err <= 1'b1;
            end
        end
    end
endmodule
