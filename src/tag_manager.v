
`timescale 1ns/1ps

module tag_manager #(parameter TAG_POOL_SIZE = 64) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         tag_req,

    input  wire [9:0]   tag_return,
    input  wire         tag_return_valid,

    input  wire [9:0]   timeout_tag,

    output reg  [9:0]   tag_alloc,
    output reg          tag_valid,
    output wire         tag_exhausted,
    output reg  [9:0]   outstanding_count,

    output reg  [63:0]  req_addr_lkup,
    output reg  [9:0]   req_len_lkup,
    output reg  [3:0]   req_type_lkup
);

reg [TAG_POOL_SIZE-1:0] free_bitmap;
reg [10:0]   outstanding_int;
reg [9:0]    prev_timeout_tag;

reg [63:0] store_addr [0:TAG_POOL_SIZE-1];
reg [9:0]  store_len  [0:TAG_POOL_SIZE-1];
reg [3:0]  store_type [0:TAG_POOL_SIZE-1];

function [9:0] find_free_tag;
    input [TAG_POOL_SIZE-1:0] bmap;
    integer i;
    begin
        find_free_tag = 10'd0;
        for (i = TAG_POOL_SIZE-1; i >= 0; i = i - 1)
            if (bmap[i])
                find_free_tag = i[9:0];
    end
endfunction

wire [9:0] next_free = find_free_tag(free_bitmap);
wire       any_free  = |free_bitmap;

assign tag_exhausted = !any_free;

wire timeout_valid = (timeout_tag != 10'd0) &&
                     (timeout_tag != prev_timeout_tag);

integer j;

reg do_alloc, do_ret, do_tout;
reg [10:0] next_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        free_bitmap       <= {TAG_POOL_SIZE{1'b1}};
        tag_alloc         <= 10'd0;
        tag_valid         <= 1'b0;
        outstanding_int   <= 11'd0;
        outstanding_count <= 10'd0;
        req_addr_lkup     <= 64'd0;
        req_len_lkup      <= 10'd0;
        req_type_lkup     <= 4'd0;
        prev_timeout_tag  <= 10'd0;
        for (j = 0; j < TAG_POOL_SIZE; j = j + 1) begin
            store_addr[j] <= 64'd0;
            store_len[j]  <= 10'd0;
            store_type[j] <= 4'd0;
        end
    end else begin

        tag_valid        <= 1'b0;
        prev_timeout_tag <= timeout_tag;

        do_alloc = tag_req && any_free;
        do_ret   = tag_return_valid && !free_bitmap[tag_return];
        do_tout  = timeout_valid    && !free_bitmap[timeout_tag];

        if (do_ret) begin
            free_bitmap[tag_return] <= 1'b1;
            store_addr[tag_return]  <= 64'd0;
            store_len[tag_return]   <= 10'd0;
            store_type[tag_return]  <= 4'd0;
        end

        if (do_tout) begin
            free_bitmap[timeout_tag] <= 1'b1;
            store_addr[timeout_tag]  <= 64'd0;
            store_len[timeout_tag]   <= 10'd0;
            store_type[timeout_tag]  <= 4'd0;
        end

        if (do_alloc) begin
            free_bitmap[next_free] <= 1'b0;
            tag_alloc              <= next_free;
            tag_valid              <= 1'b1;
            req_addr_lkup          <= store_addr[next_free];
            req_len_lkup           <= store_len[next_free];
            req_type_lkup          <= store_type[next_free];
        end

        next_cnt = outstanding_int;
        if (do_alloc) next_cnt = next_cnt + 11'd1;
        if (do_ret)   next_cnt = next_cnt - 11'd1;
        if (do_tout)  next_cnt = next_cnt - 11'd1;

        outstanding_int   <= next_cnt;
        outstanding_count <= (next_cnt[10:1] >= TAG_POOL_SIZE[10:1]) ? 10'd63 : next_cnt[9:0];

    end
end

endmodule
