# Arquitectura

## Relojes

| Reloj | Frecuencia | Uso |
|---|---|---|
| `memclk`, `memclk_p` | 57,375 MHz (0 y 90 grados) | PSRAM |
| `clk` | 28,6875 MHz (`memclk` / 2) | toda la consola |
| `clk_pix` | 27 MHz (135 / 5, en `hdmi_phy`) | vídeo y HDMI |

No hay relojes derivados por lógica: un reloj de color son 8 `clk` y un ciclo de
CPU, 24. La CPU avanza en la fase 0; la petición a la PSRAM sale en la fase 3 y
el dato se usa en la siguiente fase 0.

## Módulos (`src/sd/`)

| Fichero | Función |
|---|---|
| `atari_top.v` | pines, PLL, PSRAM, HDMI, audio |
| `atari_sys.v` | CPU, decodificación, menú, SPI/DMA, paddles, framebuffer |
| `tia.v` | vídeo, colisiones y audio |
| `riot.v` | RAM, puertos y temporizador |
| `mapper.v`, `dpc.v` | bancos del cartucho, chip DPC |
| `atari_video.v` | framebuffer de 160x240 y pantalla de texto del menú a 720x480p |
| `psram_chan.vhd` | controlador de la PSRAM |
| `../hdmi/` | HDMI de 720x480p con audio de 48 kHz ([guía](09-HDMI-COMPLETO.md)) |

## Detalles

- **TIA**: cada reloj de color se divide en cuatro pasos (escrituras retardadas,
  HMOVE y playfield, sprites, colisión y color). Incluye RESMP, modo SCORE,
  VDELBL y el efecto *starfield*.
- **RIOT**: el primer decremento llega un ciclo después de escribir el
  temporizador; tras expirar cuenta en cada ciclo hasta que se lee INTIM.
- **Bancos**: cambian al final del ciclo, de modo que `LDA $FFF9` lee el banco
  viejo, como en el cartucho real.
- **Cartucho**: ROM en la PSRAM desde 0; RAM del cartucho en `$80000`; RAM del
  menú en `$200000`.
- **Vídeo**: el framebuffer desacopla el 2600 del HDMI. Con cuadros de 286
  líneas o más se usan la paleta y el encuadre PAL.
- **Audio HDMI**: filtro paso bajo (18 kHz), eliminación de la continua (7 Hz)
  y una muestra de 16 bits por petición de `hdmi_tx`. La salida delta-sigma sigue igual.
- **Multiciclo**: la CPU solo avanza cada 24 `clk`; `atari_sd.sdc` da 2 ciclos a los
  caminos CPU/DPC -> CPU. Por eso el tic musical del DPC se aplica en la fase 1.
- **BSRAM** (26/26): framebuffer 20 (SDPB); menú y tabla de opcodes 6 (pROM).
