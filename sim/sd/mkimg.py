"""mkimg.py out.img file... : FAT32 test image (MBR, long names, fragmented files,
a subdirectory with many entries)."""
import os, random, struct, sys
random.seed(1)

class Img:
    def __init__(s, part, spc):
        s.part, s.spc = part, spc; s.res, s.fsz = 32, 600
        s.data = part + s.res + 2 * s.fsz
        s.sec = {}; s.fat = {0: 0x0FFFFFF8, 1: 0x0FFFFFFF}
        s.free = list(range(3, 20000));
    def alloc(s, data, frag=False, first=None):
        n = max(1, -(-len(data) // (s.spc * 512)))
        cl = [s.free.pop(random.randrange(3000) if frag else 0) for _ in range(n)]
        if first: s.free.append(cl[0]); cl[0] = first
        for a, b in zip(cl, cl[1:] + [0x0FFFFFFF]): s.fat[a] = b
        for i, c in enumerate(cl):
            for k in range(s.spc):
                o = (i * s.spc + k) * 512
                s.sec[s.data + (c - 2) * s.spc + k] = data[o:o + 512].ljust(512, b'\0')
        return cl[0]
    def write(s, path):
        b = bytearray(512); b[11:13] = struct.pack('<H', 512); b[13] = s.spc
        b[14:16] = struct.pack('<H', s.res); b[16] = 2
        b[36:40] = struct.pack('<I', s.fsz); b[44:48] = struct.pack('<I', 2); b[510:512] = b'\x55\xaa'
        s.sec[s.part] = bytes(b)
        if s.part:
            m = bytearray(512); m[446 + 4] = 12; m[454:458] = struct.pack('<I', s.part); m[510:512] = b'\x55\xaa'
            s.sec[0] = bytes(m)
        ft = bytearray(s.fsz * 512)
        for c, v in s.fat.items(): ft[c * 4:c * 4 + 4] = struct.pack('<I', v)
        for k in range(s.fsz): s.sec[s.part + s.res + k] = bytes(ft[k * 512:k * 512 + 512])
        with open(path, 'wb') as f:
            for k, v in s.sec.items(): f.seek(k * 512); f.write(v)

cnt = [0]
def dirent(name, cl, size, isdir=False, attr=None):
    cnt[0] += 1
    short = (b'F%06d ' % cnt[0]) + (b'   ' if isdir else b'A26')
    if name == '..': short = b'..         ';
    out = b''
    if name != '..':
        u = name.encode('utf-16le') + b'\0\0'
        while len(u) % 26: u += b'\xff\xff'
        ch = [u[i:i + 26] for i in range(0, len(u), 26)]
        for i in reversed(range(len(ch))):
            c = ch[i]
            out += bytes([(i + 1) | (0x40 if i == len(ch) - 1 else 0)]) + c[:10] + b'\x0f\0\0' + c[10:22] + b'\0\0' + c[22:]
    e = bytearray(32); e[:11] = short; e[11] = attr if attr is not None else (0x10 if isdir else 0x20)
    e[20:22] = struct.pack('<H', cl >> 16); e[26:28] = struct.pack('<H', cl & 0xFFFF); e[28:32] = struct.pack('<I', size)
    return out + bytes(e)


im = Img(2048, 8)
fs = []
for p in sys.argv[2:]:
    b = open(p, 'rb').read(); fs.append((os.path.basename(p), im.alloc(b, True), len(b)))
sub = dirent('..', 0, 0, True) + b''.join(dirent('file %02d.a26' % i, fs[0][1], fs[0][2]) for i in range(48))
root = dirent('VOL', 0, 0, attr=8) + dirent('Games', im.alloc(sub, True), 0, True)
root += b''.join(dirent(*f) for f in fs)
im.alloc(root, True, first=2)
im.write(sys.argv[1])
