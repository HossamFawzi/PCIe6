`timescale 1ns/1ps
// ============================================================
//  PCIe 6.0 Physical Layer - Symbol / Block Lock FSM
//
//  Gen1/2  : symbol lock via K28.5 comma detection (com_detect)
//  Gen3-5  : block  lock via 128b/130b sync header (01 or 10)
//  Gen6    : block  lock via FLIT sync header      (01 or 10)
//
//  States
//    S_IDLE      – no lock, idle
//    S_SYM_HUNT  – accumulating commas for symbol lock
//    S_SYM_LOCK  – symbol lock acquired
//    S_BLK_HUNT  – accumulating valid sync headers for block lock
//    S_BLK_LOCK  – block lock acquired
//    S_LOCK_LOST – lock lost; one-cycle pulse → triggers Recovery
// ============================================================
module symbol_block_lock_fsm #(
    parameter [3:0] LOCK_THRESH = 4'd4,   // consecutive good events to lock
    parameter [3:0] MISS_THRESH = 4'd4    // consecutive bad  events to lose lock
)(
    input  wire        clk,
    input  wire        rst_n,

    // Data path
    input  wire [255:0] rx_data,          // received data (unused in lock logic)
    input  wire         rx_valid,         // data / header valid
    input  wire [1:0]   sync_hdr,         // 128b/130b or FLIT sync header
    input  wire         com_detect,       // K28.5 comma detected (Gen1/2)
    input  wire         lock_timer_exp,   // lock-acquisition timeout

    // Status outputs
    output wire         symbol_lock,      // Gen1/2 symbol lock achieved
    output wire         block_lock,       // Gen3-6 block  lock achieved
    output wire         lock_err,         // failed to acquire lock (timer)
    output wire         lock_lost         // lock was lost → initiate Recovery
);

    // --------------------------------------------------------
    //  State encoding
    // --------------------------------------------------------
    localparam [2:0] S_IDLE      = 3'd0,
                     S_SYM_HUNT  = 3'd1,
                     S_SYM_LOCK  = 3'd2,
                     S_BLK_HUNT  = 3'd3,
                     S_BLK_LOCK  = 3'd4,
                     S_LOCK_LOST = 3'd5;

    reg [2:0] state;

    // 4-bit dual-purpose counter:
    //   in HUNT states : counts consecutive good events (commas / valid sync)
    //   in LOCK states : counts consecutive bad  events (misses)
    reg [3:0] cnt;

    // lock_err is a one-cycle registered pulse set on timer expiry in HUNT
    reg lock_err_r;

    // valid sync header: 01 or 10 (00 and 11 are illegal)
    wire valid_sync = (sync_hdr == 2'b01) || (sync_hdr == 2'b10);

    // --------------------------------------------------------
    //  Next-state / counter logic
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            cnt        <= 4'h0;
            lock_err_r <= 1'b0;
        end else begin
            case (state)

                // ------------------------------------------------
                //  IDLE – waiting for first lock indicator
                // ------------------------------------------------
                S_IDLE: begin
                    cnt        <= 4'h0;
                    lock_err_r <= 1'b0;
                    if (rx_valid) begin
                        if (com_detect) begin          // Gen1/2 comma
                            state <= S_SYM_HUNT;
                            cnt   <= 4'h1;
                        end else if (valid_sync) begin // Gen3-6 sync hdr
                            state <= S_BLK_HUNT;
                            cnt   <= 4'h1;
                        end
                    end
                end

                // ------------------------------------------------
                //  SYM_HUNT – accumulate consecutive commas
                // ------------------------------------------------
                S_SYM_HUNT: begin
                    if (lock_timer_exp) begin          // failed to lock
                        state      <= S_IDLE;
                        cnt        <= 4'h0;
                        lock_err_r <= 1'b1;
                    end else if (rx_valid) begin
                        if (com_detect) begin
                            if (cnt == LOCK_THRESH - 1) begin
                                state <= S_SYM_LOCK;  // lock acquired
                                cnt   <= 4'h0;
                            end else begin
                                cnt   <= cnt + 4'h1;
                            end
                        end else begin
                            cnt <= 4'h0;              // miss: reset count
                        end
                    end
                    // rx_valid=0: freeze counter
                end

                // ------------------------------------------------
                //  SYM_LOCK – maintain lock; count consecutive misses
                // ------------------------------------------------
                S_SYM_LOCK: begin
                    lock_err_r <= 1'b0;
                    if (rx_valid) begin
                        if (!com_detect) begin
                            if (cnt == MISS_THRESH - 1) begin
                                state <= S_LOCK_LOST; // lock lost
                                cnt   <= 4'h0;
                            end else begin
                                cnt <= cnt + 4'h1;
                            end
                        end else begin
                            cnt <= 4'h0;              // comma seen: clear misses
                        end
                    end
                end

                // ------------------------------------------------
                //  BLK_HUNT – accumulate consecutive valid sync hdrs
                // ------------------------------------------------
                S_BLK_HUNT: begin
                    if (lock_timer_exp) begin
                        state      <= S_IDLE;
                        cnt        <= 4'h0;
                        lock_err_r <= 1'b1;
                    end else if (rx_valid) begin
                        if (valid_sync) begin
                            if (cnt == LOCK_THRESH - 1) begin
                                state <= S_BLK_LOCK;
                                cnt   <= 4'h0;
                            end else begin
                                cnt   <= cnt + 4'h1;
                            end
                        end else begin
                            cnt <= 4'h0;              // bad header: reset count
                        end
                    end
                end

                // ------------------------------------------------
                //  BLK_LOCK – maintain lock; count invalid sync hdrs
                // ------------------------------------------------
                S_BLK_LOCK: begin
                    lock_err_r <= 1'b0;
                    if (rx_valid) begin
                        if (!valid_sync) begin
                            if (cnt == MISS_THRESH - 1) begin
                                state <= S_LOCK_LOST;
                                cnt   <= 4'h0;
                            end else begin
                                cnt <= cnt + 4'h1;
                            end
                        end else begin
                            cnt <= 4'h0;
                        end
                    end
                end

                // ------------------------------------------------
                //  LOCK_LOST – one-cycle pulse; return to IDLE
                // ------------------------------------------------
                S_LOCK_LOST: begin
                    state      <= S_IDLE;
                    cnt        <= 4'h0;
                    lock_err_r <= 1'b0;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    // --------------------------------------------------------
    //  Moore outputs
    // --------------------------------------------------------
    assign symbol_lock = (state == S_SYM_LOCK);
    assign block_lock  = (state == S_BLK_LOCK);
    assign lock_err    = lock_err_r;
    assign lock_lost   = (state == S_LOCK_LOST);

endmodule
