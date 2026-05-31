
module rx_det (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        detect_start,
    input  wire        pipe_rx_elec_idle,
    input  wire        pipe_phystatus,
    input  wire [15:0] detect_timeout_val,

    output reg          receiver_detected,
    output reg  [15:0]  lanes_det,
    output reg          detect_done,
    output reg          detect_timeout
);

localparam S_IDLE    = 3'd0;
localparam S_START   = 3'd1;
localparam S_WAIT    = 3'd2;
localparam S_SAMPLE  = 3'd3;
localparam S_DONE    = 3'd4;
localparam S_TIMEOUT = 3'd5;

reg [2:0]  state;
reg [15:0] timeout_cnt;
reg        phystatus_seen;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        receiver_detected <= 1'b0;
        lanes_det         <= 16'd0;
        detect_done       <= 1'b0;
        detect_timeout    <= 1'b0;
        state             <= S_IDLE;
        timeout_cnt       <= 16'd0;
        phystatus_seen    <= 1'b0;
    end else begin
        detect_done    <= 1'b0;
        detect_timeout <= 1'b0;

        case (state)
            S_IDLE: begin
                receiver_detected <= 1'b0;
                lanes_det         <= 16'd0;
                if (detect_start)
                    state <= S_START;
            end

            S_START: begin

                timeout_cnt    <= 16'd0;
                phystatus_seen <= 1'b0;
                state          <= S_WAIT;
            end

            S_WAIT: begin

                if (pipe_phystatus) begin
                    phystatus_seen <= 1'b1;
                    state          <= S_SAMPLE;
                end else if (timeout_cnt >= detect_timeout_val) begin
                    state <= S_TIMEOUT;
                end else begin
                    timeout_cnt <= timeout_cnt + 16'd1;
                end
            end

            S_SAMPLE: begin

                if (!pipe_rx_elec_idle) begin
                    receiver_detected <= 1'b1;
                    lanes_det         <= 16'hFFFF;
                end else begin
                    receiver_detected <= 1'b0;
                    lanes_det         <= 16'h0000;
                end
                state <= S_DONE;
            end

            S_DONE: begin
                detect_done <= 1'b1;
                state       <= S_IDLE;
            end

            S_TIMEOUT: begin
                detect_timeout    <= 1'b1;
                receiver_detected <= 1'b0;
                lanes_det         <= 16'd0;
                detect_done       <= 1'b1;
                state             <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
