
module pcie_completion_handler (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [1023:0] tlp_cpl,
    input  wire          tlp_cpl_valid,

    input  wire [9:0]    outstanding_tag,
    input  wire [9:0]    expected_len,

    output reg  [511:0]  cpl_data,
    output reg           cpl_valid,
    output reg  [9:0]    cpl_tag,
    output reg  [2:0]    cpl_status,
    output reg           cpl_match_err,

    output reg  [9:0]    tag_return,
    output reg           tag_return_valid,

    output reg           cr_return_cplh,
    output reg  [3:0]    cr_return_cpld
);

    wire [4:0]   hdr_type    = tlp_cpl[28:24];
    wire [2:0]   hdr_status  = tlp_cpl[47:45];
    wire [11:0]  hdr_bc      = tlp_cpl[43:32];
    wire [9:0]   hdr_tag     = tlp_cpl[79:70];
    wire [9:0]   hdr_length  = tlp_cpl[9:0];
    wire [511:0] hdr_payload = tlp_cpl[607:96];

    wire tag_match = (hdr_tag == outstanding_tag);

    wire [3:0] data_credits =
        (hdr_length == 10'd0)  ? 4'd0 :
        (hdr_length <= 10'd4)  ? 4'd1 :
        (hdr_length <= 10'd8)  ? 4'd2 :
        (hdr_length <= 10'd12) ? 4'd3 : 4'd4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpl_data         <= 512'd0;
            cpl_valid        <= 1'b0;
            cpl_tag          <= 10'd0;
            cpl_status       <= 3'd0;
            cpl_match_err    <= 1'b0;
            tag_return       <= 10'd0;
            tag_return_valid <= 1'b0;
            cr_return_cplh   <= 1'b0;
            cr_return_cpld   <= 4'd0;
        end else begin

            cpl_valid        <= 1'b0;
            cpl_match_err    <= 1'b0;
            tag_return_valid <= 1'b0;
            cr_return_cplh   <= 1'b0;
            cr_return_cpld   <= 4'd0;

            if (tlp_cpl_valid) begin

                cr_return_cplh <= 1'b1;
                cr_return_cpld <= data_credits;

                if (tag_match) begin
                    cpl_data   <= hdr_payload;
                    cpl_valid  <= 1'b1;
                    cpl_tag    <= hdr_tag;
                    cpl_status <= hdr_status;

                    if (hdr_bc <= {2'b00, hdr_length, 2'b00}) begin
                        tag_return       <= hdr_tag;
                        tag_return_valid <= 1'b1;
                    end
                end else begin
                    cpl_match_err <= 1'b1;
                    cpl_tag       <= hdr_tag;
                    cpl_status    <= hdr_status;
                end
            end
        end
    end

endmodule
