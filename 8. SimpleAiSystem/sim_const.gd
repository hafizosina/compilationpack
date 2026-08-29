class_name SimConst
extends RefCounted

## Tunable constants for the colony sim (module 8). Static-only helper class —
## deliberately NOT an autoload, since nothing outside this module reads it.
##
## All numbers are rebased on the module's 64px painted tilemap: one "grid" is
## one visible tile, so the per-grid energy costs from MILESTONE_1_SPEC mean one
## actual tile of travel.

## Side length of one world tile, in pixels. Movement energy is charged per grid.
const GRID_SIZE: float = 64.0

## Baseline walk speed, shared by every creature type (px/sec = 1 tile/sec).
const WALK_SPEED: float = 120.0
## Baseline run speed `R`; Type1 runs at exactly this.
const RUN_SPEED: float = 240.0
## Type2's run multiplier over `RUN_SPEED` — the predator's edge in a straight chase.
const RUN_MULT_PREDATOR: float = 1.4
## Type3's run multiplier over `RUN_SPEED` — the fast prey that outruns the predator.
const RUN_MULT_FAST_PREY: float = 2.0

## Scale applied to the ~128px animal art so one creature covers one 64px tile.
const SPRITE_SCALE: float = 0.5

## Extents of the painted TileMapLayer in world space (tiles x -3..28, y -3..15).
## Wander targets are clamped to this.
const WORLD_BOUNDS: Rect2 = Rect2(-192.0, -192.0, 2048.0, 1216.0)

## Energy spent per grid travelled at each gait. Unused until Phase 2 adds Fatigue.
const ENERGY_PER_GRID_WALK: float = 0.5
const ENERGY_PER_GRID_RUN: float = 2.0

## The pivot line: a need below this activates its goal. Unused until Phase 2.
const NEED_THRESHOLD: float = 50.0
