module FSM22 ( // Ejecucion de AutoTest
    input CLK,
    input start,
    input reset,

    input F1, // Activa este modulo
    input [7:0] Info, // Resultado obtenido de ejecutar FSMS
    input SPIRet, // Retomar control de FSMS
    input lec, // Habilita la lectura de la info
    input inactivo, // Indica que FSMS ha terminado su tarea
    
    output reg K1, // Finaliza y vuelve el control al maestro
    output reg [7:0] Data, // Información para FSMS
    output reg [7:0] BytN, // Número de procesos
    output reg SPIExe, // Activar FSMS
    output reg Err2 // Bit de error
);
    reg [4:0] estado;
    reg [5:0] count;
    wire Mp;

    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 5'b0;
            count <= 6'b0;
            Err2 <= 1'b0;
        end else begin
            case (estado)
                5'd0: if (F1) estado <= 5'd1;
                5'd1: if (SPIRet) estado <= 5'd2;
                5'd2: if (SPIRet) estado <= 5'd3;
                5'd3: if (SPIRet) begin
                    count <= 6'd0;
                    estado <= 5'd4;
                end
                5'd4: if (SPIRet) begin
                    if (count == 6'd24) begin 
                        estado <= 5'd5;
                        count <= 0;
                    end
                    else count <= count + 6'd1;
                end
                5'd5: if (SPIRet) estado <= 5'd6;
                5'd6: if (SPIRet) estado <= 5'd7;
                5'd7: if (SPIRet) estado <= 5'd8;
                5'd8: if (SPIRet) estado <= 5'd9;
                5'd9: if (SPIRet) estado <= 5'd10;
                5'd10: if (SPIRet) estado <= 5'd21;
                5'd11: if (SPIRet) estado <= 5'd12;
                5'd12: if (SPIRet) estado <= 5'd13;
                5'd13: begin
                    if (lec) begin
                        if (Info[4]) estado <= 5'd23;
                        else estado <= 5'd20;
                    end
                end
                5'd14: if (SPIRet) estado <= 5'd15;
                5'd15: if (SPIRet) estado <= 5'd16;
                5'd16: if (SPIRet) begin
                    count <= 6'd0;
                    estado <= 5'd17;
                end
                5'd17: if (lec) begin
                    if (Mp) begin
                        if (count == 6'd63) estado <= 5'd19;
                        else count <= count + 6'd1;
                    end else estado <= 5'd18;
                end                  
                5'd18: if (reset) begin
                    estado <= 5'd0;
                    count <= 5'd0;
                    Err2 <= 1'b1;
                end
                5'd19: if (inactivo) estado <= 5'd24;
                5'd20: estado <= 5'd13;
                5'd21: if (SPIRet) estado <= 5'd22;
                5'd22: if (SPIRet) estado <= 5'd11;
                5'd23: estado <= 5'd14;
                5'd24: if (SPIRet) estado <= 5'd25;
                5'd25: if (SPIRet) estado <= 5'd28;
                5'd28: if (reset) begin
                    count <= 0;
                    estado <= 0;
                end
                default: begin 
                    estado <= 5'b0;
                    count <= 5'd0;
                    Err2 <= 1'b0;
                end
            endcase
        end
    end

    always @(*) begin
        K1 = 0;
        Data = 0;
        BytN = 0;
        SPIExe = 0;
        case (estado)
            5'd0, 5'd4, 5'd10, 5'd15, 5'd20, 5'd23: ;
            5'd1: begin
                Data = 8'h2;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd2: begin
                Data = 8'hf;
            end
            5'd3: begin
                Data = 8'h12;
                BytN = 8'd25;
                SPIExe = 1'b1;
            end
            5'd5: begin
                Data = 8'h2;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd6: begin
                Data = 8'h1;
            end
            5'd7: begin
                Data = 8'h6C;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd8: begin
                Data = 8'h9;
            end
            5'd9: begin
                Data = 8'h12;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd11: begin
                Data = 8'h2;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd12: begin
                Data = 8'h3;
            end
            5'd13: begin
                Data = 8'h88;
                SPIExe = 1'b1;
                BytN = 8'd1;
            end
            5'd14: begin
                Data = 8'h2;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd16: begin
                Data = 8'h92;
                BytN = 8'd64;
                SPIExe = 1'b1;
            end
            5'd17: begin
                Data = 8'h92;
            end
            5'd18:;
            5'd19: begin
                K1 = 1'b0;
            end
            5'd21: begin
                Data = 8'h8;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd22: Data = 8'h7F;
            5'd24: begin
                Data = 8'h6C;
                BytN = 8'd1;
                SPIExe = 1'b1;
            end
            5'd25: Data = 0;
            5'd28: K1 = 1'b1;
            default: begin
                K1 = 0;
                Data = 0;
                BytN = 0;
                SPIExe = 0;
            end
        endcase
    end

    MPC Mod1(
        .info(Info),
        .conteo(count),
        .Ve(Mp)
    );
endmodule
