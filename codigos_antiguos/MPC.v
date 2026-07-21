module MPC (
    input [7:0] info,
    input [5:0] conteo,
    output Ve
);
    reg [7:0] Comparador;

    always @(*) begin
        case (conteo)
            6'd0: Comparador = 8'h0;
            6'd1: Comparador = 8'hEB;
            6'd2: Comparador = 8'h66;
            6'd3: Comparador = 8'hBA;
            6'd4: Comparador = 8'h57;
            6'd5: Comparador = 8'hBF;
            6'd6: Comparador = 8'h23;
            6'd7: Comparador = 8'h95;
            6'd8: Comparador = 8'hD0;
            6'd9: Comparador = 8'hE3;
            6'd10: Comparador = 8'h0D;
            6'd11: Comparador = 8'h3D;
            6'd12: Comparador = 8'h27;
            6'd13: Comparador = 8'h89;
            6'd14: Comparador = 8'h5C;
            6'd15: Comparador = 8'hDE;
            6'd16: Comparador = 8'h9D;
            6'd17: Comparador = 8'h3B;
            6'd18: Comparador = 8'hA7;
            6'd19: Comparador = 8'h0;
            6'd20: Comparador = 8'h21;
            6'd21: Comparador = 8'h5B;
            6'd22: Comparador = 8'h89;
            6'd23: Comparador = 8'h82;
            6'd24: Comparador = 8'h51;
            6'd25: Comparador = 8'h3A;
            6'd26: Comparador = 8'hEB;
            6'd27: Comparador = 8'h02;
            6'd28: Comparador = 8'h0C;
            6'd29: Comparador = 8'hA5;
            6'd30: Comparador = 8'h0;
            6'd31: Comparador = 8'h49;
            6'd32: Comparador = 8'h7C;
            6'd33: Comparador = 8'h84;
            6'd34: Comparador = 8'h4D;
            6'd35: Comparador = 8'hB3;
            6'd36: Comparador = 8'hCC;
            6'd37: Comparador = 8'hD2;
            6'd38: Comparador = 8'h1B;
            6'd39: Comparador = 8'h81;
            6'd40: Comparador = 8'h5D;
            6'd41: Comparador = 8'h48;
            6'd42: Comparador = 8'h76;
            6'd43: Comparador = 8'hD5;
            6'd44: Comparador = 8'h71;
            6'd45: Comparador = 8'h61;
            6'd46: Comparador = 8'h21;
            6'd47: Comparador = 8'hA9;
            6'd48: Comparador = 8'h86;
            6'd49: Comparador = 8'h96;
            6'd50: Comparador = 8'h83;
            6'd51: Comparador = 8'h38;
            6'd52: Comparador = 8'hCF;
            6'd53: Comparador = 8'h9D;
            6'd54: Comparador = 8'h5B;
            6'd55: Comparador = 8'h6D;
            6'd56: Comparador = 8'hDC;
            6'd57: Comparador = 8'h15;
            6'd58: Comparador = 8'hBA;
            6'd59: Comparador = 8'h3E;
            6'd60: Comparador = 8'h7D;
            6'd61: Comparador = 8'h95;
            6'd62: Comparador = 8'h3B;
            6'd63: Comparador = 8'h2F;
            default: Comparador = 8'h0;
        endcase
    end

    assign Ve = (Comparador == info);
endmodule
