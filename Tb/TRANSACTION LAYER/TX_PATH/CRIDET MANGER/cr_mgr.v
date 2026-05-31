`timescale 1ns / 1ps

module cr_mgr (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         fc_init_done,
    input  wire [7:0]   init_ph,
    input  wire [11:0]  init_pd,
    input  wire [7:0]   init_nph,
    input  wire [11:0]  init_npd,
    input  wire [7:0]   init_cplh,
    input  wire [11:0]  init_cpld,

    input  wire [7:0]   upd_ph,
    input  wire [11:0]  upd_pd,
    input  wire [7:0]   upd_nph,
    input  wire [11:0]  upd_npd,
    input  wire [7:0]   upd_cplh,
    input  wire [11:0]  upd_cpld,
    input  wire         upd_valid,

    input  wire         tlp_sent,
    input  wire         tlp_is_np,
    input  wire [9:0]   tlp_len,

    output reg          credit_grant_p,
    output reg          credit_grant_np,
    output reg          credit_grant_cpl,

    output wire [7:0]   dbg_ph_avail,
    output wire [11:0]  dbg_pd_avail,
    output wire [7:0]   dbg_nph_avail,
    output wire [11:0]  dbg_npd_avail
);

reg [7:0]   ph_avail;
reg [11:0]  pd_avail;
reg [7:0]   nph_avail;
reg [11:0]  npd_avail;
reg [7:0]   cplh_avail;
reg [11:0]  cpld_avail;

reg ph_infinite;
reg pd_infinite;
reg nph_infinite;
reg npd_infinite;
reg cplh_infinite;
reg cpld_infinite;

wire [11:0] data_credits_needed = (tlp_len == 10'd0) ? 12'd1024 : {2'b00, tlp_len};

reg fc_init_done_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) fc_init_done_d <= 1'b0;
    else fc_init_done_d <= fc_init_done;
end
wire init_trigger = (fc_init_done && !fc_init_done_d);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ph_avail <= 0; pd_avail <= 0; nph_avail <= 0; npd_avail <= 0; cplh_avail <= 0; cpld_avail <= 0;
        ph_infinite <= 0; pd_infinite <= 0; nph_infinite <= 0; npd_infinite <= 0; cplh_infinite <= 0; cpld_infinite <= 0;
    end else if (init_trigger) begin

        ph_avail <= init_ph; pd_avail <= init_pd; nph_avail <= init_nph; npd_avail <= init_npd; cplh_avail <= init_cplh; cpld_avail <= init_cpld;

        ph_infinite <= (init_ph == 0); pd_infinite <= (init_pd == 0); nph_infinite <= (init_nph == 0);
        npd_infinite <= (init_npd == 0); cplh_infinite <= (init_cplh == 0); cpld_infinite <= (init_cpld == 0);
    end else if (fc_init_done) begin

        if (!ph_infinite)
            ph_avail <= ph_avail + (upd_valid ? upd_ph : 8'd0) - ((tlp_sent && !tlp_is_np) ? 8'd1 : 8'd0);
        if (!pd_infinite)
            pd_avail <= pd_avail + (upd_valid ? upd_pd : 12'd0) - ((tlp_sent && !tlp_is_np) ? data_credits_needed : 12'd0);

        if (!nph_infinite)
            nph_avail <= nph_avail + (upd_valid ? upd_nph : 8'd0) - ((tlp_sent && tlp_is_np) ? 8'd1 : 8'd0);
        if (!npd_infinite)
            npd_avail <= npd_avail + (upd_valid ? upd_npd : 12'd0) - ((tlp_sent && tlp_is_np) ? data_credits_needed : 12'd0);

        if (!cplh_infinite)
            cplh_avail <= cplh_avail + (upd_valid ? upd_cplh : 8'd0);
        if (!cpld_infinite)
            cpld_avail <= cpld_avail + (upd_valid ? upd_cpld : 12'd0);
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        credit_grant_p <= 1'b0; credit_grant_np <= 1'b0; credit_grant_cpl <= 1'b0;
    end else if (fc_init_done) begin
        credit_grant_p   <= (ph_infinite || ph_avail >= 8'd1) && (pd_infinite || pd_avail >= 12'd1);
        credit_grant_np  <= (nph_infinite || nph_avail >= 8'd1) && (npd_infinite || npd_avail >= 12'd1);
        credit_grant_cpl <= (cplh_infinite || cplh_avail >= 8'd1) && (cpld_infinite || cpld_avail >= 12'd1);
    end else begin
        credit_grant_p <= 1'b0; credit_grant_np <= 1'b0; credit_grant_cpl <= 1'b0;
    end
end

assign dbg_ph_avail  = ph_avail;
assign dbg_pd_avail  = pd_avail;
assign dbg_nph_avail = nph_avail;
assign dbg_npd_avail = npd_avail;

endmodule