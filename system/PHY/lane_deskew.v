module lane_deskew #(
    parameter DATA_WIDTH = 32,
    parameter NUM_LANES  = 16,
    parameter FIFO_DEPTH = 64,
    parameter FIFO_BITS  = 6,
    parameter MAX_SKEW   = 16
)(
    input  wire                             clk,
    input  wire                             rst_n,
    input  wire [NUM_LANES*DATA_WIDTH-1:0]  lane_data,
    input  wire [NUM_LANES-1:0]             lane_valid,
    input  wire [NUM_LANES-1:0]             skp_detected,
    input  wire                             deskew_en,
    output wire [NUM_LANES*DATA_WIDTH-1:0]  deskewed_data,
    output wire [NUM_LANES-1:0]             deskew_valid,
    output reg  [4:0]                       skew_amount,
    output reg                              deskew_err
);

    integer i;

    // -----------------------------------------------------------------------
    // Per-lane data FIFOs
    // -----------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] fifo     [0:NUM_LANES-1][0:FIFO_DEPTH-1];
    reg [FIFO_BITS-1:0]  wr_ptr   [0:NUM_LANES-1];
    reg [FIFO_BITS-1:0]  rd_ptr   [0:NUM_LANES-1];
    reg [FIFO_BITS:0]    fifo_cnt [0:NUM_LANES-1];

    // -----------------------------------------------------------------------
    // Global tick counter — free-running, used ONLY for skew measurement
    // Not bounded by FIFO depth, so pointer wrap cannot corrupt skew result
    // -----------------------------------------------------------------------
    reg [7:0] global_tick;
    reg [7:0] skp_time  [0:NUM_LANES-1];   // tick when each lane saw SKP
    reg [FIFO_BITS-1:0] skp_wr_snap [0:NUM_LANES-1]; // FIFO wr_ptr at SKP

    reg [NUM_LANES-1:0] skp_seen;
    reg                 aligned;

    // Combinational temporaries (blocking inside always)
    reg [7:0]            max_tick;
    reg [7:0]            min_tick;
    reg [7:0]            raw_skew_full;
    reg [4:0]            raw_skew;
    reg [FIFO_BITS-1:0]  max_snap;
    reg [FIFO_BITS-1:0]  skew_slots;

    wire all_skp_seen = (skp_seen == {NUM_LANES{1'b1}});

    // -----------------------------------------------------------------------
    // Write path + skew tracking
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_tick <= 8'd0;
            skp_seen    <= {NUM_LANES{1'b0}};
            aligned     <= 1'b0;
            skew_amount <= 5'd0;
            deskew_err  <= 1'b0;
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                wr_ptr[i]      <= {FIFO_BITS{1'b0}};
                rd_ptr[i]      <= {FIFO_BITS{1'b0}};
                fifo_cnt[i]    <= {(FIFO_BITS+1){1'b0}};
                skp_time[i]    <= 8'd0;
                skp_wr_snap[i] <= {FIFO_BITS{1'b0}};
            end
        end else if (deskew_en) begin
            global_tick <= global_tick + 1'b1;

            // Write lane data into per-lane FIFOs
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                if (lane_valid[i] && (fifo_cnt[i] < FIFO_DEPTH)) begin
                    fifo[i][wr_ptr[i]] <= lane_data[i*DATA_WIDTH +: DATA_WIDTH];
                    // Record SKP arrival using global tick (not FIFO pointer)
                    if (skp_detected[i] && !skp_seen[i]) begin
                        skp_time[i]    <= global_tick;
                        skp_wr_snap[i] <= wr_ptr[i];
                        skp_seen[i]    <= 1'b1;
                    end
                    wr_ptr[i]   <= wr_ptr[i] + 1'b1;
                    fifo_cnt[i] <= fifo_cnt[i] + 1'b1;
                end
            end

            // All lanes have seen SKP — compute skew using tick counters
            if (all_skp_seen && !aligned) begin
                // Find max and min SKP tick values
                max_tick = skp_time[0];
                min_tick = skp_time[0];
                for (i = 1; i < NUM_LANES; i = i + 1) begin
                    if (skp_time[i] > max_tick) max_tick = skp_time[i];
                    if (skp_time[i] < min_tick) min_tick = skp_time[i];
                end

                raw_skew_full = max_tick - min_tick;
                raw_skew      = (raw_skew_full > 8'd31) ? 5'd31 : raw_skew_full[4:0];
                skew_amount  <= raw_skew;

                if (raw_skew_full > MAX_SKEW) begin
                    deskew_err <= 1'b1;
                end else begin
                    deskew_err <= 1'b0;
                    // Set read pointers so all lanes start replaying from
                    // the same logical position relative to the latest SKP
                    max_snap = skp_wr_snap[0];
                    for (i = 1; i < NUM_LANES; i = i + 1) begin
                        if (skp_wr_snap[i] > max_snap) max_snap = skp_wr_snap[i];
                    end
                    for (i = 0; i < NUM_LANES; i = i + 1) begin
                        skew_slots    = max_snap - skp_wr_snap[i];
                        rd_ptr[i]    <= skp_wr_snap[i] - skew_slots;
                    end
                end

                aligned  <= 1'b1;
                skp_seen <= {NUM_LANES{1'b0}};
            end

        end else begin
            // deskew_en deasserted — flush state
            global_tick <= 8'd0;
            aligned     <= 1'b0;
            skp_seen    <= {NUM_LANES{1'b0}};
            skew_amount <= 5'd0;
            deskew_err  <= 1'b0;
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                wr_ptr[i]   <= {FIFO_BITS{1'b0}};
                rd_ptr[i]   <= {FIFO_BITS{1'b0}};
                fifo_cnt[i] <= {(FIFO_BITS+1){1'b0}};
            end
        end
    end

    // -----------------------------------------------------------------------
    // Output mux: bypass (combinational) or deskewed (registered)
    // -----------------------------------------------------------------------
    reg  [NUM_LANES*DATA_WIDTH-1:0]  deskewed_data_r;
    reg  [NUM_LANES-1:0]             deskew_valid_r;

    // Combinational bypass: when deskew_en=0, output = input immediately
    assign deskewed_data = deskew_en ? deskewed_data_r : lane_data;
    assign deskew_valid  = deskew_en ? deskew_valid_r  : lane_valid;

    // Registered read path (used when deskew_en=1)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            deskewed_data_r <= {NUM_LANES*DATA_WIDTH{1'b0}};
            deskew_valid_r  <= {NUM_LANES{1'b0}};
        end else if (aligned) begin
            for (i = 0; i < NUM_LANES; i = i + 1) begin
                if (fifo_cnt[i] > 0) begin
                    deskewed_data_r[i*DATA_WIDTH +: DATA_WIDTH] <= fifo[i][rd_ptr[i]];
                    deskew_valid_r[i] <= 1'b1;
                    rd_ptr[i]         <= rd_ptr[i] + 1'b1;
                    fifo_cnt[i]       <= fifo_cnt[i] - 1'b1;
                end else begin
                    deskewed_data_r[i*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                    deskew_valid_r[i] <= 1'b0;
                end
            end
        end else begin
            deskewed_data_r <= {NUM_LANES*DATA_WIDTH{1'b0}};
            deskew_valid_r  <= {NUM_LANES{1'b0}};
        end
    end

endmodule
