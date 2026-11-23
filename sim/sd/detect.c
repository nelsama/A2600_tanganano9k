/* detect rom : mapper byte and last bank that the menu would choose (fat.c) */
#include "fat.h"
#include <stdio.h>
#include <string.h>
u8 mem[1 << 22];
static FILE *f; static int mp, lb;
u8 sd_read(u32 l) { return 1; }
u8 sd_dma(u32 l, u32 a) { fseek(f, (long)(l - 1000) * 512, 0); if (fread(mem + a, 1, 512, f)) {} return 1; }
void set_flags(u8 m, u8 l) { mp = m; lb = l; }
extern void host_geom(void);
int main(int c, char **v) {
  long n; f = fopen(v[1], "rb"); fseek(f, 0, 2); n = ftell(f); host_geom();
  if (fat_load(2, n)) printf("%d %d\n", mp, lb); else printf("err %d\n", fat_err);
}
