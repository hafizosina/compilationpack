# What Oxygen Not Included does to scale (study notes, 2026-11-08)

Read from the game's `Assembly-CSharp.dll` metadata and IL (method bodies), not guessed.
Gas/liquid/heat live in the native `libSimDLL.so`; only its interface was visible.
Patterns only — no Klei code copied.

**The idea everywhere: cost follows what changes or what is on screen, never what exists.**

## 1. Brains have a fixed budget per frame — biggest win
- `BrainScheduler`: creatures **5 brains/frame**, duplicants **1/frame**, round-robin.
  50 critters → each thinks every 10 frames; 500 → every 100. Cost per frame is flat.
- A **priority queue** jumps the line, fed by events: attacked, chore ended, trapped, food frozen.
- Brain sensors update only on that brain's turn (`Sensors.UpdateSensors` from brain pre-update).
- **For us:** `low_brain` and `sensor` still visit everyone each SLOW tick. Round-robin budget +
  priority queue (`EcsHurtFlag`, target gone, intent done) → flat brain cost. Next perf candidate.

## 2. Updates spread by type at fixed rates
- Rates: every tick, 33 ms (2 frames), 200 ms (12), 1 s (60), 4 s (240).
- Each bucket (one per type or per state-machine state) is placed on the next frame slot in turn.
- Our `every` + `phase` is the same idea per system; ONI also slices within a rate (cf. the stashed slicing).

## 3. Path cost is a cached window, not a search
- Each mover has a `PathGrid`: a window of cells around it holding cost-to-reach, filled by a flood.
- "How far is that job?" = one array read (`GetCost(cell)`).
- **Serial-number invalidation**: a cell is valid only if `queryId == serialNo`; reset = bump counter.
- Flood runs on a background thread (`AsyncPathProber`); longest-waiting movers first, penalty for
  failed navigation. Results include newly / no-longer reachable cells. Terrain edits dirty only cells.
- **For us:** module 10 villagers, colony pathing.

## 4. Spatial index with change subscriptions
- `ScenePartitioner`: 16×16-cell buckets, 68 layers (pickupables, plants, wires, solid/liquid changed…).
- Objects register a rectangle + callback; a cell change calls only subscribers covering it
  (lights, plants, falling debris, foundations). Nothing polls terrain.
- **For us:** `EcsWorldIndexSingleton` + sensor marking are half of this; missing half is
  grid-cell change layers (module 10: walls, doors, rooms).

## 5. Grid = flat arrays; the sim returns change lists
- One array per cell property (`elementIdx`, `mass`, `temperature`…), raw pointers into native memory.
- Flags are packed bits (`BuildMasks`: Solid, Foundation, HasDoor…).
- Sim steps every 200 ms and returns lists of **changed cells only**; game code reacts to those.
- Gas/liquid drawn from textures the sim writes, not objects.
- **For us:** never make tiles/gas/wire cells entities. Packed arrays per property; GDExtension thread later.

## 6. A network is one object
- Wires: connection bits in a grid; a change marks dirty → one flood-fill rebuild. Power solved per
  circuit from generator/consumer/battery lists. Wire length costs nothing per tick.
- Pipes (`ConduitFlow`, 1 Hz): cells ordered once at build (graph walk from sources/sinks); tick is a
  straight loop repeated while anything moved; **each network a parallel job**; contents keep
  initial/added/removed mass so order within a pass doesn't matter; machines act after flow, by priority.

## 7. Stats: compute in parallel, publish serially
- `AmountInstance` (calories, stress…): rate = **sum of a modifier list** (a buff is a modifier).
- Deltas computed in parallel into per-thread lists, then published on the main thread (events fire there).
- **For us:** hunger/thirst/energy; `EcsHealthOverTimeFlag` kinds are already close.

## 8. Fewer candidates, fewer entities
- Fetch compaction: per type, sort by (tags, priority, path cost), keep only the cheapest of each
  identical group. Rot rounded into 4 bands so freshness doesn't block grouping.
- Debris merges on landing in a cell or entering storage (same element, < 25,000 kg combined);
  the absorbed one is deleted.
- **For us:** stack dropped berries / loot; food index keeps best per (diet, place).

## 9. State machines own updates and toggles
- An object is in an update bucket only while its current state declares an update; idle = zero cost.
- Transitions mostly event-driven (283 `EventTransition`, 178 `ParamTransition` uses).
- `Toggle*` (tag, modifier, anim, status) applied on enter, removed on exit — no leaked state.
  Same as our flags raised/cleared in `_set_state()`, generalised.

## 10. Rendering, rooms, small tricks
- Animation only for controllers in visible chunks; batches write only changed entries to GPU textures.
  **For us:** `node_sync` could skip off-camera movers.
- Rooms: changed cells into a `solidChanges` set, re-probed once a second only if dirty (module 10).
- Pools everywhere (lists, path grids, partitioner entries) — no GC pauses.

## Suggested order
1. Brain budget (round-robin + priority queue) for `low_brain` and `sensor`.
2. Off-camera skip in `node_sync`.
3. Item stacking + candidate compaction.
4. Module 10: packed-array grid, cell-change subscriptions, rooms re-probed on dirty, then path-cost window.
5. Later, colony systems: networks as one object; parallel compute + serial publish.
