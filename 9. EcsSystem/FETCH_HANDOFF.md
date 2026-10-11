# Handoff — cutting the fetch time

**Status: option 1 done (2026-10-11); option 2 next.** Decided 2026-09-27 as the next job in module 9. When it is done,
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

**Those numbers are the fed case, and fed is the light case.** The stress world starts every
animal full, so no food rung ever runs. `-- --fullness=50` starts them hungry instead
(below both kinds' `forage_below`), and the brain then checks every id its sensor returns
for food. At 800 entities, same sitting:

| | fed (default) | hungry (`--fullness=50`) |
|---|---|---|
| whole tick | 47.6 ms | **85.3 ms** |
| low_brain | 8.6 ms | **46.5 ms** |
| low_brain `has` + `is_alive` per tick | 800 | **82,038** — ~100 per creature |

The stress world has no berries, so a hungry animal never finds food and rescans on every
brain tick — the worst case for that loop, and the one to fix against. **Measure every option
in both states.**

**The sensor's 73 ms is not this job.** It is engine work, and Area2D is already the cheap way
to do it — without the broadphase every entity would test every other. Fetch is the part
that is our own overhead.

## What fetch is

`systems/ecs_hunger_system.gd:32` is the whole pattern in five lines:

```gdscript
for id in world.query([EcsHungerComponent]):                                          # query
    var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent     # fetch
    var drain := hunger.drain
    if world.has(id, EcsCollapsedFlag) or world.has(id, EcsAsleepFlag):                 # fetch ×2
        drain *= hunger.asleep_drain_scale                                               # logic
    hunger.fullness = maxf(hunger.fullness - drain * delta, 0.0)                         # logic
    var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent     # fetch
```

Storage is `{ Script : { entity_id : EcsComponent } }`, so every `get_component` is two
dictionary lookups (the type's table, then the id) plus Variant boxing and the cast back.
That is ~1.4 µs, paid per call, per entity, per stage, per tick. The whole of it, from
`ecs/ecs_world.gd:65`:

```gdscript
var _alive: Dictionary = {}  # entity_id -> true
var _store: Dictionary = {}  # Script -> { entity_id -> EcsComponent }

func get_component(id: int, type: Script) -> EcsComponent:
	var table: Dictionary = _store.get(type, {})   # lookup 1 — and a fresh {} on a miss
	return table.get(id)                           # lookup 2

func has(id: int, type: Script) -> bool:
	var table: Dictionary = _store.get(type, {})
	return table.has(id)

func is_alive(id: int) -> bool:
	return _alive.has(id)
```

`query()` (`ecs/ecs_world.gd:87`) drives from the smallest requested table and tests every
other table per id, building a fresh `Array[int]` each call — the ~31 ms query line:

```gdscript
for id: int in driver:
	var matched := true
	for type: Script in include:
		if not (_store[type] as Dictionary).has(id):
			matched = false
			break
	if matched:
		for type: Script in exclude:
			var table: Dictionary = _store.get(type, {})
			if table.has(id):
				matched = false
				break
	if matched:
		result.append(id)
```

The ids come back bare, so a system then re-fetches from the very tables `query()` just
tested — every component is looked up twice per entity per stage.

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

### The brain's repeats — `systems/ecs_low_brain_system.gd`

The per-creature loop fetches brain and movement, then each rung fetches what it needs
for itself (`:60`):

```gdscript
for id in world.query([EcsPositionComponent, EcsMovementComponent, EcsLowBrainComponent]):
	var brain := world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
	var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
	if world.has(id, EcsCollapsedFlag):
		...
	# 3. Choose, highest rung first.
	if _try_eat(world, id, brain, move):          # hunger, inventory, action
		continue
	if _try_take(world, id, brain, move):         # inventory, hunger, action   — again
		continue
	if _try_seek_food(world, id, brain, move):    # hunger, inventory, sensor, position — again
		continue
	if _try_sleep(world, id, brain, move):        # energy, hunger (via _starving) — again
		continue
	...
	_wander(world, id, brain, move, delta)        # position — again
```

Hunger alone is fetched up to four times per creature per brain tick — each rung opens
the same way:

```gdscript
# _try_eat, :157
var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
# _try_take, :214 / :217 / :220
var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
var action := world.get_component(id, EcsActionComponent) as EcsActionComponent
# _try_seek_food, :273 / :278
var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
# _starving, :344 — called from _try_sleep and _worth_waking_for
var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
```

### The hungry scan — `_try_seek_food` and `_is_food`

This is the 82,038 at 800 hungry. For every id the sensor perceived (`:290`):

```gdscript
for seen in sensor.perceived:
	if not _is_food(world, seen):           # 1 is_alive + up to 3 has
		continue
	var there := (world.get_component(seen, EcsPositionComponent) as EcsPositionComponent).position
	var distance := here.distance_squared_to(there)
	...
```

and `_is_food` (`:375`) asks the expensive-to-fail questions first — an animal is alive
and has a position, so it passes two checks before failing on the consumable one:

```gdscript
func _is_food(world: EcsWorld, id: int) -> bool:
	if id == EcsWorld.NO_ENTITY or not world.is_alive(id):
		return false
	return world.has(id, EcsConsumableComponent) and world.has(id, EcsPositionComponent) \
		and not world.has(id, EcsDyingFlag)
```

`and` short-circuits, so for an animal this is `is_alive` + one `has` (consumable, false)
— already cheapest-first inside the `return`. The cost is the volume: ~53 perceived ids,
every brain tick, with no berry among them ever to end the search. `_is_takeable`
(`:250`) has the same shape for pickable.

### The bars — hunger and energy each ask "resting?" separately

```gdscript
# ecs_hunger_system.gd:39
if world.has(id, EcsCollapsedFlag) or world.has(id, EcsAsleepFlag):
	drain *= hunger.asleep_drain_scale

# ecs_energy_system.gd:37
var collapsed := world.has(id, EcsCollapsedFlag)
var resting := collapsed or world.has(id, EcsAsleepFlag)
...
	var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent  # awake only
```

`health` (`ecs_health_system.gd:22`) is the minimum case — a query with an exclude and one
get, ~9 ms of pure lookup for a `<= 0.0` test:

```gdscript
for id in world.query([EcsHealthComponent], [EcsDyingFlag]):
	var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
```

### Movement, collision, node_sync

```gdscript
# ecs_movement_system.gd:33 — 2 gets, ~97% bookkeeping
for id in world.query([EcsPositionComponent, EcsMovementComponent]):
	var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
	if not move.has_destination:
		...
	var here := world.get_component(id, EcsPositionComponent) as EcsPositionComponent

# ecs_collision_system.gd:121 — rebuilds its arrays from scratch every tick
for id in world.query([EcsPositionComponent, EcsBodyComponent]):
	var body := _manager.node_for(id, EcsConst.NODE_BODY) as Area2D
	var shape := world.get_component(id, EcsBodyComponent) as EcsBodyComponent
	var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
	...
	_places.append(place)
	_movable.append(world.has(id, EcsMovementComponent))

# ecs_node_sync_system.gd:38 — walks the manager's ids, not a query
for id: int in _manager.entity_ids():
	var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
	var sprite := world.get_component(id, EcsSpriteComponent) as EcsSpriteComponent
```

Collision's `_places` array is already a hand-rolled version of option 4's cache — held
references, walked by index — rebuilt every tick because nothing tells it when the set
changed.

## Options, cheapest first

**1. Run the slow bars less often — done.** `main.gd` now runs hunger and energy at `BARS`
(6 ticks, 10 Hz) on phases 2 and 5, the two ticks `SLOW` leaves free, and health at `SLOW`
on phase 2, so it lands right after whichever bar just ran and a death is seen the tick it
is caused. Banked delta keeps the rates exact; a run charges its whole tenth at the state
it finds (asleep, moving), which is exact on average.

Measured with the stress test's new `--every=label:every:phase` flag, which applies the
game's rates. Before is `sensor:3:0,low_brain:3:1`, after adds
`hunger:6:2,energy:6:5,health:3:2`. 4,000 entities, one sitting, each pair run twice and
agreeing within 2%:

| | before | after | |
|---|---|---|---|
| fed — average tick | 137.2 ms | **108.0 ms** | −29 ms, −21% |
| fed — heaviest tick | 179–186 ms | 149–157 ms | |
| hungry — average tick | 201.1 ms | **169.8 ms** | −31 ms, −15% |
| hungry — heaviest tick | 328–352 ms | 291–293 ms | |
| hunger + energy + health | ~37.6 ms | ~7.6 ms | |

**The heaviest tick is now the brain's.** Hungry, `low_brain` averages ~74 ms over three
ticks, so it costs ~220 ms on the one tick it runs — that is option 2's target.

**2. Fetch once per creature in the brain — and fix the hungry scan, which is the bigger half.** Get hunger, energy, inventory, action, sensor and
position once at the top of the per-creature loop and pass them to the rungs, instead of
each rung fetching its own. Takes the brain from ~6.5 gets per creature to ~4–5 in the
fed case, and removes most of the repeats. For the hungry case — ~100 store calls per
creature per tick — make `_try_seek_food` cheaper per perceived id: check the cheapest
disqualifier first (is it consumable at all — most perceived ids are other animals),
fetch position only for ids that pass, and consider letting the sensor or the world keep a
"food in view" list so the brain never tests animals. **Fed: part of ~44 ms at 4,000;
hungry: most of the ~38 ms the hungry state adds at 800. One file for the first part.**

Note that `_is_food` already fails an animal on the consumable check (see above), so
reordering alone buys little. What is left per animal is `is_alive` + `has(Consumable)`;
`destroy_entity()` erases every table, so `has(Consumable)` is already false for a dead
id and the `is_alive` in front of it is a redundant call. The real saving is not asking
~53 times at all.

A sketch of the fetch-once shape — the rungs take components instead of fetching them.
Signatures and the bundle are illustrative, not decided:

```gdscript
for id in world.query([EcsPositionComponent, EcsMovementComponent, EcsLowBrainComponent]):
	var brain := world.get_component(id, EcsLowBrainComponent) as EcsLowBrainComponent
	var move := world.get_component(id, EcsMovementComponent) as EcsMovementComponent
	...                       # collapsed / sleep / commitment checks unchanged
	if move.has_destination and brain.state != EcsLowBrainComponent.State.WANDER:
		continue              # mid-trip creatures still leave before any extra fetch

	# Fetched once, only for creatures that reach the ladder; null means "has none".
	var hunger := world.get_component(id, EcsHungerComponent) as EcsHungerComponent
	var bag := world.get_component(id, EcsInventoryComponent) as EcsInventoryComponent
	var action := world.get_component(id, EcsActionComponent) as EcsActionComponent

	if _try_eat(world, id, brain, move, hunger, bag, action):
		continue
	if _try_take(world, id, brain, move, hunger, bag, action):
		continue
	if _try_seek_food(world, id, brain, move, hunger, bag):   # sensor, position inside
		continue
	if _try_sleep(world, id, brain, move, hunger):            # energy inside
		continue
```

Fetch *after* the `has_destination` early-out, not at the top of the loop — hoisting all
six to the top would make a mid-trip creature, which today costs 2 gets, pay for all six.
The `SLEEP` branch above it (`_worth_waking_for` → `_starving`) fetches hunger for itself
and can stay as it is or take the same argument.

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

The probe is `_probe_access()` in `tests/stress_test.gd:168`. The 1.2 µs row is this loop
— the same arithmetic as `EcsMovementSystem`, over references gathered once:

```gdscript
var moves: Array[EcsMovementComponent] = []
var places: Array[EcsPositionComponent] = []
for id in _world.query([EcsPositionComponent, EcsMovementComponent]):
	moves.append(_world.get_component(id, EcsMovementComponent) as EcsMovementComponent)
	places.append(_world.get_component(id, EcsPositionComponent) as EcsPositionComponent)

for k in moves.size():          # timed
	var move := moves[k]
	var here := places[k]
	...
```

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
- The stress test runs every stage every tick unless given `--every=` — pass the game's
  rates (see option 1) to measure the tick the game actually pays.
- Run each measurement **fed and hungry**: the default, and `-- --fullness=50`.
- The split table's `gets` and `has` columns are the direct check for option 2: low_brain
  should fall from 26,003 gets at 4,000 fed, and from 82,038 has / is_alive at 800 hungry.
- `tests/lifecycle_test.tscn` must stay at 161/161 after every step.

## Done means

- Options 1 and 2 landed, each as its own commit, each with a same-sitting before/after.
- Option 4 raised as a decision, with the new numbers.
- The results folded into `HANDOFF.md` §14, and this file deleted.
