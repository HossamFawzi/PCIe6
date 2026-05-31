
module cfg_space_handler (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [255:0]  tlp_cfg,
    input  wire          tlp_cfg_valid,
    input  wire [11:0]   cfg_addr,
    input  wire [31:0]   cfg_wr_data,
    input  wire          cfg_wr_en,

    output reg  [31:0]   cfg_rd_data,
    output reg           cfg_rd_valid,

    output reg  [255:0]  cfg_cpl_tlp,
    output reg           cfg_cpl_valid,

    output reg  [2:0]    max_payload,
    output reg           flit_mode_en,
    output reg           ecrc_en,
    output reg           ro_en
);

    reg [31:0] cfg_space [0:1023];

    localparam [9:0] IDX_VENDDEV  = 10'h000;
    localparam [9:0] IDX_STATUS   = 10'h001;
    localparam [9:0] IDX_DEVCAP   = 10'h024;
    localparam [9:0] IDX_DEVCTRL  = 10'h025;
    localparam [9:0] IDX_DEVCAP2  = 10'h02C;
    localparam [9:0] IDX_DEVCTRL2 = 10'h02D;

    wire [9:0] dw_idx = cfg_addr[11:2];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 1024; i = i + 1)
                cfg_space[i] <= 32'h0;

            cfg_space[IDX_VENDDEV]  <= 32'h1234_ABCD;

            cfg_space[IDX_DEVCAP]   <= 32'h0000_0001;

            cfg_space[IDX_DEVCAP2]  <= 32'h0000_0001;

            max_payload   <= 3'b000;
            flit_mode_en  <= 1'b0;
            ecrc_en       <= 1'b0;
            ro_en         <= 1'b0;
        end
        else if (tlp_cfg_valid && cfg_wr_en) begin

            cfg_space[dw_idx] <= cfg_wr_data;

            if (dw_idx == IDX_DEVCTRL) begin
                max_payload  <= cfg_wr_data[7:5];
                ro_en        <= cfg_wr_data[4];
                ecrc_en      <= cfg_wr_data[11];
            end

            if (dw_idx == IDX_DEVCTRL2) begin
                flit_mode_en <= cfg_wr_data[0];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_rd_data  <= 32'h0;
            cfg_rd_valid <= 1'b0;
        end
        else if (tlp_cfg_valid && !cfg_wr_en) begin
            cfg_rd_data  <= cfg_space[dw_idx];
            cfg_rd_valid <= 1'b1;
        end
        else begin
            cfg_rd_valid <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_cpl_tlp   <= 256'h0;
            cfg_cpl_valid <= 1'b0;
        end
        else if (tlp_cfg_valid) begin
            if (!cfg_wr_en) begin

                cfg_cpl_tlp[255:248] <= 8'h4A;
                cfg_cpl_tlp[247:240] <= 8'h00;
                cfg_cpl_tlp[239:224] <= 16'h0001;
                cfg_cpl_tlp[223:208] <= tlp_cfg[223:208];
                cfg_cpl_tlp[207:196] <= 12'h004;
                cfg_cpl_tlp[195:192] <= 4'b0000;
                cfg_cpl_tlp[191:176] <= tlp_cfg[191:176];
                cfg_cpl_tlp[175:168] <= tlp_cfg[167:160];
                cfg_cpl_tlp[167:160] <= 8'h00;
                cfg_cpl_tlp[159:128] <= cfg_space[dw_idx];
                cfg_cpl_tlp[127:0]   <= 128'h0;
                cfg_cpl_valid        <= 1'b1;
            end
            else begin

                cfg_cpl_tlp[255:248] <= 8'h0A;
                cfg_cpl_tlp[247:128] <= 120'h0;
                cfg_cpl_tlp[127:0]   <= 128'h0;
                cfg_cpl_valid        <= 1'b1;
            end
        end
        else begin
            cfg_cpl_valid <= 1'b0;
        end
    end

endmodule
