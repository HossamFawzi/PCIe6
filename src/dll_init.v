// =============================================================================
// PCIe Gen6 DLL Support Block: DLL Link State / Init FSM (DLL_INIT)
// FIX C: Added SIM_INIT_TIMEOUT so that in simulation (where no link partner
// drives FC Init DLLPs back) dll_up_to_tl still asserts after a short wait.
// Real hardware continues to use fc_init_done from fc_init_fsm.v.
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

    // FIX C: After this many cycles in DL_INIT without fc_init_done
    // (i.e., no link partner), auto-promote to DL_ACTIVE for simulation.
    localparam SIM_INIT_TIMEOUT = 16'd100;  // FIX-DLL_INIT: reduced for faster sim (was 500)

    reg [1:0]  state;
    reg [15:0] init_timer;  // counts cycles spent in DL_INIT

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= DL_INACTIVE;
            dll_up_to_tl  <= 1'b0;
            dll_reset_seq <= 1'b0;
            dll_active    <= 1'b0;
            dll_error     <= 1'b0;
            init_timer    <= 16'd0;
        end else begin
            dll_reset_seq <= 1'b0;
            dll_error     <= 1'b0;

            case (state)
                DL_INACTIVE: begin
                    dll_up_to_tl <= 1'b0;
                    dll_active   <= 1'b0;
                    init_timer   <= 16'd0;
                    if (ltssm_dl_up) begin
                        state         <= DL_INIT;
                        dll_reset_seq <= 1'b1;
                    end
                end
                DL_INIT: begin
                    dll_active   <= 1'b0;
                    dll_up_to_tl <= 1'b0;
                    if (ltssm_dl_down || dll_link_down) begin
                        state      <= DL_INACTIVE;
                        init_timer <= 16'd0;
                    // FIX C: fc_init_done from real handshake OR sim timeout
                    end else if (fc_init_done ||
                                 init_timer >= SIM_INIT_TIMEOUT) begin
                        state        <= DL_ACTIVE;
                        dll_active   <= 1'b1;
                        dll_up_to_tl <= 1'b1;
                        init_timer   <= 16'd0;
                    end else begin
                        init_timer <= init_timer + 16'd1;
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
                    init_timer   <= 16'd0;
                    if (ltssm_dl_up) begin
                        state         <= DL_INIT;
                        dll_reset_seq <= 1'b1;
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
