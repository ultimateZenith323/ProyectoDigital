module FSM4 (
    input CLK,
    input start,
    input reset,

    input M3, // Iniciador del modulo

    input inactivo, // Indica que FSMS ha terminado su tarea
    input lectura, // Indica que se debe leer la informacion del FSMS
    input [7:0] info, // informacion de FSMS
    input ReturnSPI, // Indica que FSMS requiere otro byte o termino su tarea
    input SPIRet, // Indica que SPI pide otro byte

    output reg [7:0] dataSPI, // data para FSMS
    output reg [7:0] bytes, // numero de repeticiones de FSMS
    output reg EjcSPI, // Ejecucion de FSMS
    output reg [1:0] access_event, // Indica si se abre o no la puerta

    output reg T3, // Indica que el modulo finalizo
    output [31:0] infoTR, // UID de la ultima tarjeta
    output reg LED
);
    reg [3:0] estado;
    reg [12:0] retardo;
    
    reg EjcTR; // Ejecucion de FSMTR
    reg [7:0] bytesTR; // numero de bytes para FSMTR
    reg [7:0] command; // comando para FSMTR

    wire ReturnTR; // Indica que FSMTR inicio correctamente
    wire inactivoTR; // indica que FSMTR ha terminado su tarea

    reg [7:0] dataSPI1;
    wire [7:0] dataSPI2;
    reg [7:0] bytes1;
    wire [7:0] bytes2;
    reg EjcSPI1;
    wire EjcSPI2;
    wire PD;
    wire ErrorTR;
    
    reg B7;

    parameter UID1 = 32'h439100A6;
    parameter UID2 = 32'hF3CBD1A6;
    parameter UID3 = 32'h330E8696;
    parameter UID4 = 32'hD393C795;

    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 0;
            retardo <= 0;
        end else begin
            case (estado)
                4'd0: if (M3) begin 
                    estado <= 4'd1;
                    retardo <= 0;
                end
                4'd1: if (lectura) begin
                    if (info[1] & info[0]) estado <= 4'd2;
                    else estado <= 4'd5;
                end
                4'd2: if (inactivo) estado <= 4'd3;
                4'd3: if (lectura) begin
                    if (info[6]) estado <= 4'd12;
                    else estado <= 4'd4;
                end
                4'd4: if (reset) estado <= 4'd0;
                4'd5: if (reset) estado <= 4'd0;
                4'd6: if (ReturnTR) estado <= 4'd7;
                    else if (ErrorTR) estado <= 4'd11;
                4'd7: if (PD & ReturnSPI) begin 
                    estado <= 4'd13;
                    retardo <= 0;
                end
                4'd13: if (retardo == 13'd750) begin 
                    estado <= 4'd8;
                    retardo <= 0;
                end else retardo <= retardo + 13'd1;
                4'd8: if (ReturnTR) begin
                    if (infoTR == UID1) estado <= 4'd9;
                    else if (infoTR == UID2) estado <= 4'd9;
                    else if (infoTR == UID3) estado <= 4'd9;
                    else if (infoTR == UID4) estado <= 4'd9;
                    else estado <= 4'd10;
                end
                4'd9: if (retardo == 13'd4500) estado <= 4'd11;
                    else retardo <= retardo + 13'd1;
                4'd10: if (retardo == 13'd4500) estado <= 4'd11;
                    else retardo <= retardo + 13'd1;
                4'd11: estado <= 4'd0;
                4'd12: if (retardo == 13'd750) begin 
                    estado <= 4'd6;
                    retardo <= 0;
                end else retardo <= retardo + 13'd1;
                default: begin
                    estado <= 0;
                    retardo <= 0;
                end
            endcase
        end
    end

    always @(*) begin
        dataSPI1 = 0;
        bytes1 = 0;
        EjcSPI1 = 0;
        EjcTR = 0;
        bytesTR = 0;
        command = 0;
        access_event = 0;
        B7 = 0;
        T3 = 0;
        LED = 0;
        case (estado)
            4'd0:;
            4'd1: begin
                dataSPI1 = 8'hA8;
                bytes1 = 8'd1;
                EjcSPI1 = 1'b1;
            end
            4'd2:;
            4'd3: begin
                dataSPI1 = 8'h8C;
                bytes1 = 8'd1;
                EjcSPI1 = 1'b1;
            end
            4'd4:;
            4'd5:;
            4'd6: begin
                EjcTR = 1'b1;
                command = 8'h26;
                B7 = 1'b1;
                bytesTR = 8'd1;
            end
            4'd7: begin
                EjcTR = 1'b1;
                command = 8'h93;
                bytesTR = 8'd2;
            end
            4'd8: command = 8'h20;
            4'd9: access_event = 2'b10;
            4'd10: access_event = 2'b10;
            4'd11: T3 = 1'b1;
            4'd12:;
            4'd13: LED = 1'b1;
            default: begin
                dataSPI1 = 0;
                bytes1 = 0;
                EjcSPI1 = 0;
                EjcTR = 0;
                bytesTR = 0;
                command = 0;
                access_event = 0;
                LED = 0;
                B7 = 0;
                T3 = 0;
            end 
        endcase
    end

    always @(*) begin
        EjcSPI = EjcSPI2;
        bytes = bytes2;
        dataSPI = dataSPI2;
        case (estado)
            4'd1, 4'd3: begin
                EjcSPI = EjcSPI1;
                bytes = bytes1;
                dataSPI = dataSPI1;
            end 
            default: begin
                EjcSPI = EjcSPI2;
                bytes = bytes2;
                dataSPI = dataSPI2;
            end 
        endcase
    end

    FSMTR fsmtr (
        .CLK        (CLK),
        .start      (start),
        .reset      (reset),
        .ejecutar   (EjcTR),
        .SPIreturn  (SPIRet),
        .inactivoSPI(inactivo),
        .lecturaSPI (lectura),
        .info       (info),
        .B7a        (B7),
        .bytesTR    (bytesTR),
        .comando    (command),
        .inactivoTR (inactivoTR),
        .dataSPI    (dataSPI2),
        .EjcSPI     (EjcSPI2),
        .bytesSPI   (bytes2),
        .PD         (PD),
        .ErrorTR    (ErrorTR),
        .ReturnTR   (ReturnTR),
        .InfoTarjeta(infoTR)
    );
endmodule
