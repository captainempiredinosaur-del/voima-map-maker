"""Roblox parts -> VOIMA slabs and cards.

Geometry: every part is a convex solid (block, wedge, corner wedge, cylinder, ball). VOIMA slabs are vertical prisms, so a
part that stands straight becomes one exact slab, and a tilted one is cut into horizontal layers (its cross-section at the
middle of each layer). Overlaps are cut away (VOIMA slabs must not overlap): big parts stay whole, smaller ones are trimmed where they overlap.
Materials: a VOIMA slab with the same name wins, then the closest slab of the same family, then the closest texture colour.
Colours: the tint that makes the slab's texture show the part's colour, toned to VOIMA's look."""
import math, colorsys

# ---------------------------------------------------------------- 2D convex helpers (points are (x, z))
def cross(o, a, b): return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def hull(pts):
    pts = sorted(set((round(x, 5), round(z, 5)) for x, z in pts))
    if len(pts) < 3: return []
    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 1e-12: lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 1e-12: hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]                      # counter-clockwise


def area(poly): return sum(poly[i][0] * poly[i - 1][1] - poly[i - 1][0] * poly[i][1] for i in range(len(poly))) / -2


def clip(poly, a, b, keep_left):
    """Sutherland-Hodgman against the line a->b; keeps the left (or right) side"""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        sp, sq = cross(a, b, p), cross(a, b, q)
        if not keep_left: sp, sq = -sp, -sq
        if sp >= 0: out.append(p)
        if (sp >= 0) != (sq >= 0):
            t = sp / (sp - sq); out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out if len(out) >= 3 and abs(area(out)) > 1e-6 else []


def convex_minus(P, Q):
    """P minus Q (both convex, counter-clockwise) as a list of convex pieces"""
    pieces = []; rem = P
    for i in range(len(Q)):
        a, b = Q[i], Q[(i + 1) % len(Q)]
        out = clip(rem, a, b, keep_left=False)
        if out and abs(area(out)) > 1e-4: pieces.append(out)
        rem = clip(rem, a, b, keep_left=True)
        if not rem: break
    return pieces                                  # what is left in rem is P inside Q: cut away


def overlap(P, Q):
    """separating axis test for two convex polygons; True only for a real overlap (not edge contact)"""
    for poly in (P, Q):
        for i in range(len(poly)):
            a, b = poly[i], poly[(i + 1) % len(poly)]
            nx, nz = b[1] - a[1], a[0] - b[0]
            p1 = [nx * x + nz * z for x, z in P]; p2 = [nx * x + nz * z for x, z in Q]
            L = math.hypot(nx, nz) or 1
            if min(p1) >= max(p2) - 1e-3 * L or min(p2) >= max(p1) - 1e-3 * L: return False
    return True


def bbox(P): xs = [p[0] for p in P]; zs = [p[1] for p in P]; return min(xs), min(zs), max(xs), max(zs)


def simplify(P, max_n=60):
    while len(P) > max_n:                          # drop the corner that changes the area least
        k = min(range(len(P)), key=lambda i: abs(cross(P[i - 1], P[i], P[(i + 1) % len(P)])))
        P = P[:k] + P[k + 1:]
    return P


# ---------------------------------------------------------------- Roblox shapes -> convex point clouds in VOIMA metres
def shape_points(shape, size):
    """local-space corner points of a part (studs), x = right, y = up, z = back as Roblox has it"""
    sx, sy, sz = (v / 2 for v in size)
    if shape == 'Wedge':                          # slope rises toward -z (front), high edge at the back face top
        return [(-sx, -sy, -sz), (sx, -sy, -sz), (-sx, -sy, sz), (sx, -sy, sz), (-sx, sy, sz), (sx, sy, sz)]
    if shape == 'CornerWedge':
        return [(-sx, -sy, -sz), (sx, -sy, -sz), (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, -sz)]
    if shape == 'Cylinder':                       # axis along local x
        n = 24; sy = sz = min(sy, sz)             # Roblox draws the round part with the smaller of the y/z sizes
        return [(e * sx, sy * math.cos(2 * math.pi * k / n), sz * math.sin(2 * math.pi * k / n)) for e in (-1, 1) for k in range(n)]
    if shape == 'Ball':
        sx = sy = sz = min(sx, sy, sz)
        pts = [(0, sy, 0), (0, -sy, 0)]
        for i in range(1, 8):
            th = math.pi * i / 8
            for k in range(16):
                ph = 2 * math.pi * k / 16
                pts.append((sx * math.sin(th) * math.cos(ph), sy * math.cos(th), sz * math.sin(th) * math.sin(ph)))
        return pts
    return [(x, y, z) for x in (-sx, sx) for y in (-sy, sy) for z in (-sz, sz)]


def to_world(cf, p):
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    return (x + r00 * p[0] + r01 * p[1] + r02 * p[2], y + r10 * p[0] + r11 * p[1] + r12 * p[2], z + r20 * p[0] + r21 * p[1] + r22 * p[2])


def part_prisms(part, scale, step):
    """one part -> [(convex polygon (x, z) counter-clockwise, y0, y1)] in VOIMA metres. Roblox z is flipped (VOIMA is left-handed)."""
    pts = [to_world(part['cf'], p) for p in shape_points(part['shape'], part['size'])]
    pts = [(x * scale, y * scale, -z * scale) for x, y, z in pts]
    ys = [p[1] for p in pts]; y0, y1 = min(ys), max(ys)
    if y1 - y0 < 1e-4: return []
    lows = [p for p in pts if p[1] < y0 + 1e-3]; highs = [p for p in pts if p[1] > y1 - 1e-3]
    if len(lows) + len(highs) == len(pts):        # stands straight: one exact prism (if the top and bottom outlines match)
        hb = hull([(p[0], p[2]) for p in lows]); ht = hull([(p[0], p[2]) for p in highs])
        if hb and ht and abs(abs(area(hb)) - abs(area(ht))) < 1e-3 and abs(abs(area(hull(hb + ht))) - abs(area(hb))) < 1e-3:
            return [(simplify(hb), y0, y1)]
    n = max(1, min(400, math.ceil((y1 - y0) / step)))
    out = []
    for k in range(n):                            # cross-section through the middle of each layer
        a = y0 + (y1 - y0) * k / n; b = y0 + (y1 - y0) * (k + 1) / n; m = (a + b) / 2
        sec = [(p[0], p[2]) for p in pts if abs(p[1] - m) < 1e-6]
        for i in range(len(pts)):
            p = pts[i]
            for q in pts[i + 1:]:
                if (p[1] - m) * (q[1] - m) < 0:
                    t = (m - p[1]) / (q[1] - p[1]); sec.append((p[0] + (q[0] - p[0]) * t, p[2] + (q[2] - p[2]) * t))
        h = hull(sec)
        if h and abs(area(h)) > 1e-4: out.append((simplify(h), a, b))
    return out


# ---------------------------------------------------------------- materials
# Roblox material -> (family of VOIMA slabs to choose from, typical colour of the Roblox texture)
FAMILY = {
    'Plastic': (['concrete'], (0.64, 0.64, 0.65)), 'SmoothPlastic': (['concrete'], (0.64, 0.64, 0.65)),
    'Wood': (['wood', 'plank', 'logs', 'pine bark'], (0.55, 0.42, 0.28)), 'WoodPlanks': (['plank', 'wood'], (0.55, 0.42, 0.28)),
    'Brick': (['brick', 'brick tile'], (0.62, 0.38, 0.30)), 'Cobblestone': (['cobble', 'rocks', 'stone'], (0.45, 0.45, 0.43)),
    'Concrete': (['concrete', 'stone'], (0.55, 0.55, 0.53)), 'Pavement': (['concrete', 'cobble'], (0.50, 0.50, 0.50)),
    'Asphalt': (['concrete', 'ash'], (0.25, 0.25, 0.25)), 'Slate': (['stone', 'rocks'], (0.38, 0.38, 0.40)),
    'Rock': (['stone', 'rocks', 'mossy stone'], (0.45, 0.43, 0.40)), 'Basalt': (['stone', 'rocks', 'ash'], (0.25, 0.25, 0.27)),
    'Granite': (['stone dots', 'stone'], (0.55, 0.52, 0.50)), 'Marble': (['concrete', 'stone dots'], (0.80, 0.80, 0.78)),
    'Limestone': (['stone', 'concrete', 'sand'], (0.75, 0.70, 0.60)), 'Sandstone': (['sand', 'stone'], (0.80, 0.65, 0.48)),
    'Pebble': (['rocks', 'cobble'], (0.55, 0.52, 0.48)), 'Sand': (['sand'], (0.80, 0.72, 0.55)), 'Salt': (['snow', 'sand'], (0.90, 0.90, 0.88)),
    'Snow': (['snow'], (0.92, 0.94, 0.96)), 'Ice': (['ice'], (0.60, 0.75, 0.90)), 'Glacier': (['ice', 'snow'], (0.60, 0.80, 0.95)),
    'Grass': (['moss', 'bush'], (0.35, 0.55, 0.20)), 'LeafyGrass': (['moss', 'bush', 'blueberry bush'], (0.35, 0.55, 0.20)),
    'Ground': (['dirt'], (0.40, 0.30, 0.20)), 'Mud': (['dirt'], (0.30, 0.22, 0.15)),
    'Metal': (['metal'], (0.55, 0.57, 0.60)), 'DiamondPlate': (['metal'], (0.60, 0.62, 0.65)),
    'CorrodedMetal': (['metal', 'rocks'], (0.50, 0.35, 0.25)), 'Foil': (['metal'], (0.70, 0.70, 0.72)),
    'Fabric': (['fur', 'hay', 'sand'], (0.60, 0.55, 0.50)), 'Carpet': (['fur', 'sand'], (0.55, 0.40, 0.35)),
    'Leather': (['fur', 'pine bark'], (0.45, 0.30, 0.20)), 'Cardboard': (['plank', 'hay'], (0.65, 0.50, 0.35)),
    'Plaster': (['concrete'], (0.85, 0.83, 0.80)), 'Rubber': (['concrete', 'ash'], (0.20, 0.20, 0.20)),
    'CeramicTiles': (['white checker', 'brick tile'], (0.85, 0.85, 0.85)), 'ClayRoofTiles': (['brick tile', 'brick'], (0.70, 0.40, 0.30)),
    'RoofShingles': (['brick tile', 'stone'], (0.35, 0.33, 0.32)), 'CrackedLava': (['lava', 'ash'], (0.60, 0.20, 0.05)),
    'Glass': (['glass'], (0.60, 0.70, 0.75)), 'ForceField': (['glass'], (0.60, 0.70, 0.90)), 'Neon': (['white checker'], (1, 1, 1)),
    'Water': (['water'], (0.20, 0.40, 0.50)),
}
DEFAULT_GREY = (163 / 255, 162 / 255, 165 / 255)       # Roblox's default part colour: "not painted"


def dist(a, b): return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def pick_slab(material, slabs, cache):
    """same name in VOIMA (Content or a mod) -> that slab. Else the closest slab of its family, else the nearest texture colour."""
    if material in cache: return cache[material]
    usable = {n: s for n, s in slabs.items() if not s['special']}
    low = material.lower()
    spaced = ''.join(' ' + c.lower() if c.isupper() and i else c.lower() for i, c in enumerate(material))   # WoodPlanks -> wood planks
    for cand in (low, spaced, spaced.rstrip('s'), low.rstrip('s')):
        if cand in usable: cache[material] = (cand, 'same material'); return cache[material]
    fam, ref = FAMILY.get(material, ([], (0.6, 0.6, 0.6)))
    fam = [n for n in fam if n in usable]
    if fam:
        best = min(fam, key=lambda n: dist(usable[n]['color'], ref) + 0.08 * fam.index(n))
        cache[material] = (best, 'closest texture'); return cache[material]
    solids = [n for n, s in usable.items() if not s['fluid']]
    best = min(solids, key=lambda n: dist(usable[n]['color'], ref))
    cache[material] = (best, 'closest colour'); return cache[material]


def lum(c): return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def fit_color(target, tex, style=True, neon=False):
    """VOIMA shows texture x rgb x (1 + brightness); saturation = how much of the texture's own colour shows.
    Returns (r, g, b, saturation, brightness) that makes this slab look like the Roblox colour."""
    if dist(target, DEFAULT_GREY) < 0.02 and not neon: return (1.0, 1.0, 1.0, 1.0, 0.0)    # unpainted part: natural texture
    if dist(target, tex) < 0.08 and not neon: return (1.0, 1.0, 1.0, 1.0, 0.0)            # already the texture's colour
    if style:                                                                                 # VOIMA is earthy: calm the loud colours
        h, s, v = colorsys.rgb_to_hsv(*target)
        target = colorsys.hsv_to_rgb(h, s * 0.85, min(0.95, max(0.06, v)))
    sat = 0.35
    g = lum(tex); eff = [g + (t - g) * sat for t in tex]
    rgb = [min(4.0, c / max(0.04, e)) for c, e in zip(target, eff)]
    m = max(rgb); bright = 0.0
    if m > 1: rgb = [c / m for c in rgb]; bright = min(1.5, m - 1)
    if neon: bright = max(bright, 2.0)
    return (round(rgb[0], 4), round(rgb[1], 4), round(rgb[2], 4), sat, round(bright, 3))


# ---------------------------------------------------------------- one part -> slab and VOIMA colour
def match_part(p, slabs_cat, cache, style=True):
    """(slab name, how it was picked, VOIMA colour (r, g, b, saturation, brightness)); name None = skip, how = why.
    Used by the converter and by the Studio plugin's "VOIMA look" preview, so both always agree."""
    mat = p.get('material', 'Plastic'); tr = p.get('transparency', 0)
    slab = p.get('slab')
    if not slab and str(p.get('variant', '')).lower() in slabs_cat:      # a MaterialVariant named after a VOIMA slab
        slab = p['variant']
    if slab:
        name = slab.lower()
        if name not in slabs_cat: return None, f"unknown slab '{name}'", None
        how = 'chosen'
    else:
        if tr >= 0.95: return None, 'invisible parts', None
        m = 'Glass' if (tr >= 0.2 and mat not in ('Water', 'ForceField')) else mat
        name, how = pick_slab(m, slabs_cat, cache)
    tex = slabs_cat[name]['color']
    col = (1.0, 1.0, 1.0, 1.0, 0.0) if p.get('natural') else fit_color(tuple(p['color']), tex, style, neon=(mat == 'Neon'))
    return name, how, col


# ---------------------------------------------------------------- the whole map
def convert(payload, slabs_cat, cards_cat):
    """payload from the Roblox plugin -> (slab dicts, card dicts, player index, report)"""
    o = payload.get('options', {})
    scale = float(o.get('scale', 0.4)); step = float(o.get('step', 0.25)); style = o.get('style', True)
    fix = o.get('fix_overlaps', True)
    rep = {'holes': 0, 'parts': 0, 'slabs': 0, 'cards': 0, 'skipped': {}, 'materials': {}, 'carved': 0, 'unknown_cards': []}
    cache = {}; items = []
    # floor of the build -> y = 0, centre -> x = z = 0 (offset a little: cards at exactly 0,0 are dropped by the game)
    allpts = [to_world(p['cf'], c) for p in payload['parts'] for c in shape_points(p['shape'], p['size'])]
    if not allpts and not payload.get('cards'): raise ValueError('Nothing to convert')
    if allpts:
        ox = (min(p[0] for p in allpts) + max(p[0] for p in allpts)) / 2; oz = (min(p[2] for p in allpts) + max(p[2] for p in allpts)) / 2
        oy = min(p[1] for p in allpts)
    else:
        c0 = payload['cards'][0]; ox, oy, oz = c0['x'], c0['y'], c0['z']
    negatives = {}
    for p in payload['parts']:
        cf = list(p['cf']); cf[0] -= ox; cf[1] -= oy; cf[2] -= oz; p = dict(p, cf=cf)
        if p.get('negative'):                     # a negated part inside a union: a hole, not a slab
            negatives.setdefault(p.get('group'), []).extend({'poly': poly, 'y0': y0, 'y1': y1} for poly, y0, y1 in part_prisms(p, scale, step))
            continue
        rep['parts'] += 1
        mat = p.get('material', 'Plastic')
        name, how, col = match_part(p, slabs_cat, cache, style)
        if not name: rep['skipped'][how] = rep['skipped'].get(how, 0) + 1; continue
        rep['materials'][f'{mat} -> {name}'] = how
        for poly, y0, y1 in part_prisms(p, scale, step):
            items.append({'type': name, 'poly': poly, 'y0': y0, 'y1': y1, 'color': col, 'group': p.get('group'),
                          'vol': abs(area(poly)) * (y1 - y0), 'fluid': slabs_cat[name]['fluid']})
    if negatives:
        kept = []
        for it in items:
            hits = [q for q in negatives.get(it['group'], ()) if q['y0'] < it['y1'] - 1e-3 and q['y1'] > it['y0'] + 1e-3 and overlap(it['poly'], q['poly'])]
            if hits: rep['holes'] += 1; kept += cut(it, hits)
            else: kept.append(it)
        items = kept
    if fix: items = carve(items, rep)
    S = []
    for it in items:
        cw = it['poly'][::-1]                     # VOIMA stores corners clockwise
        S.append({'type': it['type'], 'corners': [(float(x), float(z)) for x, z in cw], 'y0': round(it['y0'], 4), 'y1': round(it['y1'], 4), 'color': it['color']})
    C = []
    for c in payload.get('cards', []):
        t = c['type'].lower()
        if t not in cards_cat: rep['unknown_cards'].append(c['type']); continue
        x, y, z = (c['x'] - ox) * scale, (c['y'] - oy) * scale, -(c['z'] - oz) * scale
        if abs(x) < 0.01 and abs(z) < 0.01: x += 0.05
        C.append({'type': t, 'x': x, 'y': y, 'z': z, 'view': c.get('view', 0.0), 'health': 1.0})
    sp = payload.get('spawn')
    player = 'bear'                                # the player is always the bear
    if sp: x, y, z = (sp[0] - ox) * scale, (sp[1] - oy) * scale, -(sp[2] - oz) * scale
    else:
        x, z = 0.05, 0.0
        y = max([s['y1'] for s in S if (bbox_c := bbox(s['corners'])) and bbox_c[0] <= 0 <= bbox_c[2] and bbox_c[1] <= 0 <= bbox_c[3]] or [0.0])
    if abs(x) < 0.01 and abs(z) < 0.01: x += 0.05
    C.append({'type': player, 'x': x, 'y': y + 0.05, 'z': z, 'view': float(payload.get('spawn_view', 0.0)), 'health': 1.0})
    rep['slabs'] = len(S); rep['cards'] = len(C) - 1
    enemies = sum(1 for c in C[:-1] if cards_cat[c['type']].get('aggressive') and cards_cat[c['type']]['type'] == 'Animal')
    rep['enemies'] = enemies
    if enemies and o.get('peaceful', True):
        rep.setdefault('warnings', []).append(f'{enemies} enemies placed but "Peaceful creatures" is on, so they will not attack')
    return S, C, len(C) - 1, rep


def cut(it, hits):
    """one prism minus a set of prisms: split into height bands at their tops and bottoms, cut each band around them"""
    cuts = sorted({it['y0'], it['y1']} | {y for q in hits for y in (q['y0'], q['y1']) if it['y0'] < y < it['y1']})
    new = []
    for a, b in zip(cuts, cuts[1:]):
        if b - a < 0.02: continue
        pieces = [it['poly']]
        for q in hits:
            if q['y0'] < b - 1e-3 and q['y1'] > a + 1e-3:
                pieces = [r for P in pieces for r in (convex_minus(P, q['poly']) if overlap(P, q['poly']) else [P])]
        new += [dict(it, poly=P, y0=a, y1=b) for P in pieces if abs(area(P)) > 0.0025]
    return new


def carve(items, rep):
    """remove overlaps: bigger pieces stay whole; each smaller piece is split into height bands and cut around them"""
    items.sort(key=lambda it: (it['fluid'], -it['vol']))         # solids before fluids, big before small: a part sunk into
                                                                 # the floor just loses its buried bit, and the floor stays whole
    placed = []; grid = {}; G = 4.0

    def cells(bb):
        for i in range(int(math.floor(bb[0] / G)), int(math.floor(bb[2] / G)) + 1):
            for j in range(int(math.floor(bb[1] / G)), int(math.floor(bb[3] / G)) + 1): yield (i, j)

    for it in items:
        bb = bbox(it['poly']); seen = set(); hits = []
        for c in cells(bb):
            for k in grid.get(c, ()):
                if k in seen: continue
                seen.add(k); q = placed[k]
                if q['y0'] < it['y1'] - 1e-3 and q['y1'] > it['y0'] + 1e-3:
                    qb = q['bb']
                    if qb[0] < bb[2] and qb[2] > bb[0] and qb[1] < bb[3] and qb[3] > bb[1] and overlap(it['poly'], q['poly']): hits.append(q)
        if hits: rep['carved'] += 1; new = cut(it, hits)
        else: new = [it]
        for n in new:
            n['bb'] = bbox(n['poly']); placed.append(n)
            for c in cells(n['bb']): grid.setdefault(c, []).append(len(placed) - 1)
    return placed
