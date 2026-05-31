
module cpl_timeout_logic #(
    parameter MAX_TAGS = 1024
)(
    input  wire         clk,
    input  wire         rst_n,

    input  wire [9:0]   tag_alloc,
    input  wire         tag_alloc_valid,

    input  wire [9:0]   tag_return,
    input  wire         tag_return_valid,

    input  wire [19:0]  cpl_timeout_val,

    output reg  [9:0]   timeout_tag,
    output reg          timeout_fired,
    output reg          cpl_abort_req,
    output reg  [3:0]   err_to_aer
);

    reg [19:0] cnt  [0:MAX_TAGS-1];
    reg        live [0:MAX_TAGS-1];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < MAX_TAGS; i = i + 1) begin
                cnt [i] <= 20'h0;
                live[i] <= 1'b0;
            end
            timeout_tag   <= 10'h0;
            timeout_fired <= 1'b0;
            cpl_abort_req <= 1'b0;
            err_to_aer    <= 4'h0;
        end
        else begin

            timeout_fired <= 1'b0;
            cpl_abort_req <= 1'b0;
            err_to_aer    <= 4'h0;

            if (tag_alloc_valid) begin
                cnt [tag_alloc] <= cpl_timeout_val;
                live[tag_alloc] <= 1'b1;
            end

            if (tag_return_valid) begin
                live[tag_return] <= 1'b0;
                cnt [tag_return] <= 20'h0;
            end

            for (i = 0; i < MAX_TAGS; i = i + 1) begin

                if (live[i] && !(tag_alloc_valid && tag_alloc == i[9:0])
                             && !(tag_return_valid && tag_return == i[9:0])) begin
                    if (cnt[i] == 20'h1) begin

                        cnt[i]        <= 20'h0;
                        live[i]       <= 1'b0;
                        timeout_tag   <= i[9:0];
                        timeout_fired <= 1'b1;
                        cpl_abort_req <= 1'b1;
                        err_to_aer    <= 4'hE;
                    end
                    else begin
                        cnt[i] <= cnt[i] - 20'h1;
                    end
                end
            end
        end
    end

endmodule
