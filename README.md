# Atari 2600 en Tang Nano 9K con cartucho microSD

Atari 2600 para la Sipeed Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5): salida HDMI
de 720x480, audio delta-sigma y juegos leídos de una microSD con un menú.
Probado en placa.

## Uso

1. Grabar [`impl/pnr/Atari2600_SD.fs`](impl/pnr/Atari2600_SD.fs) con Gowin Programmer.
2. Copiar los juegos (`.a26` o `.bin`) a una microSD en FAT32, en cualquier carpeta.
3. Encender: aparece el menú.

| Control | En el menú | En el juego |
|---|---|---|
| Arriba / abajo | elegir | joystick |
| Izquierda / derecha | cambiar de página | joystick |
| Fire | abrir | botón |
| Select (85) | abrir con *paddles* | Game Select |
| Reset (86) | volver a la carpeta anterior | Game Reset |
| S1 (4) | reset | reset |
| S2 (3) | menú | volver al menú |

Con *paddles* el joystick mueve el mando y Fire es su botón. El menú, los
formatos y los límites están en [`docs/SD.md`](docs/SD.md).

## Pines

| Señal | Pin | Señal | Pin |
|---|---|---|---|
| Reloj 27 MHz | 52 | SD SCK | 36 |
| Joystick arriba | 30 | SD CMD (MOSI) | 37 |
| Joystick abajo | 33 | SD CS | 38 |
| Joystick izquierda | 34 | SD DAT0 (MISO) | 39 |
| Joystick derecha | 40 | HDMI | 68-75 |
| Fire | 29 | LEDs | 10, 11, 13-16 |
| Audio izq. / der. | 77 / 76 | S1 / S2 | 4 / 3 |

Las entradas son activas en bajo, con pull-up interno. El segundo joystick no
tiene pines y las llaves Color/BN y dificultad son fijas (color, B).
LEDs: 0 latido, 1 menú, 2 cargando, 3 PAL, 4 mando.

## Estructura

| Ruta | Contenido |
|---|---|
| `Atari2600_SD.gprj` | proyecto Gowin (top `atari_top`) |
| `src/sd/` | consola, cartucho SD, vídeo, PSRAM, restricciones |
| `src/cpu_6502/` | CPU cpu65xx (FPGA64) |
| `menu/` | programa del menú (C y ensamblador, cc65) |
| `sim/sd/` | simulador y pruebas ([`docs/SIMULACION.md`](docs/SIMULACION.md)) |
| `tools/build.sh` | síntesis, P&R y bitstream |

Arquitectura y temporización: [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md).

## Compilar

Con Gowin EDA V1.9.12.03, desde Git Bash:

```sh
bash menu/build.sh    # solo si cambia el menú (cc65 y Python)
bash tools/build.sh   # bitstream
```

O abrir `Atari2600_SD.gprj` en el IDE. `src/sd/menu_cfg.vh` guarda la ruta
absoluta de los `.hex`: si se mueve el proyecto, ejecutar `menu/build.sh`.

| Recurso | Uso |
|---|---|
| Lógica | 4282 / 8640 (50 %) |
| BSRAM | 26 / 26 |
| PLL | 2 / 2 |

## Licencias

- cpu65xx: (c) 2005-2008 Peter Wendrich (FPGA64).
- Controlador PSRAM: basado en el de Feng Zhou, Apache 2.0
  ([`LICENSE-APACHE-2.0.txt`](LICENSE-APACHE-2.0.txt)).
