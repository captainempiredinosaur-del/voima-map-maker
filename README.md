# VOIMA Map Maker

**Build maps in Roblox Studio, play them in VOIMA.**

VOIMA Map Maker is a Roblox Studio plugin plus a small helper program (the **VOIMA Bridge**) that runs on your PC. You build with normal Roblox parts. One click turns the build into a real VOIMA world (`world.save`) that shows up in VOIMA's world list.

- **Parts become VOIMA slabs.**
  - Blocks, wedges, corner wedges, cylinders and balls all convert.
  - Upright parts become exact slabs; tilted parts become neat steps.
  - Unions keep their holes: a negated door in a wall becomes a real doorway.
  - Overlapping parts are trimmed to fit, because VOIMA slabs can't overlap.
- **Materials match automatically.**
  - A Roblox material with the same name as a VOIMA slab uses that slab (Brick → brick, Glass → glass, your mods' slabs too).
  - Anything else gets the closest VOIMA texture.
- **Colours fit VOIMA.**
  - Unpainted parts keep VOIMA's own texture colours.
  - Painted parts are tinted to match, calmed slightly to suit VOIMA's look.
  - Neon glows.
- **VOIMA look in Studio.** See your build with VOIMA's real slab textures, pixel-crisp and tiled the way VOIMA tiles them. It's an overlay: your parts stay as they are, and nothing is uploaded or saved into the place.
- **Objects and enemies.**
  - Place any VOIMA object (trees, lamps, furniture) or creature from your own VOIMA files, mods included.
  - Every object gets full health.
  - Drop enemy groups with one click.
- **Player start.** Mark where you begin as the bear, and which way you face.

Everything runs locally. The bridge only listens on `127.0.0.1` (your own PC). It reads your VOIMA files and only writes new world folders it made itself, backing up the old version before it replaces one. **No VOIMA files are included in this repository.** Textures and objects are read from your own VOIMA install.

## Requirements
- Windows 10 or 11
- VOIMA, started at least once (so `%APPDATA%\.VOIMA` exists)
- [Roblox Studio](https://create.roblox.com/)
- Python 3.10 or newer. The installer offers to install it for you if it's missing. No extra Python packages are needed.

## Install (easy way)
1. **Download** this repository: the green **Code** button, then **Download ZIP**. Unzip it anywhere.
2. **Double-click `install.bat`.**
   - It installs the bridge to `%LOCALAPPDATA%\VOIMA Map Maker`.
   - It installs the Roblox Studio plugin automatically.
   - It makes the bridge start with Windows (hidden, no window), and starts it now.
   - It needs no admin rights.
3. **Open (or restart) Roblox Studio.** Go to the **Plugins** tab and click **Map Maker**.
   - The first time, Studio asks whether the plugin may connect to `127.0.0.1`. Choose **Allow**.
4. The panel should say **Connected: N slabs, N objects**. You're ready.

To update, download the new version and run `install.bat` again. Your settings and worlds are kept. The bridge also keeps the Studio plugin up to date each time it starts.

To uninstall, run `uninstall.bat` (or Start menu → VOIMA Map Maker → Uninstall). Your VOIMA worlds are not touched.

## Use it
| Tab | What it does |
|---|---|
| **Convert** | Name your world and press **Convert to VOIMA world**. **Check map** shows the report without writing anything. Restart VOIMA to see the new world. |
| **Slabs** | **VOIMA look**: show VOIMA's textures on the whole map or the selection, and **Remove** to take them off. Click a slab to use it on the selected parts. With nothing selected, it drops a new slab where you look. |
| **Objects** | Search all VOIMA objects (trees, lamps, furniture, creatures, mods) and click one to place it where you look. |
| **Spawns** | **Place player start** (you play as the bear) and click enemies to place them, one or a group at a time. |

Full guide: [docs/guide.md](docs/guide.md).

### Good to know
- **Scale:** 0.4 m per stud by default, so a Roblox avatar is about the size of VOIMA's bear (doors about 7 studs tall).
- **Several VOIMA universes:** the bridge picks the one you played most recently. You can choose another in `config.json` in the install folder, as `{"universe": "Name"}`.
- **Not converted:** Terrain, characters with a Humanoid, and scripts. MeshParts and Intersects become their bounding box.
- **Peaceful:** VOIMA's "peaceful beings" setting stops every creature from attacking. Placing an enemy turns it off, and the report warns you if it's on.

## Troubleshooting
- **"The VOIMA Bridge isn't running":** start it from Start menu → VOIMA Map Maker → **Start VOIMA Bridge**, then press **Refresh** in the plugin. Use **VOIMA Bridge (with window)** to see what it says. The log is in `%TEMP%\voima_work\bridge.log`.
- **No Map Maker button in Studio:** restart Studio. Check that `%LOCALAPPDATA%\Roblox\Plugins\VOIMA Map Maker.lua` exists (run `install.bat` again if not).
- **HTTP requests are blocked:** in Studio, open Plugins → Manage Plugins and allow VOIMA Map Maker to access `127.0.0.1`.
- **"VOIMA is open":** close VOIMA before replacing a world with the same name, or export under a new name.
- **A world name is taken by a world you made in VOIMA:** the Map Maker never overwrites worlds it didn't make. Pick another name.

## How it works
```
Roblox Studio plugin  --HTTP on 127.0.0.1:7878-->  VOIMA Bridge (Python)  --reads-->  %APPDATA%\.VOIMA\Universes\<universe>\Content + Mods
  (parts, unions, markers)                          (slicing, matching, colours)  --writes-->  ...\Worlds\<your map>\world.save
```
- `bridge/bridge.py`: the local server.
- `bridge/convert.py`: geometry (convex slicing, union holes, overlap cutting), materials and colours.
- `bridge/voima_catalog.py`: reads slabs, objects and textures (with its own PNG reader).
- `bridge/voima_world.py`: writes the `world.save` format.
- `plugin/VOIMA Map Maker.lua`: the Studio plugin.

## License
MIT. See [LICENSE](LICENSE). VOIMA and Roblox are trademarks of their owners; this is a fan-made tool and is not affiliated with either.
