module Codificador (
    input [3:0] entrada,
    output reg [6:0] codificada
);
    always @(*) begin
        case (entrada)
            4'b0000: codificada <= 7'b1000000;
            4'b0001: codificada <= 7'b1111001;
            4'b0010: codificada <= 7'b0100100;
            4'b0011: codificada <= 7'b0110000;
            4'b0100: codificada <= 7'b0011001;
            4'b0101: codificada <= 7'b0010010;
            4'b0110: codificada <= 7'b0000010;
            4'b0111: codificada <= 7'b1111000;
            4'b1000: codificada <= 7'b0000000;
            4'b1001: codificada <= 7'b0010000;
            4'b1010: codificada <= 7'b0001000;
            4'b1011: codificada <= 7'b0000011;
            4'b1100: codificada <= 7'b1000110;
            4'b1101: codificada <= 7'b0100001;
            4'b1110: codificada <= 7'b0000110;
            4'b1111: codificada <= 7'b0001110;
            default: codificada <= 7'b1000000; 
        endcase
    end
endmodule
