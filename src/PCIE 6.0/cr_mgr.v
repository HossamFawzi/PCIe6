// ============================================================
// Module  : cr_mgr.v  [FIXED]
// Fix     : ELAB-366 — merged three always blocks that all
//           drove ph_avail/pd_avail/nph_avail/npd_avail/
//           cplh_avail/cpld_avail into ONE always block with
//           explicit priority:
//             1. INIT  (fc_init_done rising edge)  — highest
//             2. CONSUME (tlp_sent)
//             3. UPDATE  (upd_valid)
// ============================================================
module cr_mgr (
    input  wire         clk,
    input  wire         rst_n,

    // From FC_INIT
    input  wire         fc_init_done,
    input  wire [7:0]   init_ph,
    input  wire [11:0]  init_pd,
    input  wire [7:0]   init_nph,
    input  wire [11:0]  init_npd,
    input  wire [7:0]   init_cplh,
    input  wire [11:0]  init_cpld,

    // From DLL_IF (UpdateFC DLLPs)
    input  wire [7:0]   upd_ph,
    input  wire [11:0]  upd_pd,
    input  wire [7:0]   upd_nph,
    input  wire [11:0]  upd_npd,
    input  wire [7:0]   upd_cplh,
    input  wire [11:0]  upd_cpld,
    input  wire         upd_valid,

    // From ARB_TX
    input  wire         tlp_sent,
    input  wire         tlp_is_np,
    input  wire [9:0]   tlp_len,

    // To REQ_Q and ARB_TX
    output reg          credit_grant_p,
    output reg          credit_grant_np,
    output reg          credit_grant_cpl,

    // Debug
    output wire [7:0]   dbg_ph_avail,
    output wire [11:0]  dbg_pd_avail,
    output wire [7:0]   dbg_nph_avail,
    output wire [11:0]  dbg_npd_avail
);

reg [7:0]   ph_avail,  nph_avail,  cplh_avail;
reg [11:0]  pd_avail,  npd_avail,  cpld_avail;
reg         ph_infinite, pd_infinite, nph_infinite;
reg         npd_infinite, cplh_infinite, cpld_infinite;
reg         fc_init_done_prev;

wire [11:0] data_credits_needed = (tlp_len == 10'd0) ? 12'd1024 : {2'b00, tlp_len};

// ── Single always block drives all credit registers ──────────────────────────
// Priority: INIT > CONSUME > UPDATE
// This eliminates ELAB-366 "driven by more than one source" errors.
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ph_avail          <= 8'd0;  pd_avail    <= 12'd0;
        nph_avail         <= 8'd0;  npd_avail   <= 12'd0;
        cplh_avail        <= 8'd0;  cpld_avail  <= 12'd0;
        ph_infinite       <= 1'b0;  pd_infinite  <= 1'b0;
        nph_infinite      <= 1'b0;  npd_infinite <= 1'b0;
        cplh_infinite     <= 1'b0;  cpld_infinite<= 1'b0;
        fc_init_done_prev <= 1'b0;
        credit_grant_p    <= 1'b0;
        credit_grant_np   <= 1'b0;
        credit_grant_cpl  <= 1'b0;
    end else begin
        fc_init_done_prev <= fc_init_done;

        // ── Priority 1: INIT (one-shot on rising edge of fc_init_done) ────────
        if (fc_init_done && !fc_init_done_prev) begin
            ph_avail   <= init_ph;   pd_avail   <= init_pd;
            nph_avail  <= init_nph;  npd_avail  <= init_npd;
            cplh_avail <= init_cplh; cpld_avail <= init_cpld;
            ph_infinite   <= (init_ph   == 8'd0);
            pd_infinite   <= (init_pd   == 12'd0);
            nph_infinite  <= (init_nph  == 8'd0);
            npd_infinite  <= (init_npd  == 12'd0);
            cplh_infinite <= (init_cplh == 8'd0);
            cpld_infinite <= (init_cpld == 12'd0);

        // ── Priority 2: CONSUME (TLP sent) ────────────────────────────────────
        end else if (tlp_sent && fc_init_done) begin
            if (!tlp_is_np) begin
                if (!ph_infinite) ph_avail <= ph_avail - 8'd1;
                if (!pd_infinite) pd_avail <= pd_avail - data_credits_needed;
            end else begin
                if (!nph_infinite) nph_avail <= nph_avail - 8'd1;
                if (!npd_infinite) npd_avail <= npd_avail - data_credits_needed;
            end

        // ── Priority 3: UPDATE (UpdateFC DLLP) ────────────────────────────────
        end else if (upd_valid && fc_init_done) begin
            if (!ph_infinite)   ph_avail   <= ph_avail   + upd_ph;
            if (!pd_infinite)   pd_avail   <= pd_avail   + upd_pd;
            if (!nph_infinite)  nph_avail  <= nph_avail  + upd_nph;
            if (!npd_infinite)  npd_avail  <= npd_avail  + upd_npd;
            if (!cplh_infinite) cplh_avail <= cplh_avail + upd_cplh;
            if (!cpld_infinite) cpld_avail <= cpld_avail + upd_cpld;
        end

        // ── Grant logic (registered, checks after any update) ─────────────────
        if (fc_init_done) begin
            credit_grant_p   <= (ph_infinite   || ph_avail   >= 8'd1) &&
                                (pd_infinite   || pd_avail   >= 12'd1);
            credit_grant_np  <= (nph_infinite  || nph_avail  >= 8'd1) &&
                                (npd_infinite  || npd_avail  >= 12'd1);
            credit_grant_cpl <= (cplh_infinite || cplh_avail >= 8'd1) &&
                                (cpld_infinite || cpld_avail >= 12'd1);
        end else begin
            credit_grant_p   <= 1'b0;
            credit_grant_np  <= 1'b0;
            credit_grant_cpl <= 1'b0;
        end
    end
end

assign dbg_ph_avail  = ph_avail;
assign dbg_pd_avail  = pd_avail;
assign dbg_nph_avail = nph_avail;
assign dbg_npd_avail = npd_avail;

`ifdef SIMULATION
always @(posedge clk) begin
    if (rst_n && fc_init_done) begin
        if (tlp_sent && !tlp_is_np && !ph_infinite && ph_avail == 8'd0)
            $error("[CR_MGR] PH underflow!");
        if (tlp_sent &&  tlp_is_np && !nph_infinite && nph_avail == 8'd0)
            $error("[CR_MGR] NPH underflow!");
    end
end
`endif

endmodule
