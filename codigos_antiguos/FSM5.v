module FSM5 (
    input CLK,
    input start,
    input reset,

    input M4, // Activa el modulo
    input enter, // Indica el final del teclado
    input descartar, // Indica si el teclado descarto la operacion
    input [15:0] contrasena, // contrasena ingresada por el usuario

    output reg ModoAdmin, // Define el modo de administracion
    output reg Teclado, // Activa el teclado
    output reg [1:0] TextoSalida, // Textos de aviso
    output reg T4 // Fin del modulo
);
    parameter contraAdmin = 16'h1234;
    reg [2:0] estado;
    reg [12:0] retardo;

    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 0;
            ModoAdmin <= 0;
            retardo <= 0;
        end else begin
            if (reset) begin
                estado <= 0;
                ModoAdmin <= 0;
                retardo <= 0;
            end else begin
                case (estado)
                    3'd0: if (M4) begin
                        if (ModoAdmin) estado <= 3'd5;
                        else begin 
                            estado <= 3'd1;
                            retardo <= 0;
                        end
                    end
                    3'd1: if (enter) begin
                        if (descartar) estado <= 3'd4;
                        else begin
                            if (contrasena == contraAdmin) estado <= 3'd3;
                            else estado <= 3'd2;
                        end
                    end
                    3'd2: if (retardo == 13'd4500) estado <= 3'd4;
                        else retardo <= retardo + 13'd1;
                    3'd3: if (retardo == 13'd4500)  begin 
                        ModoAdmin <= 1'b1;
                        estado <= 3'd4;
                    end else retardo <= retardo + 13'd1;
                    3'd4: estado <= 3'd0;
                    3'd5: if (enter) estado <= 3'd6;
                        else if (descartar) estado <= 3'd4;
                    3'd6: begin
                        ModoAdmin <= 0;
                        estado <= 3'd4;
                    end
                    default: begin
                        ModoAdmin <= 0;
                        estado <= 3'd4;
                    end
                endcase
            end
        end
    end

    always @(*) begin
        Teclado = 0;
        T4 = 0;
        TextoSalida = 0;
        case (estado)
            3'd0, 3'd6:;
            3'd1: Teclado = 1'b1; 
            3'd2: TextoSalida = 2'd1;
            3'd3: TextoSalida = 2'd2;
            3'd4: T4 = 1'b1;
            3'd5: TextoSalida = 2'd3;
            default: begin
                Teclado = 0;
                T4 = 0;
                TextoSalida = 0;
            end
        endcase
    end
endmodule
