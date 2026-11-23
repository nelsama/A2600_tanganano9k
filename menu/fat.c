// fat.c : read-only FAT32 + cartridge loader of the menu. Also built with gcc for
// the host test (HOST).
#include "fat.h"

#ifdef HOST
u8 buf[512];
entry_t list[LIST_N];
#endif
u8 fat_err;
static u32 buf_lba;
// where each page of the current directory starts
typedef struct { u32 cl; u8 sec, off; } page_t;
#define PAGES 500
#ifdef HOST
static page_t pages[PAGES];
#else
#define pages ((page_t *)0x2200)
#endif
static u32 pg_dir;
static u16 pg_known;
u16 list_page;
static u32 fat_lba, data_lba, root_cl, part_lba;
static u8 spc;

#ifdef HOST
static u16 rd16(u16 o) { return buf[o] | (buf[o + 1] << 8); }
static u32 rd32(u16 o) { return rd16(o) | ((u32)rd16(o + 2) << 16); }
#else
#define rd16(o) (*(u16 *)(buf + (o)))
#define rd32(o) (*(u32 *)(buf + (o)))
#endif

static u8 sector(u32 lba) {
  if (buf_lba == lba) return 1;
  buf_lba = 0xFFFFFFFFUL;
  if (!sd_read(lba)) { fat_err = E_READ; return 0; }
  buf_lba = lba;
  return 1;
}

static u8 is_fat32(void) {
  return buf[510] == 0x55 && buf[511] == 0xAA && rd16(11) == 512 &&
         rd16(17) == 0 && rd16(22) == 0 && rd32(36) != 0 && buf[13] != 0;
}

u8 fat_mount(void) {
  buf_lba = 0xFFFFFFFFUL;
  pg_known = 0;
  fat_err = E_FAT;
  part_lba = 0;
  if (!sector(0)) return 0;
  if (!is_fat32()) {
    part_lba = rd32(454);            // first MBR partition
    if (part_lba == 0 || !sector(part_lba)) return 0;
    if (!is_fat32()) return 0;
  }
  spc = buf[13];
  fat_lba = part_lba + rd16(14);
  data_lba = fat_lba + rd32(36) * buf[16];
  root_cl = rd32(44);
  fat_err = 0;
  return 1;
}

static u32 next_cluster(u32 cl) {
  if (!sector(fat_lba + (cl >> 7))) return 0;
  cl = rd32(((u16)cl & 127) << 2) & 0x0FFFFFFFUL;
  if (cl < 2 || cl >= 0x0FFFFFF7UL) return 0;
  return cl;
}

// --- sequential reader ------------------------------------------------------
static u32 cur_cl, cur_lba;
static u8 cur_sec;
static void seek0(u32 cl) {
  cur_cl = cl ? cl : root_cl;
  cur_sec = 0;
  cur_lba = data_lba + (cur_cl - 2) * spc;
}
static u8 advance(void) {
  if (++cur_sec == spc) {
    cur_cl = next_cluster(cur_cl);
    if (!cur_cl) return 0;
    seek0(cur_cl);
  } else ++cur_lba;
  return 1;
}

// --- directory ----------------------------------------------------------------
u8 list_len, list_more;
static u8 is_rom(u8 *p) {
  return (p[8] == 'A' && p[9] == '2' && p[10] == '6') ||
         (p[8] == 'B' && p[9] == 'I' && p[10] == 'N');
}
static char lfn[NAME_N];
static u8 lfn_ok;
static const u8 lfn_pos[13] = {1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30};


// shows page `page` (or the last one if there are fewer)
u8 fat_list(u32 dir, u16 page) {
  u16 o, pg;
  u8 i, j, n, c, attr, isdir, *p;
  entry_t *e;
  page_t *q;
  if (page >= PAGES - 1) page = PAGES - 2;
  if (!pg_known || pg_dir != dir) {
    seek0(dir);
    pg_dir = dir;
    pg_known = 1;
    pages[0].cl = cur_cl; pages[0].sec = 0; pages[0].off = 0;
  }
restart:
  list_len = 0;
  list_more = 0;
  lfn_ok = 0;
  pg = page < pg_known ? page : pg_known - 1;
  q = &pages[pg];
  seek0(q->cl);
  cur_sec = q->sec;
  cur_lba += cur_sec;
  o = (u16)q->off << 5;
  n = 0;                                     // entries found in page pg
  for (;;) {
    if (!sector(cur_lba)) return 0;
    for (; o < 512; o += 32) {
      p = buf + o;
      if (p[0] == 0) goto end;
      if (p[0] == 0xE5) { lfn_ok = 0; continue; }
      attr = p[11];
      if ((attr & 0x3F) == 0x0F) {
        if (pg != page) continue;            // only skipping
        if (p[0] & 0x40) {
          for (i = 0; i < NAME_N; ++i) lfn[i] = 0;
          lfn_ok = 1;
        }
        j = ((p[0] & 0x1F) - 1) * 13;
        for (i = 0; i < 13; ++i, ++j) {
          if (j >= NAME_N - 1) break;
          c = p[lfn_pos[i]];
          if (p[lfn_pos[i] + 1]) c = (c == 0xFF) ? 0 : '?';
          lfn[j] = (c < 128) ? c : '?';
        }
        continue;
      }
      isdir = (attr & 0x10) != 0;
      // hidden, system, volume label, "." (".." is kept)
      if ((attr & 0x0E) || (p[0] == '.' && p[1] != '.') ||
          (!isdir && !is_rom(p))) { lfn_ok = 0; continue; }
      if (n == LIST_N) {                     // first entry of the next page
        if (pg == page) { list_more = 1; list_page = pg; return 1; }
        ++pg;
        n = 0;
        if (pg == page) goto restart;        // go back for its long name
      }
      ++n;
      if (n == LIST_N && pg + 1 == pg_known) {
        q = &pages[pg_known];
        ++pg_known;
        q->cl = cur_cl; q->sec = cur_sec; q->off = (u8)(o >> 5) + 1;
      }
      if (pg != page) continue;
      e = &list[list_len];
      ++list_len;
      e->isdir = isdir;
      e->cl = ((u32)rd16(o + 20) << 16) | rd16(o + 26);
      e->size = rd32(o + 28);
      if (lfn_ok) {
        for (i = 0; i < NAME_N; ++i) e->name[i] = lfn[i];
      } else {
        j = 0;
        for (i = 0; i < 11; ++i) {
          c = p[i];
          if (i == 8 && c != ' ') e->name[j++] = '.';
          if (c != ' ') e->name[j++] = c < 128 ? c : '?';
        }
        while (j < NAME_N) e->name[j++] = 0;
      }
      lfn_ok = 0;
    }
    if (!advance()) { if (fat_err) return 0; break; }
    o = 0;
  }
end:
  if (pg != page || (n == 0 && pg)) {        // past the end: show the last page
    page = n ? pg : pg - 1;
    goto restart;
  }
  list_page = pg;
  return 1;
}

#ifdef HOST
void pg_test(void) { pg_known = 0; }         // forget the page table
#endif

// --- loader -----------------------------------------------------------------
#ifdef HOST
extern u8 mem[];
#define rom(a) mem[a]
#else
#define WIN ((u8 *)0x6000)
#define PBANK (*(volatile u8 *)0xC009)
#endif

// signatures: mapper, times it must appear, length, bytes
static const u8 sigs[] = {
  T_E0, 1, 3, 0x8D, 0xE0, 0x1F,  T_E0, 1, 3, 0x8D, 0xE0, 0x5F,  T_E0, 1, 3, 0x8D, 0xE9, 0xFF,
  T_E0, 1, 3, 0x0C, 0xE0, 0x1F,  T_E0, 1, 3, 0xAD, 0xE0, 0x1F,  T_E0, 1, 3, 0xAD, 0xE9, 0xFF,
  T_E0, 1, 3, 0xAD, 0xED, 0xFF,  T_E0, 1, 3, 0xAD, 0xF3, 0xBF,
  T_3F, 2, 2, 0x85, 0x3F,
  T_3E, 1, 4, 0x85, 0x3E, 0xA9, 0x00,
  T_UA, 1, 3, 0x8D, 0x40, 0x02,  T_UA, 1, 3, 0xAD, 0x40, 0x02,  T_UA, 1, 3, 0xBD, 0x1F, 0x02,
  T_UA, 1, 3, 0x2C, 0xC0, 0x02,  T_UA, 1, 3, 0x8D, 0xC0, 0x02,  T_UA, 1, 3, 0xAD, 0xC0, 0x02,
  T_FE, 1, 5, 0x20, 0x00, 0xD0, 0xC6, 0xC5,  T_FE, 1, 5, 0x20, 0xC3, 0xF8, 0xA5, 0x82,
  T_FE, 1, 5, 0xD0, 0xFB, 0x20, 0x73, 0xFE,  T_FE, 1, 5, 0x20, 0x00, 0xF0, 0x84, 0xD6,
  T_0840, 2, 3, 0xAD, 0x00, 0x08,  T_0840, 2, 3, 0xAD, 0x40, 0x08,  T_0840, 2, 3, 0x2C, 0x00, 0x08,
  T_E7, 1, 3, 0xAD, 0xE2, 0xFF,  T_E7, 1, 3, 0xAD, 0xE5, 0xFF,  T_E7, 1, 3, 0xAD, 0xE5, 0x1F,
  T_E7, 1, 3, 0xAD, 0xE7, 0x1F,  T_E7, 1, 3, 0x0C, 0xE7, 0x1F,  T_E7, 1, 3, 0x8D, 0xE7, 0xFF,
  T_E7, 1, 3, 0x8D, 0xE7, 0x1F,
  T_CV, 1, 3, 0x9D, 0xFF, 0xF3,  T_CV, 1, 3, 0x99, 0x00, 0xF4,
  T_EF, 1, 3, 0x0C, 0xE0, 0xFF,  T_EF, 1, 3, 0xAD, 0xE0, 0xFF,  T_EF, 1, 3, 0x0C, 0xE0, 0x1F,
  T_EF, 1, 3, 0xAD, 0xE0, 0x1F,
  T_END };

static u8 kb;                                // image size in KB
static u8 peek(u16 hi, u16 a) {              // hi = 8 KB bank
#ifdef HOST
  return rom((u32)hi * 8192 + a);
#else
  PBANK = (u8)hi;
  return WIN[a];
#endif
}
// one pass over the image: hits[] = matches of every signature
#define SIGS 48
static u8 hits[SIGS];
#ifdef HOST
static u8 tab[256], tab2[256];
#else
#define tab ((u8 *)0x2F00)             // first bytes
#define tab2 ((u8 *)0x2E00)            // second bytes
extern u8 found, scan_pg;
u8 __fastcall__ find_at(u8 y);               // scan.s
#endif
static void scan_all(void) {
  const u8 *q;
  u8 bk, banks, k, i, npg, pg, y;
  u16 a;
  for (k = 0; k < SIGS; ++k) hits[k] = 0;
  k = 0;
  do { tab[k] = 0; tab2[k] = 0; } while (++k);
  for (q = sigs; *q != T_END; q += 3 + q[2]) { tab[q[3]] = 1; tab2[q[4]] = 1; }
  banks = (kb + 7) >> 3;
  npg = kb < 8 ? kb << 2 : 32;
  for (bk = 0; bk < banks; ++bk) {
    for (pg = 0; pg < npg; ++pg) {
      y = 0;
      do {
#ifdef HOST
        if (!tab[peek(bk, ((u16)pg << 8) + y)]) continue;
#else
        PBANK = bk;
        scan_pg = pg + 0x60;
        y = find_at(y);
        if (!found) break;
#endif
        a = ((u16)pg << 8) + y;
        if (a < 8192 - 5 && tab2[peek(bk, a + 1)]) {
          i = 0;
          for (q = sigs; *q != T_END; q += 3 + q[2]) {
            for (k = 0; k < q[2]; ++k) if (peek(bk, a + k) != q[3 + k]) break;
            if (k == q[2]) ++hits[i];
            ++i;
          }
        }
      } while (++y);
    }
  }
}
// does the image contain a signature of mapper m?
static u8 scan(u8 m) {
  const u8 *q;
  u8 i = 0;
  for (q = sigs; *q != T_END; q += 3 + q[2]) {
    if (*q == m && hits[i] >= q[1]) return 1;
    ++i;
  }
  return 0;
}
// Superchip: the first 128 bytes of every 4 KB bank (RAM) are repeated
static u8 has_sc(void) {
  u8 bk, n;
  u16 o;
  n = kb >> 2;
  for (bk = 0; bk < n; ++bk) {
    o = (bk & 1) ? 4096 : 0;
    for (; ; ++o) {
      if ((o & 0xFFF) == 128) break;
      if (peek(bk >> 1, o) != peek(bk >> 1, o + 128)) return 0;
    }
  }
  return 1;
}
static u8 same_halves(u16 half) {
  u16 a;
  for (a = 0; a < half; ++a) if (peek(0, a) != peek(0, a + half)) return 0;
  return 1;
}

// mapper (0-3) | 16 superchip; 0xFF unknown
static u8 detect(void) {
  scan_all();
  if (kb <= 2) return scan(T_CV) ? T_CV : T_2K;
  if (kb == 4) {
    // a CommaVid game dumped as 4 KB has its 2 KB at the end
    return same_halves(2048) ? T_2K : T_4K;
  }
  if (kb == 8) {
    if (has_sc()) return T_F8 | 16;
    if (scan(T_E0)) return T_E0;
    if (scan(T_E7)) return T_E7;
    if (scan(T_3E)) return T_3E;
    if (scan(T_3F)) return T_3F;
    if (scan(T_UA)) return T_UA;
    if (scan(T_FE)) return T_FE;
    if (scan(T_0840)) return T_0840;
    if (same_halves(4096)) return T_4K;
    return T_F8;
  }
  if (kb == 10) return T_4K | 16;            // DPC
  if (kb == 12) return T_FA;
  if (kb == 16) {
    if (has_sc()) return T_F6 | 16;
    if (scan(T_E7)) return T_E7;
    if (scan(T_3E)) return T_3E;
    return T_F6;
  }
  if (kb == 32) {
    if (has_sc()) return T_F4 | 16;
    if (scan(T_3E)) return T_3E;
    if (scan(T_3F)) return T_3F;
    return T_F4;
  }
  if (kb == 64) {
    if (scan(T_3E)) return T_3E;
    if (scan(T_3F)) return T_3F;
    if (scan(T_EF)) return has_sc() ? (T_EF | 16) : T_EF;
    return T_F0;
  }
  return 0xFF;
}

// loads the file; returns 1 when the game can be started
u8 fat_load(u32 cl, u32 size) {
  u8 k, n, m;
  u32 addr;
  fat_err = E_SIZE;
  if (!cl || !size) return 0;
  // files a few bytes off a standard size are accepted
  if (size <= 2048) kb = 2;
  else if (size <= 4096) kb = 4;
  else if (size <= 8192) kb = 8;
  else if (size >= 10240 && size <= 10495) kb = 10;
  else if (size <= 8448) return 0;           // Supercharger
  else if (size == 12288) kb = 12;
  else if (size == 16384) kb = 16;
  else if (size == 32768UL || size == 33792UL) kb = 32;
  else if (size == 65536UL) kb = 64;
  else return 0;
  n = (u8)((kb << 1) - 1);                   // sectors - 1
  fat_err = 0;
  // 8 KB images are loaded twice (E7 sees them as 16 KB)
  addr = 0;
  m = kb == 8 ? 2 : 1;
  do {
  seek0(cl);
  for (k = 0; ; ++k) {
    buf_lba = 0xFFFFFFFFUL;
    if (!sd_dma(cur_lba, addr)) { fat_err = E_READ; return 0; }
    addr += 512;
    if (k == n) break;
    if (!advance()) {
      if (fat_err) return 0;
      break;                                 // short file
    }
  }
  addr = 8192;
  } while (--m);
  m = detect();
  if (m == 0xFF) { fat_err = E_MAP; return 0; }
  set_flags(m, (u8)((kb >> 1) - 1));
  return 1;
}

#ifdef HOST
// one huge cluster at LBA 1000 (sim/sd/detect.c)
void host_geom(void) { data_lba = 1000; spc = 255; root_cl = 2; buf_lba = 0xFFFFFFFFUL; }
#endif
