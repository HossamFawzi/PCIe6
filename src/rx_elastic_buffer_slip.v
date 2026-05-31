
module rx_elastic_buffer_slip #(
    parameter DATA_WIDTH = 256,
    parameter DEPTH      = 32,
    parameter ADDR_W     = 5
)(

    input  wire                  clk_pipe,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  data_valid,
    input  wire                  slip_req,

    input  wire                  clk_core,
    input  wire                  pipe_ready,

    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   data_out_valid,
    output wire                  buf_empty,
    output wire                  buf_full,
    output reg                   slip_done,
    output wire [ADDR_W:0]       fill_level,
    output wire                  buf_center
);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

reg [ADDR_W:0] wr_ptr;
reg [ADDR_W:0] rd_ptr;

reg [ADDR_W:0] wr_gray, rd_gray;
reg [ADDR_W:0] wr_gray_s1, wr_gray_s2;
reg [ADDR_W:0] rd_gray_s1, rd_gray_s2;

reg [ADDR_W:0] wr_bin_sync;
reg [ADDR_W:0] rd_bin_sync;

function [ADDR_W:0] b2g;
    input [ADDR_W:0] b;
    b2g = b ^ (b >> 1);
endfunction

function [ADDR_W:0] g2b;
    input [ADDR_W:0] g;
    reg [ADDR_W:0] t;
    integer i;
    begin
        t[ADDR_W] = g[ADDR_W];
        for (i = ADDR_W-1; i >= 0; i = i-1)
            t[i] = t[i+1] ^ g[i];
        g2b = t;
    end
endfunction

always @(posedge clk_pipe or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr  <= {(ADDR_W+1){1'b0}};
        wr_gray <= {(ADDR_W+1){1'b0}};
    end else begin

        if (data_valid && !buf_full) begin
            mem[wr_ptr[ADDR_W-1:0]] <= data_in;
            wr_ptr  <= wr_ptr + 1'b1;
            wr_gray <= b2g(wr_ptr + 1'b1);
        end
    end
end

reg slip_req_s1, slip_req_s2, slip_req_d;

always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        slip_req_s1 <= 1'b0;
        slip_req_s2 <= 1'b0;
        slip_req_d  <= 1'b0;
    end else begin
        slip_req_s1 <= slip_req;
        slip_req_s2 <= slip_req_s1;
        slip_req_d  <= slip_req_s2;
    end
end

wire slip_pulse = slip_req_s2 && !slip_req_d;

always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr         <= {(ADDR_W+1){1'b0}};
        rd_gray        <= {(ADDR_W+1){1'b0}};
        data_out       <= {DATA_WIDTH{1'b0}};
        data_out_valid <= 1'b0;
        slip_done      <= 1'b0;
    end else begin
        data_out_valid <= 1'b0;
        slip_done      <= 1'b0;
        if (!buf_empty) begin
            if (slip_pulse) begin

                rd_ptr    <= rd_ptr + 1'b1;
                rd_gray   <= b2g(rd_ptr + 1'b1);
                slip_done <= 1'b1;
            end else if (pipe_ready) begin
                data_out       <= mem[rd_ptr[ADDR_W-1:0]];
                data_out_valid <= 1'b1;
                rd_ptr  <= rd_ptr + 1'b1;
                rd_gray <= b2g(rd_ptr + 1'b1);
            end
        end
    end
end

always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        wr_gray_s1 <= {(ADDR_W+1){1'b0}};
        wr_gray_s2 <= {(ADDR_W+1){1'b0}};
    end else begin
        wr_gray_s1 <= wr_gray;
        wr_gray_s2 <= wr_gray_s1;
    end
end

always @(posedge clk_pipe or negedge rst_n) begin
    if (!rst_n) begin
        rd_gray_s1 <= {(ADDR_W+1){1'b0}};
        rd_gray_s2 <= {(ADDR_W+1){1'b0}};
    end else begin
        rd_gray_s1 <= rd_gray;
        rd_gray_s2 <= rd_gray_s1;
    end
end

always @(*) begin
    wr_bin_sync = g2b(wr_gray_s2);
    rd_bin_sync = g2b(rd_gray_s2);
end

assign buf_full   = (wr_ptr[ADDR_W]   != rd_bin_sync[ADDR_W]) &&
                    (wr_ptr[ADDR_W-1:0] == rd_bin_sync[ADDR_W-1:0]);
assign buf_empty  = (wr_bin_sync == rd_ptr);
assign fill_level = wr_bin_sync - rd_ptr;

localparam CENTER_LO = DEPTH/2 - 4;
localparam CENTER_HI = DEPTH/2 + 4;
assign buf_center = (fill_level >= CENTER_LO) && (fill_level <= CENTER_HI);

endmodule
