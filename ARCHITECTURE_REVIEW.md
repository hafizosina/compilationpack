# Architecture review — modules 9, 10 and 11

2026-11-05. Covers GOAP, the ECS, data-driven design and scalability, across module 9 (the creature
simulation), module 10 (the town) and module 11 (player control). Read from the code, measured where
it mattered; no code was changed. Part 1 is the review, part 2 the follow-up discussion, part 3 the
decisions taken.

---

# Part 1 — The review

## Verdict

The ECS discipline is real:

- only sensor and collision read from nodes;
- only `EcsHealthSystem` writes health;
- the inspect system knows no component type;
- no system calls another, except one static helper thirst borrows from hunger (`EcsHungerSystem.mark`).

**Module 11 is the strongest evidence the architecture works**: a player brain replaced the AI brain
and module 9's executors ran unchanged. **Module 10's grid is the cleanest code of the three**: flat
packed arrays, one writer, a command inbox, and a generator that emits the same commands as the
player's tools.

The weak spot is the AI layer. **GOAP's actions and goals are data, but the vocabulary they are
written in — facts, needs, brain states — is code.** That layer is now also the dominant cost.

## GOAP

**1. Adding one action means editing up to 9 places.** Besides the `.tres`:

- `_facts()` (`9. EcsSystem/systems/ecs_planning_system.gd:233`), if it needs a new fact;
- `score()` (`:127`), if it needs a new need;
- `RECALLS` in the planning system;
- in the brain: the `State` enum, `_try_step` (`9. EcsSystem/systems/ecs_low_brain_system.gd:211`),
  `_serves` (`:571`), `_set_state` (`:933`) and `_flag_for` (`:989`);
- its executor system.

That is the "per-item edits to one shared system" pattern. Skills already show the fix:
`EcsSkillDef` subclasses say their own effect and requirement. Actions could do the same — each def
owns binding its target, ticking, done/failed, and the intent flag it raises. Facts could come from
small fact-source resources listed in data, and a goal's `need` could become a scorer resource. The
1,027-line brain would become a generic step runner.

**2. There are two deciders.** The ladder (`ecs_low_brain_system.gd:183–208`, plus every `gated`
branch) only runs before a creature's first plan, or for an entity without a planner. All four
animals have a planner, so in practice the ladder survives for the tests. Every rung exists twice,
gated for the ladder and ungated as a plan step. Recommendation: retire the ladder, keep the rungs
as step executors.

**3. A\* is no longer noise.** HANDOFF §14's "A\* itself is noise" was measured on 2026-10-29 with
fewer actions. `EcsPlanner.plan` timed alone, per call, desktop:

| Case | Per call |
|---|---|
| No plan exists | ~30 µs |
| `recall_food > eat_ground` (rabbit, monkey, crocodile, dog) | 180–280 µs |
| Crocodile `quench`, prey in sight — fails after a full search | 284 µs |

At the 64-replan cap that is 10–40 ms per planning run. Causes: the heuristic is only 0 or 1, so the
search expands nearly every state cheaper than the answer; every node copies a Dictionary and builds
a sorted string key; the open list pops linearly. Fixes, in order: facts as bits in an int, search
backwards from the goal, cache plans by (action set, goal, fact bits). See part 2 §4. The benchmark
is in the appendix.

**4. "Threat" is defined by diet, which breaks with the player.** `EcsHunting.can_hunt`
(`9. EcsSystem/ai/ecs_hunting.gd:14`) requires `EcsHungerComponent.eats == &"meat"`. The player has
no hunger component, so no animal treats it as a threat until it lands a hit. And `_hunted()` in
the planning system reads the threat's `EcsLowBrainComponent.state`, which the player doesn't have,
so prey the player is chasing can still hide. This shows the day the player enters module 9's world.
The chaser should raise a flag on itself, so no entity reads another entity's FSM state.

**5. Fact names are never validated.** A typo in a precondition makes an action silently never fire.
All 35 names match today. Cheap guard: a test that every precondition and desired fact is produced
by `_facts()` or by some action's effects.

**6. Action lists are copied into the four animal blueprints, and they have drifted.** Crocodiles and
dogs have no `escape`, `hide` or `go_to_cover`; rabbits have no `hunt`. Skills use a shared
`default_set.tres` plus swaps; actions could do the same, which would make "every animal is the
same" true in data.

## ECS core

1. **The pipeline is assembled by hand in 9 files** (three `main.gd`, plus tests and tools), and the
   orders already differ: module 9 runs sensor before the brain; module 11 runs it after collision
   and has danger after health. Merging the modules into one game hits this first, and the stress
   test can drift from `main.gd`. Recommendation: one pipeline definition per feature set — stages
   with their rates and phases — shared by the main scene and its tests.
2. **Module 9 is now a library.** Modules 10 and 11 both import its core. The project rule is to
   promote to `Global/` once a second module needs something; now two do. Caution:
   `EcsSnapshot._encode` saves each script's file path, so moving files breaks every save. Either
   move before saves matter, or save a key and resolve the script from a registry.
3. **Randomness isn't seeded.** 11 global `randf`/`randi` calls across 8 systems (brain, collision,
   breeding, attack, harvest, energy, wander, strike). Runs aren't reproducible, a loaded save plays
   out differently, and bug repros depend on luck. Module 10's generator is already seeded; one RNG
   singleton per world, stored in the save, fixes the rest.
4. **The sensor's node cache never forgets dead entities**
   (`9. EcsSystem/systems/ecs_sensor_system.gd:9`). With breeding and corpses, a long colony
   session grows it forever. Collision's rebuild-when-the-view-changes pattern fixes it.
5. **Storage (HANDOFF §15, open).** Position: not yet. Packed storage was measured at ~1.6–2× across
   the pipeline; scalability items 1, 3 and 4 below cut more than that.
6. **Minor.** `EcsEntityManager._make_node` turns any node kind that isn't a sprite into an area, so a
   new kind (animated sprite, light, audio) still needs a manager edit. About 100 `Ecs*` class names
   from three folders share one global registry — the problem that got module 8 deleted.

## Data-driven design

What works: blueprints, actions, goals, skills and worlds are data; town defs are identified by
name, never by number; a new tile type is a def and a PNG; overrides are keyed by component.

1. **Tuning and live state share one Resource, and saves keep both.** Blueprint components are deep
   copies with no file path, so a save stores every tuning field. Rebalancing `rabbit.tres` won't
   reach a saved rabbit. Option: save `type_id` plus only the fields that differ from the blueprint;
   load spawns from the blueprint and applies the difference.
2. **Skill costs live on the player and the brain pays them** (`EcsPlayerComponent.skill_costs`,
   `_cast` at `11. EcsControl/systems/ecs_player_control_system.gd:115`). A crocodile's dash is free
   and the player's isn't, and payment sits with the brain instead of the executor. Cost belongs on
   `EcsSkillDef`, paid by `EcsSkillSystem` when the skill starts.
3. **Room ids change on every edit.** Rooms are untyped Dictionaries on `EcsBuildingComponent`, and
   any change to a building renumbers all its rooms
   (`10. Town Generator/systems/ecs_room_detection_system.gd:58`). Harmless while nothing points at
   a room; the first bed owner, zone or job breaks. Keep ids stable by matching old rooms to new by
   overlap, or make rooms entities, before anything references them.

## Scalability

**The 4,800 ceiling is at 4 FPS** — the stress test's budget is 250 ms a tick (`BUDGET_MS`). Re-run
at the game's rates with 40 hunters (single runs, ±12% noise):

| Density | Entities | Avg tick | Worst tick | Planning share |
|---|---|---|---|---|
| Dense (50 seen per sensor) | 200 | 39.8 ms | 79 ms | 38% |
| Dense | 400 | 53.4 ms | 97 ms | 37% |
| Dense | 800 | 78.9 ms | 118 ms | 34% |
| Sparse (4 seen per sensor, `--spacing=300`) | 400 | 15.8 ms | 24.5 ms | 38% |
| Sparse | 1,600 | 60.1 ms | 92.8 ms | 35% |

At realistic density, **about 400 entities is the 60 Hz limit on desktop for the simulation alone**,
with 24 ms worst ticks already stuttering at that size; Android will be lower. Recommendation:
re-base the stress test on a frame budget and report the worst tick.

1. **Planning is the biggest stage at every density.** Levers: the bitmask/backward search, snapshot
   only planners whose inputs changed, and time-slicing — the worst tick is the one planning lands
   on, so spreading each 20 Hz stage's entities across its three ticks flattens it.
2. **Four systems build the same index.** Planning, the brain, memory and danger each keep their own
   lookup of food, bushes, water, cover, ready mates and hunters. See part 2 §2.
3. **Hunters cost more as prey gets denser.** `can_hunt` and `notices` run over every perceived id
   in danger, memory, planning's facts (twice) and planning's costs. At 200 dense entities memory
   plus danger was ~47% of the tick. See part 2 §3.
4. **The module 9 ↔ 10 seam is navigation.** Movement is a straight line and sensors see through
   walls. Room detection already gives the graph for hierarchical pathfinding — rooms as nodes,
   doors as edges. Sight should respect walls too.
5. **Module 10 is fine.** Idle cost 23 µs at 1,000 buildings, load linear, room detection recomputes
   only the building that changed.

## Suggested order

1. Bitmask facts and backward search, measured with the benchmark.
2. Actions that execute themselves; the brain becomes a generic runner; retire the ladder.
3. One shared world index.
4. A seeded RNG, and one pipeline definition shared by main and tests.
5. Before saves matter: saves that store only the difference from the blueprint, and moving the ECS
   core out of module 9.
6. Before creatures enter the town: navigation over rooms and doors, walls that block sight.
7. Before anything points at a room: stable room ids.

---

# Part 2 — Follow-up

## 1. Threading the planner

- **Only the search can move off the main thread.** `_facts()` and the scoring read the world. The
  stress numbers lump facts and search together as "planning"; only the search was timed alone.
  Measure that split first — if facts dominate, a thread helps little.
- **Do the bitmask change first.** Then a plan's input is a few ints and a fixed action table, so
  `WorkerThreadPool.add_group_task` has nothing shared to protect.
- **Running it:** the planning system sends the batch, and on its next run applies results in queue
  order — not completion order, so runs stay reproducible — and stays the only writer of
  `EcsPlannerComponent`. A plan one run late (50 ms) is fine: the brain re-validates targets.

## 2. One shared index

A new `EcsWorldIndexSystem`, right after `edit`, is the only writer of a new
`EcsWorldIndexSingleton`. Each table is rebuilt only when its view changes, as every system does now:

| Table | Built from | Replaces the copy in |
|---|---|---|
| `food` id → consumable | `[EcsConsumableComponent, EcsPositionComponent]` minus dying | planning, brain, memory |
| `crops` id → harvestable | `[EcsHarvestableComponent, EcsPositionComponent]` | planning, brain, memory |
| `water` id → true | `[EcsDrinkableComponent]` | planning, memory |
| `covers` id → cover | `[EcsCoverComponent]` | planning, memory |
| `ready` id → kind | `[EcsReadyFlag, EcsNameComponent]` | planning, memory |
| `hunters` id → hunger | `[EcsDamageComponent, EcsHungerComponent]` | memory, danger |

- **Store component references, not copied values**, so a live edit or a harvest is never stale.
- **No staleness within a tick**: executors raise dying flags late in the tick, and lifecycle removes
  those entities at the start of the next, before the index rebuilds.
- The main gain is one definition of what counts as food, a lure or a hunter (memory and planning
  each decide it today). The speed gain is modest — measure it.

## 3. Hunter cost

The same question is asked five times per pair. Sort each sensor's list once instead:

- `EcsPerceptionSystem`, right after `sensor` in the same phase, writes `EcsPerceptionComponent`:
  `threats`, `prey` (noticed only), `food` and `crops` of its diet, `water`, `cover` of kinds it can
  hide in, `mates` — and the same for `reached`.
- danger reads `threats`; memory files every list; planning's facts become
  `not perception.prey.is_empty()`; the cost pass loops over `prey`; the brain picks the nearest
  entry. With the index, `can_hunt` is a lookup in `hunters` plus a power comparison.
- The sensor stays physics-only and the new system touches no node. Hiding can change between
  sensing and planning, so lists can be one run late — the same delay already accepted for reach.
- Check it on the dense grid, where memory plus danger was ~47%.

## 4. Bitmask facts and backward search

**Bitmask.** A state is a Dictionary today, copied at every step with a sorted string key built from
it. Give each fact a bit once at load, collected from all action and goal defs (35 today):

```gdscript
# compiled once from the .tres dictionaries; the .tres files stay as they are
state = 0b...                     # one int, bit k = fact k
holds  = (state & pre_mask) == pre_value
next   = (state | eff_set) & ~eff_clear
key    = next                     # the int is the key
```

No allocation, no strings, no copies. False-valued preconditions (`hide` needs `hunted: false`) are
a masked bit with value 0. Safe to test: the current planner is the reference — compare plan costs on
thousands of random fact sets.

**Backward search.** Forward search from a hungry rabbit's `{safe, water_known, food_known,
bush_known}` tries `sleep`, `recall_water`, `recall_food`, `recall_bush`…, then branches again, and
expands everything cheaper than the answer's cost of 3. Backward from the goal:

```
want {fed}
  ← eat_ground  needs {food_in_reach}      (eat_carried needs food_in_bag: not true now)
  ← recall_food needs {food_known}  ✓ true now → plan: recall_food > eat_ground
```

`sleep`, `drink`, `recall_water` and `flee` are never looked at. A plan that can't exist fails fast —
the 284 µs crocodile `quench` stops as soon as no action leads toward `hydrated`. This is how
F.E.A.R.'s original GOAP planner searched. The one rule to get right: an action counts only if it
makes an unmet goal fact true and breaks no other goal fact.

Order: bitmask (same answers, overhead removed), then backward search, then the thread if still needed.

## 5. Room ids or pathfinding first

**Pathfinding first.** `AStarGrid2D` works on cells — walls solid, doors passable — and never needs a
room id. Stable room ids matter once something stores one across edits, or for a room-level route
cache. When building it:

- **The trip budget breaks.** `EcsMovementSystem` budgets `straight distance / speed × slack`; a path
  around a building is longer, so trips give up partway. Budget on the path's length.
- **Ownership.** One nav system as the only writer, updating solid cells from the build system's
  `CHANGED_STRUCTURE` dirty bits — the same derived-index exception as the collision areas. A path
  system turns the brain's destination into waypoints on a component, so the brain still writes only
  a destination.
- **Diagonals.** `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES`, or paths cut wall corners.
- **Cap path queries per run** like `MAX_REPLANS`, on the main thread at first — `AStarGrid2D` isn't
  safe to query while being changed.

Order: pathfinding → stable room ids when something first points at a room → a room-level route
cache if long paths prove expensive.

---

# Part 3 — Decisions (2026-11-05)

- **Planner thread:** planned for heavy planning.
- **Shared index and hunter cost:** agreed; solutions in part 2 §2 and §3.
- **Pathfinding:** `AStarGrid2D` in module 10, after the current work.
- **Order:** 2 (self-executing actions, retire the ladder), 3 (shared index) and 4 (seeded RNG, one
  pipeline definition) agreed. 1 (bitmask and backward search) explained in part 2 §4.
  5 (saves) later. 6 (navigation and sight through walls) is module 10's next plan, later.
  7 (stable room ids) later, after pathfinding.

# Part 4 — Point-by-point (2026-11-06)

**GOAP refactor — todo, later.** GOAP 1 and 2 are one job.

- **GOAP 1, actions that execute themselves.** The def answers,
  the brain applies, as with skills: an `EcsActionDef` subclass gives `bind(world, id) -> int`
  (chooses a target, writes nothing), `done`, `failed`, `make_intent(target) -> EcsFlag` and where to
  walk; the brain writes only target, destination and the flag. `State`, `_serves` and `_flag_for`
  go; brain state becomes the current step id plus its target. Facts (`_facts()`) and needs
  (`score()`) stay in code for now.
- **GOAP 2, retire the ladder.** The `_try_*` rungs become the step executors and their `gated`
  branches go. A creature with no plan yet, or no planner, wanders. Ladder tests (`_ladder_rabbit`)
  move to planned creatures or are dropped where planner tests already cover them;
  `_utility_picks_what_the_ladder_would` becomes a fixed table of expected goals.

- **GOAP 3, A\* cost — undecided.** Proposed: separate from the refactor and first in line (only
  `ecs_planner.gd` changes; the current planner is the reference to test against); measure the
  `_facts()` vs search split before starting; drop the plan cache unless numbers ask for it.
- **GOAP 4–6** (threat by diet, fact-name validation, shared action set) — not yet discussed.

**ECS core**

- **ECS 1, pipelines — by design; revisit at the merge.** A separate pipeline per module is the
  point of a prototype pack. Within module 9, `stress_test.gd` copies `main.gd`'s list by hand (it
  lacks `edit`, and runs every stage every tick unless `--every=` is passed). Left as is: one shared
  pipeline and a stress test that runs it come when the modules are combined into one base game.
- **ECS 2, module 9 as a library — stays in module 9 for now.** The ECS and GOAP aren't final (the
  GOAP refactor is still to come), so the core is promoted only once it settles: at the merge,
  before saves matter (`EcsSnapshot` stores script paths, so a move breaks old saves). Until then,
  run all three modules' tests after touching module 9's core.
- **ECS 3, seeded randomness — done 2026-11-06.** `EcsRandomSingleton` holds the world's one
  `RandomNumberGenerator`; every roll in modules 9 and 11 goes through `EcsRandomSingleton.of(world)`
  (13 calls, `EcsConst.random_point_near` included), and a save keeps its state. `main.gd`'s
  `random_seed` export sets it (0 = new each build) and the seed is printed. Module 10's wander
  is left on the global RNG. Replays hold only while the order of rolls does.

---

# Appendix — planner benchmark

Times `EcsPlanner.plan` per animal, goal and fact set. Run from the project root:
`"$GODOT" --headless --path . -s <path to this script>`.

```gdscript
extends SceneTree

# Times EcsPlanner.plan for each animal's actions against a few fact sets.

func _init() -> void:
	var cases := {
		"nothing around": {&"safe": true},
		"knows places": {&"safe": true, &"water_known": true, &"food_known": true,
			&"bush_known": true, &"lure_known": true},
		"prey in sight": {&"safe": true, &"prey_in_sight": true, &"dash_ready": true},
	}
	for kind in ["rabbit", "monkey", "crocodile", "wild_dog"]:
		var def := load("res://9. EcsSystem/defs/blueprints/%s.tres" % kind) as EcsEntityDef
		var planner := def.template(&"planner") as EcsPlannerComponent
		for label in cases:
			var facts: Dictionary = cases[label]
			for goal in planner.goals:
				if goal.id != &"satisfy_hunger" and goal.id != &"quench":
					continue
				var steps: Array[StringName] = []
				var began := Time.get_ticks_usec()
				var runs := 50
				for i in runs:
					steps = EcsPlanner.plan(facts, goal.desired, planner.actions)
				var us := float(Time.get_ticks_usec() - began) / runs
				print("%-9s %-15s %-15s %8.1f us  %s" % [kind, goal.id, label, us,
					" > ".join(steps) if not steps.is_empty() else "(no plan)"])
	quit()
```
