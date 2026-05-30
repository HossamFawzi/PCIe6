// ============================================================
// Module 41 : Data Rate Advertisement Logic (DATA_RATE_ADV)
// PCIe Gen6 Physical Layer
// Advertises and negotiates supported data rates between
// link partners using TS1/TS2 ordered set speed capability
// fields. Handles Gen1 through Gen6 (2.5 to 64 GT/s).
//
// Speed Capability Bit Map (per PCIe spec):
//   Bit 0 : 2.5 GT/s  (Gen1)
//   Bit 1 : 5.0 GT/s  (Gen2)
//   Bit 2 : 8.0 GT/s  (Gen3)
//   Bit 3 : 16.0 GT/s (Gen4)
//   Bit 4 : 32.0 GT/s (Gen5)
//   Bit 5 : 64.0 GT/s (Gen6)
//   Bits 6-7: Reserved
// ============================================================
module data_rate_adv (
    input  wire        clk,
    input  wire        rst_n,

    // Local capability inputs
    input  wire [7:0]  local_speed_cap,      // This device's supported speeds
    input  wire [7:0]  target_speed_req,     // Software-requested target speed

    // Partner advertisement (from TS1/TS2 detector)
    input  wire [7:0]  partner_speed_cap,    // Partner's advertised speed cap
    input  wire        partner_cap_valid,    // Partner cap field is valid

    // Outputs
    output reg  [7:0]  adv_speed_cap,        // Speed cap to put in our TS1/TS2
    output reg  [7:0]  negotiated_speed,     // Agreed speed capability mask
    output reg  [2:0]  negotiated_gen,       // Highest agreed Gen number (1-6)
    output reg         negotiation_done,     // Negotiation complete (pulse)
    output reg         speed_change_req      // Request speed change to LTSSM
);

// State machine
localparam S_IDLE       = 3'd0;
localparam S_ADVERTISE  = 3'd1;
localparam S_WAIT       = 3'd2;
localparam S_NEGOTIATE  = 3'd3;
localparam S_DONE       = 3'd4;

reg [2:0] state;
reg [7:0] common_speeds;   // Bitwise AND of local & partner capabilities

// Temporary registers for NEGOTIATE state (declared at module level for Verilog-2001)
reg [7:0] neg_effective;
reg [2:0] neg_gen;

// Priority encoder: find highest set bit (Gen6 → Gen1)
function [2:0] highest_gen;
    input [7:0] cap;
    begin
        if      (cap[5]) highest_gen = 3'd6;
        else if (cap[4]) highest_gen = 3'd5;
        else if (cap[3]) highest_gen = 3'd4;
        else if (cap[2]) highest_gen = 3'd3;
        else if (cap[1]) highest_gen = 3'd2;
        else if (cap[0]) highest_gen = 3'd1;
        else             highest_gen = 3'd0;
    end
endfunction

// Apply target speed mask: cap result at requested target
function [7:0] apply_target;
    input [7:0] common;
    input [7:0] target;
    begin
        case (target)
            8'h01:   apply_target = common & 8'h01;
            8'h02:   apply_target = common & 8'h03;
            8'h04:   apply_target = common & 8'h07;
            8'h08:   apply_target = common & 8'h0F;
            8'h10:   apply_target = common & 8'h1F;
            8'h20:   apply_target = common & 8'h3F;
            default: apply_target = common;
        endcase
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        adv_speed_cap    <= 8'h00;
        negotiated_speed <= 8'h00;
        negotiated_gen   <= 3'd0;
        negotiation_done <= 1'b0;
        speed_change_req <= 1'b0;
        common_speeds    <= 8'h00;
        neg_effective    = 8'h00;
        neg_gen          = 3'd0;
        state            <= S_IDLE;
    end else begin
        negotiation_done <= 1'b0;
        speed_change_req <= 1'b0;

        case (state)
            S_IDLE: begin
                negotiated_speed <= 8'h00;
                negotiated_gen   <= 3'd0;
                if (local_speed_cap != 8'h00) begin
                    adv_speed_cap <= local_speed_cap;
                    state         <= S_ADVERTISE;
                end
            end

            S_ADVERTISE: begin
                adv_speed_cap <= local_speed_cap;
                if (partner_cap_valid && partner_speed_cap != 8'h00)
                    state <= S_WAIT;
            end

            S_WAIT: begin
                common_speeds <= local_speed_cap & partner_speed_cap;
                state         <= S_NEGOTIATE;
            end

            S_NEGOTIATE: begin
                // Compute effective speed using module-level regs
                if (target_speed_req != 8'h00)
                    neg_effective = apply_target(common_speeds, target_speed_req);
                else
                    neg_effective = common_speeds;

                if (neg_effective == 8'h00)
                    neg_effective = 8'h01;   // Fallback to Gen1

                neg_gen = highest_gen(neg_effective);

                negotiated_speed <= neg_effective;
                negotiated_gen   <= neg_gen;

                if (neg_gen > 3'd1)
                    speed_change_req <= 1'b1;

                state <= S_DONE;
            end

            S_DONE: begin
                negotiation_done <= 1'b1;
                state            <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
