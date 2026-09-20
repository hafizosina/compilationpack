# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**CompilationPack** — a Godot **4.7** (GDScript) project that collects self-contained game-system demos in numbered folders. Mobile renderer, 1612×720 viewport, `sensor_landscape`, Android export target. Main scene is `res://9. EcsSystem/main.tscn`. Module 8's code has been deleted; its folder is a design archive of five `.md` files, and module 9 is the only live simulation.

There are no build scripts; the editor is the tool chain. The only tests in the repo are
module 9's, in `9. EcsSystem/tests/`:

```bash
# 47 checks over the entity lifecycle and the sensor/action layer.
# Exit code 0 only if all pass — run it after touching module 9's manager,
# collision, pickup, spawner, sensor or node sync.
"$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn"

# Population ramp: where a tick crosses 250 ms. ~4,450 entities at 4 FPS,
# simulation only. Takes a few minutes. See HANDOFF.md §9.
"$GODOT" --headless --path . "res://9. EcsSystem/tests/stress_test.tscn"
```

## Commands

The Godot editor is installed via Steam and is **not on PATH**:

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"

# Run the main scene
"$GODOT" --path .

# Run one module directly (bypasses run/main_scene)
"$GODOT" --path . "res://7. JoyStick/main.tscn"

# Headless validation after editing .tscn / .tres by hand — always do this
"$GODOT" --headless --editor --quit --path . 2>&1 | grep -iE "error|invalid|uid"

# Android export (preset "Android" → Build/CompilationPack.apk)
"$GODOT" --headless --path . --export-debug "Android" Build/CompilationPack.apk
```

Hand-edited scene/resource files are the main breakage risk in this repo: `.tscn`/`.tres` reference each other by `uid://`, every `.gd` has a sibling `.gd.uid`, and a wrong uid fails silently in-editor. Run the headless validation above after any manual scene edit.

## Layout

| Path | Role |
|------|------|
| `System/` | Autoload singletons (see below) |
| `Global/Scene/` | Shared `class_name` scripts + reusable scenes (entity, components, camera, containers) |
| `Global/Asset/`, `Global/Theme/` | Shared art and the single UI theme |
| `<N>. <Name>/` | One isolated demo module per folder |
| `docs/devlog/Summary.md` | Longer per-module write-up, one section per module |
| `8. SimpleAiSystem/*.md` | **Design archive — the code is deleted.** Five docs kept for the reasoning module 9 is built against |
| `9. EcsSystem/*.md` | Module 9 likewise — `HANDOFF.md` is its state-of-the-build, `ECS_REFACTOR_PLAN.md` the plan it follows; `HANDOFF.md` §5 covers the entity-lifecycle model |
| `9. EcsSystem/tests/` | The repo's only tests — module 9's lifecycle acceptance test and its population stress test |

Keep feature work inside the module folder it belongs to; promote something to `Global/` or `System/` only when a second module needs it.

**Module 8's code is gone — the folder is a design archive.** All 100 of its script, scene and resource files were deleted so its `Sim*` class names would stop sharing the global registry with module 9's `Ecs*` ones; its three `sim_*` signals came out of `System/EventBus.gd` with them. What remains is five `.md` files, still worth reading: the slot-vs-stub rule, one claim per entity, "each side resolves only what it alone can know" and the weapon pain case (`HANDOFF.md` §3, `HANDOFF_PSEUDOCODE.md`) are the arguments module 9 was built to answer. **Treat them as a record of a design, not a guide to files** — nothing they describe exists in the tree. To get the code back: `git checkout 3346b6e -- "8. SimpleAiSystem"`.

**Module 9 is a hand-rolled ECS, and shares nothing with module 8 but its subject.**
Entities are integer ids in an `EcsWorld`, components are field-only Resources with no
methods, and every behaviour is an `EcsSystem` the scheduler runs in order; the
`Sprite2D`s under `World/Entities` are a view `EcsNodeSyncSystem` writes, not the entities.
Three rules are non-negotiable there: components hold data only, systems hold all
behaviour and never call each other, and nothing outside a system mutates component data.
Queries key on the script object — `world.query([EcsPositionComponent])` — never on a
string.

**`EcsEntityManager` is the only thing that creates or destroys an entity id, its
component data, or its nodes**, and it does so at one instant — the `lifecycle` stage,
first in the pipeline. A system that wants something born or killed writes a note to the
`EcsLifecycleComponent` singleton; it never calls `create_entity`, `destroy_entity`,
`add_child` or `queue_free` itself. The manager *creates and destroys*; it never updates.
Per-tick writes onto nodes belong to `EcsNodeSyncSystem` (sprites) and
`EcsCollisionSystem` (bodies). Keep that line — it is what stops the manager becoming a
god object. A component says it needs a node by declaring `const NODE_KIND` naming a kind
from `EcsConst`; the manager reads the constant and builds one, never switching on
component type. A constant and not a method, because components stay method-free.

**Perception and reach are physics, not arithmetic.** `EcsSensorComponent` (what it can
see) and `EcsActionComponent` (what it can touch) each declare an area under the entity's
container, and `EcsSensorSystem` writes what they overlap into `sensor.perceived` /
`action.reached`. `EcsForageSystem` only chases a berry it perceives; `EcsPickupSystem`
only takes one its action area touches. Those two read ids off components and never touch
a node — `EcsSensorSystem` and `EcsCollisionSystem` are the **only** two files that read
back off a node, and that is the whole of the exception. **Layer policy is declared on the
component**, not chosen by the manager: alongside `NODE_KIND` it states `NODE_LAYER` (what
others can detect of it) and `NODE_MASK` (what it looks for), and the manager derives
`monitoring`/`monitorable` from those. Only `EcsShapeComponent` claims a layer
(`EcsConst.LAYER_BODY`) — a body is the only detectable thing in the world; sensors and
action areas carry none, so sensors are never reported to each other. Body's mask stays
`LAYER_BODY` because soft collision *is* body-vs-body and nothing else detects bodies at a
body's radius; it is free (measured, `HANDOFF.md` §5). Adding a new area kind is a
component with three constants and **no edit to `EcsEntityManager`**. The overlap list is a **cull, not a verdict** — it is one tick
stale, so pickup confirms reach against the components before acting. Keep an entity's
action radius above its own body radius or soft collision stops it before its reach
arrives. Solid and movable are separate: a berry has a body (so it can be seen and
touched) but no `EcsMovementComponent`, and collision moves only what can move, or a
forager would shove the berry it is chasing.

**Nodes are grouped per entity**, not pooled per kind: `World/Entities/entity_<id>/` holds
that entity's `Sprite2D`, `Area2dForBody` and whatever else its components declare. The
container carries the transform and children sit at local zero, so position is written
once per entity and one container freed takes the whole entity with it. **An `entity_<id>`
node is a container, never an entity** — no script, no data, no state, and nothing read
back off it. That discipline is all that separates this from module 8, where the node
*was* the entity (see its archive); if something hangs state on a container, that line has
been crossed.

**Node lifetime tracks the entity; what a node does tracks the components.** A berry that
is picked up loses its `EcsPositionComponent` but is not dead, so its sprite is hidden
rather than freed and comes back if it is put down. Freeing a node is kill and only kill.

**It is deliberately stripped to a bare-minimum core**: 14 components, 13 systems
(`lifecycle > spawner > sensor > forage > low_brain > movement > collision > pickup > selection > node_sync > debug > census > inspect`, where `EcsLowBrainSystem` is named for its
rank in the plan's decision ladder, not for the wandering it happens to do), and a world
of 10 entities in 2 types (5 rabbits, 5 monkeys — same component list, different authored
values). `EcsDebugSystem` is a pure
reader feeding one dumb view, `EcsDebugOverlay`, which annotates each entity in world
space (name, position, velocity vector and heading, dashed line to its destination).
`EcsShapeComponent` is the entity's body — one radius, **data not a
CollisionShape2D**, so the sim still runs with no scene tree. Collision is **soft**:
`EcsCollisionSystem` runs after movement and pushes overlapping pairs apart rather than
vetoing the move, which is what lets any future position-writer be corrected for free.
It finds the pairs with an `Area2D` per solid entity — **the one deliberate exception to
"nothing reads back off a node"**: components stay the only truth, the areas are a derived
index, and the only thing read back is which pairs are near each other, never where
anything is. Do not widen that exception. `EcsEntityManager` owns those areas (it builds
one for any entity whose `EcsShapeComponent` declares it) and they ride their entity's
container, so the collision system writes only the radius and whether the body is live.
The debug overlay does **not** draw body circles — there are real `CollisionShape2D`s in
the tree now, so Godot's Debug > Visible Collision Shapes is the viewer. The pipeline
therefore runs in **`_physics_process`** (fixed timestep; the overlap list refreshes once
per physics step, costing one tick of lag). The overlay is **drawn via `_draw()`, not built from Controls**, which is why it sits outside the
theme rather than carrying `theme_override_*`. **F1** toggles it. There is no
`EcsDebugPanel` — that was tried and removed; per-entity debug output belongs on the
entity it describes.

**Selection and the inspector are back** (restored from `928b9d1`). Left-click picks an
entity, and the bottom-left panel shows it. The chain is strictly ECS: a click is only
*recorded* on the `EcsSelectionComponent` singleton by `main.gd`, `EcsSelectionSystem`
resolves it on the next tick by a distance query over `EcsPositionComponent` (no physics
pick, no hitboxes), selection is the presence of the `EcsSelectedComponent` tag, and
`EcsInspectSystem` pushes a formatted snapshot onto `EventBus.ecs_entity_inspected`.
`ui/ui.tscn` is a dumb renderer that never touches the world. **The inspector builds its
tabs by reflection** over `PROPERTY_USAGE_SCRIPT_VARIABLE`, so a new component gets a tab,
with its fields in declaration order, without the component or the panel knowing anything
about each other — **components stay method-free; do not add a `describe()` hook to a
component** the way module 8 did without settling that argument first.

The plan's step-2 combat pipeline was built, proved out, and then cut back out so the
flow reads end to end; it is in git at `928b9d1`, and `9. EcsSystem/HANDOFF.md` §6 says
what was removed and how to restore it. The observability layer was cut with it and has
since been restored, minus its `EcsCommandSystem` and pipeline panel, which depended on
the combat demo. **Do not re-add breadth to module 9 without being asked**; the small
size is the point.

**Two architecture questions in module 9 are open arguments, not settled plans** —
how the Godot nodes are structured (a pool per concern, one view node per entity, or
server RIDs) and how component data is stored (dictionary-of-dictionaries, archetypes,
whether a node handle may live inside a component). `9. EcsSystem/HANDOFF.md` §8 records
the positions. The author has said explicitly he still wants to argue both out. **Do not
implement any option from §8**; raise it for a decision instead. Steps 3–7 are not started, and several of
them assume the cut combat layer.

Read `9. EcsSystem/HANDOFF.md` before touching that folder. Module 9 is the main scene,
ahead of the plan, which held that switch until step 6, and now the only simulation in the
repo — module 8's behaviour survives as documentation, not as something to run and compare
against.

## Autoloads

Registered in `project.godot`, available globally:

- `Constant` — `DEBUG: bool`
- `Core` — debug quit shortcut (Ctrl+Q, Escape fallback), gated on `Constant.DEBUG`
- `Global` — camera position/zoom state, written every frame by the camera
- `Utils` — `screen_to_world_position()`, `zoom_scale_ratio()` (read `Global`'s camera state)
- `EventBus` — signal-only bus; the decoupling seam between gameplay and UI
- `GraphDb` — module 6's in-memory database, also a singleton
- `GlobalAstar2` — module 3's A* signal holder (currently an empty stub)

## Architecture

**Entity + component.** `Global/Scene/base_entity.gd` defines `class_name Entity` (Node2D) and owns the movement stats (`move_speed`, `turn_speed`, `sprint_multiplier`, `size`). Behaviour lives in sibling component nodes:

- `component.gd` → `EntityComponent`, resolves `entity` from its parent in `_ready()`; subclasses must call `super()`. Used by `InventoryComponent`, and by modules 4/5 (`SelectAbleComponent`, `SenseComponent`).
- `player_control_component.gd` → `PlayerControlComponent` extends plain `Node` and takes an exported `entity` NodePath instead. It reads input, moves and rotates the entity, and implements sprint + double-tap dash.

`base_entity.tscn` is the player-shaped entity (sprite + CharacterBody2D + ControlComponent); `master_entity.tscn` is the bare sprite-only variant used by older modules.

**Input flows through the InputMap, never through direct node references.** Godot 4.7's built-in `VirtualJoystick` node drives InputMap *actions*, so the movement stick maps to `ui_left/right/up/down` and `PlayerControlComponent` reads `Input.get_vector(...)` with an explicit low deadzone (the `ui_*` actions' own 0.5 deadzone is too coarse for analog sticks). The aim/skill joysticks use the separate `aim_*` actions so dragging them never moves the player, and report casts via the `released(input_vector)` / `tapped` signals. The Sprint button presses the `sprint` action directly (`Input.action_press/release`) rather than calling into the player.

`VirtualJoystick` is engine-provided in 4.7 — do not reintroduce the third-party addon. The only thing in `addons/` is `markdown_previewer`, an **editor-only** plugin for reading this repo's `.md` docs inside Godot; it is excluded from the Android export and has no runtime role.

**UI talks to gameplay only through `EventBus`.** `InventoryComponent` mutates its own `slots` and emits `inventory_changed(slots)`; `InventoryPanel` rebuilds from that array and knows nothing about entities. `status_bar.gd` likewise listens for `health_change` / `stamina_change` / `mana_change`. Follow this pattern for new HUD elements instead of wiring node paths across the scene.

**Items** are data: `Item` is a Resource (`.tres` files in `7. JoyStick/items/`), `ItemStack` is a runtime RefCounted pair of item + count, and inventory contents change only via `InventoryComponent.add_item()` / `remove_item()`.

## UI theming

All widget styling goes through the single theme `Global/Theme/main_theme.tres` (`uid://ctheme0mainx7`), attached to a scene's **root Control** so it cascades. Do not add `theme_override_*` properties on individual nodes.

- Medieval palette: parchment `#E7D6AC`, ink `#2A2016`, wood `#5F3F22`, brass `#B98A32`; health `#9E2B25`, stamina `#5E8A2E`, mana `#2F5E93`.
- Type variations: `RoundButton` (circular parchment disc for round HUD icon buttons — set content via `icon` + `expand_icon`, not textures), `ItemSlot`. The theme also styles `VirtualJoystick` (circular via large `corner_radius`).
- Exception: the `TextureProgressBar` status bars remain texture-based, since that node ignores styleboxes.

Two custom UI helpers live in the codebase: `RBoxContainer` (`@tool` radial container used for the skill wheel) and `HoldRing` (radial hold-to-activate progress arc).

Editor-previewable scripts (`status_bar.gd`, `RBoxContainer`) are `@tool`; guard runtime-only wiring with `if Engine.is_editor_hint(): return`, and guard `_refresh`-style setters with `is_node_ready()` since property setters fire during scene load before `@onready`.

## Conventions

- GDScript with typed declarations (`:=`, typed params/returns) and `##` doc comments on exported properties and public methods — exports are tuned in the inspector, so the comment is the only spec.
- Commits are conventional-style one-liners on `main` (`feat(joystick): ...`). When asked for a "silent" commit, use a single-line message with no trailers.
- `.godot/` and `/android/` are gitignored; `Build/` holds committed APK artifacts.
