module FSM21 ( //Lectura y verificacion del registro 37h de comando de version
    input CLK,
    input start,
    input reset,

    input F0, //Inicia este modulo
    input lec, // Indica que se debe leer la información
    input [7:0] info, // Información de FSMS
    input Ret, // Retorna el control de FSMS
    
    output reg K0, //Indica el final de este modulo
    output reg [7:0] Data, // Palabra para FSMS
    output reg EjecutarSPI, // Inicia FSMS
    output reg [7:0] Bn, // Numero de repeticiones de FSMS
    output reg Err1 // Error, el VersionReg no es 92h
);
    reg [2:0] estado;
    
    always @(posedge CLK, posedge start) begin
        if (start) estado <= 3'b0;
        else begin
            case (estado)
                3'd0: if (F0) estado <= 3'd1;
                3'd1: if (Ret) estado <= 3'd2;
                3'd2: if (Ret) estado <= 3'd3;
                3'd3: estado <= 3'd4;
                3'd4: if (lec) begin
                    if (info == 8'h92) estado <= 3'd5;
                    else estado <= 3'd6;
                end
                3'd5: if (Ret) estado <= 3'd7;
                3'd6: if (reset) estado <= 3'd0;
                3'd7: estado <= 3'd0;
                default: estado <= 3'd0;
            endcase
        end
    end

    always @(*) begin
        case (estado)
            3'd0: begin
                K0 = 1'b0;
                Data = 8'b0;
                EjecutarSPI = 1'b0;
                Err1 = 1'b0;
                Bn = 0;
            end
            3'd1: begin
                K0 = 1'b0;
                Data = 8'h02;
                EjecutarSPI = 1'b1;
                Err1 = 1'b0;
                Bn = 8'd1;
            end
            3'd2: begin
                K0 = 1'b0;
                Data = 8'h0F;
                EjecutarSPI = 1'b0;
                Err1 = 1'b0;
                Bn = 8'd0;
            end
            3'd3: begin
                K0 = 1'b0;
                Data = 8'h00;
                EjecutarSPI = 1'b0;
                Err1 = 1'b0;
                Bn = 8'd0;
            end
            3'd4: begin
                K0 = 1'b0;
                Data = 8'hEE;
                EjecutarSPI = 1'b1;
                Err1 = 1'b0;
                Bn = 8'd1;
            end
            3'd5: begin
                K0 = 0;
                Data = 8'b0;
                EjecutarSPI = 1'b0;
                Err1 = 1'b0;
                Bn = 0;
            end
            3'd6: begin
                K0 = 1'b0;
                Data = 8'b0;
                EjecutarSPI = 1'b0;
                Err1 = 1'b1;
                Bn = 0;
            end
            3'd7: begin
                K0 = 1'b1;
                Data = 8'b0;
                EjecutarSPI = 1'b0;
                Err1 = 1'b0;
                Bn = 0;
            end
            default: begin
                K0 = 1'b0;
                Data = 8'b0;
                EjecutarSPI = 1'b0;
                Err1 = 1'b0;
                Bn = 0;
            end
        endcase
    end
endmodule
