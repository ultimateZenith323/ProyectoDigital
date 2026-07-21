module Seg7 (
    input OCLK,
    input start,

    input [15:0] entrada, //codigo de entrada para displays
    output reg [6:0] segmento,
    output reg [3:0] display
);
    wire [6:0] segmento1;
    wire [6:0] segmento2;
    wire [6:0] segmento3;
    wire [6:0] segmento4;

    reg [15:0] divisor;
    reg CLK;
    always @(posedge OCLK, posedge start) begin
        if (start) begin
            divisor <= 16'd0;
            CLK <= 1'b0;
        end else begin
            if (divisor == 16'd50000) begin
                divisor <= 16'd0;
                CLK <= ~CLK;
            end else divisor <= divisor + 16'd1;
        end
    end

    Codificador C0 (
        .entrada   (entrada[3:0]),
        .codificada(segmento1)
    );
    Codificador C1 (
        .entrada   (entrada[7:4]),
        .codificada(segmento2)
    );
    Codificador C2 (
        .entrada   (entrada[11:8]),
        .codificada(segmento3)
    );
    Codificador C3 (
        .entrada   (entrada[15:12]),
        .codificada(segmento4)
    );

    reg [1:0] estado;
    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 2'b0;
            segmento <= 7'b1000000;
            display <= 4'b0;
        end else begin
            case (estado)
                2'b00: begin
                    segmento <= segmento1;
                    display <= 4'b1110;
                    estado <= 2'b01;
                end
                2'b01: begin
                    segmento <= segmento2;
                    display <= 4'b1101;
                    estado <= 2'b10;
                end
                2'b10: begin
                    segmento <= segmento3;
                    display <= 4'b1011;
                    estado <= 2'b11;
                end
                2'b11: begin
                    segmento <= segmento4;
                    display <= 4'b0111;
                    estado <= 2'b00;
                end
                default: begin
                    segmento <= 7'b0;
                    display <= 4'b1110;
                    estado <= 2'b00;
                end
            endcase
        end
    end
endmodule
