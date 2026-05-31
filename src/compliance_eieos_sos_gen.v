
module compliance_eieos_sos_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        send_ts1,
    input  wire        send_ts2,
    input  wire        send_fts,
    input  wire        send_eios,
    input  wire        send_eieos,
    input  wire        send_sos,
    input  wire        send_compliance,

    input  wire [7:0]  link_num,
    input  wire [7:0]  lane_num,

    input  wire        gen6_cap,
    input  wire        flit_mode_cap,
    input  wire        fec_cap,

    output reg  [255:0] os_data,
    output reg          os_valid,
    output reg  [3:0]   os_type
);

localparam K28_0 = 8'h1C;
localparam K28_1 = 8'h3C;
localparam K28_2 = 8'h5C;
localparam K28_5 = 8'hBC;

localparam [255:0] EIEOS_PAT = {16{16'hFF00}};
localparam [255:0] SOS_PAT   = {32{8'h1C}};
localparam [255:0] EIOS_PAT  = {32{8'hBC}};
localparam [255:0] FTS_PAT   = {8'h3C,8'h3C,8'h3C,8'h3C,
                                 8'h3C,8'h3C,8'h3C,8'h3C,
                                 8'h3C,8'h3C,8'h3C,8'h3C,
                                 8'h3C,8'h3C,8'h3C,8'h3C,
                                 8'h3C,8'h3C,8'h3C,8'h3C,
                                 8'h3C,8'h3C,8'h3C,8'h3C,
                                 8'h3C,8'h3C,8'h3C,8'h3C,
                                 8'hBC,24'h0};
localparam [255:0] COMP_PAT  = {16{16'hFF00}};

wire [7:0] speed_cap = {gen6_cap, flit_mode_cap, fec_cap, 5'b00001};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        os_data  <= {256{1'b0}};
        os_valid <= 1'b0;
        os_type  <= 4'h0;
    end else begin
        os_valid <= 1'b0;
        if (send_eieos) begin
            os_data <= EIEOS_PAT; os_valid <= 1'b1; os_type <= 4'd4;
        end else if (send_eios) begin
            os_data <= EIOS_PAT;  os_valid <= 1'b1; os_type <= 4'd3;
        end else if (send_sos) begin
            os_data <= SOS_PAT;   os_valid <= 1'b1; os_type <= 4'd5;
        end else if (send_fts) begin
            os_data <= FTS_PAT;   os_valid <= 1'b1; os_type <= 4'd2;
        end else if (send_compliance) begin
            os_data <= COMP_PAT;  os_valid <= 1'b1; os_type <= 4'd6;
        end else if (send_ts1) begin
            os_data  <= {K28_0, K28_0, K28_0,
                         link_num, lane_num,
                         8'hFF, speed_cap, 8'h00, {23{8'h00}}};
            os_valid <= 1'b1; os_type <= 4'd0;
        end else if (send_ts2) begin
            os_data  <= {K28_2, K28_2, K28_2,
                         link_num, lane_num,
                         8'hFF, speed_cap, 8'h00, {23{8'h00}}};
            os_valid <= 1'b1; os_type <= 4'd1;
        end
    end
end

endmodule
