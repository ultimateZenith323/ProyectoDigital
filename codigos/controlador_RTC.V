// =============================================================================
// ds3231_controller.v
// Orquesta al i2c_master para leer continuamente hora/fecha del DS3231,
// entrega los datos en BCD y como cadena ASCII lista para el LCD, y captura
// una "foto" de la hora/fecha en el instante en que ocurre un evento de
// acceso RFID (otorgado o denegado).
//
// Direccion I2C del DS3231: 0x68  ->  byte escritura = 8'hD0, byte lectura = 8'hD1
// Mapa de registros usado (todos en BCD):
//   0x00 segundos   0x01 minutos   0x02 horas (modo 24h, bit6=0)
//   0x03 dia semana 0x04 dia mes   0x05 mes        0x06 anio (00-99)
// =============================================================================
module controlador_RTC #(
    parameter CLK_FREQ_HZ   = 50_000_000,
    parameter I2C_FREQ_HZ   = 100_000,
    parameter POLL_PERIOD_MS = 200,         // cada cuanto se refresca la hora leida

    // ---- hora/fecha inicial a escribir cuando se activa set_time_trigger (todo en BCD) ----
    // EDITA estos valores con la hora/fecha que quieras cargar, y vuelve a compilar.
    parameter [7:0] SET_SEC_BCD   = 8'h00, // segundos:   00
    parameter [7:0] SET_MIN_BCD   = 8'h00, // minutos:    00
    parameter [7:0] SET_HOUR_BCD  = 8'h12, // horas:      12 (formato 24h)
    parameter [7:0] SET_DAY_BCD   = 8'h01, // dia semana: 1 (1=lunes, ajusta a tu convencion)
    parameter [7:0] SET_DATE_BCD  = 8'h01, // dia del mes:01
    parameter [7:0] SET_MONTH_BCD = 8'h01, // mes:        01
    parameter [7:0] SET_YEAR_BCD  = 8'h26  // anio:       26 (2026)
)(
    input  wire clk,
    input  wire rst_n,

    // ---- disparo (1 pulso de 1 ciclo) para escribir la hora/fecha de arriba en el DS3231 ----
    // uso: presiona el boton UNA vez con la hora correcta ya puesta en los parametros de arriba
    // y vuelto a compilar; despues NO lo vuelvas a presionar (el DS3231 sigue el tiempo solo).
    input  wire set_time_trigger,

    // ---- evento de acceso proveniente del modulo RFID ----
    input  wire access_event,     // pulso de 1 ciclo: ocurrio un intento de acceso
    input  wire access_granted,   // valido junto con access_event (1=otorgado,0=denegado)

    // ---- salida continua de hora/fecha actual (BCD, se refresca cada POLL_PERIOD_MS) ----
    output reg [7:0] sec_bcd,
    output reg [7:0] min_bcd,
    output reg [7:0] hour_bcd,
    output reg [7:0] day_bcd,     // dia de la semana 1-7
    output reg [7:0] date_bcd,    // dia del mes 1-31
    output reg [7:0] month_bcd,
    output reg [7:0] year_bcd,
    output reg       rtc_data_valid,   // pulso: hay una lectura nueva disponible
    output reg       rtc_comm_error,   // se quedo en 1 si el DS3231 no respondio (NACK inesperado)

    // ---- cadena ASCII lista para el LCD: "HH:MM:SS DD/MM/YY" (17 caracteres) ----
    output reg [8*17-1:0] lcd_time_str,

    // ---- snapshot capturado en el instante exacto del evento de acceso ----
    output reg [7:0] event_sec_bcd,
    output reg [7:0] event_min_bcd,
    output reg [7:0] event_hour_bcd,
    output reg [7:0] event_day_bcd,
    output reg [7:0] event_date_bcd,
    output reg [7:0] event_month_bcd,
    output reg [7:0] event_year_bcd,
    output reg       event_granted,
    output reg       event_time_valid,      // pulso: el snapshot del evento ya esta listo
    output reg [8*17-1:0] event_lcd_str,     // cadena lista para mostrar el evento en el LCD

    // ---- bus fisico I2C ----
    inout  wire sda,
    output wire scl
);

    localparam [6:0] DS3231_ADDR = 7'h68;
    localparam [7:0] ADDR_W = {DS3231_ADDR, 1'b0}; // 8'hD0
    localparam [7:0] ADDR_R = {DS3231_ADDR, 1'b1}; // 8'hD1

    // ---------------- instancia del maestro I2C ----------------
    reg        cmd_start, cmd_stop, cmd_write, cmd_read, read_ack;
    reg [7:0]  wr_data;
    wire [7:0] rd_data;
    wire       busy, done, ack_error;

    i2c_master #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .I2C_FREQ_HZ(I2C_FREQ_HZ)
    ) u_i2c (
        .clk(clk), .rst_n(rst_n),
        .cmd_start(cmd_start), .cmd_stop(cmd_stop),
        .cmd_write(cmd_write), .cmd_read(cmd_read), .read_ack(read_ack),
        .wr_data(wr_data), .rd_data(rd_data),
        .busy(busy), .done(done), .ack_error(ack_error),
        .sda(sda), .scl(scl)
    );

    // ---------------- temporizador de sondeo periodico ----------------
    localparam integer POLL_CYCLES = (CLK_FREQ_HZ / 1000) * POLL_PERIOD_MS;
    reg [31:0] poll_cnt;
    reg        poll_tick;   // pulso de 1 ciclo cada POLL_PERIOD_MS; UNICO driver: este bloque

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            poll_cnt  <= 32'd0;
            poll_tick <= 1'b0;
        end else if (poll_cnt >= POLL_CYCLES-1) begin
            poll_cnt  <= 32'd0;
            poll_tick <= 1'b1;
        end else begin
            poll_cnt  <= poll_cnt + 32'd1;
            poll_tick <= 1'b0;
        end
    end

    // ---------------- FSM principal: secuencia de lectura de 7 registros ----------------
    localparam ST_WAIT        = 0,
               ST_START1      = 1,  ST_START1_W  = 2,
               ST_WR_ADDRW    = 3,  ST_WR_ADDRW_W= 4,
               ST_WR_PTR      = 5,  ST_WR_PTR_W  = 6,
               ST_START2      = 7,  ST_START2_W  = 8,
               ST_WR_ADDRR    = 9,  ST_WR_ADDRR_W= 10,
               ST_RD_SEC      = 11, ST_RD_SEC_W  = 12,
               ST_RD_MIN      = 13, ST_RD_MIN_W  = 14,
               ST_RD_HOUR     = 15, ST_RD_HOUR_W = 16,
               ST_RD_DAY      = 17, ST_RD_DAY_W  = 18,
               ST_RD_DATE     = 19, ST_RD_DATE_W = 20,
               ST_RD_MONTH    = 21, ST_RD_MONTH_W= 22,
               ST_RD_YEAR     = 23, ST_RD_YEAR_W = 24,
               ST_STOP        = 25, ST_STOP_W    = 26,
               ST_LATCH       = 27,
               // ---- secuencia de ESCRITURA de hora inicial (disparada por set_time_trigger) ----
               ST_SET_START_W = 28, ST_SET_ADDRW_W = 29, ST_SET_PTR_W  = 30,
               ST_SET_SEC_W   = 31, ST_SET_MIN_W   = 32, ST_SET_HOUR_W = 33,
               ST_SET_DAY_W   = 34, ST_SET_DATE_W  = 35, ST_SET_MONTH_W= 36,
               ST_SET_YEAR_W  = 37, ST_SET_STOP_W  = 38;

    reg [5:0] st;
    reg       pending_event;      // hay un evento RFID esperando ser "fotografiado"
    reg       pending_granted;
    reg       pending_poll;       // hay un sondeo periodico esperando ser atendido (unico driver: este bloque)
    reg       pending_settime;    // hay una solicitud de ajuste de hora esperando ser atendida

    // registros crudos leidos en la transaccion en curso
    reg [7:0] r_sec, r_min, r_hour, r_day, r_date, r_month, r_year;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st              <= ST_WAIT;
            cmd_start       <= 1'b0; cmd_stop <= 1'b0; cmd_write <= 1'b0; cmd_read <= 1'b0;
            read_ack        <= 1'b0; wr_data  <= 8'h00;
            rtc_data_valid  <= 1'b0; rtc_comm_error <= 1'b0;
            event_time_valid<= 1'b0;
            pending_event   <= 1'b0; pending_granted <= 1'b0;
            pending_poll    <= 1'b0;
            pending_settime <= 1'b0;
            sec_bcd<=0; min_bcd<=0; hour_bcd<=0; day_bcd<=0; date_bcd<=0; month_bcd<=0; year_bcd<=0;
        end else begin
            // por defecto, todos los comandos y pulsos vuelven a 0 cada ciclo
            cmd_start <= 1'b0; cmd_stop <= 1'b0; cmd_write <= 1'b0; cmd_read <= 1'b0;
            rtc_data_valid   <= 1'b0;
            event_time_valid <= 1'b0;

            // capturar la solicitud de un evento de acceso en cualquier momento
            if (access_event) begin
                pending_event   <= 1'b1;
                pending_granted <= access_granted;
            end
            // capturar el pulso periodico de sondeo (unico lugar donde se escribe pending_poll)
            if (poll_tick) pending_poll <= 1'b1;
            // capturar la solicitud de ajuste de hora (unico lugar donde se escribe pending_settime)
            if (set_time_trigger) pending_settime <= 1'b1;

            case (st)
                // ---- reposo: arrancar por ajuste de hora, sondeo periodico o evento ----
                ST_WAIT: begin
                    if (pending_settime) begin
                        pending_settime <= 1'b0;
                        cmd_start       <= 1'b1;
                        st              <= ST_SET_START_W;
                    end else if (pending_poll || access_event) begin
                        pending_poll <= 1'b0;
                        cmd_start    <= 1'b1;
                        st           <= ST_START1_W;
                    end
                end
                ST_START1_W: if (done) begin cmd_write<=1'b1; wr_data<=ADDR_W; st<=ST_WR_ADDRW_W; end

                ST_WR_ADDRW_W: if (done) begin
                    if (ack_error) begin rtc_comm_error<=1'b1; cmd_stop<=1'b1; st<=ST_STOP_W; end
                    else begin rtc_comm_error<=1'b0; cmd_write<=1'b1; wr_data<=8'h00; st<=ST_WR_PTR_W; end
                end

                ST_WR_PTR_W: if (done) begin
                    if (ack_error) begin rtc_comm_error<=1'b1; cmd_stop<=1'b1; st<=ST_STOP_W; end
                    else begin cmd_start<=1'b1; st<=ST_START2_W; end   // repeated START
                end

                ST_START2_W: if (done) begin cmd_write<=1'b1; wr_data<=ADDR_R; st<=ST_WR_ADDRR_W; end

                ST_WR_ADDRR_W: if (done) begin
                    if (ack_error) begin rtc_comm_error<=1'b1; cmd_stop<=1'b1; st<=ST_STOP_W; end
                    else begin cmd_read<=1'b1; read_ack<=1'b1; st<=ST_RD_SEC_W; end
                end

                ST_RD_SEC_W:   if (done) begin r_sec  <=rd_data; cmd_read<=1'b1; read_ack<=1'b1; st<=ST_RD_MIN_W;   end
                ST_RD_MIN_W:   if (done) begin r_min  <=rd_data; cmd_read<=1'b1; read_ack<=1'b1; st<=ST_RD_HOUR_W;  end
                ST_RD_HOUR_W:  if (done) begin r_hour <=rd_data; cmd_read<=1'b1; read_ack<=1'b1; st<=ST_RD_DAY_W;   end
                ST_RD_DAY_W:   if (done) begin r_day  <=rd_data; cmd_read<=1'b1; read_ack<=1'b1; st<=ST_RD_DATE_W;  end
                ST_RD_DATE_W:  if (done) begin r_date <=rd_data; cmd_read<=1'b1; read_ack<=1'b1; st<=ST_RD_MONTH_W; end
                ST_RD_MONTH_W: if (done) begin r_month<=rd_data; cmd_read<=1'b1; read_ack<=1'b0; st<=ST_RD_YEAR_W;  end // ultimo byte -> NACK
                ST_RD_YEAR_W:  if (done) begin r_year <=rd_data; cmd_stop<=1'b1; st<=ST_STOP_W; end

                ST_STOP_W: if (done) begin st <= ST_LATCH; end

                ST_LATCH: begin
                    if (!rtc_comm_error) begin
                        sec_bcd   <= r_sec;
                        min_bcd   <= r_min;
                        hour_bcd  <= {2'b00, r_hour[5:0]};   // se asume DS3231 configurado en modo 24h (bit6=0)
                        day_bcd   <= r_day;
                        date_bcd  <= r_date;
                        month_bcd <= {3'b000, r_month[4:0]}; // se descarta bit7 (siglo)
                        year_bcd  <= r_year;
                        rtc_data_valid <= 1'b1;

                        if (pending_event) begin
                            event_sec_bcd   <= r_sec;
                            event_min_bcd   <= r_min;
                            event_hour_bcd  <= {2'b00, r_hour[5:0]};
                            event_day_bcd   <= r_day;
                            event_date_bcd  <= r_date;
                            event_month_bcd <= {3'b000, r_month[4:0]};
                            event_year_bcd  <= r_year;
                            event_granted   <= pending_granted;
                            event_time_valid<= 1'b1;
                            pending_event   <= 1'b0;
                        end
                    end
                    st <= ST_WAIT;
                end

                // ---- secuencia de ESCRITURA: cargar la hora inicial en el DS3231 ----
                ST_SET_START_W: if (done) begin cmd_write<=1'b1; wr_data<=ADDR_W; st<=ST_SET_ADDRW_W; end
                ST_SET_ADDRW_W: if (done) begin
                    if (ack_error) begin rtc_comm_error<=1'b1; cmd_stop<=1'b1; st<=ST_SET_STOP_W; end
                    else begin cmd_write<=1'b1; wr_data<=8'h00; st<=ST_SET_PTR_W; end // puntero = registro 0x00
                end
                ST_SET_PTR_W: if (done) begin
                    if (ack_error) begin rtc_comm_error<=1'b1; cmd_stop<=1'b1; st<=ST_SET_STOP_W; end
                    else begin cmd_write<=1'b1; wr_data<=SET_SEC_BCD; st<=ST_SET_SEC_W; end
                end
                ST_SET_SEC_W:   if (done) begin cmd_write<=1'b1; wr_data<=SET_MIN_BCD;   st<=ST_SET_MIN_W;   end
                ST_SET_MIN_W:   if (done) begin cmd_write<=1'b1; wr_data<=SET_HOUR_BCD;  st<=ST_SET_HOUR_W;  end
                ST_SET_HOUR_W:  if (done) begin cmd_write<=1'b1; wr_data<=SET_DAY_BCD;   st<=ST_SET_DAY_W;   end
                ST_SET_DAY_W:   if (done) begin cmd_write<=1'b1; wr_data<=SET_DATE_BCD;  st<=ST_SET_DATE_W;  end
                ST_SET_DATE_W:  if (done) begin cmd_write<=1'b1; wr_data<=SET_MONTH_BCD; st<=ST_SET_MONTH_W; end
                ST_SET_MONTH_W: if (done) begin cmd_write<=1'b1; wr_data<=SET_YEAR_BCD;  st<=ST_SET_YEAR_W;  end
                ST_SET_YEAR_W:  if (done) begin cmd_stop<=1'b1; st<=ST_SET_STOP_W; end
                ST_SET_STOP_W:  if (done) begin st <= ST_WAIT; end   // no se toca sec_bcd/etc; la proxima
                                                                       // lectura periodica los actualizara sola

                default: st <= ST_WAIT;
            endcase
        end
    end

    // ---------------- formateo ASCII para el LCD ----------------
    function [7:0] bcd_hi_ascii(input [7:0] bcd); bcd_hi_ascii = {4'h3, bcd[7:4]}; endfunction
    function [7:0] bcd_lo_ascii(input [7:0] bcd); bcd_lo_ascii = {4'h3, bcd[3:0]}; endfunction

    // "HH:MM:SS DD/MM/YY"  (17 caracteres, indice 0 = primer caracter)
    always @(*) begin
        lcd_time_str = { bcd_hi_ascii(hour_bcd), bcd_lo_ascii(hour_bcd), 8'h3A,
                          bcd_hi_ascii(min_bcd),  bcd_lo_ascii(min_bcd),  8'h3A,
                          bcd_hi_ascii(sec_bcd),  bcd_lo_ascii(sec_bcd),  8'h20,
                          bcd_hi_ascii(date_bcd), bcd_lo_ascii(date_bcd), 8'h2F,
                          bcd_hi_ascii(month_bcd),bcd_lo_ascii(month_bcd),8'h2F,
                          bcd_hi_ascii(year_bcd), bcd_lo_ascii(year_bcd) };

        event_lcd_str = { bcd_hi_ascii(event_hour_bcd), bcd_lo_ascii(event_hour_bcd), 8'h3A,
                           bcd_hi_ascii(event_min_bcd),  bcd_lo_ascii(event_min_bcd),  8'h3A,
                           bcd_hi_ascii(event_sec_bcd),  bcd_lo_ascii(event_sec_bcd),  8'h20,
                           bcd_hi_ascii(event_date_bcd), bcd_lo_ascii(event_date_bcd), 8'h2F,
                           bcd_hi_ascii(event_month_bcd),bcd_lo_ascii(event_month_bcd),8'h2F,
                           bcd_hi_ascii(event_year_bcd), bcd_lo_ascii(event_year_bcd) };
    end

endmodule