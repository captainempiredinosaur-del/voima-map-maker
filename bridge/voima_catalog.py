"""Reads the VOIMA universe (Content + Mods, never Mods_off): every slab type with its texture's average colour, every card
with its sprite size and colour. Pure standard library (own PNG reader), so the bridge needs no pip packages."""
import os, re, struct, zlib, glob

UNIVERSES = os.path.join(os.environ.get('APPDATA', ''), '.VOIMA', 'Universes')
UNIVERSE = ''                                     # set by use_universe()


def universes():
    """every VOIMA universe on this PC (a folder in %APPDATA%\\.VOIMA\\Universes with a Content folder)"""
    try: names = os.listdir(UNIVERSES)
    except OSError: return []
    return sorted(n for n in names if os.path.isdir(os.path.join(UNIVERSES, n, 'Content')))


def use_universe(name=None):
    """pick a universe by name, else the one played most recently (newest Worlds folder)"""
    global UNIVERSE
    all_ = universes()
    if not all_: raise FileNotFoundError(f'No VOIMA universe found in {UNIVERSES}. Is VOIMA installed and has it been run once?')
    if name not in all_:
        def played(n):
            w = os.path.join(UNIVERSES, n, 'Worlds')
            try: return max([os.path.getmtime(w)] + [os.path.getmtime(os.path.join(w, d)) for d in os.listdir(w)])
            except OSError: return 0
        name = max(all_, key=played)
    if os.path.join(UNIVERSES, name) != UNIVERSE: _cache.clear()
    UNIVERSE = os.path.join(UNIVERSES, name)
    return name


# ---------------------------------------------------------------- PNG reader (8-bit, non-interlaced, as VOIMA uses)
def read_png(path):
    """returns (w, h, rows) with rows = list of bytearrays of RGBA pixels, or None if the file can't be read"""
    try: data = open(path, 'rb').read()
    except OSError: return None
    if data[:8] != b'\x89PNG\r\n\x1a\n': return None
    i = 8; idat = bytearray(); plte = None; trns = None; w = h = depth = ctype = interlace = 0
    while i < len(data):
        n, = struct.unpack('>I', data[i:i + 4]); kind = data[i + 4:i + 8]; chunk = data[i + 8:i + 8 + n]; i += 12 + n
        if kind == b'IHDR': w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', chunk)
        elif kind == b'PLTE': plte = chunk
        elif kind == b'tRNS': trns = chunk
        elif kind == b'IDAT': idat += chunk
        elif kind == b'IEND': break
    if interlace or (depth == 16 and ctype == 3) or (depth < 8 and ctype not in (0, 3)): return None
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if not ch: return None
    raw = zlib.decompress(bytes(idat)); stride = (w * ch * depth + 7) // 8; rows = []; prev = bytearray(stride); p = 0
    ch_pix = ch
    if depth < 8: ch = 1                       # filters work on whole bytes for packed 1/2/4-bit pixels
    elif depth == 16: ch = ch * 2               # 16-bit: filters step over two bytes per channel
    for _ in range(h):
        f = raw[p]; line = bytearray(raw[p + 1:p + 1 + stride]); p += 1 + stride
        if f == 1:
            for x in range(ch, stride): line[x] = (line[x] + line[x - ch]) & 255
        elif f == 2:
            for x in range(stride): line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride): line[x] = (line[x] + ((line[x - ch] if x >= ch else 0) + prev[x]) // 2) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x - ch] if x >= ch else 0; b = prev[x]; c = prev[x - ch] if x >= ch else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if depth == 16: line = line[0::2]          # keep the high byte of each channel
        if depth < 8:                          # unpack the packed indices / grey levels to one byte each
            per = 8 // depth; mask = (1 << depth) - 1
            line = bytearray((line[x // per] >> (8 - depth * (x % per + 1))) & mask for x in range(w))
            if ctype == 0: line = bytearray(v * 255 // mask for v in line)
        if ctype == 6: rows.append(line)
        elif ctype == 2: rows.append(bytearray(b for k in range(w) for b in (*line[3 * k:3 * k + 3], 255)))
        elif ctype == 0: rows.append(bytearray(b for v in line for b in (v, v, v, 255)))
        elif ctype == 4: rows.append(bytearray(b for k in range(w) for b in (line[2 * k], line[2 * k], line[2 * k], line[2 * k + 1])))
        else:
            out = bytearray()
            for v in line:
                out += plte[3 * v:3 * v + 3]; out.append(trns[v] if trns and v < len(trns) else 255)
            rows.append(out)
    return w, h, rows


def image_stats(path):
    """average sRGB colour (0..1) of the opaque pixels, and the opaque bounding box as fractions of the image size"""
    img = read_png(path)
    if not img: return None
    w, h, rows = img
    step = max(1, max(w, h) // 128)
    r = g = b = n = 0; x0, y0, x1, y1 = w, h, -1, -1
    for y in range(0, h, step):
        row = rows[y]
        for x in range(0, w, step):
            if row[4 * x + 3] > 128:
                r += row[4 * x]; g += row[4 * x + 1]; b += row[4 * x + 2]; n += 1
                x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    if not n: return None
    return {'color': (r / n / 255, g / n / 255, b / n / 255), 'w': w, 'h': h,
            'bbox': (x0 / w, y0 / h, (x1 + step) / w, (y1 + step) / h)}


# ---------------------------------------------------------------- card and slab text files
def fields(text):
    """'Key = value' and 'Key:' + tab-indented list entries -> dict of lowercased key -> str or list"""
    out = {}; key = None
    for line in text.splitlines():
        if line.startswith('\t') and key:
            out[key].extend(v.strip() for v in line.strip().rstrip(',').split(',') if v.strip()); continue
        m = re.match(r'^([A-Za-z][^=:\n]*?)\s*(=|:)\s*(.*)$', line)
        if not m: key = None; continue
        k = m.group(1).strip().lower()
        if m.group(2) == ':' and not m.group(3).strip(): out[k] = []; key = k
        else: out[k] = m.group(3).strip(); key = None
    return out


def first(v):
    if isinstance(v, list): return v[0] if v else ''
    return v.split(',')[0].strip() if v else ''


def num(v, default):
    try: return float(str(v).replace('%', '').split(',')[0])
    except ValueError: return default


_cache = {}


def png_index():
    """lowercase file stem -> path, for every PNG in Content and Mods"""
    idx = {}
    for root in (os.path.join(UNIVERSE, 'Content'), os.path.join(UNIVERSE, 'Mods')):
        for dp, _, fs in os.walk(root):
            for f in fs:
                if f.lower().endswith('.png'): idx.setdefault(f[:-4].lower(), os.path.join(dp, f))
    return idx


def find_image(idx, name):
    """a texture name as cards and slabs use it: a single PNG, or a frame folder '<name> 0' with angles '<name> 0 0'"""
    n = name.lower().strip()
    for k in (n, n + ' 0', n + ' 0 0', n + ' 1', n + ' 0 6'):
        if k in idx: return idx[k]
    return None


def text_files():
    for root, mod in ((os.path.join(UNIVERSE, 'Content'), ''), (os.path.join(UNIVERSE, 'Mods'), 'mod')):
        for f in glob.glob(os.path.join(root, '**', '*.txt'), recursive=True):
            try: t = open(f, encoding='utf-8', errors='ignore').read()
            except OSError: continue
            head = t.lstrip()[:4]
            if head in ('SLAB', 'CARD'):
                src = os.path.relpath(f, root).split(os.sep)[0] if mod else 'VOIMA'
                yield head, os.path.splitext(os.path.basename(f))[0].lower(), fields(t), src


SPECIAL = {'blur', 'blurry mirror x', 'blurry mirror y', 'forever', 'gray window', 'invert', 'inverted window', 'sky',
           'mirror x', 'mirror y', 'error checker'}


def catalog(refresh=False):
    if _cache and not refresh: return _cache
    idx = png_index(); slabs = {}; cards = {}
    for kind, name, f, src in text_files():
        if kind == 'SLAB':
            if name.startswith('bear_swim') or name.startswith('bear_water'): continue
            tex = first(f.get('wall texture', '')) or first(f.get('top texture', ''))
            st = image_stats(find_image(idx, tex)) if tex and find_image(idx, tex) else None
            top = first(f.get('top texture', ''))
            st_top = image_stats(find_image(idx, top)) if top and find_image(idx, top) else st
            effect = (first(f.get('wall effect', '')) + ' ' + first(f.get('wall shader', ''))).lower()
            look = top or tex                                       # one texture per Roblox material: the top one
            slabs[name] = {
                'texture': look, 'mirror': str(f.get('top tiling', '')).lower().startswith('m'),
                'tile_m': num(f.get('texture scale', 100), 100) / 100,   # SlabType.cs: one tile per Texture Scale metres
                'name': name, 'source': src, 'fluid': str(f.get('type', '')).lower().startswith('fluid'),
                'special': name in SPECIAL, 'see_through': any(e in effect for e in ('transparent', 'window', 'haze')),
                'glow': num(f.get('extra lighting', 0), 0) / 100,
                'color': (st or {}).get('color', (0.6, 0.6, 0.6)), 'top_color': (st_top or st or {}).get('color', (0.6, 0.6, 0.6))}
        else:
            tex = first(f.get('idle textures', '')) or first(f.get('walk textures', ''))
            path = find_image(idx, tex) if tex else None
            st = image_stats(path) if path else None
            size = num(f.get('texture size', 1), 1)
            if st:
                bx0, by0, bx1, by1 = st['bbox']
                height = (by1 - by0) * size                         # CardType.cs: Texture Size is the sprite height,
                width = (bx1 - bx0) * size * st['w'] / st['h']      # the width follows the image's aspect ratio
            else:                                                   # unreadable PNG (16-bit / interlaced): use its header size
                height, width = size, size
                try:
                    hd = open(path, 'rb').read(24); w_, h_ = struct.unpack('>II', hd[16:24]); width = size * w_ / h_
                except Exception: pass
            cards[name] = {'name': name, 'source': src, 'type': str(f.get('type', '')).strip() or 'Card',
                           'health': num(f.get('health', 10), 10), 'aggressive': str(f.get('aggressive', '')).lower().startswith('y'), 'height': round(max(0.2, height), 3),
                           'width': round(max(0.2, width), 3), 'color': (st or {}).get('color', (0.7, 0.7, 0.7))}
    _cache.clear(); _cache.update(slabs=slabs, cards=cards)
    return _cache


# ---------------------------------------------------------------- slab textures for the Studio plugin (raw RGBA)
TEX_CACHE = os.path.join(os.environ.get('TEMP', '.'), 'voima_work', 'textures')


def slab_texture(name, sat=1.0, max_size=1024):
    """the slab's texture as VOIMA tiles it: mirrored 2x2 when its tiling is Mirror, colours pulled toward grey by
    `sat` (VOIMA's saturation), and blown up with nearest-neighbour so the pixels stay crisp in Studio.
    Returns (width, height, rgba bytes, metres per tile across)."""
    s = _cache['slabs'][name]
    key = f"{os.path.basename(UNIVERSE)}_{name}_{round(sat, 2)}_{max_size}".replace(' ', '_')
    os.makedirs(TEX_CACHE, exist_ok=True)
    cpath = os.path.join(TEX_CACHE, key + '.rgba')
    path = find_image(png_index_cached(), s['texture'])
    img = read_png(path) if path else None
    if not img:
        w = h = 8; rows = [bytearray(bytes(int(c * 255) for c in s['color']) + b'\xff') * w for _ in range(h)]
    else:
        w, h, rows = img
    tile = s['tile_m']
    if s.get('mirror') and img:
        rows = [r + b''.join(r[i:i + 4] for i in range(len(r) - 4, -1, -4)) for r in rows]
        rows = rows + rows[::-1]
        w, h, tile = w * 2, h * 2, tile * 2
    if max(w, h) > max_size:                     # thumbnails: nearest-neighbour shrink
        step = -(-max(w, h) // max_size)
        rows = [bytearray(b''.join(r[i:i + 4] for i in range(0, len(r), 4 * step))) for r in rows[::step]]
        w, h = len(rows[0]) // 4, len(rows)
    k = max(1, min(4, max_size // max(w, h)))
    W, H = w * k, h * k
    if os.path.exists(cpath) and os.path.getsize(cpath) == W * H * 4:
        return W, H, open(cpath, 'rb').read(), tile
    out = bytearray()
    for r in rows:
        if sat < 0.999:
            r = bytearray(r)
            for i in range(0, len(r), 4):
                g = 0.299 * r[i] + 0.587 * r[i + 1] + 0.114 * r[i + 2]
                for c in range(3): r[i + c] = max(0, min(255, int(g + (r[i + c] - g) * sat)))
        if k > 1: r = b''.join(r[i:i + 4] * k for i in range(0, len(r), 4))
        out += bytes(r) * k
    open(cpath, 'wb').write(out)
    return W, H, bytes(out), tile


_PNG_INDEX = {}


def png_index_cached():
    if _PNG_INDEX.get('u') != UNIVERSE: _PNG_INDEX.clear(); _PNG_INDEX.update(idx=png_index(), u=UNIVERSE)
    return _PNG_INDEX['idx']


if __name__ == '__main__':
    use_universe()
    c = catalog()
    for n, s in sorted(c['slabs'].items()): print('SLAB', n, s['source'], [round(v, 2) for v in s['color']], 'fluid' if s['fluid'] else '', 'special' if s['special'] else '')
    print(len(c['cards']), 'cards, e.g.', [(n, c['cards'][n]['type'], c['cards'][n]['height']) for n in list(c['cards'])[:8]])
