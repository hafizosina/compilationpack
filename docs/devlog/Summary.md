# CompilationPack — Project Summary

**Engine:** Godot 4.7 | **Renderer:** Mobile | **Viewport:** 1612 × 720 | **Target:** Android

**Main scene:** `9. EcsSystem/main.tscn`. Module 8's code has been deleted and its folder is now a design archive of five `.md` files; module 9 is the only live simulation.

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

**Key files:** none — the code was deleted so its `Sim*` class names would stop sharing the global registry with module 9's `Ecs*` ones. The folder keeps its five design docs (`HANDOFF.md`, `HANDOFF_PSEUDOCODE.md`, `PROJECT_DEFINITION.md`, `COLONY_SIM_CONCEPT.md`, `MILESTONE_1_SPEC.md`), which is what the section above describes. Restore with `git checkout 3346b6e -- "8. SimpleAiSystem"`.

**Controls:** left-click an entity to inspect it · **F1** debug labels · **F5** respawn.

*(The old modules 8 "Player Control" and 9 "NPC AI" were removed; their ideas live on in module 7's entity/component setup.)*

---

### 9. EcsSystem
A **hand-rolled ECS** and the only live simulation — the main scene. It shares nothing with module 8 but its subject; module 8's code is deleted and its design docs are the reference. The full state of the build is `9. EcsSystem/HANDOFF.md`; the roadmap is `ECS_REFACTOR_PLAN.md`.

**Why the rewrite.** Node composition was fighting the design: a stateful wielded item and the hand-held rule "each side resolves only what it alone can know" were *manufactured* problems that ECS dissolves structurally. It is judged on interaction cleanliness, not speed.

**The core is a handful of scripts in `ecs/`.** `EcsWorld` holds ids and `{ Script : { id : component } }` tables and answers queries keyed on the script object, so a typo is a parse error. Three rules are non-negotiable: components hold data (the one exception is a display-only `describe()`), systems hold all behaviour and never call each other, and nothing outside a system mutates component data.

**Three kinds of data.** A *component* is what an entity is, present from spawn to death; a *flag* (`EcsFlag`) is what is true of it now, added and removed freely; a *singleton* (`EcsSingleton`) belongs to the world. A guideline, not an enforced rule.

**One owner for structure.** `EcsEntityManager` alone creates and destroys entities, their data and their nodes, at one instant — the `lifecycle` stage, first in the pipeline. Births are spawn notes; deaths are `EcsDyingFlag`, which is also the *claim* that stops two executors acting on one item in the same tick. Nodes are grouped per entity under `World/Entities/entity_<id>/`, a container that holds no state. Components declare what they imply (`NODE_KIND`, `NODE_LAYER`, `NODE_MASK`, `describe()`), so the manager and the inspector never switch on component type.

**Seventeen stages:** `lifecycle > spawner > hunger > energy > health > sensor > low_brain > consume > movement > collision > pickup > drop > selection > node_sync > debug > census > inspect`, with `sensor` and `low_brain` at 20 Hz — the scheduler banks delta per stage, so rate is unchanged and only latency moves.

**Perception is physics.** Sensor and action areas are culled by Godot's broadphase; only bodies are detectable. `EcsSensorSystem` and `EcsCollisionSystem` are the only two files that read back off a node. Collision is soft: overlap is allowed, then undone. Having a body, blocking and being movable are three separate questions — a berry has a body you walk over.

**One brain that chooses, executors that act.** `EcsLowBrainSystem` is an FSM (`IDLE > WANDER > SEEK_FOOD > TAKE > EAT > SLEEP`). A commitment is not reconsidered; a wander is. Its decisions go out as intent flags (`EcsEatIntentFlag`, `EcsTakeIntentFlag`, `EcsAsleepFlag`) that consume, pickup, hunger and energy read — never the brain — so a creature with no brain at all acts on a raised flag. A destination is a budget, not a standing order.

**Needs.** Fullness, energy and health are all reserves. Hunger is the motive and health the consequence: starving costs health, being well fed mends it. Energy drains awake and restores asleep; at zero the creature collapses. The rabbit (a grazer, no bag) and the monkey (a carrier) differ by one component and authored values.

**Items are records.** Picking up kills the item and keeps an `EcsItemRecord` of every component and its `uid`; a dead carrier's `EcsDropSystem` puts its records back into the world as themselves.

**Observability.** **F1** overlay: bars for fullness / energy / health, a carry badge and a sleep icon, drawn on the entities. Left-click selects (a distance query, not a physics pick); the inspector shows whatever each component's `describe()` returns and names no component type itself.

**Tests:** `tests/lifecycle_test.tscn` — 171 headless checks, exit 0 only if all pass. `tests/stress_test.tscn` — a population ramp; at the game's rates a tick stays under 250 ms past 9,600 entities, fed or hungry (`HANDOFF.md` §14).

**Cut and recoverable:** the step-2 combat pipeline, proved clean and removed so the core reads in one sitting, is in git at `928b9d1`.

**Key files:** `9. EcsSystem/ecs/ecs_world.gd`, `ecs/ecs_entity_manager.gd`, `main.gd`, `systems/ecs_low_brain_system.gd`, `systems/ecs_sensor_system.gd`

**Controls:** **Left-click** an entity to inspect it, bare ground to clear · **F1** toggles the debug overlay · **F5** rebuilds the world from data · wheel zooms, middle-drag pans.

---


## Shared Infrastructure

### Autoloads (`project.godot`)

| Singleton | File | Role |
|-----------|------|------|
| `Constant` | `System/Constant.gd` | `DEBUG: bool = true` flag |
| `Core` | `System/Core.gd` | Quit shortcut (Ctrl+Q debug / Escape fallback) |
| `Global` | `System/Global.gd` | Camera state (position + zoom) |
| `EventBus` | `System/EventBus.gd` | Signal bus — `control_dir`, `health/stamina/mana_change`, `inventory_changed`, module 9's `ecs_world_census` / `ecs_respawn_requested` / `ecs_entity_inspected` |
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

This is modules 1–7 only. Module 8 had its own `Sim`-prefixed entity/component layer registered by **slot** (code now deleted; see its docs), and module 9 has no entity nodes at all — an entity there is an integer id and components are field-only Resources. Do not carry patterns between the three without reading the module's own `HANDOFF.md`.

### Global Camera (`Global/Scene/camera_2d.tscn`)

Reusable Camera2D scene with:
- **Scroll-wheel zoom** — clamped between `min_zoom` and `max_zoom`
- **Middle-click drag** — pan the view
- **WASD / arrow keys** — keyboard pan (zoom-compensated speed)
- **State sync** — writes `Global.camera_position` + `Global.camera_zoom` every frame

### Addons

**One, editor-only.** `addons/markdown_previewer` renders this repo's `.md` docs inside the Godot editor. It is enabled in `project.godot`'s `[editor_plugins]`, excluded from the Android build by the preset's `exclude_filter="addons/*"`, and has no runtime role.

The third-party `addons/virtual_joystick` was removed — `VirtualJoystick` is engine-provided in Godot 4.7. Do not reintroduce it.

### Theme

All widget styling goes through the single theme `Global/Theme/main_theme.tres`, attached to a scene's root Control so it cascades — no `theme_override_*` on individual nodes. Medieval palette (parchment / ink / wood / brass), with `RoundButton` and `ItemSlot` type variations and the `Sim*` variations (`SimPanel`, `SimTitle`, `SimLabel`, `SimHBox`, `SimVBox`) used by module 8's inspector. Module 9 uses the `Sim*` variations too, for its restored inspector panel.

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

## Development Status (as of 2026-09-20)

| Module | Status |
|--------|--------|
| 1. PathFindingSystem | Complete |
| 2. PathFindingWithWeight | Complete |
| 3. ControlPathFinding | Complete |
| 4. SelectionSystem | Complete |
| 5. Boid | Scaffold only — flocking WIP (the working version lived in module 8's `SimFlockTrait`, now recoverable only from git) |
| 6. GraphDb | Complete |
| 7. JoyStick | Complete — mobile HUD, inventory, item resources |
| 8. SimpleAiSystem | **Design archive — the code is deleted.** Complete for its milestone when it was removed; its five `.md` docs stay as the reasoning module 9 is built against. Restore with `git checkout 3346b6e -- "8. SimpleAiSystem"` |
| 9. EcsSystem | **Active, and the only live simulation.** Hand-rolled ECS, seventeen stages, main scene. Plan steps 0–6 done (step 6 on the stripped core, without combat); step 7 (GOAP) not started. Components / flags / singletons as three kinds, intent flags, items as records, drop on death, fullness / energy / health. 171 lifecycle checks plus a population ramp; cached views took the ceiling past 9,600 entities. Combat is in git at `928b9d1`. The data-structure argument (`HANDOFF.md` §15) is open and the author's to settle |
