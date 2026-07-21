// =============================================================================
// security_top.v
// Top de hardware: DS3231 (RTC) + teclado matricial 4x4 + LCD 16x2
// + cerradura electrica (rele) + bitacora de accesos por Bluetooth (HC-05).
// =============================================================================
module security_top #(
    parameter CLK_FREQ_HZ   = 50_000_000,
    parameter DUMP_PERIOD_S = 5,          // cada cuanto se vuelca la bitacora por BT
    parameter BUZZ_MS       = 500          // duracion del beep al abrir la cerradura
)(
    input  wire CLOCK_50,     // reloj de 50 MHz de la placa
    input  wire KEY_RESET,    // boton de reset, activo en bajo
    input  wire KEY_SET_TIME, // boton para cargar la hora inicial, activo en bajo
    input  wire KEY_CLOSE,    // boton fisico para cerrar la cerradura, activo en bajo

    output wire [3:0] KP_ROWS,  // filas del teclado matricial
    input  wire [3:0] KP_COLS,  // columnas del teclado matricial

    inout  wire I2C_SDA,      // SDA del DS3231
    output wire I2C_SCL,      // SCL del DS3231

    output wire LCD_RS,       // RS LCD
    output wire LCD_E,        // E LCD
    output wire LCD_RW,       // R/W LCD
    output wire [7:0] LCD_D,  // D0-D7 LCD

    output wire BT_TXD,       // RXD modulo HC-05
    output wire RELE,         // Rele cerradura
    output wire BUZZER,       // Buzzer
    output wire [5:0] LED,    // LEDs de depuracion
    output wire LED_VERDE,    // LED verde
    output wire LED_ROJO      // LED rojo
);

    wire rst_n = KEY_RESET;

    // ---------------- boton de ajuste de hora ----------------
    reg [2:0] key_set_sync;
    always @(posedge CLOCK_50 or negedge rst_n)
        if (!rst_n) key_set_sync <= 3'b111;
        else        key_set_sync <= {key_set_sync[1:0], KEY_SET_TIME};

    wire set_time_pulse = (key_set_sync[2:1] == 2'b10);

    // ---------------- Deteccion de pulso de cierre (Boton físico) ----------------
    reg [2:0] key_close_sync;
    always @(posedge CLOCK_50 or negedge rst_n)
        if (!rst_n) key_close_sync <= 3'b111;
        else        key_close_sync <= {key_close_sync[1:0], KEY_CLOSE};

    wire key_close_pulse = (key_close_sync[2:1] == 2'b10); // Flanco de bajada

    // ---------------- volcado automatico por Bluetooth ----------------
    localparam integer DUMP_CYCLES = CLK_FREQ_HZ * DUMP_PERIOD_S;
    reg [31:0] dump_cnt;
    reg        dump_pulse_auto;
    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            dump_cnt        <= 32'd0;
            dump_pulse_auto <= 1'b0;
        end else if (dump_cnt >= DUMP_CYCLES-1) begin
            dump_cnt        <= 32'd0;
            dump_pulse_auto <= 1'b1;
        end else begin
            dump_cnt        <= dump_cnt + 32'd1;
            dump_pulse_auto <= 1'b0;
        end
    end

    // ---------------- señales RTC ----------------
    wire [7:0] sec_bcd, min_bcd, hour_bcd, day_bcd, date_bcd, month_bcd, year_bcd;
    wire       rtc_data_valid, rtc_comm_error;
    wire [8*17-1:0] lcd_time_str;
    wire [7:0] event_sec_bcd, event_min_bcd, event_hour_bcd, event_day_bcd,
               event_date_bcd, event_month_bcd, event_year_bcd;
    wire       event_granted, event_time_valid;
    wire [8*17-1:0] event_lcd_str;

    wire kp_access_event, kp_access_granted;
    wire kp_close_trigger; // pulso desde teclado (tecla '#')

    // ---------------- RTC ----------------
    controlador_RTC #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .I2C_FREQ_HZ(100_000),
        .POLL_PERIOD_MS(500),
        .SET_SEC_BCD  (8'h00),
        .SET_MIN_BCD  (8'h32),
        .SET_HOUR_BCD (8'h12),
        .SET_DAY_BCD  (8'h06),
        .SET_DATE_BCD (8'h19),
        .SET_MONTH_BCD(8'h07),
        .SET_YEAR_BCD (8'h26)
    ) u_rtc (
        .clk(CLOCK_50), .rst_n(rst_n),
        .set_time_trigger(set_time_pulse),
        .access_event(kp_access_event), .access_granted(kp_access_granted),
        .sec_bcd(sec_bcd), .min_bcd(min_bcd), .hour_bcd(hour_bcd),
        .day_bcd(day_bcd), .date_bcd(date_bcd), .month_bcd(month_bcd), .year_bcd(year_bcd),
        .rtc_data_valid(rtc_data_valid), .rtc_comm_error(rtc_comm_error),
        .lcd_time_str(lcd_time_str),
        .event_sec_bcd(event_sec_bcd), .event_min_bcd(event_min_bcd), .event_hour_bcd(event_hour_bcd),
        .event_day_bcd(event_day_bcd), .event_date_bcd(event_date_bcd),
        .event_month_bcd(event_month_bcd), .event_year_bcd(event_year_bcd),
        .event_granted(event_granted), .event_time_valid(event_time_valid),
        .event_lcd_str(event_lcd_str),
        .sda(I2C_SDA), .scl(I2C_SCL)
    );

    // ---------------- teclado + LCD ----------------
    keypad_lcd_controller #(
        .CLK_FREQ(CLK_FREQ_HZ),
        .PASSWORD_LEN(4)
    ) u_keypad_lcd (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .kp_rows(KP_ROWS),
        .kp_cols(KP_COLS),
        .lcd_rs(LCD_RS),
        .lcd_e(LCD_E),
        .lcd_rw(LCD_RW),
        .lcd_d(LCD_D),
        .hour_bcd(hour_bcd),
        .min_bcd(min_bcd),
        .rtc_data_valid(rtc_data_valid),
        .access_event(kp_access_event),
        .access_granted(kp_access_granted),
        .close_trigger(kp_close_trigger)
    );

    // ---------------- Lógica multiplexora de eventos para el LOG ----------------
    wire close_event_pulse = key_close_pulse || kp_close_trigger;

    reg        log_event_valid;
    reg [1:0]  log_event_type; // 2'b00: DENEGADO, 2'b01: OTORGADO, 2'b10: CERRADO
    reg [7:0]  log_hour_bcd, log_min_bcd, log_sec_bcd;
    reg [7:0]  log_date_bcd, log_month_bcd, log_year_bcd;

    always @(*) begin
        if (close_event_pulse) begin
            log_event_valid = 1'b1;
            log_event_type  = 2'b10; // CERRADO
            log_hour_bcd    = hour_bcd;
            log_min_bcd     = min_bcd;
            log_sec_bcd     = sec_bcd;
            log_date_bcd    = date_bcd;
            log_month_bcd   = month_bcd;
            log_year_bcd    = year_bcd;
        end else if (event_time_valid) begin
            log_event_valid = 1'b1;
            log_event_type  = event_granted ? 2'b01 : 2'b00; // OTORGADO / DENEGADO
            log_hour_bcd    = event_hour_bcd;
            log_min_bcd     = event_min_bcd;
            log_sec_bcd     = event_sec_bcd;
            log_date_bcd    = event_date_bcd;
            log_month_bcd   = event_month_bcd;
            log_year_bcd    = event_year_bcd;
        end else begin
            log_event_valid = 1'b0;
            log_event_type  = 2'b00;
            log_hour_bcd    = 8'h00;
            log_min_bcd     = 8'h00;
            log_sec_bcd     = 8'h00;
            log_date_bcd    = 8'h00;
            log_month_bcd   = 8'h00;
            log_year_bcd    = 8'h00;
        end
    end

    // ---------------- bitacora de accesos + Bluetooth ----------------
    wire [6:0] log_count;
    wire       log_dumping;

    access_log #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(9600),
        .DEPTH(64)
    ) u_log (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .event_time_valid(log_event_valid),
        .event_type(log_event_type),
        .event_hour_bcd(log_hour_bcd),
        .event_min_bcd(log_min_bcd),
        .event_sec_bcd(log_sec_bcd),
        .event_date_bcd(log_date_bcd),
        .event_month_bcd(log_month_bcd),
        .event_year_bcd(log_year_bcd),
        .dump_trigger(dump_pulse_auto),
        .uart_txd(BT_TXD),
        .log_count(log_count),
        .log_dumping(log_dumping)
    );

    // ---------------- cerradura electrica (rele) ----------------
    wire lock_open_trigger = event_time_valid && event_granted;
    wire door_open;

    lock_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .DEBOUNCE_MS(50),
        .CLOSE_HOLD_MS(1000)
    ) u_lock (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .open_trigger(lock_open_trigger),
        .close_trigger(kp_close_trigger),
        .KEY_CLOSE(KEY_CLOSE),
        .RELE(RELE),
        .door_open(door_open)
    );

    wire lock_error_trigger = kp_access_event && !kp_access_granted;

    // ---------------- controlador del buzzer ----------------
    controlador_buzzer #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) u_buzzer (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .trigger_abrir(lock_open_trigger),
        .trigger_cerrar(lock_error_trigger),
        .buzzer_out(BUZZER)
    );

    // ---------------- LEDs de depuracion y estado ----------------
    assign LED[5]   = ~log_dumping;
    assign LED[4:1] = ~log_count[3:0];
    assign LED[0]   = ~door_open;
     
    assign LED_VERDE = door_open; 
    assign LED_ROJO  = (BUZZER && !door_open);

endmodule