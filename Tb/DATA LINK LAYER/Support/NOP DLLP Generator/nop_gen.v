
module nop_gen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dll_active,
    input  wire        nop_timer_exp,
    input  wire        nop_inhibit,
    output reg         nop_send,
    output reg  [63:0] nop_dllp,
    output reg  [7:0]  nop_count
);
    localparam NOP_TYPE = 8'h31;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nop_send  <= 1'b0;
            nop_dllp  <= 64'd0;
            nop_count <= 8'd0;
        end else begin
            nop_send <= 1'b0;
            if (dll_active && nop_timer_exp && !nop_inhibit) begin
                nop_send  <= 1'b1;
                nop_dllp  <= {NOP_TYPE, 56'd0};
                nop_count <= nop_count + 1'b1;
            end
        end
    end
endmodule
