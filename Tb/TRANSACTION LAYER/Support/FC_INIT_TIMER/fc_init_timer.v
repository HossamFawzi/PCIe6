
module fc_init_timer (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         fc_init_start,
    input  wire         fc_init_done,
    input  wire [15:0]  fc_init_timeout_val,

    output reg          fc_init_timeout,
    output reg          fc_init_retry_req,
    output reg          fc_init_err
);

    localparam MAX_RETRIES = 3;

    localparam [1:0]
        S_IDLE    = 2'b00,
        S_RUNNING = 2'b01,
        S_RETRY   = 2'b10,
        S_ERROR   = 2'b11;

    reg [1:0]  state;
    reg [15:0] counter;
    reg [1:0]  retry_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            counter          <= 16'h0;
            retry_cnt        <= 2'h0;
            fc_init_timeout  <= 1'b0;
            fc_init_retry_req<= 1'b0;
            fc_init_err      <= 1'b0;
        end
        else begin

            fc_init_timeout  <= 1'b0;
            fc_init_retry_req<= 1'b0;

            case (state)

                S_IDLE: begin
                    counter   <= fc_init_timeout_val;
                    retry_cnt <= 2'h0;
                    if (fc_init_start)
                        state <= S_RUNNING;
                end

                S_RUNNING: begin
                    if (fc_init_done) begin

                        state   <= S_IDLE;
                        counter <= 16'h0;
                    end
                    else if (counter == 16'h1) begin

                        fc_init_timeout <= 1'b1;
                        counter         <= 16'h0;
                        state           <= S_RETRY;
                    end
                    else begin
                        counter <= counter - 16'h1;
                    end
                end

                S_RETRY: begin
                    if (retry_cnt < MAX_RETRIES[1:0]) begin
                        retry_cnt        <= retry_cnt + 2'h1;
                        fc_init_retry_req<= 1'b1;
                        counter          <= fc_init_timeout_val;
                        state            <= S_RUNNING;
                    end
                    else begin
                        fc_init_err <= 1'b1;
                        state       <= S_ERROR;
                    end
                end

                S_ERROR: begin
                    fc_init_err <= 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
