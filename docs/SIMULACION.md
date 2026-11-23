# Simulación

`sim/sd/build.sh` sintetiza `sim_top` con Gowin y traduce el netlist a un
programa de C++ (hace falta g++ de MSYS2, Python y ffmpeg para las imágenes).
Todo queda en `build/sim`.

```sh
bash sim/sd/build.sh
# detector de mapper (usa el mismo menu/fat.c)
gcc -O1 -DHOST -Imenu -o build/sim/detect sim/sd/detect.c menu/fat.c
# un juego: rom, mapper, último banco, frames, imagen, botones@desde-hasta
build/sim/sim game juego.a26 2 3 40 out.ppm 40@15-18
# una colección entera
python sim/sd/run_all.py CARPETA 45 40@20-24 10@30-40
# el menú con una tarjeta FAT32 de prueba
python sim/sd/mkimg.py t.img juego1.a26 juego2.a26
build/sim/sim menu t.img 120 out.ppm 02@70-72 10@80-82
```

Botones (hex): 01 arriba, 02 abajo, 04 izquierda, 08 derecha, 10 fire, 20 select,
40 reset. Cuesta 1 o 2 s por frame.

## Resultados

Colección de 251 ROMs, 45 frames cada una: casi todas dan imagen y número de
líneas estable (262 en la mayoría). Pendientes o dudosos:

| Juego | Observación |
|---|---|
| Sea Monster | pierde el VSYNC |
| Pharaoh's Curse | 272 líneas; imagen sin confirmar |
| Escape from the Mindmaster (32 KB) | parece de Supercharger; no va bien |
| 7 juegos de Supercharger | no admitidos |

Los botones se miden en frames: un juego que espera a que se suelte Reset sin
generar VSYNC (Q-bert) parece colgado en el simulador y no lo está.
