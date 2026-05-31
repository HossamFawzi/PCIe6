
module compl_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        compliance_req,
    input  wire [3:0]  compliance_pattern,
    input  wire [2:0]  deemph_req,

    output reg  [255:0] compl_data,
    output reg          compl_valid,
    output reg          compl_active
);

reg [15:0] lfsr;
wire        lfsr_fb = lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3];

reg [255:0] pattern_data;
integer i;

always @(*) begin
    case (compliance_pattern)
        4'd0: begin

            pattern_data = 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
        end
        4'd1: begin

            pattern_data = 256'h5555555555555555555555555555555555555555555555555555555555555555;
        end
        4'd2: begin

            pattern_data = {16{lfsr}};
        end
        4'd3: begin

            pattern_data = {32{8'hBC}};
        end
        4'd4: begin

            pattern_data = {32{8'hFF}};
        end
        4'd5: begin

            pattern_data = {16{16'hCC33}};
        end
        4'd6: begin

            pattern_data = {32{8'h1C}};
        end
        4'd7: begin

            pattern_data = 256'd0;
        end
        default: pattern_data = 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        compl_data   <= 256'd0;
        compl_valid  <= 1'b0;
        compl_active <= 1'b0;
        lfsr         <= 16'hFFFF;
    end else begin

        lfsr <= {lfsr[14:0], lfsr_fb};

        if (compliance_req) begin
            compl_active <= 1'b1;
            compl_valid  <= 1'b1;
            compl_data   <= pattern_data;
        end else begin
            compl_active <= 1'b0;
            compl_valid  <= 1'b0;
            compl_data   <= 256'd0;
        end
    end
end

endmodule
