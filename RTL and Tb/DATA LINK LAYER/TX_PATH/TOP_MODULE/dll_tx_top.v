// =============================================================================
// Module      : dll_tx_top
// Project     : PCIe Gen6 — Data Link Layer TX Path (Top Level)
// Description : Integrates all 10 DLL TX sub-modules into a single top-level
//               wrapper as defined in the PCIe Gen6 Base Specification.
//
// Sub-modules instantiated (in data-flow order):
//   1.  tl_interface          (TL_IF)     — TL/DLL boundary, FC forwarding
//   2.  seq_num_gen           (SEQ_GEN)   — 12-bit sequence number stamper
//   3.  crc_gen               (CRC_GEN)   — LCRC (32-bit) / FLIT CRC (24-bit)
//   4.  dllp_crc_gen          (DLLP_CRCG) — 16-bit CRC-16 for DLLPs
//   5.  retry_buf             (RETRY_BUF) — SRAM replay buffer
//   6.  flit_null_slot_inserter(NULL_INS) — Null padding for 256B FLITs
//   7.  dllp_arb              (DLLP_ARB)  — DLLP priority arbiter
//   8.  tx_datapath_mux       (TX_MUX)    — TLP/DLLP/retry mux → PHY
//   9.  scrambler             (SCRM)      — LFSR-based data scrambler
//  10.  pcie6_phy_tx          (PHY_TX)    — PIPE TX boundary to SERDES
//
// Data-flow path (normal TLP, Gen6 FLIT mode):
//   TL → TL_IF → SEQ_GEN (stamp seq#) → CRC_GEN (FLIT CRC-24)
//       → NULL_INS (pad empty slots) → TX_MUX → SCRM → PHY_TX → SERDES
//
// DLLP path:
//   External DLLP sources → DLLP_CRCG (CRC-16) → DLLP_ARB (priority sel)
//       → TX_MUX → SCRM → PHY_TX → SERDES
//
// Retry path:
//   TX_MUX captures new TLPs → RETRY_BUF; on NAK: RETRY_BUF → TX_MUX
//
// Port Map:
//   All external-facing ports of the 10 sub-modules are exposed. Internal
//   wires connect sub-modules. The only logic added here is wire routing.
// =============================================================================

`timescale 1ns/1ps

module dll_tx_top #(
    parameter BUF_DEPTH = 4096,
    parameter TLP_WIDTH = 1056,
    parameter PTR_W     = 12
)(
    // -------------------------------------------------------------------------
    // Global
    // -------------------------------------------------------------------------
    input  wire         clk,
    input  wire         rst_n,

    // =========================================================================
    // === EXTERNAL INPUTS =====================================================
    // =========================================================================

    // --- From Transaction Layer (TL_IF) --------------------------------------
    input  wire [1023:0] tlp_in,            // TLP data (legacy mode)
    input  wire          tlp_valid_in,       // TLP valid
    input  wire [2047:0] flit_in,           // 256-byte FLIT (Gen6)
    input  wire          flit_valid_in,      // FLIT valid
    input  wire          flit_mode_en,       // 0=legacy TLP, 1=Gen6 FLIT
    input  wire [7:0]    fc_update_ph,       // FC Posted-Header credit update
    input  wire          fc_update_valid,    // FC update strobe

    // --- Sequence Number Generator control -----------------------------------
    input  wire [11:0]   ack_seq,           // Highest ACK'd seq from peer
    input  wire [11:0]   nak_seq,           // NAK'd seq (replay from here)
    input  wire          retry_req,          // NAK received → replay
    input  wire          link_reset,         // Sync link-layer reset

    // --- DLLP sources (external, after CRC appended) -------------------------
    // Raw DLLP body input (48-bit) — goes through dllp_crc_gen first
    input  wire [47:0]   dllp_raw_in,       // Raw DLLP body
    input  wire          dllp_raw_valid,     // Raw DLLP valid

    // External pre-assembled DLLPs with CRC (ACK/NAK from RX path)
    input  wire [63:0]   ack_dllp,          // ACK/NAK DLLP (64-bit, CRC included)
    input  wire          ack_dllp_valid,     // ACK/NAK valid

    // Power-management DLLP
    input  wire [63:0]   pm_dllp,           // PM DLLP
    input  wire          pm_dllp_valid,      // PM valid

    // Misc DLLP valid flags (BW notification, NOP)
    input  wire          nop_valid,          // NOP DLLP
    input  wire          bw_dllp_valid,      // BW Notification DLLP

    // --- Null slot inserter --------------------------------------------------
    input  wire [1:0]    flit_slot_used,    // bit0=slot0 used, bit1=slot1 used
    input  wire [1023:0] null_pattern,      // 128-byte null-slot fill pattern

    // --- Scrambler control ---------------------------------------------------
    input  wire [22:0]   lfsr_seed,         // LFSR seed (PCIe default 7FFFFF)
    input  wire          scramble_en,        // 1=scramble, 0=bypass (compliance)

    // --- PHY TX control (LTSSM / Power Management) ---------------------------
    input  wire          tx_elec_idle_req,   // Request Electrical Idle
    input  wire          tx_compliance_req,  // Request compliance pattern

    // =========================================================================
    // === EXTERNAL OUTPUTS ====================================================
    // =========================================================================

    // --- TL Interface outputs ------------------------------------------------
    output wire          tl_ready,           // Back-pressure to TL
    output wire [71:0]   fc_to_dllp,         // FC update payload to DLLP gen
    output wire          fc_dllp_send,        // Pulse: send UpdateFC DLLP

    // --- Sequence number outputs ---------------------------------------------
    output wire [11:0]   seq_num_out,        // Current seq# stamped on TLP
    output wire          seq_valid_out,       // Seq# valid
    output wire          seq_wrap,            // Pulse: seq# wrapped 4095→0

    // --- CRC outputs ---------------------------------------------------------
    output wire [31:0]   lcrc_out,           // 32-bit LCRC (TLP mode)
    output wire [23:0]   flit_crc_out,       // 24-bit FLIT CRC (Gen6 mode)
    output wire          crc_valid,           // CRC result valid

    // --- DLLP CRC outputs ----------------------------------------------------
    output wire [15:0]   dllp_crc,           // 16-bit DLLP CRC
    output wire          dllp_crc_valid,      // DLLP CRC valid
    output wire [63:0]   dllp_full_out,       // Full 64-bit DLLP (body+CRC)

    // --- Retry buffer status -------------------------------------------------
    output wire [TLP_WIDTH-1:0] retry_tlp_out,  // Replayed TLP
    output wire          retry_valid_out,     // Replay valid
    output wire [11:0]   retry_seq_out,       // Replayed seq#
    output wire          buf_full,            // Retry buffer full
    output wire [11:0]   buf_occ,            // Retry buffer occupancy
    output wire          purge_done,          // ACK purge complete pulse

    // --- Null slot inserter outputs ------------------------------------------
    output wire [2047:0] flit_padded_out,    // Padded FLIT → downstream
    output wire          flit_padded_valid,   // Padded FLIT valid
    output wire          null_inserted,       // Null slot(s) inserted this cycle
    output wire [7:0]    null_count,          // Cumulative null insertion count

    // --- DLLP Arbiter outputs ------------------------------------------------
    output wire [63:0]   dllp_arb_out,       // Arbitrated DLLP (to TX_MUX)
    output wire          dllp_arb_valid,      // Arbitrated DLLP valid
    output wire [3:0]    dllp_type,           // DLLP type encoding

    // --- Scrambler outputs ---------------------------------------------------
    output wire [255:0]  scrambled_data,      // Scrambled output data
    output wire          scrambled_valid,      // Scrambled output valid
    output wire [22:0]   lfsr_state,          // LFSR state for debug/verification

    // --- PHY TX outputs (to SERDES) ------------------------------------------
    output wire [255:0]  phy_txd,             // 256-bit parallel data to SERDES
    output wire          phy_tx_valid,         // Data valid to SERDES
    output wire          phy_tx_elec_idle,     // Electrical idle
    output wire          phy_tx_compliance     // Compliance pattern
);

    // =========================================================================
    // Internal wires — inter-module connections
    // =========================================================================

    // TL_IF → downstream
    wire [1023:0] w_dll_tlp;
    wire          w_dll_tlp_valid;
    wire [2047:0] w_dll_flit;
    wire          w_dll_flit_valid;

    // SEQ_GEN → CRC_GEN, RETRY_BUF
    wire [11:0]   w_seq_num;
    wire          w_seq_valid;

    // CRC_GEN (outputs exposed externally, used internally for status)

    // DLLP_CRCG → DLLP_ARB
    wire [63:0]   w_dllp_full;
    wire          w_dllp_full_valid;

    // NULL_INS → TX_MUX (flit padded path)
    wire [2047:0] w_flit_null_out;
    wire          w_flit_null_valid;

    // DLLP_ARB → TX_MUX
    wire [63:0]   w_dllp_arb;
    wire          w_dllp_arb_valid;

    // RETRY_BUF → TX_MUX
    wire [TLP_WIDTH-1:0] w_retry_tlp;
    wire          w_retry_valid;
    wire [11:0]   w_retry_seq;

    // TX_MUX → SCRM
    wire [255:0]  w_mux_data;
    wire          w_mux_valid;
    wire          w_mux_sop;
    wire          w_mux_eop;

    // SCRM → PHY_TX
    wire [255:0]  w_scrm_data;
    wire          w_scrm_valid;

    // TLP to RETRY_BUF: pipeline by 1 cycle so seq_num has updated
    // seq_num_gen increments on the same posedge as w_dll_tlp_valid.
    // The registered output w_seq_num holds the NEW seq only AFTER that posedge.
    // So we delay the write enable and TLP data by 1 cycle to capture the correct seq.
    reg  [1023:0]      w_dll_tlp_d;
    reg                w_dll_tlp_valid_d;
    reg  [11:0]        w_seq_num_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_dll_tlp_d       <= {1024{1'b0}};
            w_dll_tlp_valid_d <= 1'b0;
            w_seq_num_d       <= 12'h0;
        end else begin
            w_dll_tlp_d       <= w_dll_tlp;
            w_dll_tlp_valid_d <= w_dll_tlp_valid;
            w_seq_num_d       <= w_seq_num;
        end
    end
    wire [TLP_WIDTH-1:0] w_tlp_to_retry;
    assign w_tlp_to_retry = {w_dll_tlp_d, w_seq_num_d, {(TLP_WIDTH-1036){1'b0}}};

    // =========================================================================
    // 1. TL Interface
    // =========================================================================
    tl_interface u_tl_if (
        .clk            (clk),
        .rst_n          (rst_n),
        // Inputs from TL
        .tlp_in         (tlp_in),
        .tlp_valid_in   (tlp_valid_in),
        .flit_in        (flit_in),
        .flit_valid_in  (flit_valid_in),
        .flit_mode_en   (flit_mode_en),
        .fc_update_ph   (fc_update_ph),
        .fc_update_valid(fc_update_valid),
        // Outputs to DLL internals
        .dll_tlp        (w_dll_tlp),
        .dll_tlp_valid  (w_dll_tlp_valid),
        .dll_flit       (w_dll_flit),
        .dll_flit_valid (w_dll_flit_valid),
        .tl_ready       (tl_ready),
        .fc_to_dllp     (fc_to_dllp),
        .fc_dllp_send   (fc_dllp_send)
    );

    // =========================================================================
    // 2. Sequence Number Generator
    // =========================================================================
    seq_num_gen u_seq_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_valid_in   (w_dll_tlp_valid | w_dll_flit_valid),
        .ack_seq        (ack_seq),
        .nak_seq        (nak_seq),
        .retry_req      (retry_req),
        .link_reset     (link_reset),
        // Outputs
        .seq_num        (w_seq_num),
        .seq_valid      (w_seq_valid),
        .seq_wrap       (seq_wrap)
    );

    assign seq_num_out  = w_seq_num;
    assign seq_valid_out = w_seq_valid;

    // =========================================================================
    // 3. LCRC / FLIT CRC Generator
    // =========================================================================
    crc_gen u_crc_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_in         (w_dll_tlp),
        .tlp_valid      (w_dll_tlp_valid),
        .flit_in        (w_dll_flit),
        .flit_valid     (w_dll_flit_valid),
        .flit_mode_en   (flit_mode_en),
        .seq_num        (w_seq_num),
        // Outputs
        .lcrc_out       (lcrc_out),
        .flit_crc_out   (flit_crc_out),
        .crc_valid      (crc_valid)
    );

    // =========================================================================
    // 4. DLLP CRC Generator
    //    Takes raw 48-bit DLLP body, appends 16-bit CRC → 64-bit full DLLP
    // =========================================================================
    dllp_crc_gen u_dllp_crc_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .dllp_in        (dllp_raw_in),
        .dllp_valid_in  (dllp_raw_valid),
        // Outputs
        .dllp_crc       (dllp_crc),
        .dllp_crc_valid (dllp_crc_valid),
        .dllp_full      (w_dllp_full)
    );
    assign dllp_full_out    = w_dllp_full;
    assign w_dllp_full_valid = dllp_crc_valid;

    // =========================================================================
    // 5. Retry Buffer
    //    Stores transmitted TLPs; replays on NAK
    // =========================================================================
    retry_buf #(
        .BUF_DEPTH(BUF_DEPTH),
        .TLP_WIDTH(TLP_WIDTH),
        .PTR_W    (PTR_W)
    ) u_retry_buf (
        .clk            (clk),
        .rst_n          (rst_n),
        // Write path: new TLPs
        .tlp_in         (w_tlp_to_retry),
        .tlp_write_en   (w_dll_tlp_valid_d & ~buf_full),  // 1-cycle delayed valid
        .seq_num_in     (w_seq_num),  // w_seq_num already has new seq at N+1 when write_en fires
        // ACK/NAK
        .ack_seq        (ack_seq),
        .nak_seq        (nak_seq),
        .retry_req      (retry_req),
        // Replay output
        .retry_tlp      (w_retry_tlp),
        .retry_valid    (w_retry_valid),
        .retry_seq      (w_retry_seq),
        // Status
        .buf_full       (buf_full),
        .buf_occ        (buf_occ),
        .purge_done     (purge_done)
    );
    assign retry_tlp_out  = w_retry_tlp;
    assign retry_valid_out= w_retry_valid;
    assign retry_seq_out  = w_retry_seq;

    // =========================================================================
    // 6. FLIT Null Slot Inserter
    //    Pads unused FLIT slots with null pattern before FEC / scrambling
    // =========================================================================
    flit_null_slot_inserter u_null_ins (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_in        (w_dll_flit),
        .flit_valid     (w_dll_flit_valid),
        .flit_slot_used (flit_slot_used),
        .null_pattern   (null_pattern),
        // Outputs
        .flit_out       (w_flit_null_out),
        .flit_out_valid (w_flit_null_valid),
        .null_inserted  (null_inserted),
        .null_count     (null_count)
    );
    assign flit_padded_out   = w_flit_null_out;
    assign flit_padded_valid = w_flit_null_valid;

    // =========================================================================
    // 7. DLLP Arbiter
    //    Priority: ACK/NAK > UpdateFC > PM > BW Notification > NOP
    //    The FC DLLP uses the full DLLP from dllp_crc_gen (fc path)
    // =========================================================================
    dllp_arb u_dllp_arb (
        .clk            (clk),
        .rst_n          (rst_n),
        // Source 1: ACK/NAK (highest priority — comes pre-assembled from RX path)
        .ack_dllp       (ack_dllp),
        .ack_dllp_valid (ack_dllp_valid),
        // Source 2: UpdateFC (FC DLLP assembled by dllp_crc_gen from raw input)
        .fc_dllp        (w_dllp_full),
        .fc_dllp_valid  (w_dllp_full_valid),
        // Source 3: PM
        .pm_dllp        (pm_dllp),
        .pm_dllp_valid  (pm_dllp_valid),
        // Source 4: NOP
        .nop_valid      (nop_valid),
        // Source 5: BW Notification
        .bw_dllp_valid  (bw_dllp_valid),
        // Outputs
        .dllp_out       (w_dllp_arb),
        .dllp_out_valid (w_dllp_arb_valid),
        .dllp_type      (dllp_type)
    );
    assign dllp_arb_out   = w_dllp_arb;
    assign dllp_arb_valid = w_dllp_arb_valid;

    // =========================================================================
    // 8. TX Datapath MUX
    //    Priority: Retry TLPs > New TLPs > DLLPs
    //    Serialises packets into 256-bit beats for the scrambler/PHY
    // =========================================================================
    tx_datapath_mux u_tx_mux (
        .clk            (clk),
        .rst_n          (rst_n),
        // New TLP input (from TL_IF, 1056-bit padded)
        .tlp_tx         ({w_dll_tlp, {(TLP_WIDTH-1024){1'b0}}}),
        .tlp_tx_valid   (w_dll_tlp_valid),
        // Retry TLP from replay buffer
        .retry_tlp      (w_retry_tlp),
        .retry_valid    (w_retry_valid),
        // DLLP from arbiter
        .dllp_out       (w_dllp_arb),
        .dllp_valid     (w_dllp_arb_valid),
        // Retry trigger
        .retry_req      (retry_req),
        // PHY 256-bit output
        .phy_tx_data    (w_mux_data),
        .phy_tx_valid   (w_mux_valid),
        .phy_tx_sop     (w_mux_sop),
        .phy_tx_eop     (w_mux_eop)
    );

    // =========================================================================
    // 9. Scrambler
    //    LFSR G(x)=x^23+x^18+1, 256-bit parallel expansion
    // =========================================================================
    scrambler u_scrambler (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in        (w_mux_data),
        .data_valid_in  (w_mux_valid),
        .lfsr_seed      (lfsr_seed),
        .scramble_en    (scramble_en),
        .link_reset     (link_reset),
        // Outputs
        .data_out       (w_scrm_data),
        .data_valid_out (w_scrm_valid),
        .lfsr_state     (lfsr_state)
    );
    assign scrambled_data  = w_scrm_data;
    assign scrambled_valid = w_scrm_valid;

    // =========================================================================
    // SOP / EOP pipeline alignment
    // The scrambler adds 1 registered stage to data/valid.
    // SOP and EOP from TX_MUX are combinational; they must be delayed by 1
    // cycle so they arrive at PHY_TX together with the scrambled data.
    // =========================================================================
    reg w_scrm_sop, w_scrm_eop;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_scrm_sop <= 1'b0;
            w_scrm_eop <= 1'b0;
        end else begin
            w_scrm_sop <= w_mux_sop;
            w_scrm_eop <= w_mux_eop;
        end
    end

    // =========================================================================
    // 10. PHY TX Interface (PIPE boundary)
    //     Drives SERDES with framing, electrical idle, and compliance control
    // =========================================================================
    pcie6_phy_tx u_phy_tx (
        .clk                 (clk),
        .rst_n               (rst_n),
        .tx_data             (w_scrm_data),
        .tx_valid            (w_scrm_valid),
        .tx_sop              (w_scrm_sop),   // SOP aligned with scrambled data
        .tx_eop              (w_scrm_eop),   // EOP aligned with scrambled data
        .tx_elec_idle_req    (tx_elec_idle_req),
        .tx_compliance_req   (tx_compliance_req),
        // PHY SERDES outputs
        .phy_txd             (phy_txd),
        .phy_tx_valid        (phy_tx_valid),
        .phy_tx_elec_idle    (phy_tx_elec_idle),
        .phy_tx_compliance   (phy_tx_compliance)
    );

endmodule
