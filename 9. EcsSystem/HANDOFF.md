# Module 9 — EcsSystem: state of the build

Greenfield hand-rolled ECS, built beside `8. SimpleAiSystem` per `ECS_REFACTOR_PLAN.md`.
Module 8 keeps running untouched as the behavioural reference.

**The module has been deliberately stripped to its bare minimum** — one world, one
scheduler, four systems — so the flow reads end to end without hunting. What was cut is
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

every frame, EcsScheduler runs four systems over that world:

  low_brain  picks a destination   → writes EcsMovementComponent
  movement   walks toward it       → writes EcsPositionComponent
  collision  unstacks the bodies   → writes EcsPositionComponent
             (Area2D pool under World/Bodies is a derived index)
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

Steps 3–7 are not started. Before starting one, decide whether it is built on this
stripped core or on `928b9d1`'s fuller one — several of them assume the combat layer.

- **Step 3** — inventory and pickup as relationships (`Inventory{item_ids}`, one system
  owning the move, so double-claim is structurally impossible); eat via `ConsumeSystem`.
- **Step 4** — hunger/fatigue/health as components with a system each.
- **Step 5** — `SensorSystem` writing `Perceived{ids}`; perception becomes a distance
  query over `EcsPositionComponent`, with no node areas.
- **Step 6** — FSM brain writing move/attack/eat intents, reproducing module 8's
  hungry→seek→eat loop. That is when module 8 can be retired.
- **Step 7** — GOAP planner as a pure function over a symbolic snapshot, run off-frame
  under a replan budget.
