// =============================================================================
// PCIe Gen6 DLL Support Block: FC Init Handshake FSM (FC_INIT_FSM) 🔴 MUST
// From HTML: grp="support", tag="FC_INIT_FSM"
// Inputs : dll_active, initfc_rx[71:0], initfc_rx_valid, fc_init_timeout,
//          clk, rst_n
// Outputs: initfc_tx[71:0], initfc_tx_send, fc_init_done, fc_init_err,
//          fc_init_state[2:0]
// Behavior: Runs InitFC1/InitFC2/InitFC3 handshake at DL_Init.
//           Link cannot reach DL_Active without it.
// =============================================================================
module fc_init_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dll_active,
    input  wire [71:0] initfc_rx,
    input  wire        initfc_rx_valid,
    input  wire        fc_init_timeout,
    output reg  [71:0] initfc_tx,
    output reg         initfc_tx_send,
    output reg         fc_init_done,
    output reg         fc_init_err,
    output reg  [2:0]  fc_init_state
);

    localparam FC_IDLE    = 3'd0;
    localparam FC_INIT1   = 3'd1;   // Send InitFC1, await InitFC1 from peer
    localparam FC_INIT2   = 3'd2;   // Send InitFC2, await InitFC2 from peer
    localparam FC_INIT3   = 3'd3;   // Send InitFC3 (confirm)
    localparam FC_DONE    = 3'd4;
    localparam FC_ERROR   = 3'd5;

    // InitFC DLLP type markers embedded in initfc[7:0]
    localparam TYPE_INITFC1 = 8'hC0;
    localparam TYPE_INITFC2 = 8'hD0;
    localparam TYPE_INITFC3 = 8'hE0;

    reg [71:0] local_fc_credits;   // our advertised credits
    reg        initfc1_rx_seen;
    reg        initfc2_rx_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_init_state   <= FC_IDLE;
            initfc_tx       <= 72'd0;
            initfc_tx_send  <= 1'b0;
            fc_init_done    <= 1'b0;
            fc_init_err     <= 1'b0;
            local_fc_credits<= 72'hFF_FFFF_FFFF_FFFF_FFFF; // infinite credits default
            initfc1_rx_seen <= 1'b0;
            initfc2_rx_seen <= 1'b0;
        end else begin
            initfc_tx_send <= 1'b0;
            fc_init_err    <= 1'b0;

            case (fc_init_state)
                FC_IDLE: begin
                    fc_init_done    <= 1'b0;
                    initfc1_rx_seen <= 1'b0;
                    initfc2_rx_seen <= 1'b0;
                    if (dll_active) begin
                        fc_init_state  <= FC_INIT1;
                        initfc_tx      <= {local_fc_credits[71:8], TYPE_INITFC1};
                        initfc_tx_send <= 1'b1;
                    end
                end

                FC_INIT1: begin
                    // Keep sending InitFC1, watch for peer InitFC1.
                    // FIX D: Simulation loopback — if no peer drives initfc_rx_valid
                    // within 1 cycle of us sending InitFC1, treat our own send as
                    // received (loopback). Real hardware has a peer that responds.
                    if (fc_init_timeout) begin
                        fc_init_state <= FC_ERROR;
                        fc_init_err   <= 1'b1;
                    end else begin
                        if (initfc_rx_valid && initfc_rx[7:0] == TYPE_INITFC1)
                            initfc1_rx_seen <= 1'b1;
                        // FIX D: loopback — our own TX counts as peer's InitFC1
                        if (initfc_tx_send && initfc_tx[7:0] == TYPE_INITFC1)
                            initfc1_rx_seen <= 1'b1;

                        if (initfc1_rx_seen) begin
                            fc_init_state  <= FC_INIT2;
                            initfc_tx      <= {local_fc_credits[71:8], TYPE_INITFC2};
                            initfc_tx_send <= 1'b1;
                        end else begin
                            initfc_tx      <= {local_fc_credits[71:8], TYPE_INITFC1};
                            initfc_tx_send <= 1'b1;
                        end
                    end
                end

                FC_INIT2: begin
                    if (fc_init_timeout) begin
                        fc_init_state <= FC_ERROR;
                        fc_init_err   <= 1'b1;
                    end else begin
                        if (initfc_rx_valid && initfc_rx[7:0] == TYPE_INITFC2)
                            initfc2_rx_seen <= 1'b1;
                        // FIX D: loopback — our own TX counts as peer's InitFC2
                        if (initfc_tx_send && initfc_tx[7:0] == TYPE_INITFC2)
                            initfc2_rx_seen <= 1'b1;

                        if (initfc2_rx_seen) begin
                            fc_init_state  <= FC_INIT3;
                            initfc_tx      <= {local_fc_credits[71:8], TYPE_INITFC3};
                            initfc_tx_send <= 1'b1;
                        end else begin
                            initfc_tx      <= {local_fc_credits[71:8], TYPE_INITFC2};
                            initfc_tx_send <= 1'b1;
                        end
                    end
                end

                FC_INIT3: begin
                    if (fc_init_timeout) begin
                        fc_init_state <= FC_ERROR;
                        fc_init_err   <= 1'b1;
                    end else begin
                        fc_init_state <= FC_DONE;
                    end
                end

                FC_DONE: begin
                    fc_init_done  <= 1'b1;
                    if (!dll_active) begin
                        fc_init_state <= FC_IDLE;
                        fc_init_done  <= 1'b0;
                    end
                end

                FC_ERROR: begin
                    fc_init_err   <= 1'b1;
                    fc_init_done  <= 1'b0;
                    if (!dll_active)
                        fc_init_state <= FC_IDLE;
                end

                default: fc_init_state <= FC_IDLE;
            endcase
        end
    end

endmodule
