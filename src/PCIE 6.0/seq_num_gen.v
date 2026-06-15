// =============================================================================
// Module: seq_num_gen
// Description: Sequence Number Generator (DLL TX path)
//              Generates monotonically increasing 12-bit sequence numbers
//              (0–4095) stamped onto every TLP or FLIT leaving the DLL.
//              Resets to 0 on link_reset. Supports NAK-based retry replay.
//              PCIe Gen6: sequence number embedded in FLIT header.
// =============================================================================

module seq_num_gen (
    input  wire        clk,
    input  wire        rst_n,

    // ── Control inputs ────────────────────────────────────────────────────────
    input  wire        tlp_valid_in,   // A TLP/FLIT is being dispatched → increment
    input  wire [11:0] ack_seq,        // Highest ACK'd sequence number from peer
    input  wire [11:0] nak_seq,        // NAK'd sequence number: replay from here
    input  wire        retry_req,      // 1 = NAK received, retransmit from nak_seq+1
    input  wire        link_reset,     // Synchronous link-layer reset

    // ── Outputs ───────────────────────────────────────────────────────────────
    output reg  [11:0] seq_num,        // Current sequence number to stamp
    output reg         seq_valid,      // Sequence number is valid this cycle
    output reg         seq_wrap        // Pulse when counter wraps 4095 → 0
);

    // ── Constants ─────────────────────────────────────────────────────────────
    localparam SEQ_MAX = 12'd4095;

    // ── Internal registers ────────────────────────────────────────────────────
    reg [11:0] next_seq;   // Next free sequence number
    reg [11:0] retry_ptr;  // Replay pointer (set to nak_seq+1 on NAK)
    reg        in_retry;   // 1 = currently replaying from retry_ptr

    // ── Combinational next-state ──────────────────────────────────────────────
    wire [11:0] incremented = (next_seq == SEQ_MAX) ? 12'd0 : next_seq + 12'd1;

    // ── Main FSM ──────────────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_seq   <= 12'd0;
            retry_ptr  <= 12'd0;
            in_retry   <= 1'b0;
            seq_num    <= 12'd0;
            seq_valid  <= 1'b0;
            seq_wrap   <= 1'b0;
        end else if (link_reset) begin
            // PCIe spec §3.4: sequence number resets to 0 on link reset
            next_seq   <= 12'd0;
            retry_ptr  <= 12'd0;
            in_retry   <= 1'b0;
            seq_num    <= 12'd0;
            seq_valid  <= 1'b0;
            seq_wrap   <= 1'b0;
        end else begin
            seq_wrap  <= 1'b0;  // default
            seq_valid <= 1'b0;  // default

            // ── NAK / retry handling (higher priority than normal advance) ──
            if (retry_req) begin
                // Retransmit from nak_seq (inclusive).
                retry_ptr <= nak_seq;
                in_retry  <= 1'b1;
            end

            // ── Dispatch a new or replayed sequence number ───────────────────
            if (tlp_valid_in) begin
                if (in_retry) begin
                    seq_num   <= retry_ptr;
                    seq_valid <= 1'b1;

                    // Advance replay pointer; leave retry mode when we reach
                    // the frontier (next_seq) after replaying all outstanding.
                    if (retry_ptr == next_seq - 1 || retry_ptr == SEQ_MAX) begin
                        in_retry <= 1'b0;
                    end
                    retry_ptr <= (retry_ptr == SEQ_MAX) ? 12'd0 : retry_ptr + 12'd1;
                end else begin
                    // Normal forward allocation
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

            // ── ACK processing: slide the window (informational here) ────────
            // In a full implementation next_seq lower-bound would be updated
            // based on ack_seq to release replay buffer entries.
            // (Not elaborated to keep this block self-contained.)
            // Suppress unused-signal warning:
            if (1'b0) begin
                if (ack_seq == 12'd0) begin end // reference ack_seq
            end
        end
    end

endmodule
