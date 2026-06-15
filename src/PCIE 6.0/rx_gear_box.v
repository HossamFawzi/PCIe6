module rx_gear_box (
    input  wire         clk_ser,
    input  wire         clk_par,
    input  wire         rst_n,
    input  wire [63:0]  ser_data_in,
    input  wire         ser_valid,
    input  wire [2:0]   gear_ratio,
    output reg  [255:0] par_data_out,
    output reg          par_valid
);

    // -----------------------------------------------------------------------
    // Sanitised ratio (default to 1 if 0 is passed)
    // -----------------------------------------------------------------------
    wire [2:0] ratio = (gear_ratio == 3'd0) ? 3'd1 : gear_ratio;

    // -----------------------------------------------------------------------
    // clk_ser domain
    // -----------------------------------------------------------------------
    reg [255:0] ser_accum;
    reg [2:0]   ser_count;

    // Double-buffer: ser domain writes buf_a; par domain reads buf_b via swap
    reg [255:0] buf_a;
    reg         buf_a_wr;       // one-cycle pulse in clk_ser

    // Toggle flag for CDC
    reg         ser_toggle;

    always @(posedge clk_ser or negedge rst_n) begin
        if (!rst_n) begin
            ser_accum  <= 256'd0;
            ser_count  <= 3'd0;
            buf_a      <= 256'd0;
            buf_a_wr   <= 1'b0;
            ser_toggle <= 1'b0;
        end else begin
            buf_a_wr <= 1'b0;

            if (ser_valid) begin
                // Shift accumulator: earlier data occupies the upper bits
                ser_accum <= {ser_accum[191:0], ser_data_in};
                ser_count <= ser_count + 1'b1;

                if ((ser_count + 3'd1) >= ratio) begin
                    case (ratio)
                        3'd1: buf_a <= {192'd0, ser_data_in};
                        3'd2: buf_a <= {128'd0, ser_accum[63:0], ser_data_in};
                        3'd4: buf_a <= {ser_accum[191:0],        ser_data_in};
                        default: buf_a <= {ser_accum[191:0],     ser_data_in};
                    endcase
                    buf_a_wr   <= 1'b1;
                    ser_toggle <= ~ser_toggle;
                    ser_count  <= 3'd0;
                    ser_accum  <= 256'd0;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // CDC capture register (written in clk_ser, read in clk_par)
    // Gray-coded hand-off: buf_a is frozen for at least (ratio) clk_ser cycles
    // before ser_toggle propagates through the 2-FF synchronizer — safe for
    // gear ratios >= 2.  For ratio=1 an external guarantee is needed that
    // clk_par <= clk_ser / 2.
    // -----------------------------------------------------------------------
    reg [255:0] cdc_data;

    always @(posedge clk_ser or negedge rst_n) begin
        if (!rst_n) cdc_data <= 256'd0;
        else if (buf_a_wr) cdc_data <= buf_a;
    end

    // -----------------------------------------------------------------------
    // Double-FF synchroniser: clk_ser toggle → clk_par
    // -----------------------------------------------------------------------
    reg toggle_meta, toggle_sync, toggle_prev;

    always @(posedge clk_par or negedge rst_n) begin
        if (!rst_n) begin
            toggle_meta <= 1'b0;
            toggle_sync <= 1'b0;
            toggle_prev <= 1'b0;
        end else begin
            toggle_meta <= ser_toggle;
            toggle_sync <= toggle_meta;
            toggle_prev <= toggle_sync;
        end
    end

    // -----------------------------------------------------------------------
    // clk_par domain: edge detect on synchronised toggle → latch & output
    // -----------------------------------------------------------------------
    always @(posedge clk_par or negedge rst_n) begin
        if (!rst_n) begin
            par_data_out <= 256'd0;
            par_valid    <= 1'b0;
        end else begin
            if (toggle_sync != toggle_prev) begin
                par_data_out <= cdc_data;
                par_valid    <= 1'b1;
            end else begin
                par_valid    <= 1'b0;
            end
        end
    end

endmodule
