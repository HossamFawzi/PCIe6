
module flit_sync_hdr_gen_checker (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [2047:0] flit_tx,
    input  wire          flit_tx_valid,

    input  wire [2047:0] flit_rx,
    input  wire [1:0]    sync_hdr_rx,
    input  wire          flit_rx_valid,

    output reg  [2049:0] flit_tx_with_hdr,
    output reg  [1:0]    sync_hdr_tx,
    output reg           sync_hdr_rx_ok,
    output reg           sync_hdr_rx_err,
    output wire          flit_lock
);

    localparam HDR_DATA = 2'b01;
    localparam HDR_OS   = 2'b10;

    localparam LOCK_THR   = 4'd8;
    localparam UNLOCK_THR = 4'd4;

    reg [3:0] lock_cnt;
    reg [3:0] err_cnt;
    reg       locked_r;

    assign flit_lock = locked_r;

    wire rx_hdr_ok  = (sync_hdr_rx == HDR_DATA) || (sync_hdr_rx == HDR_OS);
    wire rx_hdr_err = ~rx_hdr_ok;

    wire [1:0] tx_hdr_comb = flit_tx_valid ? HDR_DATA : HDR_OS;

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

            sync_hdr_tx      <= tx_hdr_comb;
            flit_tx_with_hdr <= {tx_hdr_comb, flit_tx};

            sync_hdr_rx_ok  <= 1'b0;
            sync_hdr_rx_err <= 1'b0;

            if (flit_rx_valid) begin
                if (rx_hdr_ok) begin

                    sync_hdr_rx_ok <= 1'b1;
                    err_cnt        <= 4'b0;

                    if (!locked_r) begin

                        if (lock_cnt == LOCK_THR - 1) begin
                            locked_r <= 1'b1;
                            lock_cnt <= 4'b0;
                        end else begin
                            lock_cnt <= lock_cnt + 1'b1;
                        end
                    end

                end else begin

                    sync_hdr_rx_err <= 1'b1;
                    lock_cnt        <= 4'b0;

                    if (locked_r) begin

                        if (err_cnt == UNLOCK_THR - 1) begin
                            locked_r <= 1'b0;
                            err_cnt  <= 4'b0;
                        end else begin
                            err_cnt <= err_cnt + 1'b1;
                        end
                    end

                end
            end

        end
    end

endmodule
