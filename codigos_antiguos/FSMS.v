module FSMS (
    input CLK,
    input start,
    input reset,

    input Ejecutar, // Inicia este modulo
    input [7:0] Bytes, // Indica el numero de bytes
    input [7:0] DataMaestro, // El byte a enviar dado por el maestro
    input MISO, // Bit enviado por la RFID por el canal MISO

    output reg Return, // Indica al maestro que envie otro byte o continue con su operacion
    output reg NSS, // Activa la RFID, este indicador es correcto como esta
    output reg Lectura, // Indica que se puede leer la informacion de RDS
    output MOSI, // Bit enviado al canal MOSI de la RFID
    output [7:0] InfoSPI, // Byte suministrado por la RFID
    output reg inactivo // Indica que la comunicacion SPI a terminado y se puede enviar otro comando
);
    reg [3:0] estado;
    reg [4:0] Bit;
    reg [7:0] PBytes;
    reg Flag;

    reg Enable;

    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 4'd0;
            Bit <= 5'd0;
            PBytes <= 8'd0;
            Flag <= 1'b0;
        end else begin
            case (estado)
                4'd0: if (Ejecutar) begin
                    PBytes <= Bytes;
                    Bit <= 5'd0;
                    Flag <= 1'b1;
                    estado <= 4'd1;
                end
                4'd1: estado <= 4'd2;
                4'd2: if (Bit == 5'd5) begin
                    if (PBytes == 8'd0) begin
                        Bit <= 5'd0;
                        estado <= 4'd6;
                    end else begin
                        PBytes <= PBytes - 8'd1;
                        Bit <= 5'd0;
                        estado <= 4'd3;
                    end
                end else Bit <= Bit + 5'd1;
                4'd3: if (Flag) begin
                    Flag <= 1'b0;
                    estado <= 4'd5;
                end else estado <= 4'd4;
                4'd4: estado <= 4'd2;
                4'd5: estado <= 4'd2;
                4'd6: estado <= 4'd7;
                4'd7: estado <= 4'd8;
                4'd8: estado <= 4'd0;
                default: begin
                    estado <= 4'd0;
                    Bit <= 5'd0;
                    PBytes <= 8'd0;
                    Flag <= 1'b0;
                end
            endcase
        end
    end

    always @(*) begin
        Return = 1'b0;
        NSS = 1'b1;
        Lectura = 1'b0;
        Enable = 1'b0;
        inactivo = 1'b0;
        case (estado)
            4'd0: inactivo = 1'b1;
            4'd1: ;
            4'd2, 4'd6: begin
                NSS = 1'b0;
                Enable = 1'b1;
            end
            4'd3: begin
                NSS = 1'b0;
                Enable = 1'b1;
                Return = 1'b1;
            end
            4'd4, 4'd7: begin
                NSS = 1'b0;
                Lectura = 1'b1;
            end
            4'd5: NSS = 1'b0;
            4'd8: Return = 1'b1;
            default: begin
                Return = 1'b0;
                NSS = 1'b1;
                Lectura = 1'b0;
                Enable = 1'b0;
            end 
        endcase
    end

    RDE rde1 (
        .data  (DataMaestro),
        .enable(Enable),
        .CLK   (CLK),
        .start (start),
        .reset (reset),
        .MOSI  (MOSI)
    );

    RDS rds1 (
        .MISO   (MISO),
        .CLK    (CLK),
        .start  (start),
        .reset  (reset),
        .info   (InfoSPI)
    );
endmodule
