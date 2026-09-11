# CompilationPack — Project Summary

**Engine:** Godot 4.7 | **Renderer:** Mobile | **Viewport:** 1612 × 720 | **Target:** Android

**Main scene:** `9. EcsSystem/main.tscn` — module 8 remains the behavioural reference it is being rebuilt against.

A numbered collection of self-contained game-system demos written in GDScript. Each folder is an isolated experiment; shared infrastructure lives in `System/` and `Global/`.

---

## Module Overview

### 1. PathFindingSystem
Basic NavigationAgent2D usage. A `CharacterBody2D` entity continuously follows the mouse cursor using `get_next_path_position()`. Demonstrates the minimum viable pathfinding setup with optional avoidance.

**Key file:** `1. PathFindingSystem/entity.gd`

---

### 2. PathFindingWithWeight
Enhanced pathfinding on a weighted tilemap. Tile `travel_cost` custom data is read at startup and applied to NavigationServer2D regions, so different terrain costs more to traverse.

- Left-click: place navigation target (snapped to 16×16 grid center)
- Right-click: teleport entity to clicked cell

**Key files:** `2. PathFindingWithWeight/entity.gd`, `tile_map_layer.gd`, `main.gd`

---

### 3. ControlPathFinding
Extends the pathfinding concept with a UI toggle that overlays travel-cost visualisation. Uses a global A* signal bus (`GlobalAstar2` autoload with `toggle_overlay_travle_cost` signal).

**Key file:** `3. ControlPathFinding/global_astar2.gd`

---

### 4. SelectionSystem
Rubber-band drag-select for RTS-style unit selection. Draws a translucent blue selection box during drag; release finalises the selection. Shift-held appends to existing selection.

**Architecture:** `SelectionManager` (Node2D) queries all nodes in the `"select_able"` group. Each unit carries a `SelectAbleComponent` that handles circle-rect intersection, visual feedback, and group membership (`"selected"`).

**Key files:** `4. SelectionSystem/selection_manager.gd`, `select_able_component.gd`

---

### 5. Boid
Boid flocking simulation scaffold. `SenseComponent` creates a circular collision area with radius `entity.size × 10`. Actual flocking steering vectors are work-in-progress.

**Key file:** `5. Boid/sense_component.gd`

---

### 6. GraphDb
An in-memory graph/relational database implemented in GDScript. Supports ORM-style record management and three relationship types:

| Operation | Method |
|-----------|--------|
| Save / update | `GraphDb.save(record)` |
| Find by ID | `GraphDb.find(ModelClass, id)` |
| Find all | `GraphDb.find_all(ModelClass)` |
| Conditional query | `GraphDb.where(ModelClass, callable)` |
| 1-to-1 | `set_one_to_one` / `get_one_to_one` |
| 1-to-many | `add_one_to_many` / `get_one_to_many` / `remove_one_to_many` |
| Many-to-many | `add_many_to_many` / `get_many_to_many` / `remove_many_to_many` |

`BaseModel` (extends Resource) is the base for all records. `PersonModel` and `CityModel` extend it as example schemas.

**Key files:** `6. GraphDb/GraphDb.gd`, `BaseModel.gd`

---

### 7. JoyStick
Mobile touch controls driving a full HUD — the module that grew into the project's UI reference.

- **Input never crosses node references.** Godot 4.7's built-in `VirtualJoystick` drives InputMap *actions*: the movement stick maps to `ui_left/right/up/down`, the aim and skill sticks to the separate `aim_*` actions so dragging them never moves the player, and the Sprint button presses the `sprint` action directly.
- **Entity + component.** `Global/Scene/base_entity.tscn` (sprite + CharacterBody2D + `PlayerControlComponent`) — sprint and double-tap dash live in the control component.
- **UI talks to gameplay only through `EventBus`.** `InventoryComponent` emits `inventory_changed(slots)`; `InventoryPanel` rebuilds from that array and knows nothing about entities. `status_bar.gd` listens for `health_change` / `stamina_change` / `mana_change`.
- **Items are data** — `Item` is a Resource (`items/*.tres`), `ItemStack` a runtime item+count pair.
- Custom UI helpers: `RBoxContainer` (`@tool` radial container, used for the skill wheel) and `HoldRing` (hold-to-activate progress arc).

**Key files:** `7. JoyStick/ui.gd`, `inventory_panel.gd`, `status_bar.gd`, `hold_ring.gd`

---

### 8. SimpleAiSystem
A **data-driven node-composition ECS foundation** for a colony sim — the largest module, and the main scene until module 9 took over. Two pillars: an **EntityFactory** that assembles entities from `.tres` blueprints (new content = a new resource, never new code) and a **GOAP AI** to come.

Four rules hold everywhere: everything is an Entity · what a thing *is* = which components it has · capability = component presence · content is data.

- **`SimEntity`** is a plain `Node2D` carrying a monitor-**able** `Body` Area2D, a component registry keyed by **slot** (`&"movement"`), and `claim_snapshot()` — the single route out of the world, so two affordances can never hand out the same berry twice.
- **Components** for movement, sensing, reach, inventory, the three bars (health / hunger / fatigue), affordances (`pickupable`, `consumable`) and a `brain` slot filled today by an FSM and later by a planner. Traits (`SimFlockTrait`) modify behaviour as data, with no subclass and no branch.
- **Affordance rule:** each side resolves only what it alone can know — the actor checks reach and capacity, the target checks availability and just hands itself over.
- **What runs:** 5 animals flock across a 3648 × 2240 map, a spawner drips berries, and `hungry → seek → pick up → eat → hungry again` closes unattended. Fatigue collapses an animal where it stands and wakes it at 50.

Its own docs live in the folder: `HANDOFF.md` (state of the build) · `HANDOFF_PSEUDOCODE.md` (every component as pseudocode, plus the open design arguments) · `PROJECT_DEFINITION.md` · `COLONY_SIM_CONCEPT.md` · `MILESTONE_1_SPEC.md`.

**Key files:** `8. SimpleAiSystem/entity/sim_entity.gd`, `entity/sim_entity_factory.gd`, `components/sim_brain_fsm_component.gd`

**Controls:** left-click an entity to inspect it · **F1** debug labels · **F5** respawn.

*(The old modules 8 "Player Control" and 9 "NPC AI" were removed; their ideas live on in module 7's entity/component setup.)*

---

### 9. EcsSystem
A **hand-rolled ECS** — the greenfield rewrite of module 8's foundation, and the current main scene. It shares nothing with module 8 but its subject: module 8 stays running, untouched, as the behavioural reference to diff against rather than guess at.

**Why the rewrite.** Node composition was fighting the design. A stateful wielded item (a weapon with durability) and the hand-held rule "each side resolves only what it alone can know" were *manufactured* problems — the rewrite's whole job is to show ECS dissolves them structurally. It is explicitly **not** a performance exercise; at 5–40 entities the cache wins are irrelevant.

**The core is ~100 lines.** Five scripts in `ecs/`: `EcsWorld` (ids, component tables, the query engine, singletons, frame events), `EcsComponent` (field-only Resource), `EcsSystem` (`run(world, delta)`), `EcsScheduler` (ordered list, drops the frame's events), `EcsEvent`. Storage is `{ Script : { entity_id : EcsComponent } }` and a query intersects the requested tables, driving the scan from the rarest. **Queries key on the script object** — `world.query([EcsPositionComponent])` — so a typo is a parse error, not a silently empty result. `EcsWorld` is 166 lines with docs, 101 without; the plan's kill criterion was "abandon past ~150".

Three rules, and each is structural rather than remembered:

- **Components hold data only.** The single method on `EcsComponent` is `key()`, returning a constant — identity, not behaviour.
- **Systems hold all behaviour**, and never call each other. They coordinate through components, frame events and run order alone.
- **Nothing outside a system mutates component data.** This holds even for input: a click writes a pick request to an `EcsSelectionComponent` singleton and a debug key appends to an `EcsCommandsComponent` singleton, which `EcsSelectionSystem` and `EcsCommandSystem` apply next frame.

**Entities are ids; nodes are views.** `EcsRenderSystem` owns a `Sprite2D` pool under `World/Entities`, keyed by entity id, created when an id starts matching `[Position, Sprite]` and freed when it stops. Data flows one way, world → node; nothing reads back off a node, which is why the whole simulation runs headless. `EcsDeathSystem` darkens the *sprite component's* tint, not a node's modulate — appearance is a fact about the entity.

**The data layer drops a whole layer** versus module 8. Module 8 needed a `SimComponentDef` subclass per component, because a blueprint could not hold a live component. Here a component is already pure data, so `EcsEntityDef.components` holds the components themselves and `EcsEntityFactory` (85 lines) copies them — the parallel `defs/components/*.gd` hierarchy vanished the moment behaviour left the components. Authored relationships point at **names**, not ids: `monkey_0`'s placement overrides `equipped.weapon_name` to `&"dagger_0"` and `EcsEquipSystem` resolves it against the name table once after spawning.

**The pipeline**, in scheduler order — decide, act, resolve, draw, report:

```
command > equip > wander > movement > weapon_carry > aggression > attack >
crit > damage > durability > death > selection > render > census > inspect
```

**The pain case landed.** The weapon is an entity id with a durability row, not a de-noded resource; `EcsEquippedComponent{weapon_id}` is the whole of "wielding". Each system reads only what it alone can resolve — `EcsAttackSystem` the attacker's damage, `EcsDamageSystem` the target's armour, `EcsDurabilitySystem` the weapon's wear — so module 8's hand-held discipline is now just the shape of the queries. Verified headless:

- **Armour was added to a live entity and the attack code did not change** — it cannot, `EcsAttackSystem` has no way to name armour.
- **Crits were added by writing one system and appending one line to the scheduler.** Neither attack nor damage mentions crits.
- **A broken weapon is not a branch.** Durability strips the weapon's `EcsDamageComponent`; attack finds nothing and falls back to fists on its own. There is no `if weapon.broken` anywhere.
- **"Attackable" is not a flag** — it is the target query asking for `EcsHealthComponent`. The 30 wandering rabbits have none, so they are invisible to aggression with no faction system and no layer mask.

**An observability layer** landed on top, which the plan never listed. `EcsSelectionSystem`, `EcsInspectSystem` (5 Hz snapshot), `EcsCensusSystem` (2 Hz count) and `ui/ui.tscn`. Two of them are evidence rather than scaffolding: **picking is a query, not a physics hit** (a distance test over `EcsPositionComponent`, no second set of hitboxes), and **the inspector's tabs are built by reflection** — module 8 needed a hand-written `describe()` per component, while `EcsInspectSystem` reads `PROPERTY_USAGE_SCRIPT_VARIABLE` off `get_property_list()`. **Nothing in that file names a component type**, so a new component kind gets a tab and neither file changes. The panel holds no reference to an entity, the world or the scheduler — everything arrives on the `EventBus` already formatted.

**Deliberately a placeholder:** `EcsAggressionSystem` is the step-6 brain seat — "swing at the nearest attackable thing in reach, on a timer". It consults no weapon, armour or durability and cannot tell whether the swing will land; all it writes is an `EcsAttackIntentComponent`. An FSM and then a planner write the same component, so nothing downstream changes.

**What runs:** 33 entities from `world1.tres` — a monkey wielding a dagger, a crocodile, and 30 rabbits drifting in the arena.

Its own docs live in the folder: `HANDOFF.md` (state of the build) · `ECS_REFACTOR_PLAN.md` (the plan it follows, with the kill criteria).

**Key files:** `9. EcsSystem/ecs/ecs_world.gd`, `main.gd`, `systems/ecs_attack_system.gd`, `systems/ecs_inspect_system.gd`

**Controls:** left-click an entity to inspect it and see its reach · **F2** toggle the crit stage in/out of the pipeline · **F3** toggle the crocodile's armour · **F5** rebuild the world from data.

*(F2 and F3 are the acceptance test made pressable.)*

---

## Shared Infrastructure

### Autoloads (`project.godot`)

| Singleton | File | Role |
|-----------|------|------|
| `Constant` | `System/Constant.gd` | `DEBUG: bool = true` flag |
| `Core` | `System/Core.gd` | Quit shortcut (Ctrl+Q debug / Escape fallback) |
| `Global` | `System/Global.gd` | Camera state (position + zoom) |
| `EventBus` | `System/EventBus.gd` | Signal bus — `control_dir`, `health/stamina/mana_change`, `inventory_changed`, module 8's `sim_world_census` / `sim_respawn_requested` / `sim_entity_inspected`, module 9's `ecs_world_census` / `ecs_respawn_requested` / `ecs_entity_inspected` / `ecs_pipeline_changed` |
| `Utils` | `System/Utils.gd` | `screen_to_world_position()`, `zoom_scale_ratio()` |
| `GlobalAstar2` | `3. ControlPathFinding/global_astar2.gd` | Travel-cost overlay toggle signal |
| `GraphDb` | `6. GraphDb/GraphDb.gd` | In-memory database singleton |

### Entity / Component Pattern

```
Entity (master_entity.gd)       — base Node2D with `size: int`
└── EntityComponent (component.gd) — auto-links to parent Entity in _ready()
    ├── SelectAbleComponent     — drag-select integration
    └── SenseComponent          — proximity sense area
```

This is modules 1–7 only. Module 8 has its own `Sim`-prefixed entity/component layer registered by **slot**, and module 9 has no entity nodes at all — an entity there is an integer id and components are field-only Resources. Do not carry patterns between the three without reading the module's own `HANDOFF.md`.

### Global Camera (`Global/Scene/camera_2d.tscn`)

Reusable Camera2D scene with:
- **Scroll-wheel zoom** — clamped between `min_zoom` and `max_zoom`
- **Middle-click drag** — pan the view
- **WASD / arrow keys** — keyboard pan (zoom-compensated speed)
- **State sync** — writes `Global.camera_position` + `Global.camera_zoom` every frame

### Addons

**None.** The third-party `addons/virtual_joystick` was removed — `VirtualJoystick` is engine-provided in Godot 4.7. Do not reintroduce it.

### Theme

All widget styling goes through the single theme `Global/Theme/main_theme.tres`, attached to a scene's root Control so it cascades — no `theme_override_*` on individual nodes. Medieval palette (parchment / ink / wood / brass), with `RoundButton` and `ItemSlot` type variations and the `Sim*` variations (`SimPanel`, `SimTitle`, `SimLabel`, `SimHBox`, `SimVBox`) used by the inspectors in modules 8 **and** 9 — module 9 reuses them as-is rather than adding an `Ecs*` set.

---

## Input Map

| Action | Keys / Buttons |
|--------|---------------|
| `ui_left` | Arrow Left, A, Joypad D-Left, Axis-0 negative |
| `ui_right` | Arrow Right, D, Joypad D-Right, Axis-0 positive |
| `ui_up` | Arrow Up, W, Joypad D-Up, Axis-1 negative |
| `ui_down` | Arrow Down, S, Joypad D-Down, Axis-1 positive |
| `aim_left` / `aim_right` / `aim_up` / `aim_down` | Aim & skill sticks (separate, so aiming never moves the player) |
| `sprint` | Sprint button (pressed via `Input.action_press/release`) |
| `QuitShortcut` | Ctrl+Q |

---

## Build & Export

- Export preset: **Android** (`export_presets.cfg`)
- Touch emulation from mouse: **enabled** (useful for editor testing)
- ETC2/ASTC texture compression: **enabled**
- Built artifacts in `Build/`

---

## Development Status (as of 2026-09-11)

| Module | Status |
|--------|--------|
| 1. PathFindingSystem | Complete |
| 2. PathFindingWithWeight | Complete |
| 3. ControlPathFinding | Complete |
| 4. SelectionSystem | Complete |
| 5. Boid | Scaffold only — flocking WIP (the working version lives in module 8's `SimFlockTrait`) |
| 6. GraphDb | Complete |
| 7. JoyStick | Complete — mobile HUD, inventory, item resources |
| 8. SimpleAiSystem | Complete for its milestone, and **kept as the behavioural reference** for module 9. Factory + components + FSM brain done; food loop closes. No longer the main scene |
| 9. EcsSystem | **Active.** Hand-rolled ECS core, data-driven factory and the weapon/durability/attack pipeline all land (plan steps 0–2), plus an unplanned observability layer. Now the main scene. Steps 3–7 — inventory, bars, sensors, FSM brain, GOAP — not started |
