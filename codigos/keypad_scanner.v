// ============================================================
// keypad_scanner.v
// Escaneo de teclado matricial 4x4 con antirrebote (debounce)
// Layout físico asumido:
//      COL0 COL1 COL2 COL3
// ROW0   1    2    3    A
// ROW1   4    5    6    B
// ROW2   7    8    9    C
// ROW3   *    0    #    D
//
// rows  : salidas del FPGA hacia las filas del teclado (activo en bajo)
// cols  : entradas del FPGA desde las columnas del teclado
//         IMPORTANTE: deben tener pull-up (interno en Quartus o resistencia
//         externa de 10k a VCC), ya que en reposo deben leerse en '1'.
//
// key_code: código de 4 bits de la tecla detectada:
//   0-9 => dígitos 0-9
//   A,B,C,D => teclas A,B,C,D
//   E => tecla '*'
//   F => tecla '#'
// key_valid: pulso de UN ciclo de reloj cuando hay una tecla nueva
//            confirmada (ya libre de rebotes)
// ============================================================

module keypad_scanner #(
    parameter CLK_FREQ    = 50_000_000, // frecuencia del reloj del sistema
    parameter DEBOUNCE_MS = 20          // tiempo de antirrebote en ms
)(
    input  wire clk,
    input  wire rst_n,
    output reg  [3:0] rows,
    input  wire [3:0] cols,
    output reg  [3:0] key_code,
    output reg        key_valid
);

    // ------------------------------------------------------------
    // Generador de tick de 1 ms (base de tiempo para escaneo y debounce)
    // ------------------------------------------------------------
    localparam integer TICK_DIV = CLK_FREQ / 1000;
    reg [$clog2(TICK_DIV+1)-1:0] div_cnt;
    reg tick_1ms;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt  <= 0;
            tick_1ms <= 1'b0;
        end else if (div_cnt == TICK_DIV-1) begin
            div_cnt  <= 0;
            tick_1ms <= 1'b1;
        end else begin
            div_cnt  <= div_cnt + 1'b1;
            tick_1ms <= 1'b0;
        end
    end

    // ------------------------------------------------------------
    // Doble sincronizador de las columnas (evita metaestabilidad)
    // ------------------------------------------------------------
    reg [3:0] cols_ff0, cols_ff1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cols_ff0 <= 4'hF;
            cols_ff1 <= 4'hF;
        end else begin
            cols_ff0 <= cols;
            cols_ff1 <= cols_ff0;
        end
    end

    wire any_col_low = (cols_ff1 != 4'hF);

    // ------------------------------------------------------------
    // Tabla de decodificación fila/columna -> código de tecla
    // ------------------------------------------------------------
    function [3:0] decode_key;
        input [1:0] r;
        input [3:0] c;
        begin
            decode_key = 4'hF; // valor por defecto, no debería usarse si any_col_low=0
            case (r)
                2'd0: case (c) // 1 2 3 A
                    4'b0111: decode_key = 4'h1;
                    4'b1011: decode_key = 4'h2;
                    4'b1101: decode_key = 4'h3;
                    4'b1110: decode_key = 4'hA;
                    default: ;
                endcase
                2'd1: case (c) // 4 5 6 B
                    4'b0111: decode_key = 4'h4;
                    4'b1011: decode_key = 4'h5;
                    4'b1101: decode_key = 4'h6;
                    4'b1110: decode_key = 4'hB;
                    default: ;
                endcase
                2'd2: case (c) // 7 8 9 C
                    4'b0111: decode_key = 4'h7;
                    4'b1011: decode_key = 4'h8;
                    4'b1101: decode_key = 4'h9;
                    4'b1110: decode_key = 4'hC;
                    default: ;
                endcase
                2'd3: case (c) // * 0 # D
                    4'b0111: decode_key = 4'hE; // '*'
                    4'b1011: decode_key = 4'h0;
                    4'b1101: decode_key = 4'hF; // '#'
                    4'b1110: decode_key = 4'hD;
                    default: ;
                endcase
            endcase
        end
    endfunction

    // ------------------------------------------------------------
    // Máquina de estados: escaneo -> debounce -> tecla válida -> espera de liberación
    // ------------------------------------------------------------
    localparam S_SCAN         = 2'd0,
               S_DEBOUNCE     = 2'd1,
               S_VALID        = 2'd2,
               S_WAIT_RELEASE = 2'd3;

    reg [1:0]  state;
    reg [1:0]  row_idx;
    reg [3:0]  found_key;
    reg [15:0] timer_ms;

    // Codificación de filas activo en bajo: se activa una sola fila a la vez
    function [3:0] row_pattern;
        input [1:0] idx;
        begin
            case (idx)
                2'd0: row_pattern = 4'b1110;
                2'd1: row_pattern = 4'b1101;
                2'd2: row_pattern = 4'b1011;
                2'd3: row_pattern = 4'b0111;
                default: row_pattern = 4'b1111;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_SCAN;
            row_idx   <= 2'd0;
            rows      <= row_pattern(2'd0);
            key_code  <= 4'h0;
            key_valid <= 1'b0;
            timer_ms  <= 16'd0;
            found_key <= 4'h0;
        end else begin
            key_valid <= 1'b0; // pulso de un solo ciclo

            if (tick_1ms) begin
                case (state)
                    // Recorremos las 4 filas buscando alguna columna en bajo
                    S_SCAN: begin
                        if (any_col_low) begin
                            found_key <= decode_key(row_idx, cols_ff1);
                            timer_ms  <= 16'd0;
                            state     <= S_DEBOUNCE;
                            // se mantiene 'rows' fija en la fila actual mientras confirmamos
                        end else begin
                            row_idx <= row_idx + 1'b1;
                            rows    <= row_pattern(row_idx + 1'b1);
                        end
                    end

                    // Confirmamos que la tecla se mantiene estable DEBOUNCE_MS
                    S_DEBOUNCE: begin
                        if (!any_col_low) begin
                            state <= S_SCAN; // fue ruido/rebote
                        end else if (timer_ms >= DEBOUNCE_MS) begin
                            key_code  <= found_key;
                            key_valid <= 1'b1; // <-- pulso: tecla confirmada
                            state     <= S_VALID;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end

                    // Esperamos que el usuario suelte la tecla
                    S_VALID: begin
                        if (!any_col_low) begin
                            timer_ms <= 16'd0;
                            state    <= S_WAIT_RELEASE;
                        end
                    end

                    // Confirmamos liberación estable antes de volver a escanear
                    S_WAIT_RELEASE: begin
                        if (any_col_low) begin
                            timer_ms <= 16'd0; // se volvió a presionar antes de tiempo
                        end else if (timer_ms >= DEBOUNCE_MS) begin
                            row_idx <= 2'd0;
                            rows    <= row_pattern(2'd0);
                            state   <= S_SCAN;
                        end else begin
                            timer_ms <= timer_ms + 1'b1;
                        end
                    end
                endcase
            end
        end
    end

endmodule