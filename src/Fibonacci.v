`default_nettype none

module tt_um_fibonacci_JoaoBortolace (
    input  wire [7:0] ui_in,    // Inputs: [0]=step_pulse_button
    output wire [7:0] uo_out,   // Outputs: [6:0]=7seg_segments (abcdefg), [7]=bcd_ready_flag
    input  wire [7:0] uio_in,   // IOs: Input mode (not used)
    output wire [7:0] uio_out,  // IOs: Output mode: [4:0]=digit_enable (active high)
    output wire [7:0] uio_oe,   // IOs: Output Enable mask
    input  wire clk,            // Main clock (~1kHz)
    input  wire ena,            // Design enable (TinyTapeout)
    input  wire rst_n           // Active low reset
);

    // PIN CONFIGURATION
    // Set uio[4:0] as outputs for 5 displays, others as inputs
    assign uio_oe  = 8'b00011111; 
    assign uio_out[7:5] = 3'b000;

    // INTERNAL SIGNALS
    wire [15:0] fib_number;
    wire [19:0] bcd_val;
    wire bcd_ready;
    wire start_bcd;

    // EXTERNAL SIGNAL SYNC (To prevent metastability)
    reg next_step_sync, next_step_d;
    always @(posedge clk) begin
        next_step_sync <= ui_in[0]; // External input synchronization
        next_step_d    <= next_step_sync;
    end
    wire step_pulse = next_step_sync && !next_step_d; // Rising edge detection

    // FIBONACCI COUNTER INSTANCE
    FibonacciCounter #(
        .NUM_BITS(16)
    ) fib_inst (
        .clk(clk),
        .rst_n(rst_n),
        .advance(step_pulse),
        .disp_ready(bcd_ready),
        .newNumber(start_bcd),
        .fib_number(fib_number)
    );

    // BINARY TO BCD CONVERTER (DOUBLE DABBLE)
    BinToBCD bcd_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_bcd),
        .bin_in(fib_number),
        .bcd_out(bcd_val),
        .ready(bcd_ready)
    );

    // 7-SEGMENT DISPLAY MULTIPLEXING (RING COUNTER)
    reg [4:0] ring_cnt;    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ring_cnt <= 5'b00001;
        else
            // Rotate bit (Ring Counter)
            ring_cnt <= {ring_cnt[3:0], ring_cnt[4]};
    end

    // DIGIT SELECTION (One-hot output)
    assign uio_out[4:0] = ring_cnt;
    assign uo_out[7] = bcd_ready; // Visual status flag

    // MUX TO SELECT BCD DIGIT FOR DECODER
    reg [3:0] dispData;
    always @(*) begin
        case (ring_cnt)
            5'b00001: dispData = bcd_val[3:0];   // Unit
            5'b00010: dispData = bcd_val[7:4];   // Ten
            5'b00100: dispData = bcd_val[11:8];  // Hundred
            5'b01000: dispData = bcd_val[15:12]; // Thousand
            5'b10000: dispData = bcd_val[19:16]; // Ten Thousand
            default:  dispData = 4'h0;
        endcase
    end
    
    // COMBINATIONAL 7-SEGMENT DECODER (Active High)
    // Order: gfedcba (bit 6 down to 0)
    assign uo_out[6:0] = (dispData == 4'h0) ? 7'b0111111 : // 0
                         (dispData == 4'h1) ? 7'b0000110 : // 1
                         (dispData == 4'h2) ? 7'b1011011 : // 2
                         (dispData == 4'h3) ? 7'b1001111 : // 3
                         (dispData == 4'h4) ? 7'b1100110 : // 4
                         (dispData == 4'h5) ? 7'b1101101 : // 5
                         (dispData == 4'h6) ? 7'b1111101 : // 6
                         (dispData == 4'h7) ? 7'b0000111 : // 7
                         (dispData == 4'h8) ? 7'b1111111 : // 8
                         (dispData == 4'h9) ? 7'b1101111 : // 9
                                              7'b1000000;  // Error Dash (-)

    wire _unused = &{ui_in[7:1], uio_in, ena, 1'b0};
endmodule

module FibonacciCounter #(
    parameter NUM_BITS = 16
)(
    input wire clk, rst_n,
    input wire advance,          // Signal to increment sequence
    input wire disp_ready,       // Is BCD converter ready?
    output reg newNumber,        // Start pulse for BinToBCD
    output reg [NUM_BITS-1:0] fib_number
);
    reg [NUM_BITS-1:0] aux_reg; 
    wire [NUM_BITS:0] sum = {1'b0, fib_number} + {1'b0, aux_reg};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fib_number  <= 0;
            aux_reg     <= 1;
            newNumber   <= 0;
        end else begin
            // Default: reset start pulse on next cycle
            newNumber <= 0;
            
            // Calculate only if requested AND BCD converter is idle
            if (advance && disp_ready) begin
                newNumber <= 1; // Trigger new conversion

                if (sum[NUM_BITS]) begin // Overflow detection (reset to start)
                    fib_number <= 0;
                    aux_reg    <= 1;
                end else begin
                    fib_number <= aux_reg;
                    aux_reg    <= sum[NUM_BITS-1:0];
                end
            end
        end
    end
endmodule

module BinToBCD (
    input wire clk, rst_n,
    input wire start,
    input wire [15:0] bin_in,
    output reg [19:0] bcd_out,
    output reg ready
);
    reg [4:0] count;
    reg [35:0] shift_reg; // [20-bit BCD | 16-bit Binary]

    // Combinational logic for BCD adjustments (Double Dabble)
    reg [35:0] bcd_temp;
    
    always @(*) begin
        bcd_temp = shift_reg;
        // If BCD digit >= 5, add 3 BEFORE shifting
        if (bcd_temp[19:16] >= 5) bcd_temp[19:16] = bcd_temp[19:16] + 3;
        if (bcd_temp[23:20] >= 5) bcd_temp[23:20] = bcd_temp[23:20] + 3;
        if (bcd_temp[27:24] >= 5) bcd_temp[27:24] = bcd_temp[27:24] + 3;
        if (bcd_temp[31:28] >= 5) bcd_temp[31:28] = bcd_temp[31:28] + 3;
        if (bcd_temp[35:32] >= 5) bcd_temp[35:32] = bcd_temp[35:32] + 3;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            shift_reg <= 0;
            ready <= 1;
            bcd_out <= 0;
        end else begin
            if (ready) begin
                if (start) begin
                    shift_reg <= {20'b0, bin_in};
                    count <= 16;
                    ready <= 0;
                end
            end else begin
                if (count == 0) begin
                    ready <= 1;
                    bcd_out <= shift_reg[35:16];
                end else begin
                    // Apply BCD adjustment and shift left
                    shift_reg <= {bcd_temp[34:0], 1'b0};
                    count <= count - 1;
                end
            end
        end
    end
endmodule
