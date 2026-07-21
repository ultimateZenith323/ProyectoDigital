// =============================================================================
// keypad_lcd_controller.v
// Fusion de "top_keypad_lcd.v" con la pantalla de reposo del RTC.
//
// Pantalla de reposo (nadie esta tecleando):
//   Linea 1: "HH:MM" (hora en vivo, se refresca con cada lectura del RTC)
//   Linea 2: "PIN:" + un '*' por cada digito ya ingresado
//
// Mapeo de teclas:
//   '*' (codigo E) -> VALIDAR la clave ingresada (equivalente a "Enter")
//   '#' (codigo F) -> CERRAR la cerradura (pulso hacia lock_controller)
//   'A' (codigo A) -> BORRAR el intento actual (vuelve a "PIN:")
//
// Al presionar '*': compara la clave y muestra "ACCESO OTORGADO" /
// "ACCESO DENEGADO" durante HOLD_CYCLES, y genera UN pulso en
// access_event/access_granted (mismo formato de interfaz que ya usa
// ds3231_controller) para que el propio RTC capture la foto hora/fecha del
// evento. Esa foto es la que ya dispara access_log y lock_controller en el
// top, exactamente igual que antes.
//
// Al presionar '#': genera un pulso en close_trigger que le pide a
// lock_controller que cierre la cerradura (si esta abierta).
// =============================================================================
module keypad_lcd_controller #(
    parameter CLK_FREQ     = 50_000_000,
    parameter PASSWORD_LEN = 4          // cantidad de digitos de la clave
)(
    input  wire clk,
    input  wire rst_n,

    output wire [3:0] kp_rows,   // filas del teclado matricial
    input  wire [3:0] kp_cols,   // columnas del teclado matricial (con pull-up)

    output wire lcd_rs,
    output wire lcd_e,
    output wire lcd_rw,
    output wire [7:0] lcd_d,     // D0-D7 del LCD (modo 8 bits)

    // ---- hora en vivo, viene de ds3231_controller (para la pantalla de reposo) ----
    input  wire [7:0] hour_bcd,
    input  wire [7:0] min_bcd,
    input  wire       rtc_data_valid,   // pulso: hay una lectura nueva del RTC

    // ---- hacia ds3231_controller: mismo formato que access_event/access_granted ----
    output reg  access_event,    // pulso de 1 ciclo: se confirmo un intento con '*'
    output reg  access_granted,  // valido junto con access_event (1=otorgado,0=denegado)
    output reg  close_trigger    // pulso de 1 ciclo: se pidio cerrar la cerradura (tecla '#')
);

    // ------------------------------------------------------------
    // Instancia del escaner de teclado
    // ------------------------------------------------------------
    wire [3:0] key_code;
    wire       key_valid;

    keypad_scanner #(
        .CLK_FREQ(CLK_FREQ),
        .DEBOUNCE_MS(20)
    ) u_keypad (
        .clk(clk),
        .rst_n(rst_n),
        .rows(kp_rows),
        .cols(kp_cols),
        .key_code(key_code),
        .key_valid(key_valid)
    );

    // ------------------------------------------------------------
    // Instancia del controlador de LCD (byte por byte, bajo demanda)
    // ------------------------------------------------------------
    reg        wr_cmd, wr_data;
    reg  [7:0] din;
    wire       busy, ready;

    lcd #(
        .CLK_FREQ_HZ(CLK_FREQ)
    ) u_lcd (
        .clk(clk),
        .rst_n(rst_n),
        .wr_cmd(wr_cmd),
        .wr_data(wr_data),
        .din(din),
        .busy(busy),
        .ready(ready),
        .LCD_RS(lcd_rs),
        .LCD_E(lcd_e),
        .LCD_RW(lcd_rw),
        .LCD_D(lcd_d)
    );

    // ------------------------------------------------------------
    // Conversion BCD -> ASCII
    // ------------------------------------------------------------
    function [7:0] bcd_hi_ascii(input [7:0] bcd); bcd_hi_ascii = {4'h3, bcd[7:4]}; endfunction
    function [7:0] bcd_lo_ascii(input [7:0] bcd); bcd_lo_ascii = {4'h3, bcd[3:0]}; endfunction

    // ------------------------------------------------------------
    // CLAVE DE ACCESO
    // Cambia estos valores para definir tu propia clave.
    // Acepta 0-9 (digitos) o A-D (teclas de letra del teclado).
    // ------------------------------------------------------------
    reg [3:0] password [0:PASSWORD_LEN-1];
    initial begin
        password[0] = 4'h1;
        password[1] = 4'h2;
        password[2] = 4'h3;
        password[3] = 4'h4;
    end

    reg [3:0] entry_buf [0:PASSWORD_LEN-1];
    reg [2:0] entry_count; // 0..PASSWORD_LEN

    wire pw_match = (entry_count == PASSWORD_LEN)   &&
                    (entry_buf[0] == password[0])   &&
                    (entry_buf[1] == password[1])   &&
                    (entry_buf[2] == password[2])   &&
                    (entry_buf[3] == password[3]);
    // Nota: si cambias PASSWORD_LEN, agrega/quita comparaciones aqui.

    // ------------------------------------------------------------
    // Mensajes de resultado (16 caracteres, linea 1)
    // ------------------------------------------------------------
    reg [7:0] msg_ok  [0:15];
    reg [7:0] msg_bad [0:15];
    initial begin
        // "ACCESO OTORGADO "
        msg_ok[0]="A"; msg_ok[1]="C"; msg_ok[2]="C"; msg_ok[3]="E";
        msg_ok[4]="S"; msg_ok[5]="O"; msg_ok[6]=" "; msg_ok[7]="O";
        msg_ok[8]="T"; msg_ok[9]="O"; msg_ok[10]="R"; msg_ok[11]="G";
        msg_ok[12]="A"; msg_ok[13]="D"; msg_ok[14]="O"; msg_ok[15]=" ";
        // "ACCESO DENEGADO "
        msg_bad[0]="A"; msg_bad[1]="C"; msg_bad[2]="C"; msg_bad[3]="E";
        msg_bad[4]="S"; msg_bad[5]="O"; msg_bad[6]=" "; msg_bad[7]="D";
        msg_bad[8]="E"; msg_bad[9]="N"; msg_bad[10]="E"; msg_bad[11]="G";
        msg_bad[12]="A"; msg_bad[13]="D"; msg_bad[14]="O"; msg_bad[15]=" ";
    end

    localparam SEL_PROMPT = 2'd0,  // reposo / entrada de clave (hora + PIN)
               SEL_OK     = 2'd1,
               SEL_BAD    = 2'd2;

    reg [1:0] cur_msg_sel;

    // ------------------------------------------------------------
    // Contenido de cada linea, calculado caracter por caracter
    // ------------------------------------------------------------
    function [7:0] line1_char(input integer idx);
        begin
            case (cur_msg_sel)
                SEL_OK:  line1_char = msg_ok[idx];
                SEL_BAD: line1_char = msg_bad[idx];
                default: begin // SEL_PROMPT: "HH:MM" + espacios
                    case (idx)
                        0: line1_char = bcd_hi_ascii(hour_bcd);
                        1: line1_char = bcd_lo_ascii(hour_bcd);
                        2: line1_char = 8'h3A; // ':'
                        3: line1_char = bcd_hi_ascii(min_bcd);
                        4: line1_char = bcd_lo_ascii(min_bcd);
                        default: line1_char = 8'h20; // espacio
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] line2_char(input integer idx);
        begin
            if (cur_msg_sel != SEL_PROMPT) begin
                line2_char = 8'h20; // linea 2 en blanco durante el resultado
            end else begin
                case (idx)
                    0: line2_char = "P";
                    1: line2_char = "I";
                    2: line2_char = "N";
                    3: line2_char = 8'h3A; // ':'
                    default: line2_char = (idx - 4 < entry_count) ? 8'h2A : 8'h20; // '*' o espacio
                endcase
            end
        end
    endfunction

    // ------------------------------------------------------------
    // FSM principal
    // ------------------------------------------------------------
    localparam
        S_WAIT_READY  = 0,
        S_SET_L1      = 1,
        S_SEND_MSG    = 2,
        S_SET_L2      = 3,
        S_IDLE        = 4,
        S_ARM         = 5,
        S_WAIT_DONE   = 6,
        S_CHECK_PW    = 7,
        S_RESULT_HOLD = 8;

    localparam integer HOLD_CYCLES = CLK_FREQ * 3; // 3 segundos mostrando el resultado

    reg [3:0]  state;
    reg [3:0]  next_state;         // retorno del handshake generico S_ARM/S_WAIT_DONE
    reg [3:0]  after_redraw_state; // a donde ir cuando terminen de escribirse las 2 lineas
    reg        cur_line;           // 0 = escribiendo linea1, 1 = escribiendo linea2
    reg [4:0]  msg_idx;            // 0..16
    reg [27:0] hold_cnt;
    reg        pending_refresh;    // hay una lectura nueva del RTC esperando redibujar la hora

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_WAIT_READY;
            wr_cmd             <= 1'b0;
            wr_data            <= 1'b0;
            din                <= 8'h00;
            msg_idx            <= 5'd0;
            cur_line           <= 1'b0;
            entry_count        <= 3'd0;
            hold_cnt           <= 28'd0;
            cur_msg_sel        <= SEL_PROMPT;
            pending_refresh    <= 1'b0;
            access_event       <= 1'b0;
            access_granted     <= 1'b0;
            close_trigger      <= 1'b0;
            after_redraw_state <= S_IDLE;
        end else begin
            wr_cmd        <= 1'b0;
            wr_data       <= 1'b0;
            access_event  <= 1'b0; // pulso de un solo ciclo
            close_trigger <= 1'b0; // pulso de un solo ciclo

            if (rtc_data_valid) pending_refresh <= 1'b1;

            case (state)
                // Esperamos a que el LCD termine su inicializacion interna
                S_WAIT_READY: begin
                    if (ready) begin
                        cur_msg_sel        <= SEL_PROMPT;
                        after_redraw_state <= S_IDLE;
                        cur_line           <= 1'b0;
                        msg_idx            <= 5'd0;
                        state              <= S_SET_L1;
                    end
                end

                // Posiciona el cursor al inicio de la linea 1 (direccion 0x80)
                S_SET_L1: begin
                    din        <= 8'h80;
                    wr_cmd     <= 1'b1;
                    cur_line   <= 1'b0;
                    msg_idx    <= 5'd0;
                    next_state <= S_SEND_MSG;
                    state      <= S_ARM;
                end

                // Envia los 16 caracteres de la linea actual (cur_line)
                S_SEND_MSG: begin
                    if (msg_idx < 16) begin
                        din        <= cur_line ? line2_char(msg_idx) : line1_char(msg_idx);
                        wr_data    <= 1'b1;
                        msg_idx    <= msg_idx + 1'b1;
                        next_state <= S_SEND_MSG;
                        state      <= S_ARM;
                    end else if (!cur_line) begin
                        state <= S_SET_L2; // termino linea1, sigue linea2
                    end else begin
                        state <= after_redraw_state; // termino linea2
                    end
                end

                // Posiciona el cursor al inicio de la linea 2 (direccion 0xC0)
                S_SET_L2: begin
                    din        <= 8'hC0;
                    wr_cmd     <= 1'b1;
                    cur_line   <= 1'b1;
                    msg_idx    <= 5'd0;
                    next_state <= S_SEND_MSG;
                    state      <= S_ARM;
                end

                // Reposo: esperando teclas o una lectura nueva del RTC
                S_IDLE: begin
                    if (pending_refresh) begin
                        pending_refresh    <= 1'b0;
                        after_redraw_state <= S_IDLE;
                        cur_line           <= 1'b0;
                        msg_idx            <= 5'd0;
                        state              <= S_SET_L1;
                    end else if (key_valid) begin
                        case (key_code)
                            4'hE: begin // '*' -> validar clave ("Enter")
                                state <= S_CHECK_PW;
                            end
                            4'hF: begin // '#' -> pedir cierre de la cerradura
                                close_trigger <= 1'b1;
                            end
                            4'hA: begin // 'A' -> borrar intento
                                entry_count        <= 3'd0;
                                after_redraw_state <= S_IDLE;
                                cur_line           <= 1'b0;
                                msg_idx            <= 5'd0;
                                state              <= S_SET_L1;
                            end
                            default: begin // digito u otra letra -> agregar al intento
                                if (entry_count < PASSWORD_LEN) begin
                                    entry_buf[entry_count] <= key_code;
                                    entry_count             <= entry_count + 1'b1;
                                    after_redraw_state      <= S_IDLE;
                                    cur_line                <= 1'b0;
                                    msg_idx                 <= 5'd0;
                                    state                   <= S_SET_L1;
                                end
                                // si ya hay PASSWORD_LEN digitos, se ignoran teclas extra
                            end
                        endcase
                    end
                end

                // Tecla '#': compara la clave ingresada y dispara el evento hacia el RTC
                S_CHECK_PW: begin
                    cur_msg_sel        <= pw_match ? SEL_OK : SEL_BAD;
                    access_event       <= 1'b1;
                    access_granted     <= pw_match;
                    hold_cnt           <= 28'd0;
                    after_redraw_state <= S_RESULT_HOLD;
                    cur_line           <= 1'b0;
                    msg_idx            <= 5'd0;
                    state              <= S_SET_L1;
                end

                // Mantiene el mensaje de resultado ~3s y luego vuelve al reposo
                S_RESULT_HOLD: begin
                    if (hold_cnt < HOLD_CYCLES) begin
                        hold_cnt <= hold_cnt + 1'b1;
                    end else begin
                        cur_msg_sel        <= SEL_PROMPT;
                        entry_count        <= 3'd0;
                        after_redraw_state <= S_IDLE;
                        cur_line           <= 1'b0;
                        msg_idx            <= 5'd0;
                        state              <= S_SET_L1;
                    end
                end

                // Handshake generico con el controlador de LCD
                S_ARM: begin
                    if (busy) state <= S_WAIT_DONE;
                end
                S_WAIT_DONE: begin
                    if (!busy) state <= next_state;
                end

                default: state <= S_WAIT_READY;
            endcase
        end
    end

endmodule