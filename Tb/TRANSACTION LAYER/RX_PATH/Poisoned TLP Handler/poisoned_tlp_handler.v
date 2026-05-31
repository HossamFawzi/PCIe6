
module poisoned_tlp_handler (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          tlp_ep_bit,
    input  wire [4:0]    tlp_type,
    input  wire          tlp_ok,
    input  wire [1023:0] tlp_rx,

    output wire          poisoned_detected,
    output wire          poison_drop,
    output wire [2:0]    poison_to_aer,
    output wire          tlp_fwd_valid
);

    localparam [2:0] AER_NONE      = 3'b000;
    localparam [2:0] AER_NON_FATAL = 3'b010;

    assign tlp_fwd_valid = tlp_ok & ~tlp_ep_bit;

    reg r_poisoned_detected;
    reg r_poison_drop;
    reg [2:0] r_poison_to_aer;
    reg tlp_ok_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_poisoned_detected <= 1'b0;
            r_poison_drop       <= 1'b0;
            r_poison_to_aer     <= AER_NONE;
            tlp_ok_prev         <= 1'b0;
        end else begin
            tlp_ok_prev <= tlp_ok;

            if (tlp_ok) begin
                r_poisoned_detected <= tlp_ep_bit;
                r_poison_drop       <= tlp_ep_bit;
                r_poison_to_aer     <= tlp_ep_bit ? AER_NON_FATAL : AER_NONE;
            end else if (!tlp_ok_prev) begin

                r_poisoned_detected <= 1'b0;
                r_poison_drop       <= 1'b0;
                r_poison_to_aer     <= AER_NONE;
            end

        end
    end

    assign poisoned_detected = r_poisoned_detected;
    assign poison_drop       = r_poison_drop;
    assign poison_to_aer     = r_poison_to_aer;

endmodule
