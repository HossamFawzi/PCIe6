
module tmo_err_manager #(
    parameter MAX_TAGS = 1024
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [9:0]   tag_start,
    input  wire         tag_start_valid,
    input  wire         tag_return_valid,
    input  wire [9:0]   tag_returned,

    input  wire [15:0]  timeout_limit,

    output reg  [9:0]   timeout_tag,
    output reg          timeout_valid,
    output reg          cpl_timeout_err,
    output reg  [3:0]   err_to_aer
);

    reg [15:0] timer [0:MAX_TAGS-1];
    reg        active[0:MAX_TAGS-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_TAGS; i = i + 1) begin
                timer [i] <= 16'h0;
                active[i] <= 1'b0;
            end
            timeout_valid    <= 1'b0;
            timeout_tag      <= 10'h0;
            cpl_timeout_err  <= 1'b0;
            err_to_aer       <= 4'h0;
        end
        else begin

            timeout_valid <= 1'b0;

            if (tag_start_valid) begin
                timer [tag_start] <= timeout_limit;
                active[tag_start] <= 1'b1;
            end

            if (tag_return_valid) begin
                active[tag_returned] <= 1'b0;
                timer [tag_returned] <= 16'h0;
            end

            for (i = 0; i < MAX_TAGS; i = i + 1) begin
                if (active[i]) begin
                    if (timer[i] == 16'h1) begin

                        timer[i]        <= 16'h0;
                        active[i]       <= 1'b0;
                        timeout_tag     <= i[9:0];
                        timeout_valid   <= 1'b1;
                        cpl_timeout_err <= 1'b1;
                        err_to_aer      <= 4'h1;
                    end
                    else if (timer[i] > 16'h1) begin
                        timer[i] <= timer[i] - 16'h1;
                    end
                end
            end
        end
    end

endmodule
