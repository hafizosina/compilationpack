# Module 13 — World Generator: handoff

A world in three map levels, each with its own zoom range, and transitions between them that hide loading.
The scene is `world.tscn` (`world_view.gd`). L3 is finished; L2 and L1 are still placeholder chunks.

## Levels

| Level | Cell | What | Drawn |
|-------|------|------|-------|
| L3 | 16,384 m (128 × 128 L2 cells) | the world map, 256 × 128 cells, made whole (`WorldMap`) | one sheet on a table |
| L2 | 128 m (128 × 128 L1 cells) | streamed in 64-cell chunks | placeholder: parent colour, checker |
| L1 | 1 m (module 10's cell) | streamed in 32-cell chunks | placeholder: parent colour, checker |

- **Frames.** The world is about 4,200 × 2,100 km, past what float32 positions hold to the metre, so each
  level draws in its own frame: 32 px a cell round an anchor cell (`_anchor[level]`) that moves to the
  camera once it strays `REANCHOR_PX` from it (`_reanchor`). Positions crossing levels go through 64-bit
  floats (`_cells_of`).
- **Chunks.** `WorldChunkStore` (one per L2 and L1): chunks round the view are planned on
  `WorkerThreadPool` nearest first (`MAX_JOBS`, more while loading), drawn as one sprite each, nodes freed past
  `KEEP`, plans kept up to `CAP` (least recently used dropped). Texture arrays and textures are made on the
  main thread only: a worker making one could deadlock with the renderer (seen 2026-11-24).
- **East-west wrap** is dropped on L3 (it is one sheet). The chunk stores still wrap x; harmless for now, to
  go when L2 is generated for real.

## L3, the world map (`ecs/world_map.gd`)

`WorldMap.make(seed)`, about 350 ms, read-only after (workers read it for chunk colours).

- **Height:** Perlin fBm sampled on a cylinder (`_at`). Sea below `SEA` 0.5, mountains from 0.74, snow from 0.84.
- **Heat:** latitude (cold at both poles), bent ±0.4 by a slow two-octave Perlin so the climate bands wave,
  minus height above the sea.
- **Humidity:** a broad three-octave Perlin, wetter by the sea and drier up to `INLAND` cells inland, plus
  `WETTER` next to a river or lake. Heat and humidity are each smoothed twice (`_blur`), so biomes come in
  broad regions without specks.
- **Biomes** (`BIOMES`, `biome_at`): heat × humidity, 11 of them: ice cap, tundra, wet tundra, cold
  steppe, taiga, dry grassland, grassland, temperate forest, desert, savanna, tropical forest. Sea, sea
  ice, lakes, rivers, mountains and snow are `WATERS`.
- **Water:** Priority-Flood from the sea and the map's edge (with a tiny rise on flats) gives each cell its
  filled level; every land cell drains to its lowest neighbour on that surface; rain (0.2 + humidity) is
  added up from the last cell filled back. Lakes are land `LAKE_DEPTH` under its filled level, in pieces of at
  least `LAKE_CELLS`. Rivers are cells with `RIVER_FLOW` or more that aren't frozen, traced from each head to
  the sea, a lake, ice or a bigger river, nudged and smoothed, widening with flow (`river_width`).
  About 80 rivers a world. This is what L2 will read to draw rivers that match across its chunks.
- **Drawing:** `art/l3_map.gdshader` reads `fields_image()` (R height, G heat, B humidity, A lake)
  smoothly, so every edge is a curve; biome colours from the `table()` lookup; flat, no shading; thin sea-blue shore and brown ridge lines (never black); everything faded onto daluang (bark paper,
  fibres). Rivers are `Line2D`s over it.
- **Modes:** biome (default), heat, height, humidity (`MODES`, keys 1–4 or the slips bottom right), each a
  banded ramp. The key bottom left (`map_key.gd`) and the slips (`mode_toggle.gd`) are drawn, not themed.
- **The sheet:** `art/table.gdshader` draws, round the map, the sheet's margin with a tumpal border (batik
  triangles, indigo and red ochre), a torn edge, its shadow and a teak table. Brass Surya Majapahit weights
  (`Global/Asset/Map/surya.png`, `make_surya.py`) sit on the corners. The camera stays over the table.

## Zoom and transitions (`world_view.gd`)

- Standard zoom: L3 fits the sheet; L2 6 px a cell; L1 16 px a cell. `RANGES`: L3 0.7–5×, L2 and L1 0.7–1.5×.
- At a limit, `HOLD_NOTCHES` wheel notches only hold (5 on L3, 2 on L2 and L1), each filling a segment of the
  hold mark in the screen's middle (`hold_mark.gd`: a daluang disc naming the next level); the next changes level (a pause
  of `HOLD_GAP` resets). A pinch past a limit by `PINCH_PAST` (1.6 on L3, 1.35 below) does the same.
- A change runs three phases: closing (the camera keeps zooming on the point while a cover shuts), loading
  (the new level is set up behind it and waits for the chunks in view, at most `LOAD_CAP`), opening.
  L3–L2 uses `art/clouds.gdshader` (clouds rising out of Perlin noise read as a height map until they fill the
  screen), L2–L1 `art/iris.gdshader` (an ink-rimmed circle on the point).
- Touch: one finger pans, two pinch. A left-button drag pans too, because the project turns mouse drags
  into touches (`emulate_touch_from_mouse`); there is no separate mouse pan, or it would pan twice.

## Tests

`tests/world_test.tscn` (18 checks, in CI): same seed same world, poles frozen and the middle warm, every
land cell drains downhill to the sea or the edge, rivers end in water, ice or another river, no lake under
`LAKE_CELLS`, the chunk store's order, wrap and trim, a chunk shows its parent's colour.

## The copied module 12 code

`ecs/world_terrain_*.gd`, the town pipeline, `defs/` and `tests/terrain_test.*` are module 12 copied at
`1b6fa66` with classes renamed `World*`, then grown to regions refined from an older 64 m L3. Their viewer,
`generator.tscn`, was removed once `world.tscn` replaced it. The new world view doesn't use them; they are
kept for the town pipeline and L2/L1 generation to draw from.

## Left to do

- **L2 for real:** each chunk refines its L3 cell (biome edges wandering by noise, rivers and lakes from
  `WorldMap`'s drainage), with L2 ground art per biome.
- **L1 for real:** small streams, trees and rocks by biome; then towns, buildings and people.
- L3 is made on the main thread at start (~350 ms).
