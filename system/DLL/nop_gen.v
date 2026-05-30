// =============================================================================
// PCIe Gen6 DLL Support Block: NOP DLLP Generator (NOP_GEN)
// =============================================================================
module nop_gen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        dll_active,
    input  wire        nop_timer_exp,
    input  wire        nop_inhibit,
    output wire        nop_send,
    output reg  [63:0] nop_dllp,
    output reg  [7:0]  nop_count
);
    localparam NOP_TYPE = 8'h31; // BUG FIX: NOP=0x31 per spec (not 0x00=ACK)

    // nop_send is combinational so the TB can check it on the same posedge
    // that nop_timer_exp is applied
    assign nop_send = dll_active && nop_timer_exp && !nop_inhibit;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            nop_dllp  <= 64'd0;
            nop_count <= 8'd0;
        end else begin
            if (dll_active && nop_timer_exp && !nop_inhibit) begin
                nop_dllp  <= {NOP_TYPE, 56'd0};
                nop_count <= nop_count + 1'b1;
            end
        end
    end
endmodule
