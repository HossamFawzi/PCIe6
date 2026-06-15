// =============================================================================
// Module: TX Elastic Buffer
// PCIe Gen6 Physical Layer
// Description: Async FIFO for TX path. Compensates clock differences between
//              core clock and PIPE TX clock. Inserts/removes SKP OS for
//              clock compensation. Width: 256 bits (Gen6 PAM4 x16).
// =============================================================================
module tx_elastic_buffer #(
    parameter DATA_WIDTH = 256,
    parameter DEPTH      = 16,         // Must be power of 2
    parameter ADDR_W     = 4          // log2(DEPTH)
)(
    // Write side (core clock domain)
    input  wire                  clk_core,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  data_valid,
    input  wire                  skp_insert_req,   // Request to insert SKP OS

    // Read side (PIPE TX clock domain)
    input  wire                  clk_pipe,
    input  wire                  pipe_ready,       // PIPE MAC ready
    input  wire                  skp_remove_req,   // Request to remove SKP OS

    // Outputs
    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   data_out_valid,
    output wire                  buf_full,
    output wire                  buf_empty,
    output wire                  buf_half,         // Half-full indicator
    output reg                   skp_inserted,
    output reg                   skp_removed,
    output wire [ADDR_W:0]       fill_level        // Current occupancy
);

// ---------------------------------------------------------------------------
// Internal signals
// ---------------------------------------------------------------------------
// FIFO memory
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Write pointer (core clock domain)
reg [ADDR_W:0] wr_ptr;
// Read pointer (pipe clock domain)
reg [ADDR_W:0] rd_ptr;

// Gray-coded pointers for CDC
reg [ADDR_W:0] wr_ptr_gray;
reg [ADDR_W:0] rd_ptr_gray;

// Synchronized gray pointers
reg [ADDR_W:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2; // sync to clk_pipe
reg [ADDR_W:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2; // sync to clk_core

// Converted binary pointers after sync
reg [ADDR_W:0] wr_ptr_sync_bin;
reg [ADDR_W:0] rd_ptr_sync_bin;

// SKP Ordered Set pattern (Gen6: repeating 0xAA pattern for EIEOS-like)
localparam [DATA_WIDTH-1:0] SKP_OS_PATTERN = {(DATA_WIDTH/8){8'hAA}};

// ---------------------------------------------------------------------------
// Gray code conversion functions
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Write side (clk_core domain)
// ---------------------------------------------------------------------------
always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr       <= {(ADDR_W+1){1'b0}};
        wr_ptr_gray  <= {(ADDR_W+1){1'b0}};
        skp_inserted <= 1'b0;
    end else begin
        skp_inserted <= 1'b0;
        if (skp_insert_req && !buf_full) begin
            // Insert SKP OS into FIFO
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

// ---------------------------------------------------------------------------
// Read side (clk_pipe domain)
// ---------------------------------------------------------------------------
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
            // Check if this is a SKP OS - if skp_remove_req, skip it
            if (skp_remove_req && mem[rd_ptr[ADDR_W-1:0]] == SKP_OS_PATTERN) begin
                skp_removed    <= 1'b1;
                data_out_valid <= 1'b0; // Absorb - do not forward
            end
            rd_ptr      <= rd_ptr + 1'b1;
            rd_ptr_gray <= bin2gray(rd_ptr + 1'b1);
        end
    end
end

// ---------------------------------------------------------------------------
// 2-FF synchronizers for gray pointers (CDC)
// ---------------------------------------------------------------------------
// wr_ptr_gray → clk_pipe domain
always @(posedge clk_pipe or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr_gray_sync1 <= {(ADDR_W+1){1'b0}};
        wr_ptr_gray_sync2 <= {(ADDR_W+1){1'b0}};
    end else begin
        wr_ptr_gray_sync1 <= wr_ptr_gray;
        wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
    end
end

// rd_ptr_gray → clk_core domain
always @(posedge clk_core or negedge rst_n) begin
    if (!rst_n) begin
        rd_ptr_gray_sync1 <= {(ADDR_W+1){1'b0}};
        rd_ptr_gray_sync2 <= {(ADDR_W+1){1'b0}};
    end else begin
        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
    end
end

// ---------------------------------------------------------------------------
// Gray → binary conversion after sync
// ---------------------------------------------------------------------------
always @(*) begin
    wr_ptr_sync_bin = gray2bin(wr_ptr_gray_sync2);
    rd_ptr_sync_bin = gray2bin(rd_ptr_gray_sync2);
end

// ---------------------------------------------------------------------------
// Status flags
// Full: checked in core domain using synced rd_ptr
// Empty: checked in pipe domain using synced wr_ptr
// ---------------------------------------------------------------------------
assign buf_full  = (wr_ptr[ADDR_W] != rd_ptr_sync_bin[ADDR_W]) &&
                   (wr_ptr[ADDR_W-1:0] == rd_ptr_sync_bin[ADDR_W-1:0]);
assign buf_empty = (wr_ptr_sync_bin == rd_ptr);
assign fill_level= wr_ptr - rd_ptr_sync_bin;
assign buf_half  = fill_level >= (DEPTH >> 1);

endmodule
