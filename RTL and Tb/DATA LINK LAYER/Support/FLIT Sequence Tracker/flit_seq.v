// =============================================================================
// PCIe Gen6 DLL Support Block: FLIT Sequence Tracker (FLIT_SEQ)
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
        if (!rst_n || link_reset) begin
            oldest_unacked_seq <= 12'd0;
            seq_window_full    <= 1'b0;
            seq_wrap_det       <= 1'b0;
            seq_err            <= 1'b0;
            last_acked         <= 12'd0;
            prev_tx_seq        <= 12'd0;
        end else begin
            seq_err      <= 1'b0;
            seq_wrap_det <= 1'b0;

            // Detect wrap: tx_seq goes from 4095 to 0
            if (prev_tx_seq == 12'd4095 && flit_tx_seq == 12'd0)
                seq_wrap_det <= 1'b1;
            prev_tx_seq <= flit_tx_seq;

            // Track oldest unacked: advance when new ACK arrives
            if (ack_seq != last_acked) begin
                last_acked         <= ack_seq;
                oldest_unacked_seq <= ack_seq + 1'b1;
            end

            // Window full
            seq_window_full <= (unacked_count >= SEQ_WINDOW);

            // Sequence error: nak points behind oldest unacked
            if (nak_seq == (oldest_unacked_seq - 1'b1))
                seq_err <= 1'b1;

            // RX out-of-order check
            if (flit_rx_seq != 12'd0 &&
                flit_rx_seq != flit_tx_seq &&
                flit_rx_seq != (oldest_unacked_seq + unacked_count))
                seq_err <= 1'b1;
        end
    end
endmodule
