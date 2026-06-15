// =============================================================================
// Module 8: TX Datapath MUX (PHY)
// PCIe Gen6 Physical Layer
// Description: Final TX multiplexer. Selects between:
//   - Electrical Idle  (Priority 1 — highest)
//   - Ordered Sets     (Priority 2)
//   - FLIT data Gen6   (Priority 3a)
//   - Encoded data Gen1-5 (Priority 3b)
//
// Note: FLIT is 2048b. This MUX passes the first 256b slice to the PIPE
//       interface; the TX Gear Box (Module 6) handles full serialization.
// =============================================================================
module tx_datapath_mux (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [255:0]  enc_data,
    input  wire          enc_valid,

    input  wire [255:0]  os_data,
    input  wire          os_valid,

    input  wire [2047:0] flit_data,
    input  wire          flit_valid,

    input  wire          tx_elec_idle,
    input  wire          flit_mode_en,

    output reg  [255:0]  tx_out,
    output reg           tx_out_valid,
    output reg           tx_elec_idle_out,
    output reg  [1:0]    mux_sel  // 0=elec_idle,1=OS,2=enc,3=flit
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_out           <= {256{1'b0}};
        tx_out_valid     <= 1'b0;
        tx_elec_idle_out <= 1'b0;
        mux_sel          <= 2'h0;
    end else begin
        tx_elec_idle_out <= 1'b0;
        tx_out_valid     <= 1'b0;

        if (tx_elec_idle) begin
            tx_out           <= {256{1'b0}};
            tx_elec_idle_out <= 1'b1;
            tx_out_valid     <= 1'b1;
            mux_sel          <= 2'h0;
        end else if (os_valid) begin
            tx_out       <= os_data;
            tx_out_valid <= 1'b1;
            mux_sel      <= 2'h1;
        end else if (flit_mode_en && flit_valid) begin
            // First 256b slice — Gear Box serializes the full 2048b FLIT
            tx_out       <= flit_data[2047:1792];
            tx_out_valid <= 1'b1;
            mux_sel      <= 2'h3;
        end else if (enc_valid) begin
            tx_out       <= enc_data;
            tx_out_valid <= 1'b1;
            mux_sel      <= 2'h2;
        end else begin
            tx_out       <= {256{1'b0}};
            tx_out_valid <= 1'b0;
            mux_sel      <= 2'h0;
        end
    end
end

endmodule
