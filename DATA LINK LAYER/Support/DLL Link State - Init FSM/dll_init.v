// =============================================================================
// PCIe Gen6 DLL Support Block: DLL Link State / Init FSM (DLL_INIT)
// =============================================================================
module dll_init (
    input  wire clk,
    input  wire rst_n,
    input  wire ltssm_dl_up,
    input  wire ltssm_dl_down,
    input  wire fc_init_done,
    input  wire replay_rollover_err,
    input  wire dll_link_down,
    output reg  dll_up_to_tl,
    output reg  dll_reset_seq,
    output reg  dll_active,
    output reg  dll_error
);
    localparam DL_INACTIVE = 2'd0;
    localparam DL_INIT     = 2'd1;
    localparam DL_ACTIVE   = 2'd2;
    localparam DL_ERROR    = 2'd3;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= DL_INACTIVE;
            dll_up_to_tl  <= 1'b0;
            dll_reset_seq <= 1'b0;
            dll_active    <= 1'b0;
            dll_error     <= 1'b0;
        end else begin
            // dll_reset_seq is a one-cycle pulse; clear every cycle by default
            dll_reset_seq <= 1'b0;
            dll_error     <= 1'b0;

            case (state)
                DL_INACTIVE: begin
                    dll_up_to_tl <= 1'b0;
                    dll_active   <= 1'b0;
                    if (ltssm_dl_up) begin
                        state         <= DL_INIT;
                        dll_reset_seq <= 1'b1;   // pulse on entry
                    end
                end
                DL_INIT: begin
                    dll_active   <= 1'b0;
                    dll_up_to_tl <= 1'b0;
                    if (ltssm_dl_down || dll_link_down) begin
                        state <= DL_INACTIVE;
                    end else if (fc_init_done) begin
                        state        <= DL_ACTIVE;
                        dll_active   <= 1'b1;
                        dll_up_to_tl <= 1'b1;
                    end
                end
                DL_ACTIVE: begin
                    dll_active   <= 1'b1;
                    dll_up_to_tl <= 1'b1;
                    if (ltssm_dl_down || dll_link_down || replay_rollover_err) begin
                        state        <= DL_ERROR;
                        dll_active   <= 1'b0;
                        dll_up_to_tl <= 1'b0;
                        dll_error    <= 1'b1;
                    end
                end
                DL_ERROR: begin
                    dll_error    <= 1'b1;
                    dll_up_to_tl <= 1'b0;
                    dll_active   <= 1'b0;
                    if (ltssm_dl_up) begin
                        state         <= DL_INIT;
                        dll_reset_seq <= 1'b1;   // pulse on re-init
                        dll_error     <= 1'b0;
                    end else if (ltssm_dl_down) begin
                        state <= DL_INACTIVE;
                    end
                end
                default: state <= DL_INACTIVE;
            endcase
        end
    end
endmodule
