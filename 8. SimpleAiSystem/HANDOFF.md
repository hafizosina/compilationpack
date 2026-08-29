# Module 8 — Handoff Brief

> Continuation context for **CompilationPack / `8. SimpleAiSystem`** (Godot 4.7, GDScript).
> Phase 1 is complete and committed. This doc is what a fresh conversation needs to
> pick up Phase 2 without re-reading the code.
>
> Companion docs in the same folder: `PROJECT_DEFINITION.md` (why / scope),
> `COLONY_SIM_CONCEPT.md` (architecture reference), `MILESTONE_1_SPEC.md` (buildable spec + numbers).

---

## 1. What this module is

A **data-driven node-composition ECS foundation** for a colony sim — not the game, the groundwork.
Two pillars from `PROJECT_DEFINITION.md`:

- **Focus 1 — EntityFactory:** one `WorldDef` resource → 30+ entities, each assembled from an
  `EntityDef` blueprint's component list. New content = a new `.tres`, never new code.
- **Focus 2 — GOAP AI:** a planner reasoning over those same components, proving the structure
  actually feeds behaviour.

Design rules the foundation must uphold: everything is an Entity (creatures, props, items alike);
what a thing *is* = which components it has; capability = component presence; content is data.

---

## 2. Status — Phase 1 complete

All four done-criteria from `PROJECT_DEFINITION.md` verified by running the game:

| Criterion | Result |
|---|---|
| 30+ entities from `world1.tres` | **31** — 12 type1, 4 type3, 3 type2, 8 berrybush, 4 bed |
| Editing `.tres` changes the result, no code | Bumped a scatter count and added a whole new Type4 → 42 entities with its own art/tint/radius, zero code touched |
| No shared-state bug | Two type1s with wander overrides + the default read **48 / 256 / 400** — three distinct radii |
| A component attaches and ticks | Over 3s: **19 moved, 12 still** — the 12 are exactly the props, which have no movement component |

Runs at 60 fps, Vulkan Forward Mobile.

**Phase 1 covered `MILESTONE_1_SPEC.md` §1 build-order steps 1–2 plus the debug overlay.**
Steps 3–7 are Phase 2 and are NOT started.

---

## 3. Locked architecture decisions

Decided during Phase 1, with reasons — do not silently revisit these.

| Decision | Choice and why |
|---|---|
| **Naming** | Every global `class_name` is `Sim`-prefixed (`SimEntity`, `SimComponentDef`, `SimMovementComponent`). `Entity` and `InventoryComponent` were already taken by `Global/Scene/`, and `ComponentDef` subclasses *need* a global `class_name` to appear in the inspector's resource picker. |
| **World authoring** | `SimWorldDef` is a flat `entries` list — one `SimPlacement` per entity (`type`, `position`, optional `overrides`). Bulk scatter rules were tried and removed: distribution will come from a purpose-built algorithm later, and the factory should only ever *read* a placement list, never generate one. |
| **Scale** | Rebased on the 64px painted tilemap: `GRID_SIZE 64`, walk 120, run 240, sprite scale 0.5, `WORLD_BOUNDS = Rect2(-192, -192, 2048, 1216)`. Energy-per-grid costs unchanged, so one "grid" is now one visible tile. Spec docs updated to match. |
| **Component lookup** | `SimEntity.components` is keyed by **slot** (`&"movement"`), not class name — the slot is already the override key, so one identifier does both jobs. |
| **No `Body` Area2D** | The concept doc gave each entity a separate Area2D for presence. Removed: an Area2D sensor detects a `CharacterBody2D` directly via `body_entered` / `get_overlapping_bodies()` (verified live). The body's own `BodyShape` is the presence — `collision_layer` keeps it detectable, `collision_mask = 0` stops entities shoving each other. Sensor radius and action reach stay separate areas on the *actor*. |
| **Self-description** | Each component owns how it appears in the inspector via `describe() -> Dictionary` and `describe_label() -> String`. `SimEntity.describe()` only aggregates and never inspects the contents. Adding a component kind adds its inspector tab for free. |

---

## 4. What exists

```
8. SimpleAiSystem/
  sim_const.gd                 static consts (grid, speeds, world bounds); NOT an autoload
  main.gd / main.tscn          entry point, click-to-select, F1/F5
  selection_marker.gd          selection ring + the selected entity's wander leash
  entity/
    sim_entity.gd/.tscn        bare base: CharacterBody2D + Sprite2D + BodyShape
    sim_entity_factory.gd      spawn_world(), deep-dup defs, per-instance overrides
  components/
    sim_component.gd           base: resolves entity from parent; slot(), describe(), describe_label()
    sim_movement_component.gd  move_to/stop/is_moving, arrived signal
    sim_wander_component.gd    drunkard's walk leashed to home_position
    sim_debug_component.gd     per-entity labels (F1), factory-injected under Constant.DEBUG
  defs/
    sim_component_def.gd       abstract: slot(), build_into()
    sim_entity_def.gd  sim_entity_catalog.gd
    sim_placement.gd  sim_world_def.gd
    components/                sim_sprite_def, sim_movement_def, sim_wander_def
    blueprints/                type1 type2 type3 berrybush bed
    catalog.tres  world1.tres
  ui/ui.gd / ui.tscn           top-right world stats; bottom-left tabbed entity inspector
```

Shared code touched outside the module: `System/EventBus.gd` gained
`sim_world_spawned(census)`, `sim_respawn_requested()`, `sim_entity_inspected(details)`;
`Global/Theme/main_theme.tres` gained `TabBar` styles.

**Controls:** left-click an entity to inspect it (+ its wander leash); click bare ground to clear;
**F1** toggles per-entity debug labels; **F5** respawns from `world1.tres`.

---

## 5. Deviations from the spec docs

Recorded in `MILESTONE_1_SPEC.md` §11:

1. `Sim` prefix on every global `class_name`.
2. `SimSpriteDef` adds no node — it configures the `Sprite2D` the base scene already owns and
   registers it under the `sprite` slot, so the factory has zero special cases.
3. The factory `add_child`s **before** building components (the spec pseudo-code does the reverse);
   `@onready` members are null until the entity is in the tree.
4. No `Body` Area2D on the base scene (see §3 above).

---

## 6. Phase 2 — what's next

`MILESTONE_1_SPEC.md` §1 build order, remaining steps. Each must run before the next is added.

- **Step 3 — Bars.** `SimHungerDef/Component`, `SimFatigueDef/Component`, `SimHealthDef/Component`
  that drain and tick. Starter numbers in §4 of the spec: hunger 100 draining 1.0/s, `=0` → −2 hp/s;
  fatigue 100 draining 0.5/s idle + movement cost, `=0` → −20 hp once + collapse; health 100,
  regen +1/s while hunger > 50. **Each gets an inspector tab for free** via `describe()`.
- **Step 4 — Actions + affordances.** `ActionDef` resources (input / time / output / mode),
  `SimActionComponent`, `SimInventoryComponent`, and the target-side components
  (`Eatable`, `Harvestable`, `PickUpAble`, `Receiver`). Prove the perform → receiver → effect
  handshake by hard-calling one action.
- **Step 5 — GOAP, hunger only.** `SimBrainComponent` + planner, the `[harvest, pickUp, eat]` chain.
  Success: herbivores feed themselves.
- **Step 6 — Sleep goal.** Rest goal, sleeping in place, plus the collapse penalty. There is no Bed
  entity: sleep is self-directed, so nothing to path to and nothing to advertise it. Voluntary rest
  is free and interruptible; collapse at 0 fatigue costs **20 HP** and is **sleep-locked until 50%
  energy**.
- **Step 7 — Sensor + Flee + predation.** `SimSensorComponent` (Area2D radius per type: 260 / 200 /
  140 after the 64px rebase), the Danger bar, `AttackComponent` do-side, live-harvest damage.

Ship nothing past step 7 for this milestone.

**Suggested starting point: step 3.** GOAP, flee and the sensor all read from the bars, and the
sensor's filtering should key off *which components a target has* (a threat is anything with an
`AttackComponent`), which needs the bars and affordances to exist first.

---

## 7. Open design questions

Still unresolved in `COLONY_SIM_CONCEPT.md` §9 — worth deciding before or during the steps that need them:

**Needed for step 3 (bars)**
- Hunger / energy drain rates and starvation damage per tick — spec has starter numbers, are they right?
- Passive fatigue drain, or only movement and actions? (An idle well-fed entity otherwise never tires.)

**Needed for step 4–5 (actions, food loop)**
- Do berry bushes deplete (give them a `HealthComponent`) or stay infinite? Regrowth timer?
- Live-harvest numbers (10 energy / 2 meat / 35 dmg) — tunable per def, but what defaults?
- `Hunt` instant vs damage-over-work-time (must out-pace the +1/s regen; burst is fine).

**Needed for step 6–7 (sleep, flee, predation)**
- Danger rise/decay rates; the danger → flee curve shape.
- Does extreme hunger wake a safe sleeper?
- **Chase balance:** Type2 runs 1.4× Type1, so a committed predator always wins a straight chase.
  Give Type2 an aggro/give-up mechanic (energy or timeout), or keep predator dominance and rely on
  Type1's 1.3× detection for the counterweight?

**The experiment the whole thing exists to run**
- Type1 (vigilant, slow) vs Type3 (oblivious, fast) on one map, same predator — does awareness or
  speed win? Needs step 7 before it can be observed.

**New, from Phase 1**
- Wander currently leashes to the **spawn point** permanently. Should `home_position` ever migrate
  or stay fixed for the whole run?
- Wander radius/interval per type, and smoothed vs pure-random heading (currently pure random).

---

## 8. Known rough edges

Deliberate, small, and safe to leave — but they'll bite eventually.

- **The entity scene's `CircleShape2D` is a shared sub-resource.** Every instance of
  `sim_entity.tscn` shares it. Nothing resizes it today, but the moment a def wants a per-type body
  size it must `duplicate()` the shape first — the same shared-state bug the factory's
  `duplicate(true)` guards against, just relocated.
- **Inspector scrollbar is Godot default grey**, not the medieval palette. Theming `VScrollBar`
  would go in the shared `main_theme.tres`, which `7. JoyStick/inventory_panel.tscn` also uses —
  so it would restyle module 7's inventory too. Left alone on purpose.
- **Inspector panel is a fixed 300×300**, so sparse tabs show visible parchment slack. The
  alternative (hug content, cap at a maximum) is a small change if the slack annoys.
- **Debug labels cost frames.** 31 entities each drawing outlined text every frame is fine now;
  it was the leash circles (19 arcs/frame, 60 → 44 fps) that hurt, which is why the leash now draws
  only for the selected entity.
- No tests, no build scripts — the editor is the toolchain, per `CLAUDE.md`.

---

## 9. How to run and verify

The Godot editor is installed via Steam and is **not on PATH**:

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"

# Run (run/main_scene already points at module 8)
"$GODOT" --path .

# Headless validation — ALWAYS after hand-editing .tscn / .tres
"$GODOT" --headless --editor --quit --path . 2>&1 | grep -iE "error|invalid|uid"
```

Hand-edited scene/resource files are this repo's main breakage risk: `.tscn`/`.tres` reference each
other by `uid://`, every `.gd` has a sibling `.gd.uid`, and a wrong uid **fails silently in-editor**.
Write `.gd` files first, run the headless import once so Godot generates the `.uid` siblings, read
those uids, *then* write the `.tscn`/`.tres` that reference them.

Conventions: typed GDScript (`:=`, typed params/returns), `##` doc comments on every `@export` and
public method, conventional one-line commit messages on `main` with no trailers.
