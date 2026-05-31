
module tl_interface (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [1023:0] tlp_in,
    input  wire          tlp_valid_in,

    input  wire [2047:0] flit_in,
    input  wire          flit_valid_in,

    input  wire          flit_mode_en,

    input  wire [7:0]    fc_update_ph,
    input  wire          fc_update_valid,

    output reg  [1023:0] dll_tlp,
    output reg           dll_tlp_valid,

    output reg  [2047:0] dll_flit,
    output reg           dll_flit_valid,

    output reg           tl_ready,

    output reg  [71:0]   fc_to_dllp,
    output reg           fc_dllp_send
);

    reg [1023:0] tlp_pipe;
    reg          tlp_vld_pipe;
    reg [2047:0] flit_pipe;
    reg          flit_vld_pipe;

    reg [7:0]    fc_ph_lat;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_pipe      <= {1024{1'b0}};
            tlp_vld_pipe  <= 1'b0;
            flit_pipe     <= {2048{1'b0}};
            flit_vld_pipe <= 1'b0;
        end else begin

            tlp_pipe      <= tlp_in;
            tlp_vld_pipe  <= tlp_valid_in & ~flit_mode_en;
            flit_pipe     <= flit_in;
            flit_vld_pipe <= flit_valid_in &  flit_mode_en;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dll_tlp       <= {1024{1'b0}};
            dll_tlp_valid <= 1'b0;
            dll_flit      <= {2048{1'b0}};
            dll_flit_valid<= 1'b0;
            tl_ready      <= 1'b1;
            fc_to_dllp    <= 72'h0;
            fc_dllp_send  <= 1'b0;
            fc_ph_lat     <= 8'h0;
        end else begin

            dll_tlp       <= tlp_pipe;
            dll_tlp_valid <= tlp_vld_pipe;

            dll_flit       <= flit_pipe;
            dll_flit_valid <= flit_vld_pipe;

            tl_ready <= 1'b1;

            if (fc_update_valid) begin
                fc_ph_lat    <= fc_update_ph;

                fc_to_dllp   <= {64'h0, fc_update_ph};
                fc_dllp_send <= 1'b1;
            end else begin
                fc_dllp_send <= 1'b0;
            end
        end
    end

endmodule
