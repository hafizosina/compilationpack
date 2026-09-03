# CompilationPack — Project Summary

**Engine:** Godot 4.7 | **Renderer:** Mobile | **Viewport:** 1612 × 720 | **Target:** Android

**Main scene:** `8. SimpleAiSystem/main.tscn`

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
A **data-driven node-composition ECS foundation** for a colony sim — the largest module, and the current main scene. Two pillars: an **EntityFactory** that assembles entities from `.tres` blueprints (new content = a new resource, never new code) and a **GOAP AI** to come.

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

## Shared Infrastructure

### Autoloads (`project.godot`)

| Singleton | File | Role |
|-----------|------|------|
| `Constant` | `System/Constant.gd` | `DEBUG: bool = true` flag |
| `Core` | `System/Core.gd` | Quit shortcut (Ctrl+Q debug / Escape fallback) |
| `Global` | `System/Global.gd` | Camera state (position + zoom) |
| `EventBus` | `System/EventBus.gd` | Signal bus — `control_dir`, `health/stamina/mana_change`, `inventory_changed`, `sim_world_census`, `sim_respawn_requested`, `sim_entity_inspected` |
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

### Global Camera (`Global/Scene/camera_2d.tscn`)

Reusable Camera2D scene with:
- **Scroll-wheel zoom** — clamped between `min_zoom` and `max_zoom`
- **Middle-click drag** — pan the view
- **WASD / arrow keys** — keyboard pan (zoom-compensated speed)
- **State sync** — writes `Global.camera_position` + `Global.camera_zoom` every frame

### Addons

**None.** The third-party `addons/virtual_joystick` was removed — `VirtualJoystick` is engine-provided in Godot 4.7. Do not reintroduce it.

### Theme

All widget styling goes through the single theme `Global/Theme/main_theme.tres`, attached to a scene's root Control so it cascades — no `theme_override_*` on individual nodes. Medieval palette (parchment / ink / wood / brass), with `RoundButton` and `ItemSlot` type variations and the `Sim*` variations used by module 8's inspector.

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

## Development Status (as of 2026-09-03)

| Module | Status |
|--------|--------|
| 1. PathFindingSystem | Complete |
| 2. PathFindingWithWeight | Complete |
| 3. ControlPathFinding | Complete |
| 4. SelectionSystem | Complete |
| 5. Boid | Scaffold only — flocking WIP (the working version lives in module 8's `SimFlockTrait`) |
| 6. GraphDb | Complete |
| 7. JoyStick | Complete — mobile HUD, inventory, item resources |
| 8. SimpleAiSystem | **Active.** Factory + components + FSM brain done; food loop closes. GOAP and actions-as-data next |
