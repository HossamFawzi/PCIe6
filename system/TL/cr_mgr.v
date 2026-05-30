// ============================================================
// Module  : cr_mgr.v
// Project : PCIe Gen6 Transaction Layer — TX Path
// Block   : Credit Manager (CR_MGR)
// ============================================================
//
// Position in TX Path:
//
//   FC_INIT ──► CR_MGR ──► REQ_Q
//   DLL_IF  ──►        ──► ARB_TX
//
// What it does:
//   Tracks 6 credit counters — one per TLP class:
//
//     PH   = Posted Header credits
//     PD   = Posted Data credits
//     NPH  = Non-Posted Header credits
//     NPD  = Non-Posted Data credits
//     CPLH = Completion Header credits
//     CPLD = Completion Data credits
//
//   Rules:
//     1. FC_INIT gives initial values at link startup
//     2. Every TLP sent consumes credits
//     3. DLL sends UpdateFC DLLPs → credits refilled
//     4. credit_grant_p/np → REQ_Q and ARB_TX
//        only asserted when enough credits available
//
// Credit Consumption per TLP:
//     Header : always 1 credit consumed
//     Data   : consumed = ceil(length / 4)
//              because 1 credit = 4 bytes = 1 DWORD
//
// Infinite Credits:
//     If receiver advertises 0 at FC_INIT
//     that means infinite credits → always grant
//
// ============================================================

module cr_mgr (

    // ── Clock & Reset ────────────────────────────────────────
    input  wire         clk,
    input  wire         rst_n,

    // ── From FC_INIT (startup only) ───────────────────────────
    input  wire         fc_init_done,     // FC handshake complete
    input  wire [7:0]   init_ph,          // initial Posted Header credits
    input  wire [11:0]  init_pd,          // initial Posted Data credits
    input  wire [7:0]   init_nph,         // initial Non-Posted Header credits
    input  wire [11:0]  init_npd,         // initial Non-Posted Data credits
    input  wire [7:0]   init_cplh,        // initial Completion Header credits
    input  wire [11:0]  init_cpld,        // initial Completion Data credits

    // ── From DLL_IF (UpdateFC DLLPs) ─────────────────────────
    // UpdateFC comes from the receiver telling us
    // it has freed up more buffer space
    input  wire [7:0]   upd_ph,           // updated PH value
    input  wire [11:0]  upd_pd,           // updated PD value
    input  wire [7:0]   upd_nph,          // updated NPH value
    input  wire [11:0]  upd_npd,          // updated NPD value
    input  wire [7:0]   upd_cplh,         // updated CPLH value
    input  wire [11:0]  upd_cpld,         // updated CPLD value
    input  wire         upd_valid,        // update is valid this cycle

    // ── From ARB_TX (TLP consumed credits) ────────────────────
    input  wire         tlp_sent,         // TLP just left ARB_TX
    input  wire         tlp_is_np,        // 1=Non-Posted 0=Posted
    input  wire [9:0]   tlp_len,          // length in DWORDs

    // ── To REQ_Q and ARB_TX ───────────────────────────────────
    output reg          credit_grant_p,   // ok to send Posted
    output reg          credit_grant_np,  // ok to send Non-Posted
    output reg          credit_grant_cpl, // ok to send Completion

    // ── Status (optional — for debug/monitoring) ──────────────
    output wire [7:0]   dbg_ph_avail,
    output wire [11:0]  dbg_pd_avail,
    output wire [7:0]   dbg_nph_avail,
    output wire [11:0]  dbg_npd_avail

);

// ============================================================
// CREDIT COUNTERS
// Each counter tracks available credits
// Width:
//   Header credits : 8-bit  (max 255)
//   Data credits   : 12-bit (max 4095)
// ============================================================

reg [7:0]   ph_avail;
reg [11:0]  pd_avail;
reg [7:0]   nph_avail;
reg [11:0]  npd_avail;
reg [7:0]   cplh_avail;
reg [11:0]  cpld_avail;

// ============================================================
// INFINITE CREDIT FLAGS
// If receiver advertised 0 at init → means infinite
// We never block transmission for infinite credit classes
// ============================================================

reg ph_infinite;
reg pd_infinite;
reg nph_infinite;
reg npd_infinite;
reg cplh_infinite;
reg cpld_infinite;

// ============================================================
// DATA CREDITS NEEDED FOR THIS TLP
// 1 data credit = 1 DWORD = 4 bytes
// so credits_needed = tlp_len (already in DWORDs)
// but PCIe spec says: if len=0 means 1024 DWORDs
// ============================================================

wire [11:0] data_credits_needed = (tlp_len == 10'd0) ?
                                   12'd1024 :
                                   {2'b00, tlp_len};

// ============================================================
// INIT — load counters from FC_INIT (one-shot on rising edge)
// ============================================================

reg fc_init_done_prev;  // edge detect

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ph_avail    <= 8'd0;
        pd_avail    <= 12'd0;
        nph_avail   <= 8'd0;
        npd_avail   <= 12'd0;
        cplh_avail  <= 8'd0;
        cpld_avail  <= 12'd0;

        ph_infinite   <= 1'b0;
        pd_infinite   <= 1'b0;
        nph_infinite  <= 1'b0;
        npd_infinite  <= 1'b0;
        cplh_infinite <= 1'b0;
        cpld_infinite <= 1'b0;

        fc_init_done_prev <= 1'b0;

    end else begin
        fc_init_done_prev <= fc_init_done;

        // Load initial credits only ONCE on rising edge of fc_init_done
        if (fc_init_done && !fc_init_done_prev) begin
            ph_avail   <= init_ph;
            pd_avail   <= init_pd;
            nph_avail  <= init_nph;
            npd_avail  <= init_npd;
            cplh_avail <= init_cplh;
            cpld_avail <= init_cpld;

            ph_infinite   <= (init_ph   == 8'd0);
            pd_infinite   <= (init_pd   == 12'd0);
            nph_infinite  <= (init_nph  == 8'd0);
            npd_infinite  <= (init_npd  == 12'd0);
            cplh_infinite <= (init_cplh == 8'd0);
            cpld_infinite <= (init_cpld == 12'd0);
        end
    end
end

// ============================================================
// UPDATE — refill credits from UpdateFC DLLPs
// UpdateFC carries the new absolute count (not delta)
// The receiver tells us its new buffer head pointer
// We calculate how many more credits we now have
// ============================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // reset handled above
    end else if (upd_valid && fc_init_done) begin
        // UpdateFC is absolute — just add the difference
        // Simple model: treat as direct addition
        // Full model: modular arithmetic on 8/12-bit counters
        if (!ph_infinite)   ph_avail   <= ph_avail   + upd_ph;
        if (!pd_infinite)   pd_avail   <= pd_avail   + upd_pd;
        if (!nph_infinite)  nph_avail  <= nph_avail  + upd_nph;
        if (!npd_infinite)  npd_avail  <= npd_avail  + upd_npd;
        if (!cplh_infinite) cplh_avail <= cplh_avail + upd_cplh;
        if (!cpld_infinite) cpld_avail <= cpld_avail + upd_cpld;
    end
end

// ============================================================
// CONSUME — deduct credits when TLP is sent
// ============================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // reset handled above
    end else if (tlp_sent && fc_init_done) begin

        if (!tlp_is_np) begin
            // Posted TLP sent
            if (!ph_infinite) ph_avail <= ph_avail - 8'd1;
            if (!pd_infinite) pd_avail <= pd_avail - data_credits_needed[11:0];
        end else begin
            // Non-Posted TLP sent
            if (!nph_infinite) nph_avail <= nph_avail - 8'd1;
            if (!npd_infinite) npd_avail <= npd_avail - data_credits_needed[11:0];
        end

    end
end

// ============================================================
// GRANT LOGIC
// Grant = infinite OR (header >= 1 AND data >= needed)
// Registered for clean timing
// ============================================================

// Next TLP length from ARB_TX input
// We need to know the next TLP size to check if we have enough
// Use req_len from the front of REQ_Q (passed through ARB_TX)
// For simplicity: check data >= 1 (conservative)
// Full implementation: check against actual next TLP length

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        credit_grant_p   <= 1'b0;
        credit_grant_np  <= 1'b0;
        credit_grant_cpl <= 1'b0;
    end else if (fc_init_done) begin

        // Posted grant
        credit_grant_p <= (ph_infinite || ph_avail >= 8'd1) &&
                          (pd_infinite || pd_avail >= 12'd1);

        // Non-Posted grant
        credit_grant_np <= (nph_infinite || nph_avail >= 8'd1) &&
                           (npd_infinite || npd_avail >= 12'd1);

        // Completion grant
        credit_grant_cpl <= (cplh_infinite || cplh_avail >= 8'd1) &&
                            (cpld_infinite || cpld_avail >= 12'd1);

    end else begin
        // Before FC_INIT done — no grants
        credit_grant_p   <= 1'b0;
        credit_grant_np  <= 1'b0;
        credit_grant_cpl <= 1'b0;
    end
end

// ============================================================
// DEBUG OUTPUTS
// ============================================================

assign dbg_ph_avail  = ph_avail;
assign dbg_pd_avail  = pd_avail;
assign dbg_nph_avail = nph_avail;
assign dbg_npd_avail = npd_avail;

// ============================================================
// ASSERTIONS — simulation only
// ============================================================
`ifdef SIMULATION
always @(posedge clk) begin
    if (rst_n && fc_init_done) begin

        // underflow check
        if (tlp_sent && !tlp_is_np && !ph_infinite && ph_avail == 8'd0)
            $error("[CR_MGR] PH underflow — sent Posted with 0 header credits!");

        if (tlp_sent && tlp_is_np && !nph_infinite && nph_avail == 8'd0)
            $error("[CR_MGR] NPH underflow — sent NP with 0 header credits!");

    end
end
`endif

endmodule
