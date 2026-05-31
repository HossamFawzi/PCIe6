module DLL_IF (
    input               clk,
    input               rst_n,

    input      [2047:0] flit_in,
    input               flit_valid_in,

    input               dll_ack,
    input               dll_nak,
    input               dll_up,
    input      [71:0]   cr_update,
    input               cr_update_valid,

    output reg [1023:0] tlp_rx_out,
    output reg          tlp_rx_valid,

    output reg [2047:0] flit_to_dll,
    output reg          flit_to_dll_valid,
    output reg          dll_ready
);

parameter TIMEOUT_MAX = 200;
parameter RETRY_MAX   = 4;

reg [1:0] state;
localparam IDLE     = 2'b00;
localparam SEND     = 2'b01;
localparam WAIT_ACK = 2'b10;
localparam REPLAY   = 2'b11;

reg [2047:0] replay_buffer;
reg [15:0]   timeout_cnt;
reg [2:0]    retry_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state             <= IDLE;
        flit_to_dll_valid <= 1'b0;
        flit_to_dll       <= 2048'h0;
        dll_ready         <= 1'b0;
        timeout_cnt       <= 16'h0;
        retry_cnt         <= 3'h0;
        tlp_rx_valid      <= 1'b0;
        tlp_rx_out        <= 1024'h0;
        replay_buffer     <= 2048'h0;
    end
    else begin

        dll_ready         <= dll_up;
        flit_to_dll_valid <= 1'b0;
        tlp_rx_valid      <= 1'b0;

        if (!dll_up) begin
            state       <= IDLE;
            retry_cnt   <= 3'h0;
            timeout_cnt <= 16'h0;
        end
        else begin

            case (state)

                IDLE: begin
                    timeout_cnt <= 16'h0;
                    if (flit_valid_in) begin
                        replay_buffer <= flit_in;
                        retry_cnt     <= 3'h0;
                        state         <= SEND;
                    end
                end

                SEND: begin
                    flit_to_dll       <= replay_buffer;
                    flit_to_dll_valid <= 1'b1;
                    timeout_cnt       <= 16'h0;
                    state             <= WAIT_ACK;
                end

                WAIT_ACK: begin
                    timeout_cnt <= timeout_cnt + 16'h1;
                    if (dll_ack) begin
                        timeout_cnt <= 16'h0;
                        state       <= IDLE;
                    end
                    else if (dll_nak) begin
                        timeout_cnt <= 16'h0;
                        state       <= REPLAY;
                    end
                    else if (timeout_cnt >= TIMEOUT_MAX) begin
                        timeout_cnt <= 16'h0;
                        state       <= REPLAY;
                    end
                end

                REPLAY: begin
                    if (retry_cnt < RETRY_MAX) begin
                        retry_cnt <= retry_cnt + 3'h1;
                        state     <= SEND;
                    end
                    else begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;

            endcase
        end

        if (cr_update_valid) begin
            tlp_rx_out   <= cr_update[63:0];
            tlp_rx_valid <= 1'b1;
        end

    end
end
endmodule