// =============================================================================
// uart_tx.v
// Transmisor UART simple (8 bits de datos, sin paridad, 1 bit de stop).
// El HC-05 por defecto viene a 9600 baudios (se puede reconfigurar con
// comandos AT, pero para este proyecto dejamos el valor de fabrica).
// =============================================================================
module uart_tx #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD_RATE   = 9600
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] tx_data,   // byte a enviar
    input  wire       tx_start,  // pulso de 1 ciclo: inicia el envio de tx_data

    output reg        tx,        // linea serial -> pin RXD del HC-05
    output reg        tx_busy    // 1 mientras se esta transmitiendo (no mandar tx_start si esta en 1)
);

    localparam integer BIT_PERIOD = CLK_FREQ_HZ / BAUD_RATE;

    localparam S_IDLE  = 2'd0,
               S_START = 2'd1,
               S_DATA  = 2'd2,
               S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] baud_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            tx        <= 1'b1;   // linea en reposo = alto
            tx_busy   <= 1'b0;
            baud_cnt  <= 0;
            bit_idx   <= 0;
            shift_reg <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        baud_cnt  <= 0;
                        state     <= S_START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                S_START: begin
                    tx <= 1'b0; // bit de start
                    if (baud_cnt < BIT_PERIOD-1)
                        baud_cnt <= baud_cnt + 1'b1;
                    else begin
                        baud_cnt <= 0;
                        bit_idx  <= 0;
                        state    <= S_DATA;
                    end
                end

                S_DATA: begin
                    tx <= shift_reg[0]; // LSB primero
                    if (baud_cnt < BIT_PERIOD-1)
                        baud_cnt <= baud_cnt + 1'b1;
                    else begin
                        baud_cnt  <= 0;
                        shift_reg <= shift_reg >> 1;
                        if (bit_idx < 7)
                            bit_idx <= bit_idx + 1'b1;
                        else
                            state <= S_STOP;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1; // bit de stop
                    if (baud_cnt < BIT_PERIOD-1)
                        baud_cnt <= baud_cnt + 1'b1;
                    else begin
                        baud_cnt <= 0;
                        tx_busy  <= 1'b0;
                        state    <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule