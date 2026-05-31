
`timescale 1ns/1ps

module pcie_ordering_rob #(
    parameter ROB_DEPTH     = 32,
    parameter ROB_PTR_WIDTH = 5,
    parameter NUM_TC        = 8
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] req_id,
    input  wire [3:0]  req_type,
    input  wire [2:0]  req_tc,
    input  wire        req_attr_ro,
    input  wire        req_valid,

    input  wire [15:0] cpl_id,
    input  wire        cpl_valid,

    output wire        ordering_ok,
    output wire        ordering_stall,
    output wire        ordering_err
);

    localparam TYPE_MWR32  = 4'h0;
    localparam TYPE_MWR64  = 4'h1;
    localparam TYPE_MSG    = 4'h2;
    localparam TYPE_MSGD   = 4'h3;
    localparam TYPE_MRD32  = 4'h4;
    localparam TYPE_MRD64  = 4'h5;
    localparam TYPE_IORD   = 4'h6;
    localparam TYPE_IOWR   = 4'h7;
    localparam TYPE_CFGRD0 = 4'h8;
    localparam TYPE_CFGWR0 = 4'h9;
    localparam TYPE_CFGRD1 = 4'hA;
    localparam TYPE_CFGWR1 = 4'hB;
    localparam TYPE_CPL    = 4'hC;
    localparam TYPE_CPLD   = 4'hD;
    localparam TYPE_CPLLK  = 4'hE;
    localparam TYPE_RSVD   = 4'hF;

    localparam CLASS_P   = 2'b00;
    localparam CLASS_NP  = 2'b01;
    localparam CLASS_CPL = 2'b10;
    localparam CLASS_INV = 2'b11;

    localparam ROB_W = 23;

    reg [ROB_W-1:0]         rob_mem  [0:ROB_DEPTH-1];
    reg [ROB_PTR_WIDTH-1:0] rob_tail;
    reg [ROB_PTR_WIDTH:0]   rob_count;
    reg [NUM_TC-1:0]        posted_pending;

    function automatic [1:0] get_tlp_class;
        input [3:0] t;
        case (t)
            TYPE_MWR32, TYPE_MWR64,
            TYPE_MSG,   TYPE_MSGD   : get_tlp_class = CLASS_P;
            TYPE_MRD32, TYPE_MRD64,
            TYPE_IORD,  TYPE_IOWR,
            TYPE_CFGRD0,TYPE_CFGWR0,
            TYPE_CFGRD1,TYPE_CFGWR1 : get_tlp_class = CLASS_NP;
            TYPE_CPL,   TYPE_CPLD,
            TYPE_CPLLK              : get_tlp_class = CLASS_CPL;
            default                 : get_tlp_class = CLASS_INV;
        endcase
    endfunction

    wire rob_full  = (rob_count == ROB_DEPTH[ROB_PTR_WIDTH:0]);
    wire rob_empty = (rob_count == 0);
    wire [1:0] req_class = get_tlp_class(req_type);
    wire posted_pend_this_tc = posted_pending[req_tc];

    reg np_pend_this_tc;
    always @(*) begin : np_scan
        integer k;
        np_pend_this_tc = 1'b0;
        for (k = 0; k < ROB_DEPTH; k = k + 1)
            if (rob_mem[k][22] &&
                rob_mem[k][21:20] == CLASS_NP &&
                rob_mem[k][18:16] == req_tc)
                np_pend_this_tc = 1'b1;
    end

    reg cpl_found_np;
    always @(*) begin : cpl_scan
        integer k;
        cpl_found_np = 1'b0;
        for (k = 0; k < ROB_DEPTH; k = k + 1)
            if (rob_mem[k][22] &&
                rob_mem[k][21:20] == CLASS_NP &&
                rob_mem[k][15:0]  == cpl_id)
                cpl_found_np = 1'b1;
    end

    reg order_ok_comb;
    reg order_stall_comb;
    reg order_err_comb;

    always @(*) begin : ordering_logic
        order_ok_comb    = 1'b1;
        order_stall_comb = 1'b0;
        order_err_comb   = 1'b0;

        if (req_valid) begin

            case (req_class)

                CLASS_P: begin

                    order_ok_comb    = 1'b1;
                    order_stall_comb = 1'b0;
                end

                CLASS_NP: begin
                    if ((posted_pend_this_tc && !req_attr_ro) ||
                        (np_pend_this_tc     && !req_attr_ro) ||
                        rob_full)
                        order_stall_comb = 1'b1;
                    else
                        order_ok_comb = 1'b1;
                end

                CLASS_CPL: begin
                    if (cpl_valid && !rob_empty && !cpl_found_np)
                        order_err_comb = 1'b1;
                    else
                        order_ok_comb = 1'b1;
                end

                CLASS_INV: begin
                    order_err_comb = 1'b1;
                end

                default: order_ok_comb = 1'b0;
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin : rob_seq
        integer k;
        if (!rst_n) begin
            rob_tail       <= {ROB_PTR_WIDTH{1'b0}};
            rob_count      <= {(ROB_PTR_WIDTH+1){1'b0}};
            posted_pending <= {NUM_TC{1'b0}};
            for (k = 0; k < ROB_DEPTH; k = k + 1)
                rob_mem[k] <= {ROB_W{1'b0}};
        end else begin

            if (req_valid && !order_stall_comb && (req_class == CLASS_NP)) begin
                rob_mem[rob_tail] <= {1'b1, CLASS_NP, req_attr_ro, req_tc, req_id};
                rob_tail          <= rob_tail + 1'b1;
                rob_count         <= rob_count + 1'b1;
            end

            if (req_valid && !order_stall_comb && (req_class == CLASS_P)) begin

                posted_pending[req_tc] <= 1'b1;

                begin : clear_other_tc
                    integer j;
                    for (j = 0; j < NUM_TC; j = j + 1)
                        if ($unsigned(j) != req_tc)
                            posted_pending[j] <= 1'b0;
                end
            end else begin

                posted_pending <= {NUM_TC{1'b0}};
            end

            if (cpl_valid && !rob_empty) begin
                for (k = 0; k < ROB_DEPTH; k = k + 1) begin
                    if (rob_mem[k][22] &&
                        rob_mem[k][21:20] == CLASS_NP &&
                        rob_mem[k][15:0]  == cpl_id) begin
                        rob_mem[k][22] <= 1'b0;
                        rob_count      <= rob_count - 1'b1;
                    end
                end
            end

        end
    end

    assign ordering_ok    = order_ok_comb;
    assign ordering_stall = order_stall_comb;
    assign ordering_err   = order_err_comb;

endmodule
