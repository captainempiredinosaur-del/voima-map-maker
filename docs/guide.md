# VOIMA Map Maker: guide

Build in Roblox Studio, click once, and play the map in VOIMA. Setup is in the [README](../README.md).

## Convert tab
- **World name**: the VOIMA world it makes.
  - If a world with that name was made by the Map Maker, the old one is backed up to `%TEMP%\voima_work\world_backups` first. VOIMA must be closed to replace it.
  - Worlds made any other way are never touched; pick another name.
- **Metres per stud**: 0.4 makes a Roblox avatar about the size of VOIMA's bear (5 studs ≈ 2 m).
- **Step height for slopes**: tilted parts become steps this tall.
- **Time of day**: 0 to 1, where 0.35 is morning.
- **Only the selected things**: converts just the selection. The player start always counts.
- **Fit colours to VOIMA's look**: calms loud colours a little.
- **Cut away overlapping parts**: keep this on. VOIMA slabs can't overlap.
- **Peaceful creatures**: VOIMA's "peaceful beings". When it's on, nothing attacks.
- **Creatures spawn naturally**: VOIMA's own spawning, on top of what you placed.
- **Convert to VOIMA world** makes the world. **Check map** shows the same report without writing anything.
- Restart VOIMA to see a new world in the menu.

## What becomes what
- **Parts → slabs.**
  - Works for blocks, wedges, corner wedges, cylinders and balls.
  - Upright parts are exact. Tilted parts become stairs of layers.
- **Unions** are split back into their parts. Negated parts cut real holes.
- **MeshParts and Intersects** become their bounding box. The report counts them.
- **Overlaps**: big parts stay whole, and smaller parts lose only the bit buried inside.
- **Materials**, in this order:
  1. A slab you chose in the Slabs tab.
  2. A MaterialVariant named after a VOIMA slab.
  3. A VOIMA slab with the material's name.
  4. The closest VOIMA texture.
  The report lists every match.
- **Colours**:
  - Unpainted parts (default grey) keep the slab's own texture colours.
  - Painted parts get the tint that makes the VOIMA texture show that colour.
  - Neon glows. See-through parts become glass. Invisible parts are skipped.
- **Objects**: markers from the Objects or Spawns tab, and any Model named like a VOIMA object (for example a model called "Adult Pine"), become that object at full health.
- **Where you start**: the player start marker. Without one, a SpawnLocation. Without either, the middle of the map.
- **Not converted**: Terrain, characters with a Humanoid, scripts.

## Slabs tab
- **VOIMA look**: **Whole map** or **Selected** puts VOIMA's real textures on your parts.
  - Each texture is pixel-crisp, mirrored and tiled the way VOIMA tiles it, and tinted with the colour the converter will use. So what you see is close to what you'll get.
  - It's an overlay: your parts' own materials and colours don't change, and it isn't saved or published with the place.
  - It comes back by itself when you reopen the place, as long as the bridge is running.
  - **Remove** takes it off.
- **Slab buttons** (with real texture thumbnails): select parts and click a slab to use it. If nothing is selected, a new 8×1×8 slab appears where you're looking.

## Objects tab
Search VOIMA's objects (trees, lamps, furniture, creatures, your mods) and click one to place a marker where you're looking. The marker has the object's real size, and its feet are at its bottom. Rotate it to turn the object; its **▲ FRONT** side is the way it faces.

## Spawns tab
- **★ Place player start where I look**: a blue, bear-sized marker where you'll start, facing the way your camera faces. There's only one start, so placing it again moves it.
- **Enemies**: creatures that attack you are listed first. Click one to place it where you look.
  - **How many per click** and **Spread** drop a group, each standing on the ground and facing a random way.
  - Enemy markers go in the `VOIMA Enemies` folder.
- Placing an attacking enemy switches **Peaceful creatures** off.

## The bridge
- It starts with Windows (hidden).
- Start menu → VOIMA Map Maker has **Start VOIMA Bridge**, **VOIMA Bridge (with window)** to watch what it does, and **Uninstall**.
- Log: `%TEMP%\voima_work\bridge.log`.
- To choose a universe, edit `%LOCALAPPDATA%\VOIMA Map Maker\config.json`: `{"universe": "Name"}`. Otherwise it uses the universe you played most recently.
- It only listens on `127.0.0.1`, so nothing outside your PC can reach it.
