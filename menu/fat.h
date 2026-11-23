#ifndef FAT_H
#define FAT_H
#ifdef HOST
#include <stdint.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;
#else
typedef unsigned char u8; typedef unsigned int u16; typedef unsigned long u32;
#endif
#define LIST_N 24
#define NAME_N 63
enum { E_OK, E_SD, E_READ, E_FAT, E_MAP, E_SIZE };
// same numbers as src/sd/mapper.v
enum { T_4K, T_2K, T_F8, T_F6, T_F4, T_E0, T_FE, T_3F, T_FA, T_E7, T_CV, T_UA, T_0840, T_F0, T_EF, T_3E, T_END = 255 };
typedef struct { u32 cl; u32 size; u8 isdir; char name[NAME_N]; } entry_t;
#ifdef HOST
extern u8 buf[512];
extern entry_t list[LIST_N];
#else               // menu RAM: $2000 sector, $2200 pages, $3800 list
#define buf ((u8 *)0x2000)
#define list ((entry_t *)0x3800)
#endif
extern u16 list_page;
extern u8 fat_err, list_len, list_more;
u8 fat_mount(void);
u8 fat_list(u32 dir, u16 page);       // dir 0 = root; list_page = page shown
u8 fat_load(u32 cl, u32 size);
// provided by the platform
u8 sd_read(u32 lba);                  // sector -> buf
u8 sd_dma(u32 lba, u32 addr); // sector -> PSRAM
void set_flags(u8 map, u8 last);
#endif
