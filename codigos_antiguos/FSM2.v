module FSM2 ( //Maquina de diagnostico inicial
    input CLK,
    input start,
    input reset,

    input M1, // Inicia este modulo
    output reg T1, // Finaliza la accion del modulo

    input lec, // Indica que la info se debe leer
    input [7:0] info, // informacion de FSMS
    input SPIRet, // Siguiente byte o final de FSMS
    input inactivo,

    output [7:0] data, // Palabra para FSMS
    output ejcSPI, // Ejecuta el modulo FSMS
    output [7:0] BytN, // Numero de ejecuciones de FSMS
    output [1:0] error // Bits de error
);
    reg [1:0] estado;
    reg [1:0] F; // Ejecuta modulos
    wire [1:0] K; // Los modulos indican su final
    
    wire [1:0] ejcSPIs;
    wire [7:0] data0;
    wire [7:0] data1;
    wire [7:0] BytN1;
    wire [7:0] BytN2;

    assign ejcSPI = F[1] ? ejcSPIs[1] : ejcSPIs[0];
    assign data = F[1] ? data1 : data0;
    assign BytN = F[1] ? BytN2 : BytN1;

    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 2'b0;
        end else begin
            case (estado)
                2'b00: if (M1) estado <= 2'b01;
                2'b01: if (K[0]) estado <= 2'b10;
                2'b10: if (K[1]) estado <= 2'b11;
                2'b11: if (reset) estado <= 2'b00;
                default: estado <= 2'b0;
            endcase
        end
    end

    always @(*) begin
        case (estado)
            2'b00: begin
                F = 2'b0;
                T1 = 1'b0;
            end
            2'b01: begin
                F = 2'b01;
                T1 = 1'b0;
            end
            2'b10: begin
                F = 2'b10;
                T1 = 1'b0;
            end
            2'b11: begin
                F = 2'b0;
                T1 = 1'b1;
            end
            default: begin
                F = 2'b0;
                T1 = 1'b0;
            end
        endcase
    end

    FSM21 MSF1 (
        .CLK(CLK),
        .start(start),
        .reset(reset),
        .F0(F[0]),
        .lec(lec),
        .info(info),
        .Ret(SPIRet),
        .K0(K[0]),
        .Data(data0),
        .EjecutarSPI(ejcSPIs[0]),
        .Bn(BytN1),
        .Err1(error[0])
    );

    FSM22 MSF2 (
        .CLK(CLK),
        .start(start),
        .reset(reset),
        .F1(F[1]),
        .Info(info),
        .SPIRet(SPIRet),
        .inactivo(inactivo),
        .lec(lec),
        .K1(K[1]),
        .Data(data1),
        .BytN(BytN2),
        .SPIExe(ejcSPIs[1]),
        .Err2(error[1])
    );

endmodule
