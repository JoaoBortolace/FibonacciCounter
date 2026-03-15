`default_nettype none

module tt_um_fibonacci_JoaoBortolace #(
    parameter NUM_BITS = 19,
    parameter NUM_DIG = 6
)(
    input  wire [7:0] ui_in,    // Inputs: [0]=step_pulse_button
    output wire [7:0] uo_out,   // Outputs: [6:0]=7seg_segments (abcdefg), [7]=bcd_ready_flag
    input  wire [7:0] uio_in,   // IOs: Input mode (not used)
    output wire [7:0] uio_out,  // IOs: Output mode: [4:0]=digit_enable (active high)
    output wire [7:0] uio_oe,   // IOs: Output Enable mask
    input  wire clk,            // Main clock (~1kHz)
    input  wire ena,            // Design enable (TinyTapeout)
    input  wire rst_n           // Active low reset
);

    // --- IO CONFIGURATION ---
    // Enable only the necessary bits for the number of digits
    assign uio_oe  = (1 << NUM_DIG) - 1; 
    assign uio_out[7:NUM_DIG] = 0; 

    // INTERNAL SIGNALS
    wire [NUM_BITS-1:0] fib_number;
    wire [(4*NUM_DIG)-1:0] bcd_val;
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
        .NUM_BITS(NUM_BITS)
    ) fib_inst (
        .clk(clk),
        .rst_n(rst_n),
        .advance(step_pulse),
        .disp_ready(bcd_ready),
        .newNumber(start_bcd),
        .fib_number(fib_number) 
    );

    // BINARY TO BCD CONVERTER (DOUBLE DABBLE)
    BinToBCD #(
        .NUM_BITS(NUM_BITS),
        .NUM_DIG(NUM_DIG)
    ) bcd_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_bcd),
        .bin_in(fib_number),
        .bcd_out(bcd_val),
        .ready(bcd_ready)
    );

    // 7-SEGMENT DISPLAY MULTIPLEXING (RING COUNTER)
    reg [NUM_DIG-1:0] ring_cnt;    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ring_cnt <= {{(NUM_DIG-1){1'b0}}, 1'b1};
        else
            // Rotate bit (Ring Counter)
            ring_cnt <= {ring_cnt[NUM_DIG-2:0], ring_cnt[NUM_DIG-1]};
    end

    // DIGIT SELECTION (One-hot output)
    assign uio_out[NUM_DIG-1:0] = ring_cnt;
    assign uo_out[7] = bcd_ready; // Visual status flag

    // MUX TO SELECT BCD DIGIT FOR DECODER
    reg [3:0] dispData;
    integer idx;
    always @(*) begin
        dispData = 4'h0;
        for (idx = 0; idx < NUM_DIG; idx = idx + 1) begin
            if (ring_cnt[idx]) 
                dispData = bcd_val[idx*4 +: 4];
        end
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
    wire [NUM_BITS-1:0] sum = fib_number + aux_reg;

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

                if (aux_reg < fib_number) begin // Overflow detection (reset to start)
                    fib_number <= 0;
                    aux_reg    <= 1;
                end else begin
                    fib_number <= aux_reg;
                    aux_reg    <= sum;
                end
            end
        end
    end
endmodule

module BinToBCD #(
    parameter NUM_BITS = 16,
    parameter NUM_DIG = 5
)(
    input wire clk, rst_n,
    input wire start,
    input wire [NUM_BITS-1:0] bin_in,
    output reg [(4*NUM_DIG)-1:0] bcd_out,
    output reg ready
);
    reg [$clog2(NUM_BITS+1)-1:0] count;
    reg [(4*NUM_DIG)+NUM_BITS-1:0] shift_reg; // [20-bit BCD | 16-bit Binary]

    // Combinational logic for BCD adjustments (Double Dabble)
    reg [(4*NUM_DIG)+NUM_BITS-1:0] bcd_temp;
    
    integer i;
    always @(*) begin
        bcd_temp = shift_reg;
        // If BCD digit >= 5, add 3 BEFORE shifting
        for (i = 0; i < NUM_DIG; i = i + 1) begin
            if (bcd_temp[(i*4) + NUM_BITS +: 4] >= 5) begin
                bcd_temp[(i*4) + NUM_BITS +: 4] = bcd_temp[(i*4) + NUM_BITS +: 4] + 3;
            end
        end
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
                    shift_reg <=  {{(4*NUM_DIG){1'b0}}, bin_in};
                    count <= NUM_BITS;
                    ready <= 0;
                end
            end else begin
                if (count == 0) begin
                    ready <= 1;
                    bcd_out <= shift_reg[(4*NUM_DIG)+NUM_BITS-1:NUM_BITS];
                end else begin
                    // Apply BCD adjustment and shift left
                    shift_reg <= bcd_temp << 1;
                    count <= count - 1;
                end
            end
        end
    end
endmodule
