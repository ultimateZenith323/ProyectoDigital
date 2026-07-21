// =============================================================================
// access_log.v
// Guarda cada evento de acceso o cierre (hora + fecha + estado) en la memoria.
//
// Tipos de evento (event_type):
//   2'b00 -> DENEGADO
//   2'b01 -> OTORGADO
//   2'b10 -> CERRADO 
//
// Formato de cada linea enviada (28 caracteres, terminada en \r\n):
//   "HH:MM:SS DD/MM/YY OTORGADO\r\n"
//   "HH:MM:SS DD/MM/YY DENEGADO\r\n"
//   "HH:MM:SS DD/MM/YY CERRADO \r\n"
// =============================================================================
module access_log #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE   = 9600,
    parameter DEPTH       = 64          // cantidad maxima de eventos guardados
)(
    input  wire clk,
    input  wire rst_n,

    // ---- captura de eventos ----
    input  wire        event_time_valid,
    input  wire [1:0]  event_type,        // 00=DENEGADO, 01=OTORGADO, 10=CERRADO
    input  wire [7:0]  event_hour_bcd,
    input  wire [7:0]  event_min_bcd,
    input  wire [7:0]  event_sec_bcd,
    input  wire [7:0]  event_date_bcd,
    input  wire [7:0]  event_month_bcd,
    input  wire [7:0]  event_year_bcd,

    // ---- pulso de descarga ----
    input  wire dump_trigger,

    output wire uart_txd,                          // hacia el pin RXD del HC-05
    output wire [$clog2(DEPTH+1)-1:0] log_count,    // cuantos eventos hay guardados
    output wire log_dumping                         // 1 mientras se esta volcando el buffer
);

    localparam integer ADDR_W = $clog2(DEPTH);
    localparam integer CNT_W  = $clog2(DEPTH+1);

    // Conversion BCD -> ASCII
    function [7:0] bcd_hi_ascii(input [7:0] bcd); bcd_hi_ascii = {4'h3, bcd[7:4]}; endfunction
    function [7:0] bcd_lo_ascii(input [7:0] bcd); bcd_lo_ascii = {4'h3, bcd[3:0]}; endfunction

    // Extrae caracter
    function [7:0] get_char28(input [8*28-1:0] str28, input integer pos);
        get_char28 = str28[(27-pos)*8 +: 8];
    endfunction

    // ---------------------------------------------------------------
    // Memoria circular
    // ---------------------------------------------------------------
    reg [55:0]        mem [0:DEPTH-1];
    reg [ADDR_W-1:0]  wr_ptr, rd_ptr;
    reg [CNT_W-1:0]   count;

    assign log_count = count;

    reg dump_read_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else begin
            if (event_time_valid) begin
                mem[wr_ptr] <= { event_hour_bcd, event_min_bcd, event_sec_bcd,
                                  event_date_bcd, event_month_bcd, event_year_bcd,
                                  {6'b0, event_type} };
                wr_ptr <= wr_ptr + 1'b1;
            end

            case ({event_time_valid, dump_read_en})
                2'b10: begin
                    if (count == DEPTH)
                        rd_ptr <= rd_ptr + 1'b1;
                    else
                        count <= count + 1'b1;
                end
                2'b01: begin
                    rd_ptr <= rd_ptr + 1'b1;
                    count  <= count - 1'b1;
                end
                2'b11: begin
                    rd_ptr <= rd_ptr + 1'b1;
                end
                default: ;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // UART TX
    // ---------------------------------------------------------------
    reg  [4:0] byte_idx;
    reg  [55:0] entry_reg;
    reg         tx_start_reg;
    wire        tx_busy;

    wire [7:0] ent_hour  = entry_reg[55:48];
    wire [7:0] ent_min   = entry_reg[47:40];
    wire [7:0] ent_sec   = entry_reg[39:32];
    wire [7:0] ent_date  = entry_reg[31:24];
    wire [7:0] ent_month = entry_reg[23:16];
    wire [7:0] ent_year  = entry_reg[15:8];
    wire [1:0] ent_type  = entry_reg[1:0];

    // Mapeo del estado a texto de exactamente 8 caracteres
    wire [8*8-1:0] status_str = (ent_type == 2'b01) ? "OTORGADO" :
                                (ent_type == 2'b10) ? "CERRADO " : "DENEGADO";

    wire [8*28-1:0] line_buf = {
        bcd_hi_ascii(ent_hour),  bcd_lo_ascii(ent_hour),  8'h3A,
        bcd_hi_ascii(ent_min),   bcd_lo_ascii(ent_min),   8'h3A,
        bcd_hi_ascii(ent_sec),   bcd_lo_ascii(ent_sec),   8'h20,
        bcd_hi_ascii(ent_date),  bcd_lo_ascii(ent_date),  8'h2F,
        bcd_hi_ascii(ent_month), bcd_lo_ascii(ent_month), 8'h2F,
        bcd_hi_ascii(ent_year),  bcd_lo_ascii(ent_year),  8'h20,
        status_str,
        8'h0D, 8'h0A   // \r\n
    };

    wire [7:0] tx_data_cur = get_char28(line_buf, byte_idx);

    uart_tx #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart (
        .clk(clk), .rst_n(rst_n),
        .tx_data(tx_data_cur),
        .tx_start(tx_start_reg),
        .tx(uart_txd),
        .tx_busy(tx_busy)
    );

    // ---------------------------------------------------------------
    // Maquina de estados del volcado
    // ---------------------------------------------------------------
    localparam D_IDLE      = 3'd0,
               D_READ      = 3'd1,
               D_LOAD      = 3'd2,
               D_WAITHIGH  = 3'd3,
               D_WAITLOW   = 3'd4,
               D_NEXT      = 3'd5;

    reg [2:0]       dstate;
    reg [CNT_W-1:0] dump_remaining;

    assign log_dumping = (dstate != D_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dstate         <= D_IDLE;
            byte_idx       <= 0;
            dump_remaining <= 0;
            entry_reg      <= 0;
            dump_read_en   <= 1'b0;
            tx_start_reg   <= 1'b0;
        end else begin
            dump_read_en <= 1'b0;
            tx_start_reg <= 1'b0;

            case (dstate)
                D_IDLE: begin
                    if (dump_trigger && count > 0) begin
                        dump_remaining <= count;
                        dstate         <= D_READ;
                    end
                end

                D_READ: begin
                    entry_reg <= mem[rd_ptr];
                    byte_idx  <= 0;
                    dstate    <= D_LOAD;
                end

                D_LOAD: begin
                    tx_start_reg <= 1'b1;
                    dstate       <= D_WAITHIGH;
                end

                D_WAITHIGH: begin
                    if (tx_busy) dstate <= D_WAITLOW;
                end

                D_WAITLOW: begin
                    if (!tx_busy) begin
                        if (byte_idx < 27) begin
                            byte_idx <= byte_idx + 1'b1;
                            dstate   <= D_LOAD;
                        end else begin
                            dstate <= D_NEXT;
                        end
                    end
                end

                D_NEXT: begin
                    dump_read_en <= 1'b1;
                    if (dump_remaining > 1) begin
                        dump_remaining <= dump_remaining - 1'b1;
                        dstate         <= D_READ;
                    end else begin
                        dump_remaining <= 0;
                        dstate         <= D_IDLE;
                    end
                end

                default: dstate <= D_IDLE;
            endcase
        end
    end
endmodule