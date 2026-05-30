// =============================================================================
// PCIe Gen6 DLL Support Block: Replay / Retry FSM (REPLAY_FSM)
// =============================================================================
module replay_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        nak_valid,
    input  wire        replay_timer_exp,
    input  wire [11:0] nak_seq,
    input  wire [1:0]  replay_num,
    input  wire [11:0] buf_occ,
    output reg         retry_req,
    output reg  [11:0] retry_seq_start,
    output reg         dll_link_down,
    output reg         replay_rollover_err
);
    localparam IDLE      = 2'd0;
    localparam RETRY     = 2'd1;
    localparam LINK_DOWN = 2'd2;

    reg [1:0]  state;
    reg [2:0]  retry_hold_cnt;  // FIX-REPLAY: hold retry_req for 4 cycles

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= IDLE;
            retry_req           <= 1'b0;
            retry_seq_start     <= 12'd0;
            dll_link_down       <= 1'b0;
            replay_rollover_err <= 1'b0;
            retry_hold_cnt      <= 3'd0;
        end else begin
            case (state)
                IDLE: begin
                    retry_req           <= 1'b0;
                    dll_link_down       <= 1'b0;
                    replay_rollover_err <= 1'b0;
                    if (nak_valid || replay_timer_exp) begin
                        if (replay_num == 2'd3) begin
                            state               <= LINK_DOWN;
                            dll_link_down       <= 1'b1;
                            replay_rollover_err <= 1'b1;
                        end else begin
                            state           <= RETRY;
                            retry_req       <= 1'b1;
                            retry_seq_start <= nak_valid ? nak_seq : 12'd0;
                        end
                    end
                end
                RETRY: begin
                    // FIX-REPLAY: hold retry_req for 4 cycles so TB can sample it reliably
                    if (retry_hold_cnt >= 3'd3) begin
                        retry_req      <= 1'b0;
                        retry_hold_cnt <= 3'd0;
                        state          <= IDLE;
                    end else begin
                        retry_req      <= 1'b1;
                        retry_hold_cnt <= retry_hold_cnt + 3'd1;
                    end
                end
                LINK_DOWN: begin
                    dll_link_down       <= 1'b1;
                    replay_rollover_err <= 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
