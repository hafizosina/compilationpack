# Module 8 — Handoff Brief

> Continuation context for **CompilationPack / `8. SimpleAiSystem`** (Godot 4.7, GDScript).
> This is the state-of-the-project doc: what actually exists right now.
>
> Companion docs in the same folder describe the *target* design, not the current build:
> `PROJECT_DEFINITION.md` (why / scope) · `COLONY_SIM_CONCEPT.md` (architecture reference) ·
> `MILESTONE_1_SPEC.md` (spec + numbers; §11 is the as-built record).
>
> `HANDOFF_PSEUDOCODE.md` is the companion to *this* doc: every component as
> pseudocode, self-contained enough to paste into a chat and argue about.

---

## 1. What this module is

A **data-driven node-composition ECS foundation** for a colony sim — not the game, the groundwork.
Two pillars from `PROJECT_DEFINITION.md`:

- **Focus 1 — EntityFactory:** one `WorldDef` resource → entities assembled from an `EntityDef`
  blueprint's component list. New content = a new `.tres`, never new code.
- **Focus 2 — GOAP AI:** a planner reasoning over those same components.

Rules the foundation upholds: everything is an Entity; what a thing *is* = which components it has;
capability = component presence; content is data.

---

## 2. Current state

**Phase 1 is complete.** Phase 2 is partly done, and deliberately out of order: the component
interaction layer was built *before* the bars, so the pick-up loop could be exercised end to end
before GOAP arrives.

| Build-order step (`MILESTONE_1_SPEC.md` §1) | Status |
|---|---|
| 1. Bare Entity + Factory + one component | **done** |
| 2. Movement + wander | **done** — wander now lives inside the brain, not its own component |
| 3. Bars — Hunger, Fatigue, Health | **done** — plus collapse, which `FatigueComponent` owns |
| 4. Actions + affordances | **most** — Action, Inventory, PickUpAble, Consumable and the stub vocabulary exist; eating works from pocket and ground. No Harvestable, and actions are still not `ActionDef` data |
| 5. GOAP — hunger only | **not started** |
| 6. Sleep goal | **half** — collapse built (fatigue-owned); the voluntary Rest goal is not |
| 7. Sensor + Flee + predation | **sensor only** |

**What runs today:** 5 animals wander a 3648×2240 map, flocking with their own kind. A berry
spawner drips berries into the world. An animal that senses a berry walks to it and picks it up,
filling its one inventory slot. Hunger drains at 1.0/s; below 50 the animal eats — from its pocket
if it is carrying something, off the ground if not — and goes back to collecting. Fatigue drains at
0.5/s idle and 1.5/s more while travelling; at zero the animal collapses where it stands and wakes
at 50. Health regenerates only while hunger is above 50, and drains while hunger is empty.

**The loop closes.** `hungry → seek → pick up → eat → hungry again` runs unattended. What it still
lacks is a planner deciding any of it — the FSM hardcodes the priority order.

---

## 3. Locked architecture decisions

| Decision | Choice and why |
|---|---|
| **Naming** | Every global `class_name` is `Sim`-prefixed. `Entity` and `InventoryComponent` were taken by `Global/Scene/`, and `ComponentDef` subclasses need a global `class_name` to appear in the inspector's resource picker. |
| **World authoring** | `SimWorldDef` is a flat `entries` list — one `SimPlacement` per entity. Scatter rules were tried and removed: distribution will come from a purpose-built algorithm later, and the factory should only ever *read* a placement list. |
| **World bounds** | Read off the `TileMapLayer` at startup (`SimConst.adopt_bounds_from`). Repaint the map and wander bounds follow; no constant to keep in sync. |
| **Component lookup** | `SimEntity.components` is keyed by **slot** (`&"movement"`), not class name — the slot is already the override key. |
| **`SimEntity` is a plain `Node2D`** | It was a `CharacterBody2D`, but with `collision_mask = 0` nothing ever collided, so `move_and_slide()` reduced to integrating position by hand — no sliding, no floor detection, none of what that node exists for. Movement integrates directly now; `velocity` is a plain field on the entity, kept there because the flock trait reads its neighbours' headings. |
| **Presence is a `Body` Area2D** | With no physics body there is nothing for a sensor to detect, so the entity carries a monitor-**able** but not monitor-**ing** `Body` area. Sensors use `get_overlapping_areas()` and click-picking queries areas; `SimEntity.of(presence)` maps an area back to its entity. One shape serves both, so there is no second set of hitboxes. |
| **Self-description** | Each component owns how it appears in the inspector via `describe()` / `describe_label()`. Returning `{}` opts out — Movement, Sensor and Action do exactly that. Adding a component adds its inspector tab for free. |
| **Stubs — the verb vocabulary** | Components declare which inventory verbs they offer: `consume` (Consumable), `equip` (Equipment), `place_item` (PlaceAble), `throw_item` (PickUpAble). Declared on both `SimComponent.stubs()` and `SimComponentDef.stubs()`, because a thing in the world is a live entity while a thing in a pocket is a blueprint snapshot — the same question must be answerable of both. A holder asks "what can I do with this?" and never checks a type. |
| **One claim, on the entity** | Leaving the world is `SimEntity.claim_snapshot()` — one flag, one route, shared by every affordance that takes a thing. `PickUpAbleComponent` and `ConsumableComponent` are **doors**, not mechanisms: each adds only its own verb and signal. Previously they held independent flags (`_taken`, `_used`), so one berry could be won twice in a frame. Callers must do all their failing first — `take()` checks inventory capacity *before* claiming, because a claim cannot be undone. |
| **One eating path** | `SimHungerComponent.eat(snapshot)` takes a `SimEntityDef` and nothing else. The caller already knows whether it is holding a pocket snapshot or looking at something on the ground — the brain has separate branches for exactly that — so it resolves the thing and hands over a snapshot. No type switch, no `Variant`. `SimConsumableComponent` only hands itself over; it never applies nourishment. The amount lives solely on `SimConsumableDef`, so ground-eating and pocket-eating cannot drift apart — verified identical at +35.0 each. |
| **Nobody disposes of someone else's item** | `SimHungerComponent.eat(snapshot)` only restores itself, then announces `SimEntity.thing_used(verb, target)`; whatever holds that snapshot drops it. Hunger never references Inventory, Inventory never references Hunger — the entity mediates. |
| **Inventory is a preference, not a requirement** | The brain looks in the pocket first because it costs no travel, then at the world. An entity with no inventory just skips the first half and eats off the ground — which is also what happens when its pocket is empty. |
| **Actor asks, target resolves** | `InventoryComponent.try_pick_up()` asks `ActionComponent` "can I reach?" and the target's `PickUpAbleComponent` "take yourself". Action is *the hand* — it knows no specific action, so a future `AttackComponent` reuses it. Movement is *the legs*. |
| **Wander inside the brain** | Wander was its own component driving movement, which meant arbitrating with the brain. Folding it in deleted the problem instead of solving it. |
| **`brain` is a component TYPE** | The slot is the type; each concrete brain is one way of filling it. `SimBrainComponent` is the abstract base, `SimBrainFSMComponent` the state-machine implementation, and a GOAP planner will be another occupying the same slot — so nothing that talks to "the brain" changes when it arrives. |
| **One brain per entity** | `SimBrainDef.build_into()` refuses to build a second brain and pushes an error naming both scripts. Two brains sharing one set of legs would fight over every `move_to`. The check lives on the base def, so every future brain kind inherits it. |
| **Traits** | `SimBrainDef.traits: Array[SimTrait]` — behaviour modifiers consulted at defined hooks. No traits = default behaviour. This is how entities sharing one brain behave differently, with no subclass and no branch. `SimFlockTrait` is the first. |
| **No Bed** | Sleep is self-directed, so nothing to path to and nothing to advertise it. |
| **Collapse is not a decision** | `FatigueComponent` owns it end to end: at zero it sets the entity's `is_sleeping`, switches the brain off, watches its own value, and switches the brain back on at 50. No health penalty — the helpless window is the cost. The brain holds no sleep code. |
| **Sleep state on the entity** | `SimEntity.is_sleeping` is a flag any component may read. Hunger slows its drain from it without ever touching Fatigue, so the two bars stay independent. |

---

## 4. What exists

```
8. SimpleAiSystem/
  sim_const.gd                 speeds, sprite scale, entity layer, edge margin, world_bounds
  main.gd / main.tscn          entry point, click-to-select, F1 labels, F5 respawn
  selection_marker.gd          selection ring + the selected entity's sensor and reach circles
  entity/
    sim_entity.gd/.tscn        bare base: Node2D + Sprite2D + Body(Area2D)
    sim_entity_factory.gd      spawn_world(), deep-dup defs, per-instance overrides, group "sim_factory"
  components/
    sim_component.gd           base: entity from parent; slot(), describe(), describe_label()
    sim_movement_component.gd  move_to / stop / is_moving, arrived signal
    sim_sensor_component.gd    Area2D; get_detected(), nearest_with(slot)
    sim_action_component.gd    extends Sensor; in_reach() only — the hand
    sim_inventory_component.gd capacity, try_pick_up(), find_with_stub(), carry badge (PROTOTYPE)
    sim_consumable_component.gd    world-side `consume`; nourishment
    sim_equipment_component.gd     `equip` — DECLARED, NOT IMPLEMENTED
    sim_place_able_component.gd    `place_item` — DECLARED, NOT IMPLEMENTED
    sim_bar_component.gd       base for the three needs
    sim_health_component.gd / sim_hunger_component.gd / sim_fatigue_component.gd
    sim_pick_up_able_component.gd  target side of pick-up
    sim_brain_component.gd     abstract base: the `brain` slot, is_thinking()
    sim_brain_fsm_component.gd seek / feed / wander state machine, consults traits
    sim_entity_spawner_component.gd  periodic spawn (TEMPORARY, stands in for a bush)
    sim_debug_component.gd     per-entity labels (F1), injected under Constant.DEBUG
  defs/
    sim_component_def.gd  sim_entity_def.gd  sim_entity_catalog.gd
    sim_placement.gd  sim_world_def.gd
    components/   sprite, movement, sensor, action, inventory, pick_up_able, brain, entity_spawner
    traits/       sim_trait.gd  sim_flock_trait.gd
    blueprints/   animal.tres  berry.tres  berry_spawner.tres
    catalog.tres  world1.tres
  ui/ui.gd / ui.tscn           top-right world stats; bottom-left tabbed entity inspector
```

Shared code touched outside the module: `System/EventBus.gd` gained `sim_world_spawned(census)`,
`sim_respawn_requested()`, `sim_entity_inspected(details)`. `Global/Theme/main_theme.tres` gained
`TabBar` styles and the `SimLabel` / `SimTitle` / `SimPanel` / `SimVBox` / `SimHBox` type variations
(scoped to the sim inspector; modules 1–7 untouched).

**Controls:** left-click an entity to inspect it (+ its sensor and reach circles); click bare ground
to clear; **F1** toggles per-entity debug labels; **F5** respawns from `world1.tres`.

---

## 5. The three blueprints

| | `animal` | `berry` | `berry_spawner` |
|---|---|---|---|
| Art | `Animal/monkey.png` @ 0.5 | `CircleButtonFull.png` @ 0.32, pink | `CircleButtonFull.png` @ 0.7, green |
| Components | sprite, movement, sensor, action, inventory, health, hunger, fatigue, brain | sprite, pickupable, consumable | sprite, spawner |
| Tuning | walk 130 / run 260, sensor 420, reach 56, capacity 1, think 0.25 s, wander step 420 | nourishment 35 | spawns `berry`, radius 1000, every 5 s, max 40 alive |
| Bars | health 100 (regen 1/s while fed), hunger 100 (drain **1.0/s**), fatigue 100 (drain **0.5/s** idle, **+1.5/s** moving, wakes at 50) | — | — |
| Traits | `SimFlockTrait` (weight 0.55, separation 110) | — | — |

Everything not listed under Tuning is the def's own default — only the values above are authored in
the `.tres`. Component *order* in the list is build order.

`world1.tres`: 5 × `animal`, 1 × `berry_spawner`. **No pre-placed berries** — the spawner supplies them.

---

## 6. Deliberately temporary

- **`SimEntitySpawnerComponent`** stands in for a berry bush. The real bush is a
  `HarvestableComponent` whose `ActionDef` carries a `SpawnOutput`, and that needs the action system
  first. The spawner itself is generic (any catalog blueprint) and may well survive as a nest or
  resource node.
- **The carry badge** in `SimInventoryComponent` — a component that holds state should not also
  render. Marked `PROTOTYPE ONLY` in place, with a removal checklist. `changed(total)` is the seam a
  real indicator should use.

---

## 7. What's next

Step 3 is done and the food loop closes, so the next move is **finishing step 4 — actions as data**.

**Why that one:** the FSM currently hardcodes its priority order, and every affordance is a method
someone knows to call. A planner cannot read either. `ActionDef {input, time, output, mode}` is what
turns "pick up" and "eat" into things with declared preconditions and effects — which is exactly
what step 5 needs, and the only reason to build it before GOAP rather than alongside.

It also unblocks the real berry bush: `HarvestableComponent` is an `ActionDef` carrying a
`SpawnOutput`, which is what retires the `[TEMP]` `SimEntitySpawnerComponent`.

**Two things to settle before step 5:**
- Does GOAP *replace* `SimBrainComponent`, or sit behind it as the planner with the current state
  machine as executor? Worth deciding before more brain code is written.
- Actions are still hardcoded. Step 4 is not finished until `ActionDef {input, time, output, mode}`
  exists, because that is what a planner reads preconditions and effects from.

**Still open, lower priority:** items are not data. Pick-up stores a whole `SimEntityDef` snapshot,
which works but is heavier than needed; `COLONY_SIM_CONCEPT.md` §2 specifies a small `SimItemDef`
(id, colour, food value) instead. That would also remove the carry badge's colour lookup.

---

## 8. Open design questions

Unresolved in `COLONY_SIM_CONCEPT.md` §9, grouped by the step that needs them.

**Step 3 (bars)**
- Hunger / energy drain rates and starvation damage per tick.
- Passive fatigue drain, or only movement and actions?

**Steps 4–5 (actions, food loop)**
- Do berry bushes deplete (give them a `HealthComponent`) or stay infinite? Regrowth timer?
- Live-harvest numbers (10 energy / 2 meat / 35 dmg) — defaults?
- `Hunt` instant vs damage-over-work-time.

**Steps 6–7 (sleep, flee, predation)**
- Danger rise/decay rates; the danger → flee curve shape.
- Does extreme hunger wake a safe sleeper?
- **Chase balance:** predators run 1.4× prey, so a committed chase always wins. Aggro/give-up
  mechanic, or rely on prey's 1.3× detection as the counterweight?

**Deferred from the prototype**
- The three-creature design (vigilant vs fast prey, one predator) still stands in the concept doc.
  The current two-type world exists to test component interaction, not to replace it.
- Wander is a pure random walk; no memory of where an entity has already searched. The last berry
  on a large map can take minutes to find.

---

## 9. Known rough edges

- **The entity scene's `CircleShape2D` is a shared sub-resource.** Nothing resizes it today, but a
  def wanting per-type body sizes must `duplicate()` it first — the shared-state bug the factory's
  `duplicate(true)` guards against, relocated.
- **Some API is intentionally unused — do not "clean" it.** A dead-code scan will flag
  `SimEntity.do_actions()` / `receive_actions()`, `SimMovementComponent.arrived`,
  `SimPickUpAbleComponent.picked_up`, `SimInventoryComponent.changed`, and
  `SimEntityCatalog.add_def()` / `has_def()`. All are declared design surface with no consumer *yet*;
  each is marked in place.
- **Inspector scrollbar is Godot default grey**, not the medieval palette. Theming `VScrollBar`
  would also restyle module 7's inventory, which shares the theme.
- No tests, no build scripts — the editor is the toolchain, per `CLAUDE.md`.

---

## 10. How to run and verify

The Godot editor is installed via Steam and is **not on PATH**:

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"

# Run (run/main_scene already points at module 8)
"$GODOT" --path .

# Headless validation — ALWAYS after hand-editing .tscn / .tres
"$GODOT" --headless --editor --quit --path . 2>&1 | grep -iE "error|invalid|uid"
```

Hand-edited scene/resource files are this repo's main breakage risk. Two traps hit during this work:

1. Write `.gd` files first, run the headless import once so Godot generates the `.uid` siblings,
   read those uids, *then* write the `.tscn`/`.tres` that reference them. A guessed uid resolves by
   path with only a warning.
2. **A parse failure can delete a declaration.** When a hand-written `traits =` line failed to parse,
   the editor's next save pruned the now-orphaned `ext_resource` for that script — so fixing the line
   alone left it referencing an id that no longer existed. Check `load_steps` and the `ext_resource`
   block after any failed parse.

Conventions: typed GDScript (`:=`, typed params/returns), `##` doc comments on every `@export` and
public method, conventional one-line commit messages on `main` with no trailers.
