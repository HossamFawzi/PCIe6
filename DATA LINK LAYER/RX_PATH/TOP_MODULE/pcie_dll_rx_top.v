// =============================================================================
// Module  : pcie_dll_rx_top
// Layer   : Data Link Layer (DLL) — RX Path Top Module
// Spec    : PCIe Gen6 Base Specification r1.0
//
// Description:
//   Top-level integration of all 12 DLL RX Path sub-modules:
//
//   PHY_IF_RX  → Descrambler → FLIT_RX_DEFRAMER → NULL_HDL
//                                     ↓
//                             RX_DEMUX
//                            /        \
//                      TLP path      DLLP path
//                   LCRC_CHK       DLLP_CRC_CHK
//                   SEQ_CHK        DLLP_MAL_CHK
//                   ACK_NAK_SCHED  DLLP_RX_DEC
//                                  ACK_NAK_RCV
//
// Datapath Summary:
//   RX beats (256b) → PHY Interface RX assembles 2048-bit FLITs
//   FLITs → Descrambler (undo LFSR scrambling)
//   Descrambled FLITs → FLIT Rx Deframer (extract TLP/DLLP slots, CRC24)
//   Null slots → Nullified TLP Handler (drop + count)
//   FLIT outputs → RX Datapath DEMUX (route TLP vs DLLP)
//   TLP path: LCRC/FLIT CRC Check → Seq Num Check → ACK/NAK Scheduler TX
//   DLLP path: DLLP CRC Check → DLLP Malformed Check → DLLP Receiver/Decoder
//              → ACK/NAK Receiver
// =============================================================================

`timescale 1ns/1ps

module pcie_dll_rx_top (
    // ── Clock & Reset ──────────────────────────────────────────────────────────
    input  wire          clk,
    input  wire          rst_n,

    // ── PHY Interface Inputs ───────────────────────────────────────────────────
    input  wire [255:0]  phy_rxd,
    input  wire          phy_rx_valid,
    input  wire [2:0]    phy_rx_status,
    input  wire [15:0]   fec_syndrome,
    input  wire          fec_corrected,
    input  wire          ltssm_dl_up,

    // ── Descrambler Control ────────────────────────────────────────────────────
    input  wire [22:0]   lfsr_seed,
    input  wire          scramble_en,
    input  wire          link_reset,

    // ── Mode Select ────────────────────────────────────────────────────────────
    input  wire          flit_mode_en,

    // ── ACK/NAK Scheduler TX Control ──────────────────────────────────────────
    input  wire          ack_timer_exp,
    input  wire [7:0]    ack_freq,

    // ── TLP Output (to Transaction Layer) ─────────────────────────────────────
    output wire [1023:0] tlp_fwd,
    output wire          tlp_fwd_valid,

    // ── Sequence Check Status ──────────────────────────────────────────────────
    output wire          tlp_seq_ok,
    output wire          tlp_dup,
    output wire          tlp_seq_err,
    output wire          nak_req,
    output wire [11:0]   next_expected,

    // ── ACK/NAK Scheduler TX Outputs ──────────────────────────────────────────
    output wire [63:0]   ack_dllp,
    output wire [63:0]   nak_dllp,
    output wire          dllp_valid_tx,
    output wire [1:0]    dllp_type_tx,

    // ── DLLP Decoder Outputs (FC Updates) ─────────────────────────────────────
    output wire [7:0]    fc_update_ph,
    output wire [11:0]   fc_update_pd,
    output wire [7:0]    fc_update_nph,
    output wire [7:0]    fc_update_cplh,
    output wire [11:0]   fc_update_cpld,
    output wire          fc_update_valid,
    output wire [2:0]    pm_type,
    output wire          pm_valid,

    // ── ACK/NAK Receiver Outputs ───────────────────────────────────────────────
    output wire [11:0]   ack_seq,
    output wire [11:0]   nak_seq,
    output wire          ack_valid,
    output wire          nak_valid,
    output wire          retry_req,

    // ── Error / Status Outputs ─────────────────────────────────────────────────
    output wire          lfsr_sync_err,
    output wire          flit_crc_err,
    output wire          flit_null,
    output wire          flit_uncorr_err,
    output wire          null_drop,
    output wire [7:0]    null_count,
    output wire          rx_parse_err,
    output wire          dllp_crc_ok,
    output wire          dllp_crc_err,
    output wire          dllp_mal_err
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // PHY_IF_RX → Descrambler
    wire [255:0]  phy_rx_data_out;
    wire          phy_rx_data_valid;
    wire [2047:0] phy_rx_flit;
    wire          phy_rx_flit_valid;

    // Descrambler → FLIT Deframer
    wire [255:0]  descr_data_out;
    wire          descr_data_valid;

    // We feed descrambled beats to FLIT deframer via a second PHY_IF_RX-like
    // accumulation. Since the Descrambler operates beat-by-beat (256b),
    // we need to re-accumulate a FLIT. In this top-level we connect the
    // FLIT (already assembled by PHY_IF_RX) through the Descrambler at
    // the 256-bit beat level, then pass the assembled FLIT directly.
    // For simplicity: PHY_IF_RX assembles the FLIT, then Descrambler
    // descrambles the 256-bit beat stream. We connect them as a pipeline:
    // PHY_IF_RX beat output → Descrambler → accumulate → FLIT Deframer.
    //
    // Architectural note: In real Gen6 HW, descrambling happens at the
    // symbol level before FLIT assembly. Here we model it with the DUT
    // modules as-given: Descrambler is 256-bit wide, takes data_valid_in
    // and outputs a 256-bit descrambled word. The PHY_IF_RX assembled FLIT
    // is used directly when scramble_en=0 (bypass). When scramble_en=1
    // the beat-level output of PHY_IF_RX feeds the Descrambler and we
    // reassemble below.

    // Reassemble FLIT from descrambled beats
    reg [2047:0] descr_flit_buf;
    reg [2:0]    descr_beat_cnt;
    reg [2047:0] descr_flit;
    reg          descr_flit_valid;
    // Forward FEC signals through to FLIT deframer
    reg [15:0]   descr_fec_syndrome_r;
    reg          descr_fec_corrected_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            descr_flit_buf      <= {2048{1'b0}};
            descr_beat_cnt      <= 3'd0;
            descr_flit          <= {2048{1'b0}};
            descr_flit_valid    <= 1'b0;
            descr_fec_syndrome_r<= 16'h0;
            descr_fec_corrected_r<= 1'b0;
        end else begin
            descr_flit_valid <= 1'b0;
            if (descr_data_valid) begin
                descr_fec_syndrome_r  <= fec_syndrome;
                descr_fec_corrected_r <= fec_corrected;
                case (descr_beat_cnt)
                    3'd0: descr_flit_buf[255:0]    <= descr_data_out;
                    3'd1: descr_flit_buf[511:256]   <= descr_data_out;
                    3'd2: descr_flit_buf[767:512]   <= descr_data_out;
                    3'd3: descr_flit_buf[1023:768]  <= descr_data_out;
                    3'd4: descr_flit_buf[1279:1024] <= descr_data_out;
                    3'd5: descr_flit_buf[1535:1280] <= descr_data_out;
                    3'd6: descr_flit_buf[1791:1536] <= descr_data_out;
                    3'd7: begin
                        descr_flit       <= {descr_data_out, descr_flit_buf[1791:0]};
                        descr_flit_valid <= 1'b1;
                    end
                endcase
                if (descr_beat_cnt == 3'd7)
                    descr_beat_cnt <= 3'd0;
                else
                    descr_beat_cnt <= descr_beat_cnt + 3'd1;
            end
        end
    end

    // FLIT Deframer → DEMUX
    wire [1023:0] flit_tlp;
    wire          flit_tlp_valid;
    wire [63:0]   flit_dllp_raw;
    wire          flit_dllp_valid;
    wire [11:0]   flit_seq;

    // Null handler
    wire          flit_null_int;

    // DEMUX → CRC checkers
    wire [1055:0] tlp_rx_wire;
    wire          tlp_rx_valid_wire;
    wire [63:0]   dllp_raw_wire;
    wire          dllp_rx_valid_wire;

    // LCRC checker → Seq checker
    wire          lcrc_crc_ok;
    wire          lcrc_crc_err;
    wire [1023:0] lcrc_tlp_clean;
    wire          lcrc_tlp_clean_valid;
    wire [11:0]   lcrc_seq_rx;

    // Seq checker → ACK/NAK Scheduler
    wire          seq_tlp_seq_ok;
    wire          seq_tlp_dup;
    wire          seq_tlp_seq_err;
    wire          seq_nak_req;
    wire          seq_dup_ack;
    wire [11:0]   seq_err_val;
    wire [11:0]   seq_next_expected;
    wire [1023:0] seq_tlp_fwd;
    wire          seq_tlp_fwd_valid;

    // DLLP CRC checker → MAL checker
    wire [47:0]   dllp_body_wire;
    wire          dllp_crc_ok_int;
    wire          dllp_crc_err_int;
    wire          dllp_valid_out_wire;

    // MAL checker → DLLP Decoder
    wire          dllp_type_ok_wire;
    wire          dllp_mal_err_int;
    wire [47:0]   dllp_clean_wire;
    wire          dllp_clean_valid_wire;

    // DLLP Decoder → ACK/NAK Receiver
    wire [23:0]   ack_out_wire;
    wire          ack_out_valid_wire;

    // =========================================================================
    // Module instantiations
    // =========================================================================

    // 1. PHY Interface RX
    phy_interface_rx u_phy_if_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .phy_rxd       (phy_rxd),
        .phy_rx_valid  (phy_rx_valid),
        .phy_rx_status (phy_rx_status),
        .fec_syndrome  (fec_syndrome),
        .fec_corrected (fec_corrected),
        .ltssm_dl_up   (ltssm_dl_up),
        .rx_data       (phy_rx_data_out),
        .rx_valid      (phy_rx_data_valid),
        .rx_flit       (phy_rx_flit),
        .rx_flit_valid (phy_rx_flit_valid)
    );

    // 2. Descrambler (operates on beat-level 256-bit data)
    Descrambler u_descrambler (
        .clk           (clk),
        .rst_n         (rst_n),
        .data_in       (phy_rx_data_out),
        .data_valid_in (phy_rx_data_valid),
        .lfsr_seed     (lfsr_seed),
        .scramble_en   (scramble_en),
        .link_reset    (link_reset),
        .data_out      (descr_data_out),
        .data_valid_out(descr_data_valid),
        .lfsr_sync_err (lfsr_sync_err)
    );

    // 3. FLIT RX Deframer (uses descrambled FLIT when scramble_en, else phy FLIT)
    flit_rx_deframer u_flit_deframer (
        .clk            (clk),
        .rst_n          (rst_n),
        .rx_flit        (scramble_en ? descr_flit : phy_rx_flit),
        .rx_flit_valid  (scramble_en ? descr_flit_valid : phy_rx_flit_valid),
        .fec_syndrome   (fec_syndrome),
        .fec_corrected  (fec_corrected),
        .flit_tlp       (flit_tlp),
        .flit_tlp_valid (flit_tlp_valid),
        .flit_dllp      (flit_dllp_raw),
        .flit_dllp_valid(flit_dllp_valid),
        .flit_seq       (flit_seq),
        .flit_crc_err   (flit_crc_err),
        .flit_null      (flit_null_int),
        .flit_uncorr_err(flit_uncorr_err)
    );

    assign flit_null = flit_null_int;

    // 4. Nullified TLP Handler
    nullified_tlp_handler u_null_hdl (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_null      (flit_null_int),
        .flit_slot_data (flit_tlp),
        .flit_slot_valid(flit_tlp_valid | flit_null_int),
        .null_drop      (null_drop),
        .null_count     (null_count)
    );

    // 5. RX Datapath DEMUX
    rx_datapath_demux u_rx_demux (
        .clk            (clk),
        .rst_n          (rst_n),
        .rx_data        (phy_rx_data_out),
        .rx_valid       (phy_rx_data_valid),
        .flit_tlp       (flit_tlp),
        .flit_tlp_valid (flit_tlp_valid),
        .flit_dllp      (flit_dllp_raw),
        .flit_dllp_valid(flit_dllp_valid),
        .flit_mode_en   (flit_mode_en),
        .tlp_rx         (tlp_rx_wire),
        .tlp_rx_valid   (tlp_rx_valid_wire),
        .dllp_raw       (dllp_raw_wire),
        .dllp_rx_valid  (dllp_rx_valid_wire),
        .rx_parse_err   (rx_parse_err)
    );

    // 6. LCRC / FLIT CRC Checker
    lcrc_flit_crc_chk u_lcrc_chk (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_rx         (tlp_rx_wire),
        .tlp_rx_valid   (tlp_rx_valid_wire),
        .flit_mode_en   (flit_mode_en),
        .crc_ok         (lcrc_crc_ok),
        .crc_err        (lcrc_crc_err),
        .tlp_clean      (lcrc_tlp_clean),
        .tlp_clean_valid(lcrc_tlp_clean_valid),
        .seq_rx         (lcrc_seq_rx)
    );

    // 7. Sequence Number Checker RX
    seq_num_checker_rx u_seq_chk (
        .clk            (clk),
        .rst_n          (rst_n),
        .link_reset     (link_reset),
        .seq_rx         (lcrc_seq_rx),
        .tlp_rx_valid   (lcrc_tlp_clean_valid),
        .tlp_ok         (lcrc_crc_ok),
        .tlp_clean      (lcrc_tlp_clean),
        .tlp_seq_ok     (seq_tlp_seq_ok),
        .tlp_dup        (seq_tlp_dup),
        .tlp_seq_err    (seq_tlp_seq_err),
        .nak_req        (seq_nak_req),
        .seq_dup_ack    (seq_dup_ack),
        .seq_err_val    (seq_err_val),
        .next_expected  (seq_next_expected),
        .tlp_fwd        (seq_tlp_fwd),
        .tlp_fwd_valid  (seq_tlp_fwd_valid)
    );

    // 8. ACK/NAK Scheduler TX
    ack_nak_scheduler_tx u_ack_sched (
        .clk            (clk),
        .rst_n          (rst_n),
        .seq_rx         (lcrc_seq_rx),
        .crc_ok         (lcrc_crc_ok),
        .tlp_rx_valid   (lcrc_tlp_clean_valid),
        .ack_timer_exp  (ack_timer_exp),
        .ack_freq       (ack_freq),
        .ack_dllp       (ack_dllp),
        .nak_dllp       (nak_dllp),
        .dllp_valid     (dllp_valid_tx),
        .dllp_type      (dllp_type_tx)
    );

    // 9. DLLP CRC Checker
    dllp_crc_chk u_dllp_crc (
        .clk            (clk),
        .rst_n          (rst_n),
        .dllp_raw       (dllp_raw_wire),
        .dllp_rx_valid  (dllp_rx_valid_wire),
        .dllp_body      (dllp_body_wire),
        .dllp_crc_ok    (dllp_crc_ok_int),
        .dllp_crc_err   (dllp_crc_err_int),
        .dllp_valid_out (dllp_valid_out_wire)
    );

    assign dllp_crc_ok  = dllp_crc_ok_int;
    assign dllp_crc_err = dllp_crc_err_int;

    // 10. DLLP Malformed Checker
    dllp_mal_chk u_dllp_mal (
        .clk             (clk),
        .rst_n           (rst_n),
        .dllp_body       (dllp_body_wire),
        .dllp_crc_ok     (dllp_crc_ok_int),
        .dllp_valid_in   (dllp_valid_out_wire),
        .dllp_type_ok    (dllp_type_ok_wire),
        .dllp_mal_err    (dllp_mal_err_int),
        .dllp_clean      (dllp_clean_wire),
        .dllp_clean_valid(dllp_clean_valid_wire)
    );

    assign dllp_mal_err = dllp_mal_err_int;

    // 11. DLLP Receiver / Decoder
    dllp_receiver_decoder u_dllp_dec (
        .clk             (clk),
        .rst_n           (rst_n),
        .dllp_clean      (dllp_clean_wire),
        .dllp_clean_valid(dllp_clean_valid_wire),
        .fc_update_ph    (fc_update_ph),
        .fc_update_pd    (fc_update_pd),
        .fc_update_nph   (fc_update_nph),
        .fc_update_cplh  (fc_update_cplh),
        .fc_update_cpld  (fc_update_cpld),
        .fc_update_valid (fc_update_valid),
        .pm_type         (pm_type),
        .pm_valid        (pm_valid),
        .ack_out         (ack_out_wire),
        .ack_out_valid   (ack_out_valid_wire)
    );

    // 12. ACK/NAK Receiver
    ack_nak_receiver u_ack_rcv (
        .clk             (clk),
        .rst_n           (rst_n),
        .ack_out         (ack_out_wire),
        .ack_out_valid   (ack_out_valid_wire),
        .ack_seq         (ack_seq),
        .nak_seq         (nak_seq),
        .ack_valid       (ack_valid),
        .nak_valid       (nak_valid),
        .retry_req       (retry_req)
    );

    // ── Passthrough output assignments ─────────────────────────────────────────
    assign tlp_fwd        = seq_tlp_fwd;
    assign tlp_fwd_valid  = seq_tlp_fwd_valid;
    assign tlp_seq_ok     = seq_tlp_seq_ok;
    assign tlp_dup        = seq_tlp_dup;
    assign tlp_seq_err    = seq_tlp_seq_err;
    assign nak_req        = seq_nak_req;
    assign next_expected  = seq_next_expected;

endmodule
