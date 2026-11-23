// menu.c : file browser of the flash cart (runs on the console's own CPU)
#include "fat.h"
#define REG(a) (*(volatile u8 *)(a))
#define SPI REG(0xC000)
#define SPI_ST REG(0xC001)
#define CFG REG(0xC006)
#define PADS REG(0xC006)
#define LASTB REG(0xC007)
#define VBL REG(0xC007)
#define LAUNCH REG(0xC008)
#define HLROW REG(0xC00A)
#define SCR ((u8 *)0x8000)
#define FONT ((u8 *)0x9000)

extern const u8 font[];
static u8 sdhc;

// --- SD card ------------------------------------------------------------------
static u8 __fastcall__ xfer(u8 b) {
  SPI = b;
  while (SPI_ST & 0x80) ;
  return SPI;
}
static u8 speed;          // 0 slow, 2 fast
static void deselect(void) { SPI_ST = speed | 1; xfer(0xFF); }
static u8 command(u8 c, u32 arg, u8 crc) {
  u8 i, r;
  deselect();
  SPI_ST = speed;
  xfer(0xFF);
  xfer(c | 0x40);
  xfer((u8)(arg >> 24)); xfer((u8)(arg >> 16)); xfer((u8)(arg >> 8)); xfer((u8)arg);
  xfer(crc);
  for (i = 0; i < 10; ++i) {
    r = xfer(0xFF);
    if (!(r & 0x80)) break;
  }
  return r;
}
static u8 sd_init(void) {
  u8 i, r, v2;
  u16 n;
  speed = 0;
  SPI_ST = 1;
  for (i = 0; i < 12; ++i) xfer(0xFF);
  for (n = 0; n < 50; ++n) if (command(0, 0, 0x95) == 1) break;
  if (n == 50) return 0;
  v2 = 0;
  if (command(8, 0x1AA, 0x87) == 1) {
    xfer(0xFF); xfer(0xFF); xfer(0xFF);
    if (xfer(0xFF) != 0xAA) return 0;
    v2 = 1;
  }
  for (n = 0; n < 2000; ++n) {
    command(55, 0, 0xFF);
    r = command(41, v2 ? 0x40000000UL : 0, 0xFF);
    if (r == 0) break;
  }
  if (r) return 0;
  sdhc = 0;
  if (v2) {
    if (command(58, 0, 0xFF)) return 0;
    if (xfer(0xFF) & 0x40) sdhc = 1;
    xfer(0xFF); xfer(0xFF); xfer(0xFF);
  }
  if (!sdhc && command(16, 512, 0xFF)) return 0;
  speed = 2;
  deselect();
  return 1;
}
static u8 start_read(u32 lba) {
  u16 n;
  u8 r;
  if (!sdhc) lba <<= 9;
  if (command(17, lba, 0xFF)) return 0;
  for (n = 0; n < 20000; ++n) {
    r = xfer(0xFF);
    if (r == 0xFE) return 1;
    if (r != 0xFF) return 0;
  }
  return 0;
}
u8 sd_dma(u32 lba, u32 addr) {
  if (!start_read(lba)) { deselect(); return 0; }
  REG(0xC002) = (u8)addr;
  REG(0xC003) = (u8)(addr >> 8);
  REG(0xC004) = (u8)(addr >> 16);
  __asm__("lda #0");
  __asm__("sta $C005");
  __asm__("w: bit $C001");                   // no RAM access while it runs
  __asm__("bmi w");
  xfer(0xFF); xfer(0xFF);
  deselect();
  return 1;
}
u8 sd_read(u32 lba) { return sd_dma(lba, 0x202000UL); }
static u8 flags;
void set_flags(u8 map, u8 last) { flags = map; LASTB = last; }

// --- screen -------------------------------------------------------------------
static void vblank(void) {
  while (VBL & 0x80) ;
  while (!(VBL & 0x80)) ;
}
static void at(u8 x, u8 y, const char *s) {
  u8 *p = SCR + (u16)y * 80 + x;
  while (*s) { *p = *s - 32; ++p; ++s; }
}
static void cls(void) {
  u16 i;
  for (i = 0; i < 2400; ++i) SCR[i] = 0;
}
static const char *const msgs[] = {"", "NO SD CARD", "SD READ ERROR", "NOT FAT32",
  "CARTRIDGE TYPE NOT SUPPORTED", "ROM SIZE NOT SUPPORTED"};

static u8 pad_now, pad_new;
static void readpad(void) {                  // 1 U 2 D 4 L 8 R 10 fire 20 select 40 reset
  u8 old = pad_now;
  pad_now = PADS;
  pad_new = pad_now & ~old;
}

static u32 dir_stack[6];
static u16 page_stack[6];
static u8 sel_stack[6];
static u8 depth, sel;
static u32 dir;
static u16 page;

static void title(void) { at(27, 0, "ATARI 2600 - TANG NANO 9K"); }

static void fail(void) {
  HLROW = 31;
  cls();
  title();
  at(10, 12, msgs[fat_err]);
  at(10, 15, "PRESS FIRE");
  do { vblank(); readpad(); } while (!(pad_new & 0x10));
}

static void draw(void) {
  u8 i;
  HLROW = 31;
  cls();
  title();
  if (!list_len) at(4, 10, "NO .A26 OR .BIN FILES HERE");
  for (i = 0; i < list_len; ++i) {
    at(2, i + 3, list[i].isdir ? "/" : " ");
    at(3, i + 3, list[i].name);
  }
  if (page) at(3, 28, "< LEFT");
  if (list_more) at(70, 28, "RIGHT >");
  at(12, 29, "FIRE: OPEN   SELECT: OPEN WITH PADDLES   RESET: BACK");
  HLROW = list_len ? sel + 3 : 31;
}

static u8 rep;

static void browse(void) {
  u8 redraw, back;
  entry_t *e;
  depth = 0; dir = 0; page = 0; sel = 0;
  for (;;) {
    if (!fat_list(dir, page)) return;
    page = list_page;
    if (sel >= list_len) sel = list_len ? list_len - 1 : 0;
    draw();
    redraw = 0;
    while (!redraw) {
      back = 0;
      vblank();
      readpad();
      if (pad_now & 0x0F) {                    // auto repeat
        if (++rep >= 18) { rep = 15; pad_new |= pad_now & 0x0F; }
      } else rep = 0;
      if ((pad_new & 0x02) && list_len) {
        if (sel + 1 < list_len) ++sel;
        else if (list_more) { ++page; sel = 0; redraw = 1; }
        else if (page) { page = 0; sel = 0; redraw = 1; }
        else sel = 0;
      } else if ((pad_new & 0x01) && list_len) {
        if (sel) --sel;
        else if (page) { --page; sel = LIST_N - 1; redraw = 1; }
        else sel = list_len - 1;
      } else if ((pad_new & 0x08) && list_more) { ++page; sel = 0; redraw = 1; }
      else if ((pad_new & 0x04) && page) { --page; sel = 0; redraw = 1; }
      else if (pad_new & 0x40) back = 1;
      else if ((pad_new & 0x30) && list_len) {
        e = &list[sel];
        if (e->isdir) {
          if (e->name[0] == '.' && e->name[1] == '.') back = 1;
          else if (depth < 6) {
            dir_stack[depth] = dir; page_stack[depth] = page; sel_stack[depth] = sel; ++depth;
            dir = e->cl; page = 0; sel = 0;
            redraw = 1;
          }
        } else {
          at(30, 28, "LOADING...");
          redraw = 1;
          back = pad_new & 0x20;
          if (fat_load(e->cl, e->size)) {
            if (back) flags |= 0x20;           // paddles
            while (PADS & 0x30) ;
            CFG = flags;
            vblank();
            LAUNCH = 1;
            for (;;) ;
          }
          fail();
          fat_err = 0;
          back = 0;
        }
      }
      if (back && depth) {
        --depth; dir = dir_stack[depth]; page = page_stack[depth]; sel = sel_stack[depth];
        redraw = 1;
      }
      if (list_len && !redraw) HLROW = sel + 3;
    }
  }
}

void main(void) {
  u16 i;
  for (i = 0; i < 768; ++i) FONT[i] = font[i];
  cls();
  for (;;) {
    fat_err = E_SD;
    if (sd_init() && fat_mount()) browse();
    fail();
  }
}
