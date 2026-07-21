// ============================================================
// lcd_hd44780.v
// Controlador HD44780 en modo 8 BITS (D0-D7), solo escritura.
// Basado en el mismo esquema de tiempos y máquina de estados
// que "lcd_rtc_display.v" (SETUP -> PULSE -> HOLD), ya que ese
// módulo funciona de forma confiable en el hardware del usuario.
//
// A diferencia del módulo RTC (que refresca un buffer fijo todo
// el tiempo), este controlador expone una interfaz de "escribir
// un byte bajo demanda", porque aquí el contenido cambia cada vez
// que el usuario presiona una tecla, no en un refresco periódico.
//
// Uso desde el módulo top:
//   - Esperar 'ready' = 1 (fin de inicialización)
//   - Poner 'din' con el byte deseado
//   - Pulsar 'wr_cmd' (comando: posición de cursor, clear, etc.)
//     o 'wr_data' (carácter ASCII a imprimir)
//   - Esperar a que 'busy' vuelva a 0 antes de la siguiente orden
//
// Conexiones físicas:
//   LCD_RS -> pin RS del LCD
//   LCD_RW -> pin R/W del LCD (el propio módulo lo maneja, siempre en 0 = escritura)
//   LCD_E  -> pin E del LCD
//   LCD_D[7:0] -> pines D0-D7 del LCD (bus completo, modo 8 bits)
//   VO (contraste) -> potenciómetro entre VCC y GND
// ============================================================

module lcd #(
    parameter CLK_FREQ_HZ = 50_000_000
)(
    input  wire clk,
    input  wire rst_n,

    input  wire wr_cmd,     // pulso de 1 ciclo: escribir comando
    input  wire wr_data,    // pulso de 1 ciclo: escribir dato/caracter
    input  wire [7:0] din,  // byte a escribir

    output reg  busy,       // 1 mientras el controlador procesa
    output reg  ready,      // 1 cuando terminó la inicialización

    output reg  LCD_RS,
    output reg  LCD_E,
    output reg  LCD_RW,
    output reg  [7:0] LCD_D
);

    // ---------------------------------------------------------------
    // Tiempos (en ciclos de reloj), igual que en lcd_rtc_display.v
    // ---------------------------------------------------------------
    localparam integer POWERON_CYCLES   = (CLK_FREQ_HZ/1000)    * 20; // 20 ms tras reset
    localparam integer CMD_DELAY_CYCLES = (CLK_FREQ_HZ/1000)    * 2;  // 2 ms de margen tras cada comando/dato
    localparam integer SETUP_CYCLES     = 16;                         // margen de setup antes de subir E
    localparam integer EN_PULSE_CYCLES  = (CLK_FREQ_HZ/1_000_000)*1;  // ~1us de ancho de pulso E

    // ---------------------------------------------------------------
    // ROM de inicialización del HD44780 en modo 8 bits (todo con RS=0)
    // ---------------------------------------------------------------
    reg [7:0] init_rom [0:3];
    initial begin
        init_rom[0] = 8'h38; // Function Set: interfaz 8 bits, 2 lineas, fuente 5x8
        init_rom[1] = 8'h0C; // Display ON, cursor off, blink off
        init_rom[2] = 8'h01; // Clear Display (requiere >=1.52ms de ejecucion)
        init_rom[3] = 8'h06; // Entry Mode Set: incrementa cursor, sin shift de pantalla
    end

    // ---------------------------------------------------------------
    // Máquina de estados
    // ---------------------------------------------------------------
    localparam S_POWERUP = 3'd0,
               S_IDLE     = 3'd2,
               S_SETUP    = 3'd3,
               S_PULSE    = 3'd4,
               S_HOLD     = 3'd5;

    reg [2:0]  state;
    reg [1:0]  init_idx;      // 0..3, recorre init_rom
    reg        phase_init;    // 1 = todavía enviando la secuencia de inicialización
    reg [20:0] delay_cnt;
    reg [15:0] en_cnt;
    reg [7:0]  cur_byte;
    reg        cur_rs;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_POWERUP;
            init_idx   <= 2'd0;
            phase_init <= 1'b1;
            delay_cnt  <= 21'd0;
            en_cnt     <= 16'd0;
            busy       <= 1'b1;
            ready      <= 1'b0;
            LCD_E      <= 1'b0;
            LCD_RW     <= 1'b0;   // siempre en modo escritura
            LCD_RS     <= 1'b0;
            LCD_D      <= 8'h00;
            cur_byte   <= 8'h00;
            cur_rs     <= 1'b0;
        end else begin
            case (state)

                // Espera minima de encendido antes de mandar el primer comando
                S_POWERUP: begin
                    if (delay_cnt < POWERON_CYCLES)
                        delay_cnt <= delay_cnt + 1'b1;
                    else begin
                        delay_cnt <= 21'd0;
                        init_idx  <= 2'd0;
                        cur_byte  <= init_rom[0];
                        cur_rs    <= 1'b0;
                        state     <= S_SETUP;
                    end
                end

                // Reposo: esperando ordenes del módulo top
                S_IDLE: begin
                    LCD_E <= 1'b0;
                    busy  <= 1'b0;
                    ready <= 1'b1;
                    if (wr_cmd || wr_data) begin
                        busy     <= 1'b1;
                        cur_byte <= din;
                        cur_rs   <= wr_data; // 0 = comando, 1 = dato/caracter
                        state    <= S_SETUP;
                    end
                end

                // Coloca RS y datos en el bus ANTES de activar E (setup time)
                S_SETUP: begin
                    LCD_D  <= cur_byte;
                    LCD_RS <= cur_rs;
                    LCD_RW <= 1'b0;
                    if (delay_cnt < SETUP_CYCLES)
                        delay_cnt <= delay_cnt + 1'b1;
                    else begin
                        delay_cnt <= 21'd0;
                        en_cnt    <= 16'd0;
                        state     <= S_PULSE;
                    end
                end

                // Pulso de Enable
                S_PULSE: begin
                    LCD_E <= 1'b1;
                    if (en_cnt < EN_PULSE_CYCLES)
                        en_cnt <= en_cnt + 1'b1;
                    else begin
                        LCD_E     <= 1'b0;
                        delay_cnt <= 21'd0;
                        state     <= S_HOLD;
                    end
                end

                // Espera a que el LCD ejecute el comando/dato
                S_HOLD: begin
                    if (delay_cnt < CMD_DELAY_CYCLES)
                        delay_cnt <= delay_cnt + 1'b1;
                    else begin
                        delay_cnt <= 21'd0;
                        if (phase_init) begin
                            if (init_idx == 2'd3) begin
                                phase_init <= 1'b0;
                                state      <= S_IDLE;
                            end else begin
                                init_idx <= init_idx + 1'b1;
                                cur_byte <= init_rom[init_idx + 1'b1];
                                cur_rs   <= 1'b0;
                                state    <= S_SETUP;
                            end
                        end else begin
                            state <= S_IDLE;
                        end
                    end
                end

                default: state <= S_POWERUP;
            endcase
        end
    end

endmodule