// =============================================================================
// lock_controller.v
// Controla el rele de la cerradura electrica (12V), replicando la logica del
// codigo de Arduino.
//
// LOGICA DEL RELE (CONFIRMADA en la placa integrada real, probando
// rtc_lcd_top con este controlador):
//   RELE = 0  ->  cerradura CERRADA (rele desactivado)
//   RELE = 1  ->  cerradura ABIERTA (rele activado, pasan los 12V)
//
// NOTA: esta polaridad es la del cableado/rele de tu proyecto integrado
// (puede diferir del proyecto de prueba lock_test, que usaba otro
// pin/canal de rele). Si en algun momento cambias el modulo de rele fisico
// y vuelve a comportarse al reves, intercambia los 1'b1 <-> 1'b0 en las 4
// asignaciones de RELE de abajo.
// =============================================================================
module lock_controller #(
    parameter CLK_FREQ_HZ  = 50_000_000,
    parameter DEBOUNCE_MS  = 50,   // antirrebote del boton (igual al delay(50) del Arduino)
    parameter CLOSE_HOLD_MS= 1000  // pausa de seguridad tras cerrar (igual al delay(1000))
)(
    input  wire clk,
    input  wire rst_n,

    input  wire open_trigger,  // pulso de 1 ciclo: se concedio un acceso -> abrir
    input  wire close_trigger, // pulso de 1 ciclo: se pidio cerrar (p.ej. desde el teclado, tecla '#')
    input  wire KEY_CLOSE,     // boton fisico de cierre (opcional), activo en bajo (INPUT_PULLUP)

    output reg  RELE,          // al modulo rele: 0=cerrado, 1=abierto
    output wire door_open      // 1 mientras la puerta esta abierta (util para LED/debug)
);

    localparam integer DEBOUNCE_CYCLES   = (CLK_FREQ_HZ/1000) * DEBOUNCE_MS;
    localparam integer CLOSE_HOLD_CYCLES = (CLK_FREQ_HZ/1000) * CLOSE_HOLD_MS;

    localparam S_CLOSED  = 2'd0,  // cerradura cerrada, esperando un acceso otorgado
               S_OPEN    = 2'd1,  // cerradura abierta, esperando boton de cierre
               S_CLOSING = 2'd2;  // recien cerrada, pausa de seguridad antes de aceptar otro acceso

    reg [1:0]  state;
    reg [31:0] debounce_cnt;
    reg [31:0] hold_cnt;

    // ---- sincronizacion del boton fisico (mismo patron que los demas botones) ----
    reg [2:0] key_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) key_sync <= 3'b111;
        else        key_sync <= {key_sync[1:0], KEY_CLOSE};

    wire key_level_low = ~key_sync[2]; // 1 mientras el boton esta sostenido (activo en bajo)

    assign door_open = (state == S_OPEN) || (state == S_CLOSING);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_CLOSED;
            RELE         <= 1'b0;      // arranca cerrado
            debounce_cnt <= 0;
            hold_cnt     <= 0;
        end else begin
            case (state)
                S_CLOSED: begin
                    RELE         <= 1'b0;
                    debounce_cnt <= 0;
                    if (open_trigger) begin
                        RELE  <= 1'b1; // activa el rele -> pasan los 12V -> abre
                        state <= S_OPEN;
                    end
                end

                S_OPEN: begin
                    RELE <= 1'b1;
                    if (close_trigger) begin
                        // cierre pedido por pulso (p.ej. tecla '#' del teclado, ya antirrebotada)
                        RELE     <= 1'b0;
                        hold_cnt <= 0;
                        state    <= S_CLOSING;
                    end else if (key_level_low) begin
                        // boton sostenido: cuenta el tiempo de antirrebote
                        if (debounce_cnt < DEBOUNCE_CYCLES)
                            debounce_cnt <= debounce_cnt + 1'b1;
                        else begin
                            // sigue presionado tras el tiempo de antirrebote -> confirmado
                            RELE     <= 1'b0;
                            hold_cnt <= 0;
                            state    <= S_CLOSING;
                        end
                    end else begin
                        debounce_cnt <= 0; // se solto antes de tiempo, se reinicia el conteo
                    end
                end

                S_CLOSING: begin
                    RELE <= 1'b0;
                    if (hold_cnt < CLOSE_HOLD_CYCLES)
                        hold_cnt <= hold_cnt + 1'b1;
                    else
                        state <= S_CLOSED; // pausa de seguridad terminada, listo para otro acceso
                end

                default: state <= S_CLOSED;
            endcase
        end
    end
endmodule