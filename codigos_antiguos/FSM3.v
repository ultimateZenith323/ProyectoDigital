module FSM3 (
    input CLK,
    input start,
    input reset,

    input M2,
    output reg T2,

    input RetSPI, // Indica el que FSMS requiere otro byte
    input inactivo, // Indica que FSMS ha terminado su tarea
    input lectura, // Indica que se debe leer la informacion de SPI
    input [7:0] info, // Informacion de SPI

    output reg [7:0] data, // data para FSMS
    output reg EjcSPI, // Iniciar FSMS
    output reg [7:0] bytes // Repeticiones de FSMS
);
    reg [4:0] estado;

    always @(posedge CLK, posedge start) begin
        if (start) begin
            estado <= 0;
        end else begin
            if (reset) estado <= 0;
            else begin
                case (estado)
                    5'd0:  if (M2) estado <= 5'd1;
                    5'd1:  if (RetSPI) estado <= 5'd2;
                    5'd2:  if (inactivo) estado <= 5'd3;
                    5'd3:  if (RetSPI) estado <= 5'd4;
                    5'd4:  if (inactivo) estado <= 5'd5;
                    5'd5:  if (RetSPI) estado <= 5'd6;
                    5'd6:  if (inactivo) estado <= 5'd7;
                    5'd7:  if (RetSPI) estado <= 5'd8;
                    5'd8:  if (inactivo) estado <= 5'd9;
                    5'd9:  if (RetSPI) estado <= 5'd10;
                    5'd10: if (inactivo) estado <= 5'd11;
                    5'd11: if (RetSPI) estado <= 5'd12;
                    5'd12: if (inactivo) estado <= 5'd13;
                    5'd13: if (RetSPI) estado <= 5'd14;
                    5'd14: if (inactivo) estado <= 5'd15;
                    5'd15: if (RetSPI) estado <= 5'd16;
                    5'd16: if (inactivo) estado <= 5'd17;
                    5'd17: if (RetSPI) estado <= 5'd18;
                    5'd18: if (inactivo) estado <= 5'd19;
                    5'd19: if (RetSPI) estado <= 5'd20;
                    5'd20: if (inactivo) estado <= 5'd21;
                    5'd21: if (RetSPI) estado <= 5'd22;
                    5'd22: if (inactivo) estado <= 5'd23;
                    5'd23: if (RetSPI) estado <= 5'd24;
                    5'd24: if (inactivo) estado <= 5'd25;
                    5'd25: if (RetSPI) estado <= 5'd26;
                    5'd26: if (inactivo) estado <= 5'd27;
                    5'd27: if (lectura) begin
                        if (info[2:0] == 3'b010) estado <= 5'd28;
                        else estado <= 5'd29;
                    end
                    5'd28: if (inactivo) estado <= 5'd27;
                    5'd29: if (inactivo) estado <= 5'd30;
                    5'd30: if (reset) estado <= 5'd0;
                    default: estado <= 5'd0;
                endcase
            end
        end
    end

    always @(*) begin
        T2 = 0;
        data = 0;
        EjcSPI = 0;
        bytes = 0;
        case (estado)
            5'd0:;
            5'd1: begin
                data = 8'h2;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd2: data = 8'hF;
            5'd3: begin
                data = 8'h4;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd4: data = 8'h23;
            5'd5: begin
                data = 8'h6;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd6: data = 8'h80;
            5'd7: begin
                data = 8'h24;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd8: data = 8'h0;
            5'd9: begin
                data = 8'h26;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd10: data = 8'h0;
            5'd11: begin
                data = 8'h48;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd12: data = 8'h26;
            5'd13: begin
                data = 8'h54;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd14: data = 8'h80;
            5'd15: begin
                data = 8'h56;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd16: data = 8'hA9;
            5'd17: begin
                data = 8'h58;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd18: data = 8'h3;
            5'd19: begin
                data = 8'h5A;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd20: data = 8'hE8;
            5'd21: begin
                data = 8'h2A;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd22: data = 8'h40;
            5'd23: begin
                data = 8'h22;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd24: data = 8'h3D;
            5'd25: begin
                data = 8'h28;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd26: data = 8'h83;
            5'd27: begin
                data = 8'h90;
                bytes = 8'd1;
                EjcSPI = 1'b1;
            end
            5'd28, 5'd29:;
            5'd30: T2 = 1'b1;
            default: begin
                T2 = 0;
                data = 0;
                EjcSPI = 0;
                bytes = 0;
            end
        endcase
    end
endmodule
