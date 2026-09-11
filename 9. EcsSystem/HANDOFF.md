# Module 9 — EcsSystem: state of the build

Greenfield hand-rolled ECS, built beside `8. SimpleAiSystem` per `ECS_REFACTOR_PLAN.md`.
Module 8 keeps running untouched as the behavioural reference.

**Steps 0–2 of the plan's port order are done, plus an observability layer the plan
never listed** (§5 below). Steps 3–7 are not started.

`project.godot`'s main scene is **now module 9** (`uid://daecsmain0001`), so a plain run
opens this module. That is ahead of the plan, which held the switch until module 9 had
reproduced module 8's loop at step 6 — the swap was made because module 9 is what is
being worked on, not because it is finished. Module 8 is untouched and still the
behavioural reference; run either directly:

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
"$GODOT" --path . "res://9. EcsSystem/main.tscn"
"$GODOT" --path . "res://8. SimpleAiSystem/main.tscn"
```

Two things outside this folder belong to module 9 and would be lost if the folder were
moved alone: the main-scene line in `project.godot`, and four `ecs_*` signals in
`System/EventBus.gd` (`ecs_world_census`, `ecs_respawn_requested`,
`ecs_entity_inspected`, `ecs_pipeline_changed`).

---

## 1. The core (~100 lines of code)

Five scripts in `ecs/`:

| Script | Role |
|---|---|
| `ecs_world.gd` | entity ids, component tables, the query engine, singletons, frame events |
| `ecs_component.gd` | base: `extends Resource`, fields only |
| `ecs_system.gd` | base: `run(world, delta)` |
| `ecs_scheduler.gd` | ordered system list; `run_all()` then drops the frame's events |
| `ecs_event.gd` | base for transient inter-system records |

Storage is `{ Script : { entity_id : EcsComponent } }` and a query intersects the
tables it was asked for, driving the scan from the rarest one. **Queries key on the
script object, not a string** — `world.query([EcsPositionComponent])`, so a typo is a
parse error rather than a silently empty result.

`EcsWorld` is 166 lines with docs, **101 without**. The plan's kill criterion was
"abandon if the query layer passes ~150 lines"; it is not close.

Two API notes:

- The read accessor is **`get_component()`**, not `get()` — `Object.get(property)`
  already exists and GDScript will not let it be redefined.
- Entity id **0 is `EcsWorld.NO_ENTITY`**, so an unresolved relationship field reads
  false through `is_alive()` with no null dance. Ids are never reused, so a stale id
  goes permanently false instead of aliasing a new entity.

`components_of()` and `count()` exist for the inspector and the stats panel — an
enumeration accessor for the one reader that has to show an entity without knowing what
it is. Ordinary systems ask for the components they want by type and never enumerate.

### The rules, and where each is enforced

- **Components hold data only.** The single method on `EcsComponent` is `key()`, which
  returns a constant — identity, not behaviour. It exists so a `.tres` override block
  and the HUD can name a component; storage never uses it.
- **Systems hold all behaviour**, and never call each other. They coordinate through
  components, frame events and run order.
- **Nothing outside a system mutates component data.** This survives contact with the
  keyboard and the mouse: `main.gd`'s debug keys append to an `EcsCommandsComponent`
  singleton and a click writes a pick request to an `EcsSelectionComponent` singleton.
  `EcsCommandSystem` and `EcsSelectionSystem` apply them on the next frame.

## 2. Entities are ids; nodes are views

`EcsRenderSystem` owns a pool of `Sprite2D`s under `World/Entities`, keyed by entity id,
created when an id starts matching `[Position, Sprite]` and freed when it stops. Data
flows one way, world → node. Nothing reads back off a node, which is why the whole
simulation runs headless (that is how the acceptance test below was verified).

`EcsSelectionMarker` under `World/SelectionMarker` is the same deal: unlike module 8's
marker it follows nothing, holds no entity reference and runs no `_process` —
`EcsSelectionSystem` pushes it a position and a radius each frame.

`EcsDeathSystem` darkens the *sprite component's* tint rather than a node's modulate.
Appearance is a fact about the entity; the view just renders whatever the data says.

## 3. The data layer

`defs/` mirrors module 8's shape — catalog of blueprints, placement list, per-instance
deep-duplication, overrides keyed by component — with **one layer deleted**.

Module 8 needed a `SimComponentDef` subclass per component: a blueprint could not hold a
live component, so each def carried the authored config *and* the code to build a node
from it. Here a component is already pure data, so `EcsEntityDef.components` holds the
components themselves and `EcsEntityFactory` copies them. The entire parallel
`defs/components/*.gd` hierarchy vanished the moment behaviour left the components.
`ecs_entity_factory.gd` is 85 lines (54 of code) and still never switches on component
type.

Identity and position come from the placement, not the blueprint — every entity has
both, and neither is a property of its type. Everything else comes from the blueprint.

Authored relationships point at **names**, not ids: a `.tres` cannot know a runtime id,
so `monkey_0`'s placement overrides `equipped.weapon_name` to `&"dagger_0"` and
`EcsEquipSystem` resolves that against the name table once, after spawning. Edit
`world1.tres`, press **F5**, see the change with no code touched.

## 4. Step 2 — the pain case, and whether it landed

The pipeline, in scheduler order (`main.gd::_build`):

```
command > equip > wander > movement > weapon_carry > aggression > attack >
crit > damage > durability > death > selection > render > census > inspect
```

Decide, then act, then resolve the consequences, then draw the result, then report it.

**The weapon is an entity id with a `EcsDurabilityComponent` row.** Not a de-noded
resource, not a value copied into its holder. `EcsEquippedComponent{weapon_id}` on the
wielder is the whole of "wielding". Durability is mutated by the one system that queries
it; nobody reaches into the weapon, and nobody had to agree not to.

Each of the three systems reads exactly the part of a `EcsDamageEvent` that only it can
resolve:

| System | Reads | Writes |
|---|---|---|
| `EcsAttackSystem` | attacker's `Equipped`, weapon's `Damage` (else attacker's own) | emits `EcsDamageEvent` |
| `EcsDamageSystem` | target's `Armor` | target's `Health` |
| `EcsDurabilitySystem` | — | weapon's `Durability` |

Module 8's hand-held discipline "each side resolves only what it alone can know" is now
just the shape of the queries. There is nothing to enforce.

### Acceptance test — verified headless, not asserted

Run `main.tscn`; **F3** toggles an `EcsArmorComponent` on `crocodile_0`, **F2** pulls
`EcsCritSystem` out of the pipeline. Observed, in one run:

```
t=3   crocodile 79.5 -> 70.5     dagger hits for 9,  wear 2/6
>>> F3: give crocodile_0 an EcsArmorComponent
t=4   crocodile 65.5 -> 60.5     same dagger now lands 5 (9 - 4),  wear 0/6
t=5   dagger BROKEN, damage row stripped
t=6   crocodile 59.5 -> 56.0     monkey falls back to fists: 3 x 2.5 crit - 4 armour
>>> F2: pull EcsCritSystem out of the pipeline
t=9   crocodile 56.0 -> 55.0     fists: 3 - 4, floored at armour minimum 1
```

- **Armour was added to a live entity and the attack code did not change.** It cannot —
  `EcsAttackSystem` has no way to name armour.
- **Crits were added by writing one system and appending one line to the scheduler.**
  Neither the attack nor the damage system mentions crits.
- **A broken weapon is not a branch.** `EcsDurabilitySystem` removes the weapon's
  `EcsDamageComponent`; `EcsAttackSystem` then finds nothing on the weapon and falls
  back to the attacker's own damage on its own. There is no `if weapon.broken` anywhere.
- **"Attackable" is not a flag.** It is the target query asking for `EcsHealthComponent`.
  The 30 wandering rabbits have none, so they are invisible to aggression with no
  special case, no faction system and no layer mask.

Per the plan's §7, step 2 landing clean means none of the kill criteria trigger.

## 5. The observability layer — not a plan step, built anyway

Four systems and a HUD scene landed after the plan's step 2, so the module could be read
while it runs. They are worth knowing about because two of them are evidence for the
rewrite rather than scaffolding around it.

| Piece | What it does |
|---|---|
| `EcsSelectionSystem` | consumes the click request, moves the `EcsSelectedComponent` tag, drives the marker |
| `EcsInspectSystem` | 5 Hz snapshot of the tagged entity onto `EventBus.ecs_entity_inspected` |
| `EcsCensusSystem` | 2 Hz entity count onto `EventBus.ecs_world_census` |
| `ui/ui.tscn` + `ui.gd` | stats block, tabbed inspector, and the live pipeline read-out |

- **Picking is a query, not a physics hit.** Module 8 point-queried a per-entity
  `Area2D`; here it is a distance test over `EcsPositionComponent` with each candidate's
  radius read off its own sprite, so there is no second set of hitboxes to keep in sync.
  This is the plan's claim about perception collapsing into queries, arriving early.
- **The inspector's tabs are built by reflection.** Module 8 needed a `describe()` on
  every component, hand-written per kind and kept in step with its fields. A component
  here is a field-only Resource, so `EcsInspectSystem` reads
  `PROPERTY_USAGE_SCRIPT_VARIABLE` off `get_property_list()` — the script's own
  declarations, in declaration order. **Nothing in that file names a component type**, so
  a new component kind gets a tab with its fields and neither file changes. An int field
  named `*_id` is rendered as the target's name, so a relationship reads as
  "this monkey wields that dagger".
- The panel holds no reference to an entity, the world or the scheduler. Counts,
  snapshots and the pipeline text all arrive on the `EventBus` already formatted, and
  the respawn button asks for a rebuild the same way.

Controls: **left-click** an entity to inspect it and see the reach it can strike within,
click bare ground to clear; **F2** toggles the crit stage, **F3** toggles the
crocodile's armour, **F5** rebuilds the world from data.

## 6. What is deliberately a placeholder

`EcsAggressionSystem` is the brain seat from step 6 — "swing at the nearest attackable
thing in reach, on a timer". It consults no weapon, no armour, no durability; it cannot
even tell whether the swing will land. All it produces is an
`EcsAttackIntentComponent`. Swapping it for an FSM and then a planner changes nothing
downstream, because all three write the same intent component.

## 7. Next, per the plan

- **Step 3** — inventory and pickup as relationships (`Inventory{item_ids}`, one system
  owning the move, so double-claim is structurally impossible); eat via `ConsumeSystem`.
- **Step 4** — hunger/fatigue/health as components with a system each.
- **Step 5** — `SensorSystem` writing `Perceived{ids}`; perception becomes a distance
  query over `EcsPositionComponent`, with no node areas. `EcsSelectionSystem` already
  does this shape of query, so there is a working precedent to copy.
- **Step 6** — FSM brain writing move/attack/eat intents, reproducing module 8's
  hungry→seek→eat loop. That is when module 8 can be retired — and the point the main
  scene was meant to switch, which it already has.
- **Step 7** — GOAP planner as a pure function over a symbolic snapshot, run off-frame
  under a replan budget.

Not started, and deliberately not designed for yet.
