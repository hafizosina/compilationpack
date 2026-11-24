# Module 13 — World Generator: handoff

A world in three map levels, each with a locked zoom range and an animated transition between them.

## Where it came from

Copied from module 12 at commit `1b6fa66` (main): `ecs/`, `defs/`, `generator_view.gd`, `generator.tscn`
and `tests/terrain_test.*`. Module 12 is untouched. Godot's class registry is global, so all 24
`class_name`s were renamed `Ecs*` → `World*` (`WorldTerrainGenerator`, `WorldLandDef`, `WorldTerrainChunks`,
`WorldSettlementSite`, …), their files `ecs_*.gd` → `world_*.gd`, and every copied `.uid` and `uid=` header
was dropped so the editor made new ones. Module 10's `Ecs*` classes are shared and unchanged.

## Levels

| Level | Cell | Map | Drawn at | Standard zoom |
|-------|------|-----|----------|---------------|
| L3 | 64 m | the world, `defs/lands/world.tres`, 128×96, river to the sea | scale 1 | 1 |
| L2 | 8 m | a region, `region.tres`, 256×192 = a 32×24 L3 window refined 8× | 1/8 | 8 |
| L1 | 1 m | chunks (32/64/128) refined 8× from their region | 1/64 | 64 |

- The world is planned with `plan()`. Each region is `refine()`d from its L3 window, the same call as L2→L1,
  so `WorldTerrainCheck.follows` holds L3→L2 and L2→L1 (the terrain test checks both).
- `refine()` now hands back the river lines it drew, in its own cells, so a region's L1 redraws them. It also
  gives a region its own deposits when the world has none, and with `border` it returns `outer_kinds` so
  regions draw without a seam between them.
- Regions stream like chunks: `WorldRegions` (keyed by region cell, PLAN then DRAW, on workers, kept round
  the view, dropped far away; plans stay). Chunks are one `WorldTerrainChunks` over the whole world, and
  a chunk starts only once its region is planned.

## Zoom and transitions (`generator_view.gd`)

- `STANDARD = [0.25, 2.0, 32.0]` (L3's fits the whole world on screen; L1's shows 16 px a cell, as module 12) and `RANGE = Vector2(0.7, 1.5)`. `_zoom_at` keeps the zoom between
  `STANDARD[_level] * RANGE.x` and `STANDARD[_level] * RANGE.y`. The camera allows 0.15 to 48.
- A wheel notch past the top goes down a level, and past the bottom up a level. L3 has no up and L1 no down.
- `_go_to_level` runs one tween of `TRANSITION` (0.45 s), sine in-out. The zoom eases (log-lerp) to the new
  standard, and the world point under the mouse keeps its screen point. The finer of the two levels fades
  in or out. The coarser level stays opaque beneath it, so anything not made yet shows its parent. Wheel,
  click and pan are ignored while it runs (`camera.manual_control` off). The new level's jobs start at once,
  for the view the transition ends on.
- Picking and cell info key off `_level`. They fall back to a coarser level where the finer one isn't made yet.
- The camera keeps `pan_speed = 4.0`, and roofs are hidden by default.

## Left to do

- **Towns per region.** The town/site/road/plot/census pipeline is copied and renamed but not wired in. Next
  is one town per region.
- **L1 seams at region borders.** A chunk refines only from its own region, and that region's seed, so L1
  can show a seam on a region line. L2 has no seam between regions.
- The L3 river is 2–3 L3 cells wide (128–192 m), because one cell is the least that stays a single water body.
