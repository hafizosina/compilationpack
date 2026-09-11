# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**CompilationPack** — a Godot **4.7** (GDScript) project that collects self-contained game-system demos in numbered folders. Mobile renderer, 1612×720 viewport, `sensor_landscape`, Android export target. Main scene is `res://9. EcsSystem/main.tscn`; module 8 is the behavioural reference it is being rebuilt against.

There are no tests and no build scripts; the editor is the tool chain.

## Commands

The Godot editor is installed via Steam and is **not on PATH**:

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"

# Run the main scene
"$GODOT" --path .

# Run one module directly (bypasses run/main_scene)
"$GODOT" --path . "res://8. SimpleAiSystem/main.tscn"
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
| `8. SimpleAiSystem/*.md` | Module 8 has its own doc set — `HANDOFF.md` is its state-of-the-build; read it before touching that folder |
| `9. EcsSystem/*.md` | Module 9 likewise — `HANDOFF.md` is its state-of-the-build, `ECS_REFACTOR_PLAN.md` the plan it follows |

Keep feature work inside the module folder it belongs to; promote something to `Global/` or `System/` only when a second module needs it.

**Module 8 is a world of its own.** It does not use `Global/Scene/`'s `Entity`/`EntityComponent` — it has its own `Sim`-prefixed entity/component/def layer, a `.tres`-driven factory, and components registered by **slot** rather than by class. Its rules (slots vs stubs, one claim per entity, "each side resolves only what it alone can know") are written up in `8. SimpleAiSystem/HANDOFF.md` §3 and `HANDOFF_PSEUDOCODE.md`. Do not carry patterns between module 8 and modules 1–7 in either direction without reading those first.

**Module 9 is a hand-rolled ECS, and shares nothing with module 8 but its subject.**
Entities are integer ids in an `EcsWorld`, components are field-only Resources with no
methods, and every behaviour is an `EcsSystem` the scheduler runs in order; the
`Sprite2D`s under `World/Entities` are a view the render system writes, not the entities.
Three rules are non-negotiable there: components hold data only, systems hold all
behaviour and never call each other, and nothing outside a system mutates component data
(even the debug keys queue a command for `EcsCommandSystem`). Queries key on the script
object — `world.query([EcsPositionComponent])` — never on a string. It is at plan steps
0–2 plus an observability layer (selection, reflective inspector, census, HUD) the plan
never listed; steps 3–7 are not started. Read `9. EcsSystem/HANDOFF.md` before touching
that folder. Module 9 is now the main scene, ahead of the plan, which held that switch
until step 6 — module 8 is untouched and remains the behavioural reference, so do not
delete or refactor it.

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

There is no `addons/` directory — `VirtualJoystick` is engine-provided in 4.7. Do not reintroduce the third-party addon.

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
