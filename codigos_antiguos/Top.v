module Top (
    input OCLK, //cambiar CLK
    input reset,

    input MISO, // Informacion desde RFID
    input IRQ, // Pin IRQ de RFID
    output [1:0] error1a,
    output MOSI, // Informacion para RFID
    output NSS, // Control de la RFID
    output SCK, // Reloj para RFID
    output LEDIRQ, // Indica que el estado de IRQ
    output RST, // Pin de reinicio de RFID, activo en bajo
    output modo,

    output [6:0] segmento,
    output [3:0] display,
    output [2:0] estado,
    output LED,
    output LEDa,

    output [3:0] filas,
    input [3:0] columnas,

    output [1:0] event1
);

    wire [1:0] error1;
    assign LEDIRQ = ~IRQ;
    assign error1a = ~error1;
    
    wire [2:0] estadoa;
    assign estado = ~estadoa;
    wire modoa;
    assign modo = modoa;
    
    assign LED = ~LEDa;

    wire CLK;

    reg [5:0] por_count = 6'b0;
    wire start = (por_count >= 6'd16 && por_count < 6'd32);

    always @(posedge OCLK) begin
        if (por_count != 6'd63)
            por_count <= por_count + 6'd1;
    end

    DCLK DivFreq (
        .OCLK(OCLK),
        .start(start),
        .FCLK(CLK)
    );

    wire lec;
    wire SPIRet;
    wire [7:0] data;
    wire ejcSPI;
    wire [7:0] Bytes;
    wire [7:0] info;
    wire inactivo;

    wire confirmar;
    wire cancelar;
    wire [15:0] contrasena;
    wire teclado;

    wire [31:0] UID;


    FSMP fsmp (
        .CLK   (CLK),
        .start (start),
        .reset (reset),
        .lec   (lec),
        .info  (info),
        .SPIRet(SPIRet),
        .inactivo(inactivo),
        .confirmar (confirmar),
        .cancelar (cancelar),
        .contrasena (contrasena),
        .teclado (teclado),
        .data  (data),
        .access_event (event1),
        .TextoSalida2 (),
        .ejcSPI(ejcSPI),
        .bytes  (Bytes),
        .error (error1),
        .UID (UID),
        .estadoActual (estadoa),
        .modoS (modoa),
        .LED   (LEDa)
    );
    
    FSMS fsms1 (
        .CLK        (CLK),
        .start      (start),
        .reset      (reset),
        .Ejecutar   (ejcSPI),
        .Bytes      (Bytes),
        .DataMaestro(data),
        .MISO       (MISO),
        .Return     (SPIRet),
        .NSS        (NSS),
        .Lectura    (lec),
        .MOSI       (MOSI),
        .InfoSPI    (info),
        .inactivo   (inactivo)
    );

    assign SCK = ~CLK;
    assign RST = ~(reset | start);

    wire [15:0] datas;
    assign datas = {info, data};

    Seg7 DS71 (
        .OCLK    (OCLK),
        .start   (start),
        .entrada (datas),
        .segmento(segmento),
        .display (display)
    );

    wire confirmarBtn;
    wire cancelarBtn;

    assign confirmarBtn = (estado == 3'd4);
    assign cancelarBtn = confirmarBtn;

    Teclado teclado1 (
        .CLK         (CLK),
        .reset       (reset),
        .activar     (teclado),
        .filas       (filas),
        .columnas    (columnas),
        .confirmarBtn(confirmarBtn),
        .cancelarBtn (cancelarBtn),
        .enter       (confirmar),
        .descartar   (cancelar),
        .contrasena  (contrasena)
    );
endmodule
