module controlador_buzzer #(
    parameter CLK_FREQ_HZ = 50_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire trigger_abrir,
    input  wire trigger_cerrar,
    output wire buzzer_out
);

    localparam integer BEEP_LARGO_CYCLES = (CLK_FREQ_HZ/1000) * 500; // 500 ms (piii)
    localparam integer BEEP_CORTO_CYCLES = (CLK_FREQ_HZ/1000) * 100; // 100 ms (pi)
    localparam integer SILENCIO_CYCLES   = (CLK_FREQ_HZ/1000) * 100; // 100 ms de espacio

    reg [31:0] buzz_timer;
    reg [2:0]  buzz_state;
    reg        buzzer_reg;

    reg reg_abrir, reg_cerrar;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_abrir  <= 1'b0;
            reg_cerrar <= 1'b0;
        end else begin
            reg_abrir  <= trigger_abrir;
            reg_cerrar <= trigger_cerrar;
        end
    end

    wire start_open_buzz  = (trigger_abrir == 1'b1 && reg_abrir == 1'b0);
    wire start_close_buzz = (trigger_cerrar == 1'b1 && reg_cerrar == 1'b0);

    localparam STATE_IDLE     = 3'd0,
               STATE_LONGBEEP = 3'd1,
               STATE_BEEP1    = 3'd2,
               STATE_SIL1     = 3'd3,
               STATE_BEEP2    = 3'd4,
               STATE_SIL2     = 3'd5,
               STATE_BEEP3    = 3'd6;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            buzz_state <= STATE_IDLE;
            buzz_timer <= 32'd0;
            buzzer_reg <= 1'b0;
        end else begin
            case (buzz_state)
                STATE_IDLE: begin
                    buzzer_reg <= 1'b0;
                    if (start_open_buzz) begin
                        buzz_timer <= BEEP_LARGO_CYCLES;
                        buzz_state <= STATE_LONGBEEP;
                    end else if (start_close_buzz) begin
                        buzz_timer <= BEEP_CORTO_CYCLES;
                        buzz_state <= STATE_BEEP1;
                    end
                end

                STATE_LONGBEEP: begin
                    buzzer_reg <= 1'b1;
                    if (buzz_timer != 0) buzz_timer <= buzz_timer - 32'd1;
                    else                 buzz_state <= STATE_IDLE;
                end

                STATE_BEEP1: begin
                    buzzer_reg <= 1'b1;
                    if (buzz_timer != 0) buzz_timer <= buzz_timer - 32'd1;
                    else begin
                        buzz_timer <= SILENCIO_CYCLES;
                        buzz_state <= STATE_SIL1;
                    end
                end

                STATE_SIL1: begin
                    buzzer_reg <= 1'b0;
                    if (buzz_timer != 0) buzz_timer <= buzz_timer - 32'd1;
                    else begin
                        buzz_timer <= BEEP_CORTO_CYCLES;
                        buzz_state <= STATE_BEEP2;
                    end
                end

                STATE_BEEP2: begin
                    buzzer_reg <= 1'b1;
                    if (buzz_timer != 0) buzz_timer <= buzz_timer - 32'd1;
                    else begin
                        buzz_timer <= SILENCIO_CYCLES;
                        buzz_state <= STATE_SIL2;
                    end
                end

                STATE_SIL2: begin
                    buzzer_reg <= 1'b0;
                    if (buzz_timer != 0) buzz_timer <= buzz_timer - 32'd1;
                    else begin
                        buzz_timer <= BEEP_CORTO_CYCLES;
                        buzz_state <= STATE_BEEP3;
                    end
                end

                STATE_BEEP3: begin
                    buzzer_reg <= 1'b1;
                    if (buzz_timer != 0) buzz_timer <= buzz_timer - 32'd1;
                    else                 buzz_state <= STATE_IDLE;
                end

                default: buzz_state <= STATE_IDLE;
            endcase
        end
    end

    assign buzzer_out = buzzer_reg;

endmodule