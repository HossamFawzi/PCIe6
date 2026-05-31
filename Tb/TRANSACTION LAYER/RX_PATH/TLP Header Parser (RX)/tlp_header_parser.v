
module tlp_header_parser (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [1023:0] tlp_rx,
    input  wire          tlp_rx_valid,
    input  wire          tlp_rx_sop,

    output reg  [4:0]    tlp_type,
    output reg  [2:0]    tlp_fmt,
    output reg  [2:0]    tlp_tc,
    output reg  [2:0]    tlp_attr,
    output reg  [9:0]    tlp_len,
    output reg  [9:0]    tlp_tag,
    output reg  [15:0]   tlp_req_id,
    output reg  [63:0]   tlp_addr,
    output reg           tlp_ep_bit,
    output reg           tlp_td_bit,
    output reg           parse_err,
    output reg           parse_valid
);

    wire [31:0] dw0 = tlp_rx[31:0];
    wire [31:0] dw1 = tlp_rx[63:32];
    wire [31:0] dw2 = tlp_rx[95:64];
    wire [31:0] dw3 = tlp_rx[127:96];

    wire [2:0] raw_fmt    = dw0[31:29];
    wire [4:0] raw_type   = dw0[28:24];
    wire [2:0] raw_tc     = dw0[22:20];
    wire       raw_td     = dw0[15];
    wire       raw_ep     = dw0[14];
    wire [1:0] raw_attr10 = dw0[13:12];
    wire       raw_attr2  = dw0[18];
    wire [9:0] raw_len    = dw0[9:0];

    wire [15:0] raw_req_id  = dw1[31:16];
    wire [7:0]  raw_tag_lo  = dw1[15:8];
    wire [1:0]  raw_tag_hi  = {dw0[19], dw0[23]};

    wire is_4dw = raw_fmt[0];

    wire fmt_type_valid = (raw_fmt <= 3'b011) && (raw_type <= 5'b11111);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_type    <= 5'b0;
            tlp_fmt     <= 3'b0;
            tlp_tc      <= 3'b0;
            tlp_attr    <= 3'b0;
            tlp_len     <= 10'b0;
            tlp_tag     <= 10'b0;
            tlp_req_id  <= 16'b0;
            tlp_addr    <= 64'b0;
            tlp_ep_bit  <= 1'b0;
            tlp_td_bit  <= 1'b0;
            parse_err   <= 1'b0;
            parse_valid <= 1'b0;
        end else begin
            parse_valid <= 1'b0;
            parse_err   <= 1'b0;

            if (tlp_rx_valid && tlp_rx_sop) begin

                tlp_fmt    <= raw_fmt;
                tlp_type   <= raw_type;
                tlp_tc     <= raw_tc;
                tlp_attr   <= {raw_attr2, raw_attr10};
                tlp_len    <= raw_len;
                tlp_td_bit <= raw_td;
                tlp_ep_bit <= raw_ep;

                tlp_tag    <= {raw_tag_hi, raw_tag_lo};

                tlp_req_id <= raw_req_id;

                if (is_4dw) begin
                    tlp_addr <= {dw2, dw3[31:2], 2'b00};
                end else begin
                    tlp_addr <= {32'b0, dw2[31:2], 2'b00};
                end

                if (!fmt_type_valid) begin
                    parse_err <= 1'b1;
                end

                parse_valid <= 1'b1;
            end
        end
    end

endmodule
