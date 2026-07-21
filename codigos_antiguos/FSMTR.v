module FSMTR (
    input CLK,
    input start,
    input reset,

    input ejecutar, // inicia el modulo
    input SPIreturn, // FSMS indica que necesita otro byte
    input inactivoSPI, // FSMS termino
    input lecturaSPI, // FSMS indica que hay que leer info
    input [7:0] info, // FSMS envia informacion de RFID
    input B7a, // Indicacion de comando de 7 bits
    input [7:0] bytesTR, // indica el numero de bytes que se usaran de comando
    input [7:0] comando, // indica el comando de comunicacion

    output reg inactivoTR, // Indica que FSMTR no tiene nada que hacer
    output reg [7:0] dataSPI, // data para FSMS
    output reg EjcSPI, // Inicia FSMS
    output reg [7:0] bytesSPI, // numero de bytes para FSMS
    output reg PD, // indica que el comando tiene mas bytes
    output reg ErrorTR, // indica que la comunicacion ha fallado
    output reg ReturnTR, // indica que la comunicacion ha sido un exito
    output reg [31:0] InfoTarjeta
);
    reg [5:0] estado;
    reg [12:0] retardo;
    reg [7:0] bytesFIFO;
    reg B7;

    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 6'd0;
            retardo <= 13'd0;
            bytesFIFO <= 0;
            InfoTarjeta <= 0;
            B7 <= 0;
        end else begin
            case (estado)
                6'd0: if (ejecutar) begin
                    estado <= 6'd1;
                    B7 <= B7a;
                    retardo <= 0;
                end
                6'd1: if (SPIreturn) estado <= 6'd2;
                6'd2: if (inactivoSPI) estado <= 6'd3;
                6'd3: if (SPIreturn) estado <= 6'd4;
                6'd4: if (inactivoSPI) estado <= 6'd5;
                6'd5: if (SPIreturn) estado <= 6'd6;
                6'd6: if (inactivoSPI) estado <= 6'd7;
                6'd7: if (SPIreturn) begin
                    if (B7) estado <= 6'd9;
                    else estado <= 6'd8;
                end
                6'd8: if (inactivoSPI) estado <= 6'd10;
                6'd9: if (inactivoSPI) estado <= 6'd10;
                6'd10: if (SPIreturn) begin
                    if (B7) estado <= 6'd12;
                    else estado <= 6'd11;
                end
                6'd11: if (inactivoSPI) estado <= 6'd13;
                6'd12: if (inactivoSPI) estado <= 6'd13;
                6'd13: if (SPIreturn) estado <= 6'd14;
                6'd14: if (inactivoSPI) estado <= 6'd15;
                6'd15: if (SPIreturn) begin
                    if (B7) estado <= 6'd17;
                    else estado <= 6'd16;
                end
                6'd16: if (inactivoSPI) estado <= 6'd18;
                6'd17: if (inactivoSPI) estado <= 6'd18;
                6'd18: if (SPIreturn) estado <= 6'd19;
                6'd19: if (inactivoSPI) estado <= 6'd20;
                6'd20: if (SPIreturn) begin
                    if (B7) estado <= 6'd22;
                    else estado <= 6'd21;
                end
                6'd21: if (inactivoSPI) estado <= 6'd23;
                6'd22: if (inactivoSPI) estado <= 6'd23;
                6'd23: if (lecturaSPI) begin
                    if (info[1]) estado <= 6'd25;
                    else if (info [0]) estado <= 6'd29;
                    else if (info[4] || info[5]) begin
                        estado <= 6'd30;
                        retardo <= 0;
                    end
                    else estado <= 6'd24;
                end
                6'd24: if (inactivoSPI) estado <= 6'd23;
                6'd25: if (inactivoSPI) estado <= 6'd26;
                6'd26: if (lecturaSPI) begin
                    if (info[3]) estado <= 6'd27;
                    else if (info[6]) estado <= 6'd28;
                    else estado <= 6'd39;
                end
                6'd27: if (retardo == 13'd4500) estado <= 6'd39;
                    else retardo <= retardo + 13'd1;
                6'd28: if (reset) estado <= 6'd39;
                6'd29: if (inactivoSPI) estado <= 6'd39;
                6'd30: estado <= 6'd31;
                6'd31: if (inactivoSPI) estado <= 6'd32;
                6'd32: if (lecturaSPI) begin
                    bytesFIFO <= info;
                    estado <= 6'd33;
                end
                6'd33: if (inactivoSPI) estado <= 6'd34;
                6'd34: if (lecturaSPI) begin
                    bytesFIFO <= bytesFIFO - 8'd1;
                    InfoTarjeta <= {InfoTarjeta[23:0], info};
                    if (bytesFIFO == 8'd1) estado <= 6'd35;
                end
                6'd35: if (inactivoSPI) estado <= 6'd36;
                6'd36: if (lecturaSPI) begin
                    if (info[2:0] == 3'b000) estado <= 6'd38;
                    else estado <= 6'd37;
                end
                6'd37: if (inactivoSPI) estado <= 6'd36;
                6'd38: if (inactivoSPI) estado <= 6'd0;
                6'd39: if (inactivoSPI) estado <= 6'd0;
                default: begin
                    estado <= 6'd0;
                    retardo <= 13'd0;
                    bytesFIFO <= 0;
                    InfoTarjeta <= 0;
                end
            endcase
        end
    end

    always @(*) begin
        inactivoTR = 0;
        dataSPI = 0;
        EjcSPI = 0;
        bytesSPI = 0;
        PD = 0;
        ErrorTR = 0;
        ReturnTR = 0;
        case (estado)
            6'd0: inactivoTR = 1'b1;
            6'd1: begin
                dataSPI = 8'h2;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd2: dataSPI = 8'h0;
            6'd3: begin
                dataSPI = 8'h8;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd4: dataSPI = 8'h7F;
            6'd5: begin
                dataSPI = 8'h14;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd6: dataSPI = 8'h80;
            6'd7: begin
                dataSPI = 8'h24;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd8: dataSPI = 8'h80;
            6'd9: dataSPI = 8'h0;
            6'd10: begin
                dataSPI = 8'h26;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd11: dataSPI = 8'h80;
            6'd12: dataSPI = 8'h0;
            6'd13: begin
                dataSPI = 8'h12;
                bytesSPI = bytesTR;
                EjcSPI = 1'b1;
            end 
            6'd14: begin
                PD = 1'b1;
                dataSPI = comando;
            end
            6'd15: begin
                dataSPI = 8'h1A;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd16: dataSPI = 8'h0;
            6'd17: dataSPI = 8'h7;
            6'd18: begin
                dataSPI = 8'h2;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd19: dataSPI = 8'hC;
            6'd20: begin
                dataSPI = 8'h1A;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd21: dataSPI = 8'h80;
            6'd22: dataSPI = 8'h87;
            6'd23: begin
                dataSPI = 8'h88;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd24:;
            6'd25:;
            6'd26: begin
                dataSPI = 8'h8C;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd27:;
            6'd28:;
            6'd29:;
            6'd30:;
            6'd31:;
            6'd32: begin
                dataSPI = 8'h94;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd33:;
            6'd34: begin
                dataSPI = 8'h92;
                bytesSPI = bytesFIFO;
                EjcSPI = 1'b1;
            end 
            6'd35:;
            6'd36: begin
                dataSPI = 8'h90;
                bytesSPI = 8'd1;
                EjcSPI = 1'b1;
            end 
            6'd37:;
            6'd38: ReturnTR = 1'b1;
            6'd39: ErrorTR = 1'b1;
            default: begin
                inactivoTR = 0;
                dataSPI = 0;
                EjcSPI = 0;
                bytesSPI = 0;
                PD = 0;
                ErrorTR = 0;
                ReturnTR = 0;
            end 
        endcase
    end
endmodule
