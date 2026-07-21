module DCLK_lento (
    input OCLK,
    input start,
    output reg FCLK
);
    reg [24:0] contador;

    always @(posedge OCLK or posedge start) begin
        if (start) begin
            contador <= 25'b0;
            FCLK <= 1'b0;
        end else begin
            if (contador == 25'd6249999) begin
                FCLK <= ~FCLK;
                contador <= 25'b0;
            end else begin
                contador <= contador + 25'b1;
            end
        end
    end
endmodule
