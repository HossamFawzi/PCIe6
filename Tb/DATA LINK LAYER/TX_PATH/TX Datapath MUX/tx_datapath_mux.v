
`timescale 1ns / 1ps

module tx_datapath_mux (

    input  wire          clk,
    input  wire          rst_n,

    input  wire [1055:0] tlp_tx,
    input  wire          tlp_tx_valid,

    input  wire [1055:0] retry_tlp,
    input  wire          retry_valid,

    input  wire [63:0]   dllp_out,
    input  wire          dllp_valid,

    input  wire          retry_req,

    output reg  [255:0]  phy_tx_data,
    output reg           phy_tx_valid,
    output reg           phy_tx_sop,
    output reg           phy_tx_eop
);

    localparam TLP_BEATS  = 5;

    localparam DLLP_BEATS = 1;

    localparam [2:0]
        S_IDLE      = 3'b001,
        S_TLP_SEND  = 3'b010,
        S_DLLP_SEND = 3'b100;

    localparam [1:0]
        SRC_NONE  = 2'b00,
        SRC_RETRY = 2'b01,
        SRC_TLP   = 2'b10,
        SRC_DLLP  = 2'b11;

    reg  [2:0]    state, next_state;

    reg  [1055:0] tlp_reg;
    reg  [63:0]   dllp_reg;
    reg  [1:0]    src_reg;

    reg  [2:0]    beat_cnt;
    wire [2:0]    beat_cnt_max;

    wire [255:0]  tlp_slice;

    wire [1:0]    arb_winner;

    assign arb_winner = (retry_valid || retry_req) ? SRC_RETRY :
                        tlp_tx_valid               ? SRC_TLP   :
                        dllp_valid                 ? SRC_DLLP  :
                                                     SRC_NONE  ;

    assign beat_cnt_max = (src_reg == SRC_DLLP) ? (DLLP_BEATS - 1) :
                                                    (TLP_BEATS  - 1) ;

    assign tlp_slice = (beat_cnt == 3'd0) ? tlp_reg[255:0]   :
                       (beat_cnt == 3'd1) ? tlp_reg[511:256]  :
                       (beat_cnt == 3'd2) ? tlp_reg[767:512]  :
                       (beat_cnt == 3'd3) ? tlp_reg[1023:768] :
                                            {tlp_reg[1055:1024], {224{1'b0}}} ;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        case (state)
            S_IDLE: begin
                if (arb_winner == SRC_DLLP)
                    next_state = S_DLLP_SEND;
                else if (arb_winner != SRC_NONE)
                    next_state = S_TLP_SEND;
                else
                    next_state = S_IDLE;
            end

            S_TLP_SEND: begin

                if (beat_cnt == beat_cnt_max)
                    next_state = S_IDLE;
                else
                    next_state = S_TLP_SEND;
            end

            S_DLLP_SEND: begin

                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_reg  <= {1056{1'b0}};
            dllp_reg <= 64'h0;
            src_reg  <= SRC_NONE;
        end
        else if (state == S_IDLE && arb_winner != SRC_NONE) begin
            src_reg <= arb_winner;
            case (arb_winner)
                SRC_RETRY: tlp_reg <= retry_tlp;
                SRC_TLP:   tlp_reg <= tlp_tx;
                SRC_DLLP:  dllp_reg <= dllp_out;
                default: ;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            beat_cnt <= 3'd0;
        else if (state == S_IDLE)
            beat_cnt <= 3'd0;
        else if (state == S_TLP_SEND || state == S_DLLP_SEND)
            beat_cnt <= (beat_cnt == beat_cnt_max) ? 3'd0 : beat_cnt + 1'b1;
    end

    always @(*) begin

        phy_tx_data  = 256'h0;
        phy_tx_valid = 1'b0;
        phy_tx_sop   = 1'b0;
        phy_tx_eop   = 1'b0;

        case (state)

            S_TLP_SEND: begin
                phy_tx_valid = 1'b1;
                phy_tx_data  = tlp_slice;
                phy_tx_sop   = (beat_cnt == 3'd0);
                phy_tx_eop   = (beat_cnt == beat_cnt_max);
            end

            S_DLLP_SEND: begin
                phy_tx_valid = 1'b1;
                phy_tx_data  = {dllp_reg, {192{1'b0}}};
                phy_tx_sop   = 1'b1;
                phy_tx_eop   = 1'b1;
            end

            default: begin

            end
        endcase
    end

endmodule
