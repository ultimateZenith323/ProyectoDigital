module FSMP ( //maquina principal del sistema. Controla el resto de maquinas de estado.
    input CLK,
    input start,
    input reset,

    input lec, // Indica que la info se debe leer
    input [7:0] info, // informacion de FSMS
    input SPIRet, // Siguiente byte o final de FSMS
    input inactivo, // Indica FSMS si esta listo para otra operacion


    input confirmar, // entradas por teclado
    input cancelar,
    input [15:0] contrasena, // contrasena de teclado
    output teclado, // Inicia el modulo teclado para contrasena

    output reg [7:0] data, // Palabra para FSMS
    output reg ejcSPI, // Ejecuta el modulo FSMS
    output reg [7:0] bytes, // Numero de ejecuciones de FSMS
    output [1:0] error, // Bits de error
    output [1:0] access_event, // Indicadores y texto para la LCD
    output [1:0] TextoSalida2, // Textos para comandos de contrasena
    output [31:0] UID,
    output [2:0] estadoActual,
    output modoS,
    output LED
);

    reg [2:0] estado;
    wire [5:0] T;
    reg [4:0] M;
    reg modo = 0;
    wire ModoAdmin;

    assign modoS = modo;

    assign estadoActual = estado;

    wire ejcSPI1;
    wire ejcSPI2;
    wire ejcSPI3;
    wire [7:0] bytes1;
    wire [7:0] bytes2;
    wire [7:0] bytes3;
    wire [7:0] data1;
    wire [7:0] data2;
    wire [7:0] data3;


    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 3'b0;
        end else begin
            case (estado)
                3'd0: if (reset) estado <= 3'd0;
                    else estado <= 3'd1;
                3'd1: if (reset) estado <= 3'd0;
                    else if(T[0]) estado <= 3'd2;
                3'd2: if (reset) estado <= 3'd0;
                    else if(T[1]) estado <= 3'd3;
                3'd3: if (reset) estado <= 3'd0;
                    else if(T[2]) estado <= 3'd4;
                3'd4: if (reset) estado <= 3'd0;
                    else if(modo) estado <= 3'd5;
                    else estado <= 3'd6;
                3'd5: if (reset) estado <= 3'd0;
                    else if(T[3]) estado <= 3'd4;
                3'd6: if (reset) estado <= 3'd0;
                    else if(T[4]) estado <= 3'd4;
                default: estado <= 3'd0;
            endcase
        end
    end

    always @(*) begin
        case (estado)
            3'd0: M = 5'b00000;
            3'd1: M = 5'b00001;
            3'd2: M = 5'b00010;
            3'd3: M = 5'b00100;
            3'd4: M = 0; 
            3'd5: M = 5'b01000;
            3'd6: M = 5'b10000;
            default: M = 5'b00000;
        endcase
    end

    reg [1:0] estado2;
    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado2 = 0;
        end else begin
            if (!reset) begin
                case (estado2)
                    2'd0: if (confirmar) estado2 <= 2'd1;
                    2'd1: if (!confirmar) estado2 <= 2'd2;
                        else if (!cancelar) estado2 <= 2'd0; 
                    2'd2: if (cancelar) estado2 <= 2'd1;
                    default: estado2 <= 2'd0;
                endcase
            end
        end
    end

    always @(*) begin
        case (estado2)
            2'd0: modo = 0;
            2'd1: modo = 0;
            2'd2: modo = 1'b1;
            default: modo = 0;
        endcase
    end

    FSM1 MSF0 (
        .CLK(CLK),
        .start(start),
        .reset(reset),
        .M0(M[0]),
        .T0(T[0])
    );

    FSM2 MSF1 (
        .CLK(CLK),
        .start(start),
        .reset(reset),
        .M1(M[1]),
        .T1(T[1]),
        .lec(lec),
        .inactivo(inactivo),
        .info(info),
        .SPIRet(SPIRet),
        .data(data1),
        .ejcSPI(ejcSPI1),
        .BytN(bytes1),
        .error(error)
    );

    FSM3 MSF2 (
        .CLK     (CLK),
        .start   (start),
        .reset   (reset),
        .M2      (M[2]),
        .T2      (T[2]),
        .RetSPI  (SPIRet),
        .inactivo(inactivo),
        .lectura (lec),
        .info    (info),
        .data    (data2),
        .EjcSPI  (ejcSPI2),
        .bytes   (bytes2)
    );

    FSM4 MSF3 (
        .CLK         (CLK),
        .start       (start),
        .reset       (reset),
        .M3          (M[3]),
        .inactivo    (inactivo),
        .lectura     (lec),
        .info        (info),
        .ReturnSPI   (SPIRet),
        .dataSPI     (data3),
        .bytes       (bytes3),
        .EjcSPI      (ejcSPI3),
        .access_event(access_event),
        .SPIRet      (SPIRet),
        .infoTR      (UID),
        .T3          (T[3]),
        .LED         (LED)
    );

    FSM5 MSF5 (
        .CLK        (CLK),
        .start      (start),
        .reset      (reset),
        .M4         (M[4]),
        .enter      (confirmar),
        .descartar  (cancelar),
        .contrasena (contrasena),
        .ModoAdmin  (ModoAdmin),
        .Teclado    (teclado),
        .TextoSalida(TextoSalida2),
        .T4         (T[4])
    );

    always @(*) begin
        case (M)
            5'b00001, 5'b00010: begin
                ejcSPI = ejcSPI1;
                bytes = bytes1;
                data = data1;
            end
            5'b00100: begin
                ejcSPI = ejcSPI2;
                bytes = bytes2;
                data = data2;
            end
            5'b01000: begin
                ejcSPI = ejcSPI3;
                bytes = bytes3;
                data = data3;
            end
            5'b10000: begin
                ejcSPI = ejcSPI3;
                bytes = bytes3;
                data = data3;
            end
            default: begin
                ejcSPI = 0;
                bytes = 0;
                data = 0;
            end
        endcase
    end
endmodule
