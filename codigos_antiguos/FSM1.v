module FSM1 ( //Retardo inicial de encendido
    input CLK,
    input start,
    input reset,

    input M0,
    output reg T0
);
    reg [1:0] estado;

    always @(posedge CLK or posedge start) begin
        if (start) begin
            estado <= 2'b0;
        end else begin
            case (estado)
                2'b00: if (M0) estado <= 2'b01;
                2'b01: estado <= 2'b10;
                2'b10: if (reset) estado <= 2'b00;
                default: estado <= 2'b00;
            endcase
        end
    end

    always @(*) begin
        case (estado)
            2'b00, 2'b01: T0 = 1'b0;
            2'b10:        T0 = 1'b1;
            default:      T0 = 1'b0;
        endcase
    end
endmodule
