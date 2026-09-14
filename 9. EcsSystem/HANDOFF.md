# Module 9 — EcsSystem: state of the build

Greenfield hand-rolled ECS, built beside `8. SimpleAiSystem` per `ECS_REFACTOR_PLAN.md`.
Module 8 keeps running untouched as the behavioural reference.

**The module has been deliberately stripped to its bare minimum** — one world, one
scheduler, eight systems — so the flow reads end to end without hunting. What was cut is
listed in §6 and is recoverable from git; nothing was lost, only set aside.

`project.godot`'s main scene is module 9 (`uid://daecsmain0001`), so a plain run opens it.
Run either module directly:

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
"$GODOT" --path . "res://9. EcsSystem/main.tscn"
"$GODOT" --path . "res://8. SimpleAiSystem/main.tscn"
```

One thing outside this folder belongs to module 9 and would be lost if the folder were
moved alone: the main-scene line in `project.godot`. (The four `ecs_*` signals that used
to live in `System/EventBus.gd` went with the observability layer — module 9 now touches
the `EventBus` not at all.)

---

## 1. The whole flow, in order

```
world1.tres  ──►  EcsEntityFactory  ──►  EcsWorld          (once, at startup)
(placements)      resolves each row       ids + component
                  against catalog.tres    tables

every frame, EcsScheduler runs eight systems over that world:

  spawner    adds new entities     → creates ids, files components
  forage     go get a berry        → writes EcsMovementComponent
  low_brain  else wander           → writes EcsMovementComponent
  movement   walks toward it       → writes EcsPositionComponent
  collision  unstacks the bodies   → writes EcsPositionComponent
             (Area2D pool under World/Bodies is a derived index)
  pickup     takes what it reached → removes EcsPositionComponent
  render     draws where it ended  → writes Sprite2D nodes
  debug      reports all of it     → writes the on-entity overlay
```

Read `systems/ecs_low_brain_system.gd`, `ecs_movement_system.gd` and
`ecs_render_system.gd` in that order and you have seen every behaviour in the module.
Each is under 60 lines.

`EcsLowBrainSystem` / `EcsLowBrainComponent` are named for their **rank, not their
behaviour** — they are the bottom of the decision ladder, and what they happen to do
today is wander. The plan's step 6 puts an FSM above them and step 7 a planner; all three
do the same single thing, write a destination into `EcsMovementComponent`, so a smarter
brain replaces this one without movement, render or debug changing a line. Carrying the
component is the whole of "this entity decides for itself".

`EcsDebugSystem` is the odd one out and deliberately so: it is a **pure reader**. It
writes no component and creates no entity, so pulling it out of the scheduler changes the
simulation not at all — which is the cleanest possible demonstration that a system is just
something the scheduler calls. It feeds one dumb view, `EcsDebugOverlay`, which draws on
the entities themselves: name, position, the velocity vector with its heading, and a
dashed line to the ring marking the spot the low brain picked, plus the green circle of
its `EcsShapeComponent` body. **F1** toggles it.

That body is **data, not a `CollisionShape2D` under a `PhysicsBody2D`** — one radius in a
component table. Putting a real physics body there would move the truth back inside nodes
and force every system to read it out of the view, which is the thing this module exists
to avoid.

### Collision is soft, and leans on Godot's broadphase

`EcsCollisionSystem` runs straight after movement: movement proposes a position, collision
corrects it, and neither knows the other exists. Overlap is **allowed to happen and then
undone**, never prevented — no sweep test, no veto inside movement. Applying it as a
constraint after the fact is what makes it compose: anything else that ever writes a
position (knockback, a spawner, a debug teleport) gets cleaned up for free.

**It keeps a pool of `Area2D` under `World/Bodies`, and that is a deliberate exception to
"nothing reads back off a node".** Be precise about what it is: `EcsPositionComponent` is
still the only truth, the pool is a *derived index* rebuilt from it every tick, and the
only thing read back is **which pairs are near each other** — never where anything is.
Delete the pool and the simulation is still complete. That is a different thing from
module 8, where the node *was* the entity. If a future system starts reading state off
these areas, that line has been crossed.

Why bend the rule at all: finding which circles overlap is a spatial-index problem and
Godot ships one in C++. Measured on this machine, per tick:

| n | Area2D | the GDScript O(n²) it replaced | 60Hz tick |
|---|---|---|---|
| 100 | 1.56 ms | 3.82 ms | 9% |
| 200 | 3.24 ms | 13.61 ms | 19% |
| 400 | 6.56 ms | 52.12 ms | 39% |
| 800 | 11.38 ms | 201.84 ms | 68% |
| 1600 | 21.33 ms | ~800 ms | 128% |

Near-linear instead of quadratic. Note where the time actually goes: the physics
broadphase is only ~0.2 ms at 100 entities. The rest is GDScript — which is why `_sync`
gathers component references into parallel arrays once per tick and `_resolve` then never
touches the world. That gather is worth ~30%, and is the reason the system is shaped the
way it is rather than calling `get_component` in the inner loop.

**The pipeline runs on the physics tick**, not the render frame. A simulation wants a
fixed timestep, and `get_overlapping_areas()` is refreshed once per physics step, so
running faster would re-read the same answer.

**One tick of lag.** The overlap list reports what the server saw at the end of the last
step, so a correction always trails the positions that caused it — about two pixels at
walking speed, invisible. It also means the relaxation passes the GDScript version used
are gone: the list cannot be refreshed mid-tick, so it is one pass per tick, converging
over a handful of ticks instead of instantly.
`PhysicsDirectSpaceState2D.intersect_shape()` is the synchronous alternative if that ever
matters — it works same-tick from `_physics_process`, at the cost of a query per body.

Carrying an `EcsShapeComponent` is what makes an entity solid. Anything without one never
gets a body, so it passes through everything with no `solid` flag, no layer mask and no
branch. Every pair is reported twice, A sees B and B sees A; rather than deduplicating,
each body moves only *itself* by half the overlap, so the double report is what makes the
correction symmetric.

Verified: the ten entities spawn piled within ~60 px and separate from 46.6 px of overlap
to under 1 px in ten ticks; **F5** rebuilds without leaking bodies.

**What soft costs:** a fast enough mover can pass through something between ticks, a body
squeezed by two others can be pushed through a third, and there is no bounce — separation
is positional only, velocity is untouched.

### The berry spawner

`EcsSpawnerComponent` is the settings — blueprint id, radius, interval, `max_alive` — and
`EcsSpawnerSystem` is the doing. It runs **first**, so anything born this tick is decided
for, moved, collided, drawn and reported in the same tick, with no frame where a berry
exists but is invisible. Spawning mid-iteration is safe because `query()` returns a
snapshot: new ids are not in the list being walked, and every later system picks them up.

Two things it does differently from module 8's `SimEntitySpawnerComponent`:

- **The component holds no behaviour.** Module 8's ran its own `_process` and did the
  spawning itself.
- **It tracks entity ids, not node references.** Module 8 kept nodes and pruned with
  `is_instance_valid()`. Ids are never reused, so a harvested berry's id goes permanently
  false through `world.is_alive()` and can never alias a later entity. The factory and
  catalog arrive through `_init` rather than a group lookup, so the dependency is visible
  in `main.gd`'s pipeline and cannot go missing at runtime.

**A berry is a sprite and nothing else** — no shape, no movement, no brain. So it is not
solid, cannot move, and never enters the collision query: 36 entities in the world, 12
`Area2D` bodies. No `is_item` flag, no layer mask, no branch. That is the same trick the
deleted dagger prop showed, arriving again for free.

Nothing harvests berries yet, so each bush fills to `max_alive` (12) and stops. That is
the cap working, not a bug.

Verified: 14 entities at t=0 → 36 by t=25s, holding steady, 12 per bush, bodies constant
at 12 throughout.

### Foraging: the decision ladder, made out of run order

`EcsForageSystem` has the *same shape* as `EcsLowBrainSystem` — look at an entity with
nothing to do, write a destination — and it runs **before** it. That is the entire
priority mechanism. Forage gets first refusal; an entity it declines (bag full) falls
through to aimless wandering on its own. No state machine, no priority field, no brain
arbitrating. Adding a third rung is one system and one scheduler line, and neither
existing brain changes.

Both write the same `destination` field, so movement, collision and render never learn
that foraging exists.

### Picking up is removing a component

`EcsPickupSystem` takes anything within the picker's own body radius. The whole of
"leaving the world" is `world.remove(berry, EcsPositionComponent)`:

- the render query stops matching, so the view is freed — nothing was told to hide it
- the forage query stops matching, so nobody walks toward a berry in someone's pocket
- the spawner stops counting it against `max_loose`, so the bush resumes producing

One removed component, three consequences, no `is_carried` flag to keep in step.

**The berry stays a live entity.** This is the inventory version of the weapon pain case.
Module 8's `SimInventoryComponent` could not hold a live entity, so picking something up
took a **blueprint snapshot** of it and destroyed the world entity in the same breath — a
carried thing was a recipe for itself rather than itself. Here nothing is snapshotted and
nothing is destroyed: verified, a held berry reads `alive=true, has position=false,
has sprite=true, has pickable=true`.

Having an `EcsInventoryComponent` is what makes an entity forage, so a berry bush never
goes looking for berries and nothing had to tell it not to. `EcsPickableComponent` is what
separates a berry from the bush — both are sprites sitting in the world, only one answers
the forager's query.

Verified over 50 s: 14 entities → 54, held berries 0 → 30, 6 of 10 bags full, and **54
entities with only 24 drawn** — the held ones have no position. Each animal's `items`
array is its own (the factory's deep copy holds); rabbits carry 3, monkeys 5.

Two known roughnesses, both fine at this scale: two animals can target the same berry and
the loser simply re-targets next tick (module 8 needed an explicit one-claim-per-entity
rule for this; here it self-corrects because the berry stops matching the query), and the
nearest-berry search is O(foragers x berries) with no range cap.

## 6. What was removed, and how to get it back

Everything below was built, worked, and was cut to keep the core readable. It is all in
git at **`928b9d1`**:

```bash
git show 928b9d1 -- "9. EcsSystem"                  # see it
git checkout 928b9d1 -- "9. EcsSystem"              # take the whole module back
git checkout 928b9d1 -- "9. EcsSystem/systems/ecs_attack_system.gd"   # or one file
```

**The combat pipeline** — 10 components (`aggression`, `armor`, `attack_intent`, `broken`,
`crit_chance`, `damage`, `dead`, `durability`, `equipped`, `health`) and 8 systems
(`aggression`, `attack`, `crit`, `damage`, `death`, `durability`, `equip`,
`weapon_carry`), plus `ecs/ecs_event.gd` and `events/ecs_damage_event.gd`.

It was the plan's step 2 and it landed clean. Armour was added to a live entity without
the attack code changing; crits were added by writing one system and appending one line to
the scheduler; a broken weapon fell back to fists with no `if weapon.broken` anywhere;
"attackable" was never a flag, only the target query asking for `EcsHealthComponent`.
**The evidence for the rewrite is in that commit, not in the working tree.**

**The observability layer** — `selection`/`selected`/`commands` components,
`EcsSelectionSystem`, `EcsInspectSystem`, `EcsCensusSystem`, `EcsCommandSystem`,
`ecs_selection_marker.gd`, `ui/ui.tscn` + `ui.gd`, and the four `ecs_*` signals in
`System/EventBus.gd`. Two pieces of it were evidence rather than scaffolding: picking was
a distance query over `EcsPositionComponent` rather than a physics hit, and the
inspector's tabs were built by reflection over `PROPERTY_USAGE_SCRIPT_VARIABLE` with
nothing in the file naming a component type.

**Also trimmed from files that stayed:** `EcsWorld` lost singletons, the frame-event API
and `components_of()`/`count()` (the enumeration accessors the inspector needed);
`EcsSystem` lost `enabled`; `EcsScheduler` lost `find()` and the end-of-frame
`clear_events()`. The crocodile and dagger blueprints were deleted and the monkey
rewritten as a plain wanderer, leaving two entity types; `world1.tres` went from 33
placements to 10 — 5 rabbits and 5 monkeys.

Note one demo went with the dagger: it was the only entity with **no**
`EcsMovementComponent`, so it showed "capability is component presence" — a prop that
cannot move, with no `is_static` flag and no branch. Both current types move. Bringing it
back is one blueprint plus a placement, no code.

## 7. Next, per the plan

**Step 3 is most of the way done.** The plan asked for "inventory and pickup as
relationships (`Inventory{item_ids}`, one system owning the move, so double-claim is
structurally impossible)" — that is exactly what `EcsInventoryComponent` and
`EcsPickupSystem` are. Double-claim is not merely prevented, it stopped being a category:
the berry drops out of the query the moment it is taken, so the second forager re-targets
without anything arbitrating. What step 3 still wants is **eating** — a
`EcsConsumableComponent` and a `ConsumeSystem`, which needs step 4's bars to be worth
doing.

Before starting any of the rest, decide whether it builds on this stripped core or on
`928b9d1`'s fuller one — steps 6 and 7 assume the combat layer that was cut.

- **Step 3 (remainder)** — eat via `ConsumeSystem`, once there is a hunger bar to feed.
- **Step 4** — hunger/fatigue/health as components with a system each. This is the
  natural next step: the forage loop currently has no *reason*, and hunger is the reason.
- **Step 5** — `SensorSystem` writing `Perceived{ids}`; perception becomes a distance
  query over `EcsPositionComponent`, with no node areas. `EcsForageSystem`'s nearest-berry
  scan is already this shape and is where a range cap or spatial index belongs.
- **Step 6** — FSM brain writing move/eat/attack intents. Note the decision ladder is
  already here in miniature: `forage > low_brain` is priority expressed as run order, and
  an FSM is a third rung rather than a rewrite.
- **Step 7** — GOAP planner as a pure function over a symbolic snapshot, run off-frame
  under a replan budget.

## 8. Open arguments — node structure and data structure

**These are unsettled and deliberately so.** Claude made recommendations during the
session that built this; they were **not accepted**, and the author has said explicitly
that both questions are still to be argued out. Nothing below is a plan. Treat it as the
state of a disagreement, so the argument can resume with its context rather than be
re-derived — and do not quietly implement any of it.

### The node-structure argument

What exists: one pool per concern. `EcsRenderSystem` owns `Sprite2D`s under
`World/Entities`, `EcsCollisionSystem` owns `Area2D`s under `World/Bodies`. Each is keyed
by entity id, each has its own lifecycle, each writes position separately.

Positions on the table:

- **Keep pools per concern.** Each system owns exactly what it needs and a concern can be
  deleted in one piece; an entity pays only for the components it has.
- **One view node per entity, children per concern.** Position written once (children
  inherit the transform), one lifetime, one first-tick spike. Collapses to two scene
  parents however many concerns appear. The objection: a per-entity node carrying sprite,
  area and audio is structurally one step from module 8, where the node *was* the entity.
- **No nodes — `PhysicsServer2D` / `RenderingServer` RIDs.** Cheapest, and an RID is
  honest data rather than a Node reference. Costs editor visibility and manual lifetimes.
  The author has said they want to keep using Godot nodes for collision, sprite drawing,
  animation and sound, which argues against this — but it has not been argued *through*.

Also unresolved: whether the `Area2D` pool should exist at all, given it is the one place
the "nothing reads back off a node" rule is bent (§4).

### The data-structure argument

What exists: `_store = { Script : { entity_id : EcsComponent } }`, components as
field-only `Resource` subclasses, queries intersecting tables driven from the rarest.

Open questions, none settled:

- Should a node or RID handle ever live **inside a component** (the `EcsBodyComponent`
  idea)? It would make `EcsCollisionSystem` pure behaviour and split lifecycle from
  resolution — at the cost of the data layer knowing the scene tree exists.
- Should storage stay dictionary-of-dictionaries, or become archetype/packed arrays? The
  API would not change (`ecs_world.gd`'s header already says so), but the measured
  bottleneck is `get_component` call overhead, which archetypes would attack directly.
- Should components be `Resource` at all, given `.tres` authoring only ever uses the
  exported half and every component now carries runtime-only fields beside them?

Nothing here is blocking step 4. It is blocking a decision about what module 9 *is*, which
is a different thing and worth taking the time over.

## 9. Measured performance, on the machine that built this

Intel Iris Xe, GDScript, per tick. Stale the moment the systems change; the shape is the
durable part.

| n | collision (Area2D) | collision (the O(n²) it replaced) |
|---|---|---|
| 100 | 1.56 ms | 3.82 ms |
| 400 | 6.56 ms | 52.12 ms |
| 1600 | 21.33 ms | ~800 ms |

A simple linear system costs **~4–6 µs per entity per tick** (`low_brain` 4.0,
`movement` 4.4, `render` 5.8, `debug` 13.5 — turn the overlay off when measuring anything
else). Budget at 60 Hz: ~30–40 such systems at 100 entities, ~15–20 at 200.

Two levers matter far more than optimising any system, and neither is taken yet:

1. **Decouple sim tick from frame rate.** A colony sim does not need 60 Hz simulation.
   Running the scheduler at 10–20 Hz is a 3–6x headroom multiplier and costs nothing —
   the scheduler already takes `delta`.
2. **Stagger systems across ticks.** Hunger does not need 20 updates a second. Slice the
   query result and run a quarter of the entities per tick.

The first tick after a world is built creates every pooled node at once: 5 ms at 100
entities, 70 ms at 400, 345 ms at 1000 — 97% of it `Area2D` creation. Behind a loading
screen this is free; for a mid-game spawn wave it would need a per-tick creation cap.
