// ============================================================
//  PCIe Gen6 — Data Link Layer
//  Module  : Retry Buffer  (RETRY_BUF)
//  Tag     : RETRY_BUF
//  Group   : TX Path
//
//  Function:
//    SRAM-based replay buffer.  Stores all transmitted TLPs
//    (with sequence number) until the remote receiver sends
//    an ACK.  On NAK (or replay-timer expiry signalled by
//    retry_req), replays TLPs starting from nak_seq.
//    TLPs are purged on ACK up-to ack_seq.
//
//  Bug fix (TC9 — sequence wrap-around):
//    The original seq_le function computes (b-a)&0xFFF <= 0x7FF,
//    which is a pure 12-bit modular distance check.  This is
//    WRONG for ACK purging because it has no knowledge of
//    which entries are actually inside the buffer window.
//
//    Example failure:
//      tail_seq = 0xFFE, ack_seq = 0x01D (left over from TC8).
//      (0x01D - 0xFFE) & 0xFFF = 0x01F = 31 <= 0x7FF → seq_le=TRUE
//      So 0xFFE is wrongly considered ACK'd and purged immediately.
//
//    Root cause: seq_le only knows about seq-number distance,
//    not buffer occupancy.  The correct guard is:
//      purge ONLY when the tail entry's seq# is within the live
//      [tail_seq .. ack_seq] window AND the buffer is non-empty.
//
//    Fix: replace seq_le with seq_in_window(a, b, c):
//      "Is seq b in the forward arc from a to c (inclusive)?"
//      This is true when:
//        ((b - a) & 0xFFF) <= ((c - a) & 0xFFF)
//      Applied as: seq_in_window(tail_seq, ack_seq, head_seq-1)
//      i.e. "is ack_seq between tail_seq and the last written seq?"
//      If yes, the tail entry is ACK'd.
//
//  Parameters:
//    BUF_DEPTH  – number of TLP slots  (default 4096)
//    TLP_WIDTH  – width of one TLP slot (default 1056 bits)
//
//  Port list (unchanged from original):
//    Inputs : tlp_in[1055:0], tlp_write_en, seq_num_in[11:0],
//             ack_seq[11:0], nak_seq[11:0], retry_req,
//             clk, rst_n
//    Outputs: retry_tlp[1055:0], retry_valid, retry_seq[11:0],
//             buf_full, buf_occ[11:0], purge_done
// ============================================================
`timescale 1ns/1ps

module retry_buf #(
    parameter BUF_DEPTH = 4096,        // must be power-of-2
    parameter TLP_WIDTH = 1056,
    parameter PTR_W     = 12           // log2(BUF_DEPTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Write path (new TLPs from TX path)
    input  wire [TLP_WIDTH-1:0]  tlp_in,
    input  wire                  tlp_write_en,
    input  wire [11:0]           seq_num_in,

    // ACK/NAK from ACK_RX
    input  wire [11:0]           ack_seq,
    input  wire [11:0]           nak_seq,
    input  wire                  retry_req,

    // Replay output
    output reg  [TLP_WIDTH-1:0]  retry_tlp,
    output reg                   retry_valid,
    output reg  [11:0]           retry_seq,

    // Status
    output wire                  buf_full,
    output reg  [11:0]           buf_occ,
    output reg                   purge_done
);

    // ----------------------------------------------------------
    // Storage arrays
    // ----------------------------------------------------------
    reg [TLP_WIDTH-1:0] mem_data [0:BUF_DEPTH-1];
    reg [11:0]          mem_seq  [0:BUF_DEPTH-1];

    // ----------------------------------------------------------
    // Pointers
    // head_ptr  – next write location
    // tail_ptr  – oldest unACK'd entry (next to purge/replay)
    // replay_ptr– current replay read pointer
    // ----------------------------------------------------------
    reg [PTR_W-1:0] head_ptr;
    reg [PTR_W-1:0] tail_ptr;
    reg [PTR_W-1:0] replay_ptr;

    // ----------------------------------------------------------
    // FSM states
    // ----------------------------------------------------------
    localparam ST_IDLE    = 2'b00;
    localparam ST_REPLAY  = 2'b01;

    reg [1:0] state;

    // ----------------------------------------------------------
    // Occupancy & full
    // ----------------------------------------------------------
    wire [PTR_W-1:0] occ_w = head_ptr - tail_ptr; // wraps naturally
    assign buf_full = (occ_w == BUF_DEPTH - 1);

    // ----------------------------------------------------------
    // Registered occupancy output (12-bit matches port width)
    // ----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) buf_occ <= 12'h0;
        else        buf_occ <= {{(12-PTR_W){1'b0}}, occ_w};
    end

    // ----------------------------------------------------------
    // Write path
    // ----------------------------------------------------------
    integer wi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= {PTR_W{1'b0}};
            for (wi = 0; wi < BUF_DEPTH; wi = wi + 1) begin
                mem_data[wi] <= {TLP_WIDTH{1'b0}};
                mem_seq [wi] <= 12'h0;
            end
        end else if (tlp_write_en && !buf_full) begin
            mem_data[head_ptr] <= tlp_in;
            mem_seq [head_ptr] <= seq_num_in;
            head_ptr           <= head_ptr + 1'b1;
        end
    end

    // ----------------------------------------------------------
    // FIX: seq_in_window(base, seq, top)
    //   Returns TRUE when `seq` lies in the forward arc
    //   [base .. top] (inclusive) in 12-bit modular space.
    //
    //   Formula: ((seq - base) & 0xFFF) <= ((top - base) & 0xFFF)
    //
    //   Applied for ACK purge:
    //     base = tail entry's seq#   (oldest unACK'd)
    //     seq  = ack_seq             (what the peer acknowledged)
    //     top  = seq of newest entry = mem_seq[head_ptr - 1]
    //
    //   This ensures we only purge when ack_seq is genuinely
    //   between the tail and the head in the live buffer window,
    //   preventing spurious purges after a sequence wrap.
    // ----------------------------------------------------------
    function automatic seq_in_window;
        input [11:0] base;   // oldest seq in buffer
        input [11:0] seq;    // ack_seq to test
        input [11:0] top;    // newest seq in buffer
        begin
            seq_in_window = (((seq - base) & 12'hFFF) <=
                             ((top - base) & 12'hFFF));
        end
    endfunction

    // Seq of the newest entry (head_ptr - 1)
    wire [PTR_W-1:0] last_ptr  = head_ptr - 1'b1;
    wire [11:0]      top_seq   = mem_seq[last_ptr];

    // ACK purge condition: buffer non-empty AND ack_seq is inside
    // the live window [tail_seq .. top_seq]
    wire do_purge = (occ_w > 0) &&
                    seq_in_window(mem_seq[tail_ptr], ack_seq, top_seq);

    // ----------------------------------------------------------
    // Main FSM
    // ----------------------------------------------------------
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
            purge_done  <= 1'b0;   // default pulse
            retry_valid <= 1'b0;

            case (state)
                // ---- IDLE: watch for ACK / NAK ----
                ST_IDLE: begin
                    // Purge one entry per cycle while ACK'd entries remain
                    if (do_purge) begin
                        tail_ptr   <= tail_ptr + 1'b1;
                        purge_done <= 1'b1;
                    end

                    // NAK / replay-timer → start replay
                    if (retry_req) begin
                        replay_ptr <= tail_ptr;
                        state      <= ST_REPLAY;
                    end
                end

                // ---- REPLAY: stream TLPs from replay_ptr to head_ptr ----
                ST_REPLAY: begin
                    if (replay_ptr != head_ptr) begin
                        retry_tlp   <= mem_data[replay_ptr];
                        retry_seq   <= mem_seq [replay_ptr];
                        retry_valid <= 1'b1;
                        replay_ptr  <= replay_ptr + 1'b1;
                    end else begin
                        // Replay complete
                        retry_valid <= 1'b0;
                        state       <= ST_IDLE;
                    end

                    // Continue purging ACKs during replay
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
