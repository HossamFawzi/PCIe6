
module l0_fsm (

    input  wire clk,
    input  wire rst_n,

    input  wire l0s_req,
    input  wire fts_detected,
    input  wire eios_detected,
    input  wire l0s_timer_exp,
    input  wire recv_req,

    output reg  send_fts,
    output reg  send_eios,
    output reg  l0_active,
    output reg  l0s_tx_active,
    output reg  l0s_rx_active,
    output reg  l0s_exit
);

    localparam [2:0]
        ST_L0          = 3'd0,
        ST_L0S_TX_ENTRY = 3'd1,
        ST_L0S_TX      = 3'd2,
        ST_L0S_TX_EXIT = 3'd3,
        ST_L0S_RX      = 3'd4,
        ST_L0S_RX_EXIT = 3'd5,
        ST_EXIT_DONE   = 3'd6;

    reg [2:0] state, next_state;

    reg [2:0] fts_rx_cnt;
    localparam FTS_REQUIRED = 3'd2;

    always @(posedge clk) begin
        if (!rst_n)
            state <= ST_L0;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;

        if (recv_req && (state != ST_L0)) begin

            next_state = ST_L0;
        end else begin
            case (state)

                ST_L0: begin
                    if (recv_req)
                        next_state = ST_L0;
                    else if (l0s_req)
                        next_state = ST_L0S_TX_ENTRY;
                    else if (eios_detected)
                        next_state = ST_L0S_RX;
                end

                ST_L0S_TX_ENTRY: begin
                    if (l0s_timer_exp)
                        next_state = ST_L0S_TX;
                end

                ST_L0S_TX: begin

                    if (l0s_timer_exp)
                        next_state = ST_L0S_TX_EXIT;
                end

                ST_L0S_TX_EXIT: begin
                    if (l0s_timer_exp)
                        next_state = ST_EXIT_DONE;
                end

                ST_L0S_RX: begin
                    if (fts_detected)
                        next_state = ST_L0S_RX_EXIT;
                end

                ST_L0S_RX_EXIT: begin
                    if (fts_rx_cnt >= FTS_REQUIRED)
                        next_state = ST_EXIT_DONE;
                end

                ST_EXIT_DONE: begin
                    next_state = ST_L0;
                end

                default: next_state = ST_L0;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            send_fts      <= 1'b0;
            send_eios     <= 1'b0;
            l0_active     <= 1'b1;
            l0s_tx_active <= 1'b0;
            l0s_rx_active <= 1'b0;
            l0s_exit      <= 1'b0;
            fts_rx_cnt    <= 3'd0;
        end else begin

            send_fts   <= 1'b0;
            send_eios  <= 1'b0;
            l0s_exit   <= 1'b0;

            case (state)

                ST_L0: begin
                    l0_active     <= 1'b1;
                    l0s_tx_active <= 1'b0;
                    l0s_rx_active <= 1'b0;
                    fts_rx_cnt    <= 3'd0;
                end

                ST_L0S_TX_ENTRY: begin
                    l0_active <= 1'b0;
                    send_eios <= 1'b1;
                end

                ST_L0S_TX: begin
                    l0s_tx_active <= 1'b1;
                end

                ST_L0S_TX_EXIT: begin
                    send_fts <= 1'b1;
                end

                ST_L0S_RX: begin
                    l0_active     <= 1'b0;
                    l0s_rx_active <= 1'b1;
                    fts_rx_cnt    <= 3'd0;
                end

                ST_L0S_RX_EXIT: begin
                    if (fts_detected && fts_rx_cnt < 3'd7)
                        fts_rx_cnt <= fts_rx_cnt + 3'd1;
                end

                ST_EXIT_DONE: begin
                    l0_active     <= 1'b1;
                    l0s_tx_active <= 1'b0;
                    l0s_rx_active <= 1'b0;
                    l0s_exit      <= 1'b1;
                    fts_rx_cnt    <= 3'd0;
                end

                default: ;
            endcase
        end
    end

endmodule
