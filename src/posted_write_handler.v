
module pcie_mwr_hdl (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1023:0] tlp_mwr,
    input  wire          tlp_mwr_valid,
    input  wire [63:0]   tlp_addr,
    input  wire [9:0]    tlp_len,
    output reg  [511:0]  mwr_data,
    output reg  [63:0]   mwr_addr,
    output reg  [63:0]   mwr_be,
    output reg           mwr_valid,
    output wire          mwr_full
);

    wire [3:0]   first_be = tlp_mwr[963:960];
    wire [3:0]   last_be  = tlp_mwr[967:964];
    wire [9:0]   hdr_len  = tlp_mwr[1001:992];
    wire [511:0] payload  = tlp_mwr[895:384];

    reg  [63:0] be_expanded;
    integer i;
    reg [31:0] last_start;
    reg [31:0] total_bytes;

    always @(*) begin
        be_expanded  = 64'h0;
        total_bytes  = {22'h0, hdr_len} * 4;
        last_start   = total_bytes - 4;

        be_expanded[0] = first_be[0];
        be_expanded[1] = first_be[1];
        be_expanded[2] = first_be[2];
        be_expanded[3] = first_be[3];

        if (hdr_len > 10'd1) begin

            for (i = 4; i < 60; i = i + 1)
                be_expanded[i] = (i < last_start) ? 1'b1 : 1'b0;

            if (last_start <= 60) begin
                be_expanded[last_start  ] = last_be[0];
                be_expanded[last_start+1] = last_be[1];
                be_expanded[last_start+2] = last_be[2];
                be_expanded[last_start+3] = last_be[3];
            end
        end

    end

    assign mwr_full = mwr_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mwr_data  <= 512'h0;
            mwr_addr  <= 64'h0;
            mwr_be    <= 64'h0;
            mwr_valid <= 1'b0;
        end else if (tlp_mwr_valid) begin
            mwr_addr  <= tlp_addr;
            mwr_data  <= payload;
            mwr_be    <= be_expanded;
            mwr_valid <= 1'b1;
        end else begin

            mwr_valid <= 1'b0;
        end
    end

endmodule
