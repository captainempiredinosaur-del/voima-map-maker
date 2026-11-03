"""VOIMA Bridge: a tiny local server (127.0.0.1:7878, this PC only) that the Roblox Studio plugin "VOIMA Map Maker" talks to.
It lists the slabs and objects of your VOIMA universe, hands Studio the slab textures, and turns a Roblox build into a
new VOIMA world (world.save). It only ever writes world folders it made itself (details.txt Creator = VOIMA Map Maker);
it never changes Content, Mods or anyone's own worlds."""
import json, os, sys, re, time, shutil, subprocess, uuid, traceback
from urllib.parse import urlparse, parse_qs
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(os.environ.get('TEMP', HERE), 'voima_work')
os.makedirs(WORK, exist_ok=True)
if sys.stdout is None:                            # started hidden (pythonw at Windows start-up): log to a file, errors included
    sys.stdout = sys.stderr = open(os.path.join(WORK, 'bridge.log'), 'a', encoding='utf-8', buffering=1)
sys.path.insert(0, HERE)
import voima_catalog, convert, voima_world

VERSION = '1.1.0'
PORT = 7878
CREATOR = 'VOIMA Map Maker'
BACKUPS = os.path.join(WORK, 'world_backups')
CONFIG = os.path.join(HERE, 'config.json')
PLUGIN = next((p for p in (os.path.join(HERE, 'VOIMA Map Maker.lua'), os.path.join(HERE, '..', 'plugin', 'VOIMA Map Maker.lua'))
               if os.path.exists(p)), os.path.join(HERE, 'VOIMA Map Maker.lua'))   # installed copy, or running from the repo
ROBLOX_PLUGINS = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Roblox', 'Plugins')
JOBS = {}


def log(*a): print(time.strftime('%H:%M:%S'), *a, flush=True)


def config():
    try: return json.load(open(CONFIG, encoding='utf-8'))
    except (OSError, ValueError): return {}


def save_config(**kw):
    c = config(); c.update(kw)
    json.dump(c, open(CONFIG, 'w', encoding='utf-8'), indent=2)


def worlds_dir(): return os.path.join(voima_catalog.UNIVERSE, 'Worlds')


def set_universe(name=None):
    name = voima_catalog.use_universe(name or config().get('universe'))
    voima_world.UNIVERSE = voima_catalog.UNIVERSE; voima_world._MAXH.clear()
    return name


def install_plugin():
    """keep the Studio plugin in Roblox's Plugins folder the same as the one shipped with this bridge"""
    try:
        if not os.path.exists(PLUGIN): return 'no plugin file next to the bridge'
        os.makedirs(ROBLOX_PLUGINS, exist_ok=True)
        dst = os.path.join(ROBLOX_PLUGINS, 'VOIMA Map Maker.lua')
        new = open(PLUGIN, 'rb').read()
        if os.path.exists(dst) and open(dst, 'rb').read() == new: return 'plugin up to date'
        open(dst, 'wb').write(new)
        return 'plugin installed (restart Roblox Studio to load it)'
    except OSError as e:
        return f'could not install the plugin: {e}'


def voima_running():
    try:
        out = subprocess.run(['tasklist', '/FO', 'CSV', '/NH'], capture_output=True, text=True, timeout=10,
                             creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)).stdout.lower()
        return '"voima.exe"' in out
    except Exception: return False


def newest_mtime():
    m = 0
    for root in (os.path.join(voima_catalog.UNIVERSE, 'Content'), os.path.join(voima_catalog.UNIVERSE, 'Mods')):
        for dp, _, fs in os.walk(root):
            for f in fs:
                if f.endswith('.txt'):
                    try: m = max(m, os.path.getmtime(os.path.join(dp, f)))
                    except OSError: pass
    return m


def get_catalog(refresh=False):
    """the catalog is slow to build (it reads every texture), so it is cached on disk until a .txt in Content/Mods changes"""
    uname = os.path.basename(voima_catalog.UNIVERSE)
    cache = os.path.join(WORK, f'catalog_{re.sub(r"[^A-Za-z0-9_-]", "_", uname)}.json')
    stamp = f'{newest_mtime()}-v6'                 # bump the -vN when the catalog code changes
    if not refresh and voima_catalog._cache.get('stamp') != stamp and os.path.exists(cache):
        try:
            c = json.load(open(cache, encoding='utf-8'))
            if c.get('stamp') == stamp: voima_catalog._cache.clear(); voima_catalog._cache.update(slabs=c['slabs'], cards=c['cards'], stamp=stamp)
        except Exception: pass
    if refresh or voima_catalog._cache.get('stamp') != stamp:
        log(f'reading the VOIMA universe "{uname}" ...')
        c = voima_catalog.catalog(refresh=True); c['stamp'] = stamp
        json.dump({'stamp': stamp, 'slabs': c['slabs'], 'cards': c['cards']}, open(cache, 'w', encoding='utf-8'))
    return voima_catalog._cache


def safe_name(n):
    n = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '', str(n)).strip().strip('.')
    return n[:60] or 'Roblox Map'


def ours(folder):
    try: return f'Creator = {CREATOR}' in open(os.path.join(folder, 'details.txt'), encoding='utf-8').read()
    except OSError: return False


def finish(job):
    cat = get_catalog()
    t = time.time()
    S, C, player, rep = convert.convert(job, cat['slabs'], cat['cards'])
    if job.get('dry'):                            # "Check map": the report only, nothing written
        rep['seconds'] = round(time.time() - t, 2); return rep
    name = safe_name(job.get('world', 'Roblox Map')); folder = os.path.join(worlds_dir(), name)
    if os.path.exists(folder):
        if not ours(folder):
            raise ValueError(f'A VOIMA world called "{name}" already exists and was not made by the Map Maker. Pick another name.')
        if voima_running():
            raise ValueError(f'VOIMA is open. Close it before replacing "{name}", or export under a new name.')
        dst = os.path.join(BACKUPS, f'{name} {time.strftime("%Y-%m-%d %H-%M-%S")}')
        shutil.copytree(folder, dst); shutil.rmtree(folder)
        rep['backup'] = dst
    o = job.get('options', {})
    voima_world.write_world(folder, S, C, player_index=player, time_of_day=float(o.get('time', 0.35)),
                            spawn_cards=bool(o.get('spawning', False)), peaceful=bool(o.get('peaceful', True)))
    open(os.path.join(folder, 'details.txt'), 'w', encoding='utf-8', newline='\n').write(
        f'Play Time = 0\nCreator = {CREATOR}\nLast Played = {time.strftime("%Y %m %d %H %M %S")}\nSurvival = no\n')
    rep.update(world=name, folder=folder, seconds=round(time.time() - t, 2),
               size_mb=round(os.path.getsize(os.path.join(folder, 'world.save')) / 1e6, 2), voima_running=voima_running())
    log(f'wrote "{name}": {rep["slabs"]} slabs, {rep["cards"]} objects from {rep["parts"]} parts in {rep["seconds"]} s')
    return rep


def preview(items, style=True):
    """the VOIMA look for each distinct part look: which slab, and the colour Studio should tint it"""
    cat = get_catalog(); cache = {}; out = []
    for p in items:
        name, how, col = convert.match_part(p, cat['slabs'], cache, style)
        out.append({'slab': name, 'how': how, 'color': col})
    return out


class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(b)))
        self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        try:
            url = urlparse(self.path); q = {k: v[0] for k, v in parse_qs(url.query).items()}
            if url.path == '/ping':
                return self.send(200, {'ok': True, 'version': VERSION, 'universe': os.path.basename(voima_catalog.UNIVERSE),
                                       'universes': voima_catalog.universes(), 'voima_running': voima_running()})
            if url.path == '/catalog':
                c = get_catalog(refresh='refresh' in q)
                return self.send(200, {'slabs': sorted(c['slabs'].values(), key=lambda s: (s['special'], s['source'] != 'VOIMA', s['name'])),
                                       'cards': sorted(c['cards'].values(), key=lambda s: (s['type'], s['name']))})
            if url.path == '/texture':                # raw RGBA pixels for an EditableImage in Studio
                get_catalog()
                if q.get('name') not in voima_catalog._cache['slabs']: return self.send(404, {'error': 'no such slab'})
                w, h, data, tile = voima_catalog.slab_texture(q['name'], float(q.get('sat', 1)), max(16, min(1024, int(q.get('max', 1024)))))
                self.send_response(200); self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Length', str(len(data))); self.send_header('X-Width', str(w)); self.send_header('X-Height', str(h))
                self.send_header('X-Tile', str(tile)); self.end_headers(); self.wfile.write(data); return
            if url.path == '/worlds':
                wd = worlds_dir()
                ws = sorted(d for d in os.listdir(wd) if os.path.exists(os.path.join(wd, d, 'world.save')))
                return self.send(200, {'worlds': [{'name': w, 'ours': ours(os.path.join(wd, w))} for w in ws]})
            self.send(404, {'error': 'no such page'})
        except Exception as e:
            traceback.print_exc(); self.send(500, {'error': str(e)})

    def do_POST(self):
        try:
            body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
            if self.path == '/export/begin':
                jid = uuid.uuid4().hex[:8]
                JOBS[jid] = dict(body, parts=[], cards=[]); return self.send(200, {'id': jid})
            if self.path == '/export/chunk':
                j = JOBS[body['id']]; j['parts'] += body.get('parts', []); j['cards'] += body.get('cards', [])
                return self.send(200, {'parts': len(j['parts']), 'cards': len(j['cards'])})
            if self.path == '/export/finish':
                j = JOBS.pop(body['id'])
                return self.send(200, finish(j))
            if self.path == '/preview':
                return self.send(200, {'looks': preview(body.get('items', []), body.get('style', True))})
            if self.path == '/universe':
                name = set_universe(body.get('name')); save_config(universe=name)
                get_catalog(); log(f'now using universe "{name}"')
                return self.send(200, {'universe': name})
            self.send(404, {'error': 'no such page'})
        except ValueError as e:
            self.send(400, {'error': str(e)})
        except Exception as e:
            traceback.print_exc(); self.send(500, {'error': f'{type(e).__name__}: {e}'})


if __name__ == '__main__':
    try:
        server = ThreadingHTTPServer(('127.0.0.1', PORT), H)
    except OSError:
        log('VOIMA Bridge is already running.'); sys.exit(0)
    log(f'VOIMA Bridge {VERSION}: {install_plugin()}')
    try:
        log(f'universe: {set_universe()} ({len(voima_catalog.universes())} found)')
        get_catalog()
    except FileNotFoundError as e:
        log(str(e))
    log(f'ready on http://127.0.0.1:{PORT}. Leave this running while you use VOIMA Map Maker in Roblox Studio.')
    server.serve_forever()
