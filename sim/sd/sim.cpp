// sim game rom.bin mapper last frames out.ppm [buttons@from-to ...]
// sim menu sd.img frames out.ppm [buttons@from-to ...]
// Runs the atari_sys netlist (netlist.h, PIX = 5). buttons (hex): 01 up 02 down
// 04 left 08 right 10 fire 20 select 40 reset. Frames: game = vsyncs, menu =
// 1/60 s. Prints lines per frame and the number of distinct frames.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include "netlist.h"
#include "pal.h"
static uint8_t ps[1 << 22], fb[65536];
static FILE *sd; static int dbg = getenv("DBG") ? atoi(getenv("DBG")) : 0;
// --- SD card, SPI mode 0 ------------------------------------------------------
static struct {
  int sck = 0, n = 0, in = 0, out = 0xFF, acmd = 0, idle = 1, tries = 0;
  std::vector<uint8_t> cmd, q; size_t qi = 0;
  void byte(int b) {
    if (cmd.empty() && (b & 0xC0) != 0x40) return;
    cmd.push_back(b);
    if (cmd.size() < 6) return;
    int c = cmd[0] & 63; uint32_t a = cmd[1] << 24 | cmd[2] << 16 | cmd[3] << 8 | cmd[4];
    cmd.clear(); q.clear(); qi = 0; q.push_back(0xFF);
    if (c == 0) { q.push_back(1); idle = 1; }
    else if (c == 8) { for (int x : {1, 0, 0, 1, 0xAA}) q.push_back(x); }
    else if (c == 55) q.push_back(idle);
    else if (c == 41) { if (++tries > 2) idle = 0; q.push_back(idle); }
    else if (c == 58) { for (int x : {0, 0xC0, 0xFF, 0x80, 0}) q.push_back(x); }
    else if (c == 17) {
      uint8_t s[512]; memset(s, 0, 512); fseek(sd, (long)a * 512, SEEK_SET); if (fread(s, 1, 512, sd)) {}
      q.push_back(0); q.push_back(0xFF); q.push_back(0xFE);
      q.insert(q.end(), s, s + 512); q.push_back(0); q.push_back(0);
    } else q.push_back(0);
  }
  int miso(int cs, int k, int mosi) {
    if (cs) { n = 0; out = 0xFF; sck = k; cmd.clear(); return 1; }
    if (k && !sck) { in = (in << 1 | mosi) & 255; }
    if (!k && sck) {
      if (++n == 8) { n = 0; byte(in); out = qi < q.size() ? q[qi++] : 0xFF; }
    }
    sck = k;
    return out >> (7 - n) & 1;
  }
} card;

int main(int argc, char **argv) {
  bool game = !strcmp(argv[1], "game");
  struct P { unsigned b; int f, t; };
  std::vector<P> ev;
  int frames, first; const char *out;
  unsigned map = 0, last = 0;
  if (game) {
    FILE *f = fopen(argv[2], "rb"); if (!f) return 1;
    if (fread(ps, 1, 1 << 19, f)) {} fclose(f);
    map = strtoul(argv[3], 0, 0); last = strtoul(argv[4], 0, 0); frames = atoi(argv[5]); out = argv[6]; first = 7;
  } else { sd = fopen(argv[2], "rb"); frames = atoi(argv[3]); out = argv[4]; first = 5; }
  for (int i = first; i < argc; i++) { P p; if (sscanf(argv[i], "%x@%d-%d", &p.b, &p.f, &p.t) == 3) ev.push_back(p); }
  sim_init();
  set_reset_in(1); set_to_menu(game ? 0 : 1); set_joy0(0); set_joy1(0); set_sw_select(0); set_sw_reset(0);
  set_sw_bw(0); set_sw_diff(0); set_sd_dat0(1); set_vblank_in(0); set_mq(0);
  set_tmode(game); set_tcfg(map); set_tlast(last);
  for (int i = 0; i < 40; i++) { eval(); tick(); }
  set_reset_in(0); set_to_menu(0);
  unsigned mt = get_mt(); int vs = 0; long t = 0, lastv = 0, fr = 0, lines_bad = 0;
  std::map<uint64_t, int> seen; std::map<long, int> lens;
  long period = 15L * 1193182 / 60; int vbl = 0;
  while (fr < frames) {
    unsigned b = 0;
    for (auto &e : ev) if (fr >= e.f && fr <= e.t) b |= e.b;
    set_joy0(b & 31); set_sw_select(b >> 5 & 1); set_sw_reset(b >> 6 & 1);
    if (!game) { vbl = t % period < period / 12; set_vblank_in(vbl); set_sd_dat0(card.miso(get_sd_cs(), get_sd_sck(), get_sd_cmd())); }
    eval();
    if (get_mt() != mt) {
      mt = get_mt(); unsigned a = get_ma(); if (dbg-- > 0) printf("%ld %x %d %02x;", t, a, get_mwe(), ps[a]);
      if (get_mwe()) ps[a] = get_md(); else set_mq(ps[a]);
      eval();
    }
    if (get_fb_we()) fb[get_fb_a()] = get_fb_d();
    bool nf = false;
    if (get_menu()) nf = t % period == 0 && t;
    else { int v = get_vsync_o(); if (vs && !v) nf = true; vs = v; if (!game && t - lastv > 2 * period) nf = true; }
    if (nf) {
      if (!get_menu()) lens[(t - lastv + 570) / 1140]++;
      lastv = t; fr++;
      uint64_t h = 1469598103934665603ull; for (int i = 0; i < 38400; i++) h = (h ^ fb[i]) * 1099511628211ull;
      seen[h]++;
    }
    tick(); t++;
    if (game && t > lastv + (getenv("DBG") ? 1 : 600) * period) { printf("NOVSYNC "); break; }
  }
  std::string l; int best = 0; long bl = 0;
  for (auto &p : lens) { if (p.second > best) { best = p.second; bl = p.first; } if (p.second > 1) l += std::to_string(p.first) + "x" + std::to_string(p.second) + " "; }
  int nz = 0; for (int i = 0; i < 38400; i++) nz += fb[i] != 0;
  printf("lines %ld distinct %d pixels %d menu %d pal %d [%s]\n", bl, (int)seen.size(), nz, get_menu(), get_pal(), l.c_str());
  FILE *o = fopen(out, "wb");
  if (get_menu()) {
    fprintf(o, "P6 640 480 255\n");
    for (int y = 0; y < 480; y++) for (int x = 0; x < 640; x++) {
      uint8_t c = fb[y / 16 * 80 + x / 8], d = fb[4096 + (c & 127) * 8 + y / 2 % 8];
      int on = (d >> (7 - x % 8) & 1) ^ (get_hl_row() == (unsigned)y / 16);
      for (int k = 0; k < 3; k++) fputc(on ? 240 : 24, o);
    }
  } else {
    fprintf(o, "P6 320 240 255\n");
    for (int y = 0; y < 240; y++) for (int x = 0; x < 320; x++) {
      unsigned q = pal[(get_pal() << 7) | (fb[y * 160 + x / 2] & 127)];
      fputc((q >> 12) << 2, o); fputc((q >> 6 & 63) << 2, o); fputc((q & 63) << 2, o);
    }
  }
  fclose(o);
}
