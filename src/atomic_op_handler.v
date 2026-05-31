
module pcie_atomic_op_handler (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [1023:0] tlp_atomic,
    input  wire          tlp_atomic_valid,

    input  wire [1:0]    atomic_type,
    input  wire [63:0]   atomic_addr,
    input  wire [63:0]   atomic_operand,

    output reg  [63:0]   atop_rd_addr,
    output reg  [63:0]   atop_wr_data,
    output reg           atop_wr_en,

    output reg  [63:0]   atop_cpl_data,
    output reg           atop_cpl_valid,
    output reg  [9:0]    atop_tag
);

    localparam ATOP_FETCHADD = 2'b00;
    localparam ATOP_SWAP     = 2'b01;
    localparam ATOP_CAS      = 2'b10;

    wire [9:0] tlp_tag = tlp_atomic[79:70];

    reg [63:0] mem_model [0:255];

    reg         s1_valid;
    reg [1:0]   s1_type;
    reg [63:0]  s1_addr;
    reg [63:0]  s1_operand;
    reg [63:0]  s1_orig;
    reg [9:0]   s1_tag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid   <= 1'b0;
            s1_type    <= 2'b00;
            s1_addr    <= 64'd0;
            s1_operand <= 64'd0;
            s1_orig    <= 64'd0;
            s1_tag     <= 10'd0;
        end else begin
            s1_valid   <= tlp_atomic_valid;
            s1_type    <= atomic_type;
            s1_addr    <= atomic_addr;
            s1_operand <= atomic_operand;
            s1_orig    <= mem_model[atomic_addr[9:2]];
            s1_tag     <= tlp_tag;
        end
    end

    reg [63:0] new_val;
    integer j;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            atop_rd_addr   <= 64'd0;
            atop_wr_data   <= 64'd0;
            atop_wr_en     <= 1'b0;
            atop_cpl_data  <= 64'd0;
            atop_cpl_valid <= 1'b0;
            atop_tag       <= 10'd0;
            for (j = 0; j < 256; j = j + 1)
                mem_model[j] <= 64'd0;
        end else if (s1_valid) begin
            case (s1_type)
                ATOP_FETCHADD: new_val = s1_orig + s1_operand;
                ATOP_SWAP    : new_val = s1_operand;
                ATOP_CAS     : begin
                    if (s1_orig[63:32] == s1_operand[63:32])
                        new_val = {s1_orig[63:32], s1_operand[31:0]};
                    else
                        new_val = s1_orig;
                end
                default: new_val = s1_orig;
            endcase

            mem_model[s1_addr[9:2]] <= new_val;

            atop_rd_addr   <= s1_addr;
            atop_wr_data   <= new_val;
            atop_wr_en     <= 1'b1;

            atop_cpl_data  <= s1_orig;
            atop_cpl_valid <= 1'b1;
            atop_tag       <= s1_tag;
        end

    end

endmodule
