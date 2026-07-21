// =============================================================================
// i2c_master.v
// Maestro I2C generico, controlado por comandos, para Altera Cyclone IV (Quartus)
//
// Interfaz de comandos: el modulo de mas alto nivel (ds3231_controller) pide
// UNA operacion a la vez (START, WRITE, READ o STOP) y espera el pulso 'done'
// antes de pedir la siguiente. Encadenar START -> WRITE -> START (sin STOP en
// medio) genera automaticamente un "repeated START", tal como lo requiere el
// DS3231 para pasar de escribir el puntero de registro a leerlo.
//
// SCL se maneja como salida push-pull (el DS3231 no hace clock-stretching en
// modo lectura normal, por lo que esto es valido). SDA es verdaderamente
// bidireccional (open-drain simulado con alta impedancia + resistencia de
// pull-up externa en el hardware real, o 'pullup' en el testbench).
// =============================================================================
module i2c_master #(
    parameter CLK_FREQ_HZ = 50_000_000,   // reloj del sistema (Cyclone IV)
    parameter I2C_FREQ_HZ = 100_000       // velocidad I2C deseada (100 kHz standard-mode)
)(
    input  wire       clk,
    input  wire       rst_n,

    // ---- interfaz de comandos (pulsos de 1 ciclo, uno por vez) ----
    input  wire        cmd_start,   // generar START o repeated START
    input  wire        cmd_stop,    // generar STOP
    input  wire        cmd_write,   // escribir wr_data, capturar ACK del esclavo
    input  wire        cmd_read,    // leer un byte
    input  wire        read_ack,    // valido junto con cmd_read: 1=enviar ACK (mas bytes), 0=enviar NACK (ultimo byte)
    input  wire [7:0]  wr_data,

    output reg  [7:0]  rd_data,
    output reg         busy,        // 1 mientras se ejecuta el comando actual
    output reg         done,        // pulso de 1 ciclo al terminar el comando
    output reg         ack_error,   // 1 = el esclavo respondio NACK en la ultima escritura

    // ---- bus fisico ----
    inout  wire        sda,
    output reg         scl
);

    localparam integer DIV = (CLK_FREQ_HZ / (I2C_FREQ_HZ * 2) < 2) ? 2 : (CLK_FREQ_HZ / (I2C_FREQ_HZ * 2));

    // ---------------- generador de "tick" (medio periodo de SCL) ----------------
    reg [31:0] div_cnt;
    reg        tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 32'd0;
            tick    <= 1'b0;
        end else if (div_cnt == DIV-1) begin
            div_cnt <= 32'd0;
            tick    <= 1'b1;
        end else begin
            div_cnt <= div_cnt + 32'd1;
            tick    <= 1'b0;
        end
    end

    // ---------------- control de SDA (open-drain) ----------------
    reg sda_oe;   // 1 = manejamos sda_out, 0 = liberamos la linea (alta impedancia)
    reg sda_out;
    assign sda = sda_oe ? sda_out : 1'bz;

    // ---------------- estados ----------------
    localparam S_IDLE      = 0,
               S_START1    = 1,
               S_START2    = 2,
               S_START3    = 3,
               S_WBIT_LO   = 4,
               S_WBIT_HI   = 5,
               S_WACK_LO   = 6,
               S_WACK_HI   = 7,
               S_WEND      = 8,
               S_RBIT_LO   = 9,
               S_RBIT_HI   = 10,
               S_MACK_LO   = 11,
               S_MACK_HI   = 12,
               S_MACK_END  = 13,
               S_STOP1     = 14,
               S_STOP2     = 15,
               S_STOP3     = 16,
               S_CMD_DONE  = 17;

    reg [4:0] state;
    reg [3:0] bitidx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            scl       <= 1'b1;
            sda_oe    <= 1'b1;
            sda_out   <= 1'b1;
            busy      <= 1'b0;
            done      <= 1'b0;
            ack_error <= 1'b0;
            rd_data   <= 8'h00;
            bitidx    <= 4'd0;
        end else begin
            done <= 1'b0; // 'done' es un pulso, por defecto se apaga cada ciclo

            case (state)
                // -------- reposo: esperar un comando (no depende del tick) --------
                S_IDLE: begin
                    busy <= 1'b0;
                    if (cmd_start) begin
                        busy  <= 1'b1;
                        state <= S_START1;
                    end else if (cmd_stop) begin
                        busy  <= 1'b1;
                        state <= S_STOP1;
                    end else if (cmd_write) begin
                        busy    <= 1'b1;
                        bitidx  <= 4'd7;
                        state   <= S_WBIT_LO;
                    end else if (cmd_read) begin
                        busy    <= 1'b1;
                        bitidx  <= 4'd7;
                        state   <= S_RBIT_LO;
                    end
                end

                // -------- condicion START / repeated START --------
                S_START1: if (tick) begin sda_oe<=1'b1; sda_out<=1'b1; scl<=1'b1; state<=S_START2; end
                S_START2: if (tick) begin sda_out<=1'b0; scl<=1'b1; state<=S_START3; end            // SDA cae con SCL=1 -> START
                S_START3: if (tick) begin scl<=1'b0; state<=S_CMD_DONE; end

                // -------- escritura de un byte (MSB primero) + ACK del esclavo --------
                S_WBIT_LO: if (tick) begin
                    sda_oe  <= 1'b1;
                    sda_out <= wr_data[bitidx];
                    scl     <= 1'b0;
                    state   <= S_WBIT_HI;
                end
                S_WBIT_HI: if (tick) begin
                    scl <= 1'b1;
                    if (bitidx == 4'd0) state <= S_WACK_LO;
                    else begin bitidx <= bitidx - 4'd1; state <= S_WBIT_LO; end
                end
                S_WACK_LO: if (tick) begin sda_oe<=1'b0; scl<=1'b0; state<=S_WACK_HI; end // liberar SDA para que el esclavo haga ACK
                S_WACK_HI: if (tick) begin
                    scl       <= 1'b1;
                    ack_error <= sda;   // 0 = ACK del esclavo, 1 = NACK (nadie respondio o rechazo)
                    state     <= S_WEND;
                end
                S_WEND: if (tick) begin
                    scl     <= 1'b0;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b1;
                    state   <= S_CMD_DONE;
                end

                // -------- lectura de un byte (MSB primero) + ACK/NACK del maestro --------
                S_RBIT_LO: if (tick) begin sda_oe<=1'b0; scl<=1'b0; state<=S_RBIT_HI; end // liberar SDA, la maneja el esclavo
                S_RBIT_HI: if (tick) begin
                    scl            <= 1'b1;
                    rd_data[bitidx] <= sda;
                    if (bitidx == 4'd0) state <= S_MACK_LO;
                    else begin bitidx <= bitidx - 4'd1; state <= S_RBIT_LO; end
                end
                S_MACK_LO: if (tick) begin
                    sda_oe  <= 1'b1;
                    sda_out <= read_ack ? 1'b0 : 1'b1;  // ACK=0 (pido mas bytes), NACK=1 (ultimo byte)
                    scl     <= 1'b0;
                    state   <= S_MACK_HI;
                end
                S_MACK_HI: if (tick) begin scl<=1'b1; state<=S_MACK_END; end
                S_MACK_END: if (tick) begin
                    scl     <= 1'b0;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b1;
                    state   <= S_CMD_DONE;
                end

                // -------- condicion STOP --------
                S_STOP1: if (tick) begin sda_oe<=1'b1; sda_out<=1'b0; scl<=1'b0; state<=S_STOP2; end
                S_STOP2: if (tick) begin scl<=1'b1; sda_out<=1'b0; state<=S_STOP3; end
                S_STOP3: if (tick) begin sda_out<=1'b1; scl<=1'b1; state<=S_CMD_DONE; end // SDA sube con SCL=1 -> STOP

                // -------- comando terminado --------
                S_CMD_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule