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
A **hand-rolled ECS**, deliberately stripped to the smallest thing that still runs, so the shape of a frame is readable end to end. It is the current main scene. It shares nothing with module 8 but its subject; module 8's code has since been deleted, leaving its design docs as the reference.

**Why the rewrite.** Node composition was fighting the design. A stateful wielded item (a weapon with durability) and the hand-held rule "each side resolves only what it alone can know" were *manufactured* problems that ECS dissolves structurally. It is explicitly **not** a performance exercise; at 5–40 entities the cache wins are irrelevant.

**Why it is this small.** The combat pipeline and the observability layer were built, proved out (armour added to a live entity without touching attack code, crits spliced in as one scheduler line, a broken weapon falling back to fists with no branch), and then **cut back out** so the core reads in one sitting. They are recoverable from git at `928b9d1`; `HANDOFF.md` §"What was removed" lists exactly what and where.

**The core is four scripts in `ecs/`:** `EcsWorld` (ids, component tables, the query engine), `EcsComponent` (field-only Resource), `EcsSystem` (`run(world, delta)`), `EcsScheduler` (ordered list). Storage is `{ Script : { entity_id : EcsComponent } }` and a query intersects the requested tables, driving the scan from the rarest. **Queries key on the script object** — `world.query([EcsPositionComponent])` — so a typo is a parse error, not a silently empty result.

Three rules, each structural rather than remembered:

- **Components hold data only.** The single method on `EcsComponent` is `key()`, returning a constant — identity, not behaviour. It exists so a `.tres` placement can address a component in an override block.
- **Systems hold all behaviour**, and never call each other. They coordinate through shared components and run order alone.
- **Nothing outside a system mutates component data.** `main.gd` owns the world, the scheduler and the views, and reads no component in the loop.

**One owner for structure, and one instant for it.** `EcsEntityManager` is the only thing that creates or destroys an entity id, its component data or its nodes, and it does so at a single point in the frame — the `lifecycle` stage, first in the pipeline. A system that wants something born or killed writes a note to the `EcsLifecycleComponent` singleton; it never calls `create_entity`, `destroy_entity`, `add_child` or `queue_free` itself. So no system reshapes the world while another is walking it, and everything after that stage only ever writes values. The manager *creates and destroys* — it never updates; per-tick writes onto nodes belong to `EcsNodeSyncSystem` and `EcsCollisionSystem`. A component asks for a node by declaring `const NODE_KIND`, and the manager reads the constant rather than switching on component type, so a new node-backed component costs no edit to the manager — and components stay method-free.

**Entities are ids; nodes are views.** The nodes are grouped **per entity, not pooled per kind**: `World/Entities/entity_<id>/` holds that entity's `Sprite2D` and whatever areas its components declare. The container carries the transform and the children sit at local zero, so position is written once per entity and one container freed takes the whole entity with it. An `entity_<id>` node is a **container, never an entity** — no script, no data, no state, and nothing read back off it. That discipline is the whole line between this and module 8, where the node *was* the entity. Data flows one way, world → node, which is why the simulation still runs headless — that is how the behaviour below was verified.

**The data layer drops a whole layer** versus module 8. Module 8 needed a `SimComponentDef` subclass per component, because a blueprint could not hold a live component. Here a component is already pure data, so `EcsEntityDef.components` holds the components themselves and `EcsEntityManager` copies them, deep-duplicated per instance — the parallel `defs/components/*.gd` hierarchy vanished the moment behaviour left the components. The manager never switches on component type.

**The whole pipeline is thirteen systems:**

```
lifecycle > spawner > sensor > forage > low_brain > movement > collision
          > pickup > selection > node_sync > debug > census > inspect
```

`EcsLowBrainSystem` picks a destination and writes `EcsMovementComponent`; movement walks toward it and writes `EcsPositionComponent`; node sync draws where it ended up. Read those three files in that order and you have seen every behaviour in the module. The last three stages are pure readers — pull `debug`, `census` or `inspect` out and the simulation does not notice.

**The brain is named for its rank, not its behaviour.** `EcsLowBrainComponent` is the bottom of the decision ladder and what it does today is wander; step 6's FSM and step 7's planner sit above it and write the same single field, a destination on `EcsMovementComponent`. So a smarter brain replaces this one without movement, node sync or debug changing a line — which is the point of separating deciding from doing.

**`EcsDebugSystem` is a pure reader** — it writes no component and creates no entity, so pulling it out of the scheduler changes the simulation not at all. It feeds one dumb view, `EcsDebugOverlay`, which annotates the entities themselves: name, position, the velocity vector with its heading (or `pausing 1.4s` when idle), a velocity arrow, and a dashed line to the ring marking the spot the low-brain system picked. It no longer draws the body circle: there are real `CollisionShape2D`s in the tree now, so Godot's **Debug > Visible Collision Shapes** is the viewer for those. **The body is still data, not a `CollisionShape2D`.** `EcsBodyComponent` is a radius and a flag in a component table and the shape node is derived from it, so the simulation still runs with no scene tree at all — authoritative position never moves inside a node.

**Collision is soft, applied after the fact, and leans on Godot's broadphase.** `EcsCollisionSystem` runs straight after movement: movement proposes a position, collision corrects it, neither knows the other exists. That after-the-fact shape is what makes it compose — anything else that writes a position is cleaned up for free.

It finds the overlapping pairs with an `Area2D` per solid entity, riding that entity's own container — the **one deliberate exception to "nothing reads back off a node"**: the components remain the only truth, the areas are a derived index, and the only thing read back is *which pairs are near each other*, never where anything is. `EcsEntityManager` owns those areas, so the collision system writes only the radius and whether the body is live. Measured per tick at 100/400/1600 entities: 1.56 / 6.56 / 21.33 ms, versus 3.82 / 52.12 / ~800 ms for the GDScript O(n²) it replaced — near-linear instead of quadratic. The physics broadphase is only ~0.2 ms of that at n=100; the rest is GDScript, which is why the system gathers component references into parallel arrays once per tick rather than calling `get_component` in the inner loop.

The pipeline therefore runs in `_physics_process` — a sim wants a fixed timestep, and the overlap list refreshes once per physics step. That costs one tick of lag (~2 px at walking speed) and rules out mid-tick relaxation passes, so a pile converges over ~10 ticks rather than instantly. Carrying an `EcsBodyComponent` is what gives an entity a body, and that component's `is_solid` is what makes the body block. Verified: ten entities spawn piled and separate from 46.6 px of overlap to under 1 px in ten ticks, and F5 rebuilds without leaking bodies.

**The berry spawner shows what a system-shaped feature costs.** `EcsSpawnerComponent` is settings (blueprint id, radius, interval, `max_alive`), `EcsSpawnerSystem` is the doing, and it creates nothing itself: it writes a note to the `EcsLifecycleComponent` inbox, which `EcsLifecycleSystem` fulfils at the top of the next tick, handing the id back so the spawner can keep counting its own berries. Module 8's equivalent ran `_process` inside the component and tracked spawned **nodes** with `is_instance_valid()`; this tracks **entity ids** and prunes with `world.is_alive()` — ids are never reused, so a harvested berry can never alias a later entity. **Having a body, blocking and moving are three separate questions:** a berry has a body, so it can be seen and touched, but `is_solid = false` so walkers pass straight over it, and no `EcsMovementComponent` so nothing could shove it anyway. A bush blocks and never budges; a rabbit does both. No `is_item` flag anywhere.

**Hunger gave the loop a motive** (the plan's step 4). `EcsHungerComponent.value` climbs, and two authored thresholds turn it into behaviour: below `forage_at` the brain's food rung declines, so a sated creature wanders past a berry it can see; above `eat_at` it eats what it is carrying. `eat_at` sits above `forage_at` on purpose, so it gathers while peckish and eats when properly hungry — both rungs visible, and a `.tres` edit away from behaving otherwise. Pinned at the top, `EcsHungerSystem` spends health (starvation is hunger's rule, so it lives with hunger) and `EcsHealthSystem` owns only the threshold, writing a kill note at zero — the module's first death by simulation. **Eating needs no inventory:** the condition is "I am hungry and there is food within reach", and a pocket is only one place reach can mean, so `EcsConsumeSystem` checks the bag first and the action area second. The two creature types are that contrast, differing by one component and some authored numbers — the monkey carries (bag, gather at 30, eat at 60) and the rabbit has no inventory at all (eat at 30, forage at 35, hunger climbing slower to match), which makes it graze: it eats what it walked to, where it lies. `eat_at` below `forage_at` is the whole of "grazer"; there is no `is_grazer` flag and no branch in any system. **Eating is a kill where picking up is not:** a carried berry has merely lost its position and returns if put down, while an eaten one is freed with its nodes. The brain *decides* to eat by entering `EAT` and `EcsConsumeSystem` carries it out, one bite per tick — step 6's intent pattern in miniature, and what stops the brain growing hands.

**Deciding became one brain with state.** `EcsForageSystem` and `EcsLowBrainSystem` used to be two deciders whose priority was which line of `main.gd` they sat on — forage got first refusal, wandering caught what it declined. Elegant, and stateless: a creature's only memory between ticks was `has_destination`, one borrowed boolean. So nothing could persist ("I am going to *that* berry"), nothing could interrupt (a rung may fill an empty destination slot, never take a full one), and a threshold near its trigger flickered. They are now one `EcsLowBrainSystem` running a small FSM — `IDLE > WANDER > SEEK_FOOD` — with `state` and `target` on the component. A commitment runs to its end; a wander is interruptible, so a drifting creature notices a berry the tick it sees it; and a target that is eaten or stolen is dropped rather than walked to. It still says one thing downstream: a destination.

**A destination is a budget, not a standing order.** `EcsMovementSystem` prices each trip the tick it first sees it — distance over speed, times `timeout_slack`, plus `timeout_grace` — and drops the destination when that runs out, exactly as if it had been reached. Without it an entity held off its target by soft collision keeps `has_destination` true forever, and both brain rungs skip it *because* it already has somewhere to be: the stuck entity was a livelock across stages, not a fault inside one. Giving up and arriving are the same event to every other system, so nothing downstream learned a field.

**Perception and reach are physics, not arithmetic.** `EcsSensorComponent` (what it can see) and `EcsActionComponent` (what it can touch) each declare an area under the entity's container, and `EcsSensorSystem` writes what they overlap into `sensor.perceived` / `action.reached` — culled by Godot's broadphase in C++ rather than by measuring to every entity in GDScript. `EcsForageSystem` chases only a berry it perceives; `EcsPickupSystem` takes only one its action area touches. **Layer policy is declared on the component**, not chosen by the manager: `NODE_LAYER` for what others can detect of it, `NODE_MASK` for what it looks for. Only `EcsBodyComponent` claims a layer, so sensors are never reported to each other, and a whole new area kind is a component with three constants and no edit to `EcsEntityManager`. **The overlap list is the verdict on reach.** Pickup and consume once re-checked the distance against the components, until it was clear that the check was the same condition the physics server had already tested, on numbers about a pixel fresher — so it went, and the accepted error is one tick of motion. What they still re-ask is whether the thing named is still in the world, which is a different question entirely.

**The decision ladder is made out of run order.** `EcsForageSystem` has the same shape as `EcsLowBrainSystem` — look at an entity with nothing to do, write a destination — and runs *before* it, on the berries the sensor stage says it can actually see. That is the whole priority mechanism: forage gets first refusal, anything it declines (bag full) falls through to wandering. No state machine, no priority field. A third rung is one system and one scheduler line.

**Picking up is removing a component.** `world.remove(berry, EcsPositionComponent)` and three things follow for free: the node sync query stops matching so the sprite is *hidden*, the forage query stops matching so nobody walks toward a pocketed berry, and the spawner stops counting it against `max_loose` so the bush resumes. Hidden and not freed, because **node lifetime tracks the entity while what a node does tracks the components** — a berry that is put back down shows the same node again. Freeing a node is kill and only kill. No `is_carried` flag. And the berry stays a **live entity** — this is the inventory version of the weapon pain case, where module 8's inventory had to take a *blueprint snapshot* and destroy the world entity because it could not hold a live one. Verified over 50s: 14 entities → 54, 30 berries held, 6/10 bags full, and 54 entities with only 24 drawn.

**A type is a component list, not a class.** Rabbit and monkey carry the identical `[Shape, Sprite, Movement, LowBrain, Sensor, Action, Inventory]` set and share every line of code — only the authored values differ (speed 72 vs 130, wander radius 320 vs 420, body radius 22 vs 36). There is no rabbit class, no monkey class, and no base creature to inherit from; `EcsEntityDef.components` *is* the type.

**Overrides are per-instance.** `rabbit_0`'s placement overrides `movement.speed` to `18.0`; the other four rabbits keep the blueprint's `72.0`, because the manager deep-copies each component rather than sharing one object across a type.

**What runs:** 10 entities of 2 types from `world1.tres` — 5 rabbits drifting slowly across the top of a **3200×1680** arena and 5 faster, twitchier monkeys across the bottom. The arena rect is an export on `main.gd`, adopted into `EcsConst.world_bounds` at startup, so moving the ground plate moves the wander bounds with it; the camera sits at zoom 0.4 so the whole thing is on screen at once.

**It carries the repo's only tests.** `tests/lifecycle_test.tscn` runs 49 headless checks over the parts with no visible failure mode — births and deaths landing at the `lifecycle` stage and nowhere else, a container freed taking the whole entity with it, a picked-up berry losing its position but keeping its nodes, soft collision settling two stacked bodies, and seeing-is-not-reaching across the sensor and action areas. Exit code 0 only if all pass. `tests/stress_test.tscn` ramps the population to find where a tick crosses 250 ms.

Its own docs live in the folder: `HANDOFF.md` (state of the build) · `ECS_REFACTOR_PLAN.md` (the plan it follows, with the kill criteria).

**Selection and inspection are queries, not machinery.** Left-click records the click on a singleton; `EcsSelectionSystem` resolves it next tick as a *distance query over `EcsPositionComponent`* — no physics pick, no hitboxes, hit radius taken from each entity's own sprite so the clickable area is whatever you can see. Being selected is the presence of `EcsSelectedComponent`, which is why the marker and the inspector both find it with an ordinary query while holding no reference to an entity.

**The inspector's tabs are built by reflection, and no component describes itself.** `EcsInspectSystem` reads `PROPERTY_USAGE_SCRIPT_VARIABLE` off each component, so fields appear in declaration order and a new component kind gets a tab with no edit to the panel, the system, or the component. Module 8 needed a hand-written `describe()` per component to do the same job; here components stay method-free, which is the rule. Proof: the inspector predates `shape`, `low_brain` and `inventory` and shows all three correctly. The cost is that a pure tag like `EcsSelectedComponent` gets an empty tab, since reflection has no way to be told "don't show me" — an open presentation question, noted in `HANDOFF.md` §6a.

**Key files:** `9. EcsSystem/ecs/ecs_world.gd`, `ecs/ecs_entity_manager.gd`, `main.gd`, `systems/ecs_low_brain_system.gd`, `systems/ecs_sensor_system.gd`, `systems/ecs_inspect_system.gd`

**Controls:** **Left-click** an entity to inspect it, bare ground to clear · **F1** toggles the on-entity debug overlay · **F5** rebuilds the world from data — edit `world1.tres` or a blueprint, press F5, see the change with no code touched.

---


## Shared Infrastructure

### Autoloads (`project.godot`)

| Singleton | File | Role |
|-----------|------|------|
| `Constant` | `System/Constant.gd` | `DEBUG: bool = true` flag |
| `Core` | `System/Core.gd` | Quit shortcut (Ctrl+Q debug / Escape fallback) |
| `Global` | `System/Global.gd` | Camera state (position + zoom) |
| `EventBus` | `System/EventBus.gd` | Signal bus — `control_dir`, `health/stamina/mana_change`, `inventory_changed`, module 9's `ecs_world_census` / `ecs_respawn_requested` / `ecs_entity_inspected` / `ecs_pipeline_changed` |
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
| 9. EcsSystem | **Active, and the only live simulation.** Hand-rolled ECS core, stripped back to a readable pipeline of thirteen stages (`lifecycle > spawner > sensor > forage > low_brain > movement > collision > pickup > selection > node_sync > debug > census > inspect`), with a drawn on-entity debug overlay on F1 and a click-to-select reflective inspector. Now the main scene. `EcsEntityManager` is the single owner of entity structure and nodes are grouped per entity; perception and reach are physics areas. Covered by the repo's only tests — 49 lifecycle/sensor checks plus a population ramp. The combat and observability layers were built, proved out and cut; they are in git at `928b9d1`. **Step 3 is most of the way done** — inventory and pickup landed as relationships, leaving eating, which wants step 4's bars first. **Step 5 landed early and differently** — sensing is areas, not the planned distance query. Steps 4, 6 and 7 — bars, FSM brain, GOAP — not started. The node-structure argument in `HANDOFF.md` §8 is now **settled** (one container per entity); the data-structure one is still an **open argument the author wants to settle**, not a plan, and nothing there is to be implemented unasked |
