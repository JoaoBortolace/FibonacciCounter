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