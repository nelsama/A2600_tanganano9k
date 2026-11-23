# Cartucho microSD

## Tarjeta

- FAT32, con o sin tabla de particiones (la primera MBR).
- Ficheros `.a26` y `.bin`; el resto no se muestra.
- Carpetas: hasta 6 niveles. 24 entradas por página, unas 499 páginas por carpeta.
- Nombres largos: se muestran hasta 62 caracteres.
- El orden es el de la tarjeta (el de copia), no alfabético.

## Cartuchos admitidos

El tipo se detecta por el tamaño y por el código del juego (`menu/fat.c`).

| Tamaño | Tipos |
|---|---|
| 2 KB | 2K, CV |
| 4 KB | 4K |
| 8 KB | F8, F8+SC, E0, E7, 3E, 3F, UA, FE, 0840 |
| 10 KB | DPC |
| 12 KB | FA |
| 16 KB | F6, F6+SC, E7, 3E |
| 32 KB | F4, F4+SC, 3E, 3F |
| 64 KB | F0, EF, EF+SC, 3E, 3F |

No se admiten los de Supercharger (8448 bytes y múltiplos).

La detección recorre la ROM con la CPU de la consola: un juego de 8 KB tarda
unos 1,7 s en arrancar y los mayores, más.

## Registros (solo en modo menú)

El menú es un programa de 10 KB (`$D800-$FFFF`) que corre en la CPU de la
consola. El mapa completo está al principio de `src/sd/atari_sys.v`.
