module DCLK (
    input OCLK,
    input start,
    output reg FCLK
);
    reg [13:0] contador;

    always @(posedge OCLK, posedge start) begin
        if (start) begin
            contador <= 14'b0;
            FCLK <= 1'b0;
        end else begin
            if (contador == 14'b11111111111111) begin
                FCLK <= ~FCLK;
                contador <= 14'b0;
            end
            else contador <= contador + 14'b00000000000001;
        end
    end
endmodule
