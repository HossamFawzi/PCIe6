`timescale 1ns/1ps

module symbol_block_lock_fsm #(
    parameter [3:0] LOCK_THRESH = 4'd4,
    parameter [3:0] MISS_THRESH = 4'd4
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [255:0] rx_data,
    input  wire         rx_valid,
    input  wire [1:0]   sync_hdr,
    input  wire         com_detect,
    input  wire         lock_timer_exp,

    output wire         symbol_lock,
    output wire         block_lock,
    output wire         lock_err,
    output wire         lock_lost
);

    localparam [2:0] S_IDLE      = 3'd0,
                     S_SYM_HUNT  = 3'd1,
                     S_SYM_LOCK  = 3'd2,
                     S_BLK_HUNT  = 3'd3,
                     S_BLK_LOCK  = 3'd4,
                     S_LOCK_LOST = 3'd5;

    reg [2:0] state;

    reg [3:0] cnt;

    reg lock_err_r;

    wire valid_sync = (sync_hdr == 2'b01) || (sync_hdr == 2'b10);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            cnt        <= 4'h0;
            lock_err_r <= 1'b0;
        end else begin
            case (state)

                S_IDLE: begin
                    cnt        <= 4'h0;
                    if (rx_valid) begin
                        if (com_detect) begin
                            state <= S_SYM_HUNT;
                            cnt   <= 4'h0;
                        end else if (valid_sync) begin
                            state <= S_BLK_HUNT;
                            cnt   <= 4'h0;
                        end
                    end
                end

                S_SYM_HUNT: begin
                    if (lock_timer_exp) begin
                        state      <= S_IDLE;
                        cnt        <= 4'h0;
                        lock_err_r <= 1'b1;
                    end else if (rx_valid) begin
                        if (com_detect) begin
                            if (cnt >= LOCK_THRESH - 1) begin
                                state <= S_SYM_LOCK;
                                cnt   <= 4'h0;
                            end else begin
                                cnt   <= cnt + 4'h1;
                            end
                        end else begin
                            cnt <= 4'h0;
                        end
                    end

                end

                S_SYM_LOCK: begin
                    lock_err_r <= 1'b0;
                    if (rx_valid) begin
                        if (!com_detect) begin
                            if (cnt >= MISS_THRESH - 1) begin
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

                S_BLK_HUNT: begin
                    if (lock_timer_exp) begin
                        state      <= S_IDLE;
                        cnt        <= 4'h0;
                        lock_err_r <= 1'b1;
                    end else if (rx_valid) begin
                        if (valid_sync) begin
                            if (cnt >= LOCK_THRESH - 1) begin
                                state <= S_BLK_LOCK;
                                cnt   <= 4'h0;
                            end else begin
                                cnt   <= cnt + 4'h1;
                            end
                        end else begin
                            cnt <= 4'h0;
                        end
                    end
                end

                S_BLK_LOCK: begin
                    lock_err_r <= 1'b0;
                    if (rx_valid) begin
                        if (!valid_sync) begin
                            if (cnt >= MISS_THRESH - 1) begin
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

                S_LOCK_LOST: begin
                    state      <= S_IDLE;
                    cnt        <= 4'h0;
                    lock_err_r <= 1'b0;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    assign symbol_lock = (state == S_SYM_LOCK);

    assign block_lock  = (state == S_BLK_LOCK);

    assign lock_err    = lock_err_r;
    assign lock_lost   = (state == S_LOCK_LOST);

endmodule
