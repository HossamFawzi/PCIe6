
module tx_elastic_buffer #(
    parameter DATA_WIDTH = 256,
    parameter DEPTH      = 16,
    parameter ADDR_W     = 4
)(

    input  wire                  clk_core,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  data_valid,
    input  wire                  skp_insert_req,

    input  wire                  clk_pipe,
    input  wire                  pipe_ready,
    input  wire                  skp_remove_req,

    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   data_out_valid,
    output wire                  buf_full,
    output wire                  buf_empty,
    output wire                  buf_half,
    output reg                   skp_inserted,
    output reg                   skp_removed,
    output wire [ADDR_W:0]       fill_level
);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

reg [ADDR_W:0] wr_ptr;

reg [ADDR_W:0] rd_ptr;

reg [ADDR_W:0] wr_ptr_gray;
reg [ADDR_W:0] rd_ptr_gray;

reg [ADDR_W:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
reg [ADDR_W:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;

reg [ADDR_W:0] wr_ptr_sync_bin;
reg [ADDR_W:0] rd_ptr_sync_bin;

localparam [DATA_WIDTH-1:0] SKP_OS_PATTERN = {(DATA_WIDTH/8){8'hAA}};

function [ADDR_W:0] bin2gray;
    input [ADDR_W:0] bin;
    begin
        bin2gray = bin ^ (bin >> 1);
    end
endfunction

function [ADDR_W:0] gray2bin;
    input [ADDR_W:0] gray;
    integer i;
    reg [ADDR_W:0] tmp;
    begin
        tmp[ADDR_W] = gray[ADDR_W];
        for (i = ADDR_W-1; i >= 0; i = i-1)
            tmp[i] = tmp[i+1] ^ gray[i];
        gray2bin = tmp;
    end
endfunction

always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr       <= {(ADDR_W+1){1'b0}};
        wr_ptr_gray  <= {(ADDR_W+1){1'b0}};
        skp_inserted <= 1'b0;
    end else begin
        skp_inserted <= 1'b0;
        if (skp_insert_req && !buf_full) begin

            mem[wr_ptr[ADDR_W-1:0]] <= SKP_OS_PATTERN;
            wr_ptr      <= wr_ptr + 1'b1;
            wr_ptr_gray <= bin2gray(wr_ptr + 1'b1);
            skp_inserted <= 1'b1;
        end else if (data_valid && !buf_full) begin
            mem[wr_ptr[ADDR_W-1:0]] <= data_in;
            wr_ptr      <= wr_ptr + 1'b1;
            wr_ptr_gray <= bin2gray(wr_ptr + 1'b1);
        end
    end
end

always @(posedge clk_pipe or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr      <= {(ADDR_W+1){1'b0}};
        rd_ptr_gray <= {(ADDR_W+1){1'b0}};
        data_out       <= {DATA_WIDTH{1'b0}};
        data_out_valid <= 1'b0;
        skp_removed    <= 1'b0;
    end else begin
        skp_removed    <= 1'b0;
        data_out_valid <= 1'b0;
        if (!buf_empty && pipe_ready) begin
            data_out <= mem[rd_ptr[ADDR_W-1:0]];
            data_out_valid <= 1'b1;

            if (skp_remove_req && mem[rd_ptr[ADDR_W-1:0]] == SKP_OS_PATTERN) begin
                skp_removed    <= 1'b1;
                data_out_valid <= 1'b0;
            end
            rd_ptr      <= rd_ptr + 1'b1;
            rd_ptr_gray <= bin2gray(rd_ptr + 1'b1);
        end
    end
end

always @(posedge clk_pipe or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr_gray_sync1 <= {(ADDR_W+1){1'b0}};
        wr_ptr_gray_sync2 <= {(ADDR_W+1){1'b0}};
    end else begin
        wr_ptr_gray_sync1 <= wr_ptr_gray;
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end
end

always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr_gray_sync1 <= {(ADDR_W+1){1'b0}};
        rd_ptr_gray_sync2 <= {(ADDR_W+1){1'b0}};
    end else begin
        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end
end

always @(*) begin
    wr_ptr_sync_bin = gray2bin(wr_ptr_gray_sync2);
    rd_ptr_sync_bin = gray2bin(rd_ptr_gray_sync2);
end

assign buf_full  = (wr_ptr[ADDR_W] != rd_ptr_sync_bin[ADDR_W]) &&
                   (wr_ptr[ADDR_W-1:0] == rd_ptr_sync_bin[ADDR_W-1:0]);
assign buf_empty = (wr_ptr_sync_bin == rd_ptr);
assign fill_level= wr_ptr - rd_ptr_sync_bin;
assign buf_half  = fill_level >= (DEPTH >> 1);

endmodule
