# Informe Final: Sistema de Control de Acceso con RFID sobre FPGA

## Índice

1. [Introducción](https://www.google.com/search?q=%231-introducci%C3%B3n)
2. [Impacto de la solución](https://www.google.com/search?q=%232-impacto-de-la-soluci%C3%B3n)
3. [Cumplimiento de los objetivos](https://www.google.com/search?q=%233-cumplimiento-de-los-objetivos)
4. [Arquitectura implementada](https://www.google.com/search?q=%234-arquitectura-implementada)
5. [Funcionamiento y pruebas](https://www.google.com/search?q=%235-funcionamiento-y-pruebas)
6. [Presentación física del proyecto](https://www.google.com/search?q=%236-presentaci%C3%B3n-f%C3%ADsica-del-proyecto)
7. [Reporte de uso de IA](https://www.google.com/search?q=%238-reporte-de-uso-de-ia)
8. [Conclusiones](https://www.google.com/search?q=%239-conclusiones)
9.  [Bibliografía](https://www.google.com/search?q=%2310-bibliograf%C3%ADa)

---

## 1. Introducción

El presente informe detalla el diseño e implementación de un sistema de control de acceso mediante tecnología RFID, desarrollado sobre la tarjeta de desarrollo FPGA Cyclone IV. El núcleo del sistema integra un lector RFID RC522, un módulo de reloj en tiempo real (RTC) DS3231, una pantalla LCD 16x2 y una cerradura eléctrica de 12V. La organización del hardware se realiza mediante una Máquina de Estados Finita (FSM) principal y submódulos de comunicación (SPI, I2C, UART y bus paralelo) descritos en Verilog. Este diseño parte de una base funcional previa de control de acceso por teclado matricial.

---

## 2. Impacto de la solución

La implementación de este sistema en hardware dedicado (FPGA) garantiza tiempos de respuesta deterministas y un alto nivel de seguridad, eliminando las vulnerabilidades de los sistemas basados en software convencional (Sistemas Operativos). Además, la inclusión de un registro histórico en memoria no volátil exportable vía UART añade un control de auditoría riguroso, fundamental para entornos institucionales o corporativos que requieren trazabilidad de accesos.

---

## 3. Cumplimiento de los objetivos

* **Lectura y Autenticación:** Se implementó la comunicación SPI para extraer el UID de tarjetas y contrastarlo contra una memoria ROM interna en un solo ciclo de reloj.
* **Registro de Eventos:** Se logró integrar la captura de la hora/fecha exacta (BCD a ASCII) al momento de cada acceso, almacenándola en un buffer circular y transmitiéndola por puerto serial.
* **Control Físico:** Se diseñó el circuito de potencia aislado galvánicamente mediante optoacoplador (PC817) y transistor (2N2222) para accionar la cerradura de 12V con señales lógicas de 3.3V.

---

## 4. Arquitectura implementada

El sistema se estructura en una FSM principal que coordina módulos de bajo nivel. A continuación, se detallan los controladores lógicos finales incorporados:

### 4.1. Comunicación UART (`uart_tx.v`)

Transmisor serial estándar configurado por defecto a 9600 baudios (frecuencia base de 50 MHz). Opera con una máquina de estados de 4 pasos (IDLE, START, DATA, STOP) para enviar tramas de 8 bits sin paridad (LSB primero). Provee una bandera `tx_busy` para evitar sobreescritura de datos durante la transmisión.

Código del módulo: [uart_tx.v](codigos/uart_tx.v)

### 4.2. Registro de Accesos (`access_log.v`)

Módulo encargado de la bitácora del sistema.

* **Memoria:** Implementa un buffer circular de 64 posiciones.
* **Lógica:** Ante un pulso `event_time_valid`, concatena la fecha, hora y el tipo de evento (DENEGADO `00`, OTORGADO `01`, CERRADO `10`).
* **Volcado de datos:** Al activar `dump_trigger`, una FSM interna extrae los registros, convierte los valores BCD a ASCII, formatea cadenas de 28 caracteres (ej. *"HH:MM:SS DD/MM/YY OTORGADO\r\n"*) y las envía secuencialmente instanciando el módulo `uart_tx`.


Código del módulo: [acces_log](codigos/acces_log.v)

### 4.3. Controlador RTC e I2C (`ds3231_controller.v` y `i2c_master.v`)

* **Maestro I2C:** Módulo genérico operando a 100 kHz. Maneja las señales SCL (push-pull) y SDA (open-drain bidireccional). Soporta "repeated START" encadenando comandos START y WRITE sin STOP intermedio, vital para direccionar los registros del DS3231.
* **Controlador DS3231:** Orquesta al maestro I2C mediante una FSM. Realiza un sondeo ("polling") cada 200 ms para actualizar los registros de fecha y hora. Tiene una doble función crítica:
1. Mantiene una salida continua en formato ASCII para el refresco del LCD.
2. Captura una foto de la hora exacta ante un pulso `access_event` proveniente del RFID, levantando la bandera `event_time_valid` para que el `access_log` la guarde. También permite ajustar la hora del RTC en hardware mediante un trigger.


Código del módulo ds3231_controller: [DS3231_controlador](codigos/controlador_RTC.V)

Código del módulo i2c_master: [12c_master](codigos/i2c_master.v)

### 4.4. FSM Principal y Autenticación

El sistema entra en estado LECTURA al detectar una tarjeta mediante el controlador SPI. Si el UID coincide en la ROM (estado VALIDACIÓN), pasa a CONCEDIDO, activando el LED verde y un contador que energiza la cerradura por 3 segundos. Si falla, pasa a DENEGADO encendiendo el LED rojo.


### 4.5. Módulo de Integración Principal (`security_top`)

Este es el módulo de mayor jerarquía (Top-Level) del diseño. Su propósito es instanciar e interconectar todos los submódulos funcionales del sistema, mapeando las señales lógicas internas con los pines físicos de la FPGA (entradas de botones, teclado, señales I2C, pines de la LCD, transmisión UART y salidas al relé/buzzer).

* **Multiplexación de Eventos:** Emplea lógica combinacional para determinar qué evento (Acceso Otorgado, Acceso Denegado o Puerta Cerrada) y con qué marca de tiempo se envía al módulo de bitácora (`access_log`).
* **Transmisión Automática:** Integra un contador basado en el reloj del sistema que genera un pulso de disparo (trigger) cada 5 segundos para forzar el volcado periódico de la memoria FIFO a través de Bluetooth.
* **Sincronización de Entradas:** Aplica registros de desplazamiento (shift registers) a los botones físicos (Reset, Ajuste de Hora y Cierre Manual) para sincronizarlos con el dominio del reloj principal y evitar problemas de metaestabilidad.



### 4.6. Controlador de Interfaz de Usuario (`keypad_lcd_controller`)

Este bloque actúa como el cerebro de la interacción con el usuario. Coordina la información que ingresa desde el teclado y la que se visualiza en la pantalla, gestionando de forma aislada la validación de la contraseña del sistema.

* **Máquina de Estados de Pantalla:** Controla la inicialización de la LCD y el posicionamiento del cursor, dibujando en la línea superior la hora en vivo (proveniente del RTC) y en la línea inferior los intentos de contraseña.
* **Gestión de Privacidad:** Enmascara los dígitos ingresados reemplazándolos con caracteres `*` para proteger el PIN.
* **Validación de Credenciales:** Compara el arreglo de teclas ingresadas con la clave maestra configurada en hardware y despacha señales de un solo ciclo de reloj (`access_event`, `access_granted`) para disparar las capturas de tiempo y la apertura física.


### 4.7. Escáner de Teclado Matricial (`keypad_scanner`)

Este submódulo de bajo nivel se encarga del barrido continuo de un teclado matricial 4x4 físico, traduciendo coordenadas eléctricas en datos lógicos interpretables por el sistema.

* **Doble Sincronización:** Emplea dos flip-flops en serie para las señales de las columnas, asegurando una lectura estable y libre de metaestabilidad.
* **Filtro Antirrebote (Debounce):** Implementa un temporizador interno que exige que una tecla se mantenga mecánicamente estable durante al menos 20 ms antes de validar la pulsación.
* **Decodificación Hexadecimal:** Convierte la intersección de la fila activa (en bajo) y la columna detectada en un código de 4 bits (0-9, A-F) que representa la tecla exacta pulsada.



### 4.8. Controlador de Cerradura (`lock_controller`)

Este módulo es el responsable de la actuación de potencia del sistema, traduciendo las directrices lógicas en el control de un relé electromecánico de 12V.

* **Lógica de Potencia:** Activa o desactiva la señal del relé respetando la polaridad requerida por el hardware físico (nivel alto para abrir, nivel bajo para cerrar).
* **Pausa de Seguridad (Hold):** Incorpora un estado de transición (`S_CLOSING`) que aplica un retardo forzado de 1000 ms tras el cierre, previniendo aperturas erráticas o rebotes eléctricos en la bobina de la cerradura.
* **Filtro Independiente:** Gestiona un contador de antirrebote dedicado de 50 ms para el botón físico de cierre interno, independiente del teclado principal.



### 4.9. Controlador de Alertas Sonoras (`controlador_buzzer`)

Este componente proporciona retroalimentación auditiva crítica, mejorando la experiencia del usuario al confirmar el resultado de las interacciones con el sistema de acceso.

* **Base de Tiempos Precisa:** Deriva sus temporizaciones directamente de la frecuencia del reloj principal de 50 MHz para garantizar duraciones exactas de los tonos.
* **Tono de Aceptación:** Responde a la señal de apertura con un pitido continuo y largo de 500 ms, indicando acceso exitoso.
* **Secuencia de Rechazo/Cierre:** Responde a intentos fallidos o solicitudes de bloqueo con un patrón repetitivo de tres pitidos cortos de 100 ms, separados por silencios de igual duración.


---

## 5. Funcionamiento y pruebas

Las pruebas se dividieron en subsistemas antes de la integración total:

1. **Pruebas I2C/UART:** Se validó mediante terminal serial la recepción correcta de tramas con formatos ASCII estructurados. El polling del RTC demostró estabilidad cada 200 ms sin colisionar con eventos de escritura.
2. **Pruebas SPI (Lector RFID):** Se utilizó un osciloscopio para verificar los tiempos de establecimiento y retención (setup/hold time) del Modo 0 de SPI a frecuencias divididas[cite: 1]. Se comprobó la correcta inicialización de los registros del RC522 (CommandReg, ModeReg) para energizar la antena[cite: 1].
3. **Prueba de Potencia:** Se validó la apertura de la cerradura eléctrica accionando el relay de 5V comandado por el optoacoplador desde un pin GPIO de la FPGA[cite: 1].

---

## 6. Presentación física del proyecto

El prototipo final se encuentra ensamblado en un locker de MDF diseñado a medida. El panel frontal dispone el lector RFID, la pantalla LCD, los LEDs indicadores (rojo y verde), la puerta simulada con su cerradura de golpe, el circuito de potencia de 12V y la tarjeta FPGA. En la parte posterior hay un espacio para guardar el contenido del locker.

---

## 8. Reporte de uso de IA

Para la realización de este proyecto, se emplearon herramientas de Inteligencia Artificial (ej. ChatGPT/Claude) de forma acotada y estrictamente como asistencia técnica en las siguientes tareas:

* **Generación de rutinas repetitivas:** Creación de las funciones de conversión de BCD a ASCII en Verilog.
* **Estructuración documental:** Corrección de estilo y formato Markdown para este informe final en el repositorio de GitHub.
* **Aclaración de protocolos:** Consultas teóricas rápidas sobre la máquina de estados interna del chip NXP RC522 para la temporización del bus SPI.

* Se usa IA además para hacer verificación y comentariado de los códigos diseñados en cada módulo.

---

## 9. Conclusiones

* La separación en módulos síncronos independientes (I2C, UART, SPI) controlados por una FSM supervisora garantizó que no hubiese cuellos de botella al leer la tarjeta, consultar el reloj y actualizar la pantalla simultáneamente.
* El manejo correcto de líneas inout en Verilog (como en el pin SDA del I2C) y el entendimiento de los tiempos de setup/hold a nivel de osciloscopio fueron determinantes para estabilizar la comunicación con los periféricos.
* Se cumplió con la meta de migrar de un sistema básico de teclado a un sistema IoT/RFID, agregando trazabilidad mediante memoria circular y transmisión asíncrona (UART), demostrando un dominio sólido de los sistemas digitales en hardware.

---

## 10. Bibliografía

* [1] T. Floyd, *Fundamentos de sistemas digitales*, 9th ed. PEARSON EDUCATION, 2006[cite: 1].
* [2] P. Ashenden, *DIGITAL DESIGN An Embedded Systems Approach Using VERILOG*. MORGAN KAUFMANN PUBLISHERS, 2008[cite: 1].