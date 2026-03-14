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