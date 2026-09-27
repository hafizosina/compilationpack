# Handoff — cutting the fetch time

**Status: not started.** Decided 2026-09-27 as the next job in module 9. When it is done,
fold what it measured into `HANDOFF.md` §14 and delete this file, the same way the step 6
plans were folded in.

## The problem, measured

About half of every tick is spent **looking components up**, not using them. From
`tests/stress_test.tscn` at 4,000 entities (commit `400a655`, one sitting):

| | ms per tick | share |
|---|---|---|
| **fetch** — `get_component` / `has` / `is_alive` | ~130 | ~50% |
| sensor's real work — reading physics overlaps | ~73 | ~28% |
| **query** — `world.query()` building id lists | ~31 | ~12% |
| everything else's real work | ~23 | ~9% |
| **tick** | **257** | ceiling 3,200 entities under 250 ms |

Per stage (the stress test prints this table at the end of every run):

| stage | total ms | bookkeeping | real work | gets / has per tick |
|---|---|---|---|---|
| sensor | 93.3 | ~22% | 72.6 | 8,000 / 0 |
| low_brain | 44.3 | ~100% | ~0 | **26,003** / 4,000 |
| collision | 34.0 | ~54% | 15.8 | 8,000 / 4,000 |
| node_sync | 23.8 | ~50% | 11.9 | 8,000 / 0 |
| energy | 18.2 | ~100% | ~0 | 8,000 / 8,000 |
| hunger | 18.0 | ~100% | ~0 | 8,000 / 8,000 |
| movement | 16.5 | ~97% | ~0.5 | 8,000 / 0 |
| health | 9.1 | ~100% | ~0 | 4,000 / 0 |

Unit costs that sitting: `get_component` ~1.3–1.5 µs, `has` ~0.6 µs, `is_alive` ~0.2 µs,
one bare loop iteration ~0.02 µs. The priced columns are estimates and read a few percent
high (simple stages come out at 104–110% bookkeeping); the direct movement probe agrees.

**The sensor's 73 ms is not this job.** It is engine work, and Area2D is already the cheap way
to do it — without the broadphase every entity would test every other. Fetch is the part
that is our own overhead.

## What fetch is

```gdscript
for id in world.query([EcsHungerComponent]):                                         # query
    var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent    # fetch
    if world.has(id, EcsCollapsedFlag) or world.has(id, EcsAsleepFlag):                # fetch
        drain *= hunger.asleep_drain_scale                                              # logic
```

Storage is `{ Script : { entity_id : EcsComponent } }`, so every `get_component` is two
dictionary lookups (the type's table, then the id) plus Variant boxing and the cast back.
That is ~1.4 µs, paid per call, per entity, per stage, per tick.

## Where the lookups are

| system | per entity per tick | what to look at |
|---|---|---|
| `ecs_low_brain_system.gd` | ~6.5 gets + 1 has | **the same components fetched again in each rung**: hunger in `_try_eat`, `_try_take` and `_try_seek_food`; inventory and action in `_try_eat`'s helpers and `_try_take`; energy in `_try_sleep`; position in `_wander`. Hungry creatures add more: `_try_seek_food` runs `_is_food` (1 `is_alive` + 3 `has`) and a position get for every perceived id — about 53 ids per sensor on the dense grid |
| `ecs_hunger_system.gd` | 2 gets + 2 has | hunger, health, and the asleep / collapsed flags |
| `ecs_energy_system.gd` | 2–3 gets + 2 has | energy, movement (for velocity), health on collapse, the two flags |
| `ecs_movement_system.gd` | 2 gets | movement, position |
| `ecs_collision_system.gd` | 2 gets + 1 has | body, position, has movement — rebuilt into arrays every tick |
| `ecs_node_sync_system.gd` | 2 gets | position, sprite — walks `_manager.entity_ids()`, not a query |
| `ecs_health_system.gd` | 1 get | health |
| `ecs_sensor_system.gd` | 2 gets | sensor, action |

Note: the stress test calls every stage every tick. In the game, `sensor` and `low_brain`
run at 20 Hz, so their real cost there is a third of the table's.

## Options, cheapest first

**1. Run the slow bars less often.** hunger, energy and health: ~45 ms together, all lookup.
The bars change slowly; a tenth of a second of latency is invisible. `EcsScheduler.add(system,
every, phase)` already does this and banks delta, so drain and heal rates stay exact — only
latency changes. In `main.gd`, e.g. every 6 ticks (10 Hz) on three different phases so they
never share a tick. **~35 ms off the game's tick; no code change beyond `main.gd`.** Watch:
collapse and death land up to 0.1 s later; the tests that assume per-tick bars drive the
systems directly and are unaffected.

**2. Fetch once per creature in the brain.** Get hunger, energy, inventory, action, sensor and
position once at the top of the per-creature loop and pass them to the rungs, instead of
each rung fetching its own. Takes the brain from ~6.5 gets per creature to ~4–5 in the
fed case, and removes most of the repeats. For the hungry case, make `_try_seek_food`
cheaper per perceived id: check the cheapest disqualifier first, and fetch position only
for ids that pass. **Part of ~44 ms (15 ms in game at 20 Hz); one file, no behaviour change.**

**3. Trim duplicate `has` checks.** hunger and energy each test two flags per entity to mean
"resting". Small, a few ms each. Only worth it if 1 and 2 leave it visible.

**4. Cached queries that return component references — the big one, and not ours to start.**
Components are now fixed from spawn to death, and births and deaths happen only at the
lifecycle stage. So a query's ids *and* their component references stay valid until the
next structural change, which is most ticks. A cached query (versioned per component
table, rebuilt only when one of its tables changed) could hand a system arrays of
references, skipping both `query()` and `get_component`. The movement probe already
measures this exact shape: **4.1 → 1.2 µs per entity, ~70% off a lookup-bound stage**,
potentially most of the ~130 ms fetch plus ~31 ms query. Flags churn, but they are separate
tables, so a flag change invalidates only queries that name that flag.

This changes `EcsWorld`, which is `HANDOFF.md` §15's storage argument — **the author's
decision. Raise it with the numbers after 1–3; do not implement it unasked.**

## How to measure

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
"$GODOT" --headless --path . "res://9. EcsSystem/tests/stress_test.tscn"             # ramp + split table
"$GODOT" --headless --path . "res://9. EcsSystem/tests/stress_test.tscn" -- --n=4000  # one population
```

- **Before and after in the same sitting**, back to back. Throughput on this machine drifts by
  up to ~50% across a day; a cross-sitting comparison proves nothing.
- Repeat anything under ~15% — run-to-run noise is about ±12%.
- The stress test runs every stage every tick, so option 1 **will not show there**. Measure
  it by adding the same rates to the stress pipeline, or from `main.gd`'s real tick.
- The split table's `gets` column is the direct check for option 2: low_brain should fall from
  26,003 at 4,000 entities.
- `tests/lifecycle_test.tscn` must stay at 161/161 after every step.

## Done means

- Options 1 and 2 landed, each as its own commit, each with a same-sitting before/after.
- Option 4 raised as a decision, with the new numbers.
- The results folded into `HANDOFF.md` §14, and this file deleted.
