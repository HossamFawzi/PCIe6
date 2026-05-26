// =============================================================================
// Module 10: RX Elastic Buffer with Slip
// PCIe Gen6 Physical Layer
// Description: Async FIFO between PIPE clock (PHY) and core clock (MAC).
//              Performs clock compensation by inserting/removing SKP OS
//              (Slip operation). Maintains center fill level for stability.
//              Gen6: Also used for FLIT boundary alignment.
// =============================================================================
module rx_elastic_buffer_slip #(
    parameter DATA_WIDTH = 256,
    parameter DEPTH      = 32,
    parameter ADDR_W     = 5
)(
    // Write side (PIPE clock - from PHY)
    input  wire                  clk_pipe,
    input  wire                  rst_n,
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  data_valid,
    input  wire                  slip_req,    // Request to slip (remove) one entry

    // Read side (core clock - to MAC)
    input  wire                  clk_core,
    input  wire                  pipe_ready,  // Core ready to accept data

    // Outputs
    output reg  [DATA_WIDTH-1:0] data_out,
    output reg                   data_out_valid,
    output wire                  buf_empty,
    output wire                  buf_full,
    output reg                   slip_done,   // Slip operation completed
    output wire [ADDR_W:0]       fill_level,  // Current occupancy
    output wire                  buf_center   // Buffer near center (healthy)
);

// ---------------------------------------------------------------------------
// FIFO memory
// ---------------------------------------------------------------------------
reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

// Pointers (binary)
reg [ADDR_W:0] wr_ptr; // Write: clk_pipe domain
reg [ADDR_W:0] rd_ptr; // Read:  clk_core domain

// Gray pointers for CDC
reg [ADDR_W:0] wr_gray, rd_gray;
reg [ADDR_W:0] wr_gray_s1, wr_gray_s2; // sync to clk_core
reg [ADDR_W:0] rd_gray_s1, rd_gray_s2; // sync to clk_pipe

// Binary converted after sync
reg [ADDR_W:0] wr_bin_sync;
reg [ADDR_W:0] rd_bin_sync;

// ---------------------------------------------------------------------------
// Gray code helpers
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Write side (clk_pipe) — pure write, no slip logic here
// ---------------------------------------------------------------------------
always @(posedge clk_pipe or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr  <= {(ADDR_W+1){1'b0}};
        wr_gray <= {(ADDR_W+1){1'b0}};
    end else begin
        // Normal write — slip does NOT block writes
        if (data_valid && !buf_full) begin
            mem[wr_ptr[ADDR_W-1:0]] <= data_in;
            wr_ptr  <= wr_ptr + 1'b1;
            wr_gray <= b2g(wr_ptr + 1'b1);
        end
    end
end

// ---------------------------------------------------------------------------
// slip_req comes from outside (unknown domain) — sync it into clk_core
// ---------------------------------------------------------------------------
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

// Synchronized rising-edge pulse of slip_req
wire slip_pulse = slip_req_s2 && !slip_req_d;

// ---------------------------------------------------------------------------
// Read side (clk_core) — uses synced slip_pulse
// slip: advance rd_ptr without forwarding data (discards one SKP OS)
// ---------------------------------------------------------------------------
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
                // SLIP: consume one FIFO entry silently (clock compensation)
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

// ---------------------------------------------------------------------------
// 2-FF CDC synchronizers
// ---------------------------------------------------------------------------
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

// Binary conversion of synced pointers
always @(*) begin
    wr_bin_sync = g2b(wr_gray_s2);
    rd_bin_sync = g2b(rd_gray_s2);
end

// ---------------------------------------------------------------------------
// Status flags
// All comparisons use pointers in the SAME domain to avoid metastability.
// buf_full:   write-side check → wr_ptr vs rd_bin_sync (both visible in clk_pipe)
// buf_empty:  read-side check  → wr_bin_sync vs rd_ptr  (both in clk_core)
// fill_level: clk_core domain  → wr_bin_sync - rd_ptr
// ---------------------------------------------------------------------------
assign buf_full   = (wr_ptr[ADDR_W]   != rd_bin_sync[ADDR_W]) &&
                    (wr_ptr[ADDR_W-1:0] == rd_bin_sync[ADDR_W-1:0]);
assign buf_empty  = (wr_bin_sync == rd_ptr);
assign fill_level = wr_bin_sync - rd_ptr;  // both in clk_core domain — safe

// Center threshold: DEPTH/2 ±4
localparam CENTER_LO = DEPTH/2 - 4;
localparam CENTER_HI = DEPTH/2 + 4;
assign buf_center = (fill_level >= CENTER_LO) && (fill_level <= CENTER_HI);

endmodule
