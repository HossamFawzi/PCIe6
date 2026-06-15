// ============================================================
//  PCIe Gen6 - FLIT Sync Header Generator / Checker
//  Tag : FLIT_SYNC  |  Group : gen6  |  Gen : Gen6
// ============================================================
//
//  INTERFACE (from HTML reference):
//    Inputs :
//      flit_tx[2047:0]          - 2048-bit TX FLIT payload
//      flit_tx_valid            - 1=Data FLIT, 0=Ordered-Set FLIT
//      flit_rx[2047:0]          - 2048-bit received FLIT payload
//      sync_hdr_rx[1:0]         - 2-bit sync header extracted from RX
//      flit_rx_valid            - RX FLIT valid strobe
//      clk                      - system clock (rising-edge)
//      rst_n                    - active-low synchronous reset
//
//    Outputs:
//      flit_tx_with_hdr[2049:0] - {sync_hdr_tx[1:0], flit_tx[2047:0]}
//      sync_hdr_tx[1:0]         - 2-bit sync header being transmitted
//      sync_hdr_rx_ok           - RX header valid (01 or 10)
//      sync_hdr_rx_err          - RX header invalid (00 or 11)
//      flit_lock                - FLIT boundary lock achieved
//
//  PCIe Gen6 sync header encoding:
//    2'b01 = Data FLIT
//    2'b10 = Ordered-Set FLIT
//    2'b00 / 2'b11 = Reserved / illegal
//
//  Lock FSM:
//    LOCK_THR  consecutive valid headers -> flit_lock asserted
//    UNLOCK_THR consecutive invalid headers -> flit_lock de-asserted
// ============================================================

module flit_sync_hdr_gen_checker (
    input  wire         clk,
    input  wire         rst_n,

    // TX path
    input  wire [2047:0] flit_tx,
    input  wire          flit_tx_valid,

    // RX path
    input  wire [2047:0] flit_rx,
    input  wire [1:0]    sync_hdr_rx,
    input  wire          flit_rx_valid,

    // Outputs
    output reg  [2049:0] flit_tx_with_hdr,
    output reg  [1:0]    sync_hdr_tx,
    output reg           sync_hdr_rx_ok,
    output reg           sync_hdr_rx_err,
    output wire          flit_lock
);

    // ----------------------------------------------------------
    // Sync header values
    // ----------------------------------------------------------
    localparam HDR_DATA = 2'b01;
    localparam HDR_OS   = 2'b10;

    // ----------------------------------------------------------
    // Lock / unlock thresholds
    // ----------------------------------------------------------
    localparam LOCK_THR   = 4'd8;
    localparam UNLOCK_THR = 4'd4;

    // ----------------------------------------------------------
    // Internal state
    // ----------------------------------------------------------
    reg [3:0] lock_cnt;     // counts valid RX headers toward lock
    reg [3:0] err_cnt;      // counts invalid RX headers toward unlock
    reg       locked_r;     // registered lock state

    // flit_lock reflects locked_r combinatorially (no extra cycle lag)
    assign flit_lock = locked_r;

    // ----------------------------------------------------------
    // Combinatorial RX header validity
    // ----------------------------------------------------------
    wire rx_hdr_ok  = (sync_hdr_rx == HDR_DATA) || (sync_hdr_rx == HDR_OS);
    wire rx_hdr_err = ~rx_hdr_ok;

    // ----------------------------------------------------------
    // Combinatorial TX header selection
    // ----------------------------------------------------------
    wire [1:0] tx_hdr_comb = flit_tx_valid ? HDR_DATA : HDR_OS;

    // ----------------------------------------------------------
    // Sequential logic
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            flit_tx_with_hdr <= 2050'b0;
            sync_hdr_tx      <= 2'b00;
            sync_hdr_rx_ok   <= 1'b0;
            sync_hdr_rx_err  <= 1'b0;
            locked_r         <= 1'b0;
            lock_cnt         <= 4'b0;
            err_cnt          <= 4'b0;
        end else begin

            // -- TX: prepend header every cycle ----------------
            sync_hdr_tx      <= tx_hdr_comb;
            flit_tx_with_hdr <= {tx_hdr_comb, flit_tx};

            // -- RX: check header and run lock FSM -------------
            sync_hdr_rx_ok  <= 1'b0;
            sync_hdr_rx_err <= 1'b0;

            if (flit_rx_valid) begin
                if (rx_hdr_ok) begin
                    // Valid header received
                    sync_hdr_rx_ok <= 1'b1;
                    err_cnt        <= 4'b0;

                    if (!locked_r) begin
                        // Not yet locked: increment toward lock threshold
                        if (lock_cnt == LOCK_THR - 1) begin
                            locked_r <= 1'b1;
                            lock_cnt <= 4'b0;
                        end else begin
                            lock_cnt <= lock_cnt + 1'b1;
                        end
                    end
                    // Already locked: stay locked, err_cnt already cleared

                end else begin
                    // Invalid header received
                    sync_hdr_rx_err <= 1'b1;
                    lock_cnt        <= 4'b0;

                    if (locked_r) begin
                        // Currently locked: count toward unlock threshold
                        if (err_cnt == UNLOCK_THR - 1) begin
                            locked_r <= 1'b0;
                            err_cnt  <= 4'b0;
                        end else begin
                            err_cnt <= err_cnt + 1'b1;
                        end
                    end
                    // Not locked: stay unlocked
                end
            end

        end
    end

endmodule
