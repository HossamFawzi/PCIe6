
module pcie_completion_queue #(
    parameter DEPTH      = 16,
    parameter DATA_WIDTH = 1024,
    parameter ADDR_BITS  = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [DATA_WIDTH-1:0] cpl_tlp,
    input  wire                  cpl_valid_in,

    input  wire                  credit_grant_cpl,

    output wire [DATA_WIDTH-1:0] cpl_out,
    output wire                  cpl_valid_out,

    output wire                  q_full_cpl,
    output wire [7:0]            q_occ_cpl
);

    localparam [ADDR_BITS:0] DEPTH_W = DEPTH[ADDR_BITS:0];

    reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];

    reg [ADDR_BITS:0] wr_ptr;
    reg [ADDR_BITS:0] rd_ptr;
    reg [ADDR_BITS:0] count;

    wire [ADDR_BITS-1:0] wr_addr = wr_ptr[ADDR_BITS-1:0];
    wire [ADDR_BITS-1:0] rd_addr = rd_ptr[ADDR_BITS-1:0];

    wire q_empty = (count == {(ADDR_BITS+1){1'b0}});

    assign q_full_cpl = (count == DEPTH_W);
    assign q_occ_cpl  = {{(8-ADDR_BITS-1){1'b0}}, count};

    wire bypass = q_empty & cpl_valid_in & credit_grant_cpl;

    wire do_enqueue = cpl_valid_in & ~q_full_cpl & ~bypass;
    wire do_dequeue = credit_grant_cpl & ~q_empty;

    assign cpl_out       = bypass ? cpl_tlp : fifo_mem[rd_addr];
    assign cpl_valid_out = bypass | do_dequeue;

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {(ADDR_BITS+1){1'b0}};
            for (k = 0; k < DEPTH; k = k + 1)
                fifo_mem[k] <= {DATA_WIDTH{1'b0}};
        end else if (do_enqueue) begin
            fifo_mem[wr_addr] <= cpl_tlp;
            wr_ptr            <= wr_ptr + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= {(ADDR_BITS+1){1'b0}};
        end else if (do_dequeue) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= {(ADDR_BITS+1){1'b0}};
        end else begin
            case ({do_enqueue, do_dequeue})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule
