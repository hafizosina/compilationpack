# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**CompilationPack** — a Godot **4.7** (GDScript) project that collects self-contained game-system demos in numbered folders. Mobile renderer, 1612×720 viewport, `sensor_landscape`, Android export target. Main scene is `res://9. EcsSystem/main.tscn`. Module 8's code has been deleted; its folder is a design archive of five `.md` files, and module 9 is the only live simulation.

There are no build scripts; the editor is the tool chain. The only tests in the repo are
module 9's, in `9. EcsSystem/tests/`:

```bash
# 153 checks over the entity lifecycle, the sensor/action layer, solidity, the
# movement trip clock, the brain's commitments, the hunger/health/energy loop,
# intent flags, items as records and the drop on death.
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
first in the pipeline. A system that wants something born writes a note to the
`EcsLifecycleSingleton`; one that wants something dead adds `EcsDyingFlag` to it. It never
calls `create_entity`, `destroy_entity`,
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
`monitoring`/`monitorable` from those. Only `EcsBodyComponent` claims a layer
(`EcsConst.LAYER_BODY`) — a body is the only detectable thing in the world; sensors and
action areas carry none, so sensors are never reported to each other. Body's mask stays
`LAYER_BODY` because soft collision *is* body-vs-body and nothing else detects bodies at a
body's radius; it is free (measured, `HANDOFF.md` §5). Adding a new area kind is a
component with three constants and **no edit to `EcsEntityManager`**. **The overlap list is the verdict on reach**, and that is a decision, not an
oversight: pickup and consume used to re-check `distance <= reach + radius` against the
components, but that is the *same condition* the physics server already tested, on numbers
about one tick — roughly a pixel — fresher. The accepted error is one tick of motion. What
those systems still re-ask is whether the thing named is *still in the world*, which is a
different question and a cheap one. If items ever become droppable, something that jumps
position could be taken from where it used to be for one tick, and that is the line to
revisit. Keep a
*solid* entity's action radius above its own body radius or soft collision stops it
before its reach arrives.

**Having a body, blocking the way and being movable are three separate questions.**
`EcsBodyComponent` is the body — a radius, and an area on the body layer, so the entity
can be perceived and reached. Its **`is_solid`** decides whether that body takes part in
soft collision at either end. `EcsMovementComponent` is what lets the resolve move it
rather than only push others out of it. A bush is a solid body and no movement: seen,
walked into, never budged. A rabbit is solid and movable. **A berry is a body with
`is_solid = false`** — it has one for a single reason, to be seen and picked up, and
everything walks straight over it; ground items, corpses and dropped tools set the same
flag. Solidity is the module's one authored boolean of this kind, chosen over a tag
component deliberately: radius and solidity are one physical fact about a body, and the
`.tres` reads as one block.

**Hunger is the motive, and health is the consequence** (the plan's step 4). The number is
**`EcsHungerComponent.fullness`, not hunger** — it starts at `max_fullness` and drains to
zero, the same shape as health, so both of an entity's bars deplete and both mean trouble
at the bottom. The class keeps the name because hunger is what it is *about*; the field is
named for what it counts, so no call site has to hold the inversion in its head. The
brain's food rung declines *above* `forage_below`, so a fed creature wanders past a berry
it can plainly see, and its eat rung fires below `eat_below`.
**What being empty or full does to you is hunger's rule**, so both halves live in
`EcsHungerSystem`: at zero it spends `EcsHealthComponent` at `starve_damage`, above
`heal_above` it gives health back at the slower `heal_rate`, and the band between does
neither. `EcsHealthSystem` owns only the threshold, adding `EcsDyingFlag` at zero. Each
system owns the consequences of the component it is named for and neither knows the other
exists. Regeneration was argued against while starvation was the only damage source —
gating it on being *well fed* is what answers that: mending is the reward for having
eaten, not the absence of starving.
**The brain is the only thing that chooses.** `EcsPickupSystem` used to be a reflex — it
ran on reach alone, so a sated monkey pocketed every berry it wandered across with nothing
having decided that. Taking is now a `TAKE` rung on the brain, gated on the same
`forage_at` that sends a creature out for food, and pickup does nothing until it fires.
The executors stayed systems rather than folding into the brain, which would have been
shorter: the brain would begin mutating *another entity's* components, the same argument
would then swallow `EcsConsumeSystem` and every verb after it, and **step 7's planner
emits action ids that want one executor each**. The intent flags are the instruction;
`EcsPickupSystem` and `EcsConsumeSystem` are their executors. **Carrying is provisioning, not a step on the
way to a meal**: you fill the bag while wandering so that later hunger is answered where
you stand. So the rungs are ordered `EAT > TAKE`, and the brain looks in the bag before
the ground when it names a meal — a creature hungry enough to eat, standing over a berry, eats it where
it lies and never pockets it first. That order is pinned by a test that watches the bag
stay empty, because the end state cannot tell the two paths apart. **Reaching what it set out for ends the
commitment** — a trip's destination is the item's centre, so waiting for the trip to end
would walk a creature onto the thing before it grabbed it.

**Eating does not require an inventory.** "I am hungry and there is food within reach" is
the condition, and a pocket is only one place reach can mean: a carrier eats out of its
`EcsInventoryComponent`, a **grazer** eats what its action area is touching, off the
ground. The two creature types are now that contrast, from authored values alone — the
**monkey** carries (bag, `eat_below` 40 < `forage_below` 70: gather, carry, eat later) and
the **rabbit** has no `EcsInventoryComponent` at all (`eat_below` 70 > `forage_below` 65:
walk to it, eat it where it lies, and its fullness drains slower to match). The brain's food rung treats
a bag as a *cap on how much it may fetch*, never as a requirement to go. Food is
`EcsConsumableComponent`, not `EcsPickableComponent` — a hungry animal must not chase a
tool. The brain *decides* to eat by raising `EcsEatIntentFlag` naming the meal;
`EcsConsumeSystem` carries it out, one berry per decision. **Do not let the brain grow
hands.**

**Components, flags and singletons are three kinds.** A **component** is what an entity
*is*: present from spawn to death, its data authored in the blueprint or placement. A wall
that gains movement is no longer a wall — that is a kill and a spawn, not an `add()`. A
**flag** (`EcsFlag`, `…Flag` suffix, in `flags/`) is what is true of it *now*, added and
removed freely by the system that owns it; it may carry runtime data (an intent names its
target) but never `@export`. A **singleton** (`EcsSingleton`, in `singletons/`) belongs to
the world, not an entity. This is a **guideline, not an enforced rule** — `EcsWorld` stores
all three alike; break it for a good reason and write the reason down where it breaks. The
inspector gives each component a tab and lists all flags on one "Flags" tab.

**Step 6 is done on the stripped core: the brain speaks in flags.** `state` is the FSM's
memory; `EcsEatIntentFlag{target_id | record_uid}`, `EcsTakeIntentFlag{target_id}` and
`EcsAsleepFlag` are its instructions, raised and cleared in `_set_state()` — the one place
`state` is written — so they cannot disagree (a test watches 400 live ticks for it).
Consume, pickup, hunger and energy read the flags and never `EcsLowBrainComponent`, so a
creature with **no brain at all** eats, takes and sleeps when one is raised on it. There is
**no `MoveIntent` yet** — decided and deferred: the destination stays a field on
`EcsMovementComponent` until this proof of concept has run.

**Dying is a flag, and the flag is the claim.** Death is still deferred to the next
lifecycle stage, so every system in a tick sees the same entities, but `EcsDyingFlag` lands
in the store *instantly*: every executor that eats or takes refuses anything carrying it.
That is the Valheim/Minecraft duplication fix — one authority checks and commits in one
step, and systems run one at a time, so the executor *is* that authority and no entity
learns another's intent. It closed a real race (a grazer eating and a carrier pocketing the
same berry in one tick), pinned by a test.

**A carried item is a record, not an entity** — a deliberate reversal of step 3, because in
most games an item in a bag, chest or shop is not a live entity. Picking up *kills* the item
and puts an `EcsItemRecord` in the bag: **every component, Position included, no flags**,
copied by reflection over `PROPERTY_USAGE_SCRIPT_VARIABLE` — measured: `Resource.duplicate()`
drops runtime `var`s. A record keeps instance values the catalog cannot know. **`uid`** on
`EcsNameComponent` is who a thing is; the int id is the store's key and changes when an item
goes back into the world. One record, one slot; capacity, stacking and anything a carried
item *does* (durability, rot) are deferred. **When a carrier dies, `EcsDropSystem` puts
back what it carried**, where it fell, as itself — same uid, new id, via
`EcsEntityManager.restore()`. That also fixed a leak: a dead carrier's berries used to live
forever with no position. Later, death by health should leave a lootable corpse instead.

**Deciding is one system with state, not a rung per behaviour.** `EcsLowBrainSystem` is a
small FSM — `IDLE > WANDER > SEEK_FOOD > TAKE > EAT > SLEEP` — and `EcsLowBrainComponent` holds its `state` and
its `target`. It replaced `EcsForageSystem`, which was a second decider whose priority was
its line number in `main.gd`. That read well but was stateless: a creature's only memory
between ticks was `has_destination`, so nothing could persist ("I am going to *that*
berry"), nothing could interrupt (a rung could fill an empty destination slot, never take
a full one), and a threshold near its trigger flickered. **A commitment is not
reconsidered; a wander is** — the food rung preempts an aimless leg mid-walk, and a target
that is eaten or stolen is dropped the tick the brain notices. Every destination write goes
through one helper that also zeroes `time_left`, because overwriting a live trip would
otherwise inherit the old one's budget. The brain reads components that are not its own
(sensor, inventory) and that is accepted: it is the one place that knows several concerns
at once, and it still *writes* only `state`, `target`, `pause_left` and a destination.

**A stage may declare how often it runs.** `EcsScheduler.add(system, every, phase)` takes a
rate in ticks — `main.gd` runs `sensor` and `low_brain` at `SLOW` (3 ticks, 20 Hz) while
`movement`, `collision` and `node_sync` stay at every tick. This is safe only because every
system already takes `delta` and means it: **the scheduler banks delta per system**, so a
stage ticked a third as often is handed three ticks' worth and hunger still climbs at its
authored points-per-second. What changes is latency, never rate. **`phase` is not
optional** — two slow stages landing on the same tick make one heavy frame in three instead
of three even ones, which buys the same average and looks worse; a system runs when
`tick % every == phase`, and giving a consumer the phase just after its producer keeps it
reading data one tick old exactly as it did at full rate. Per-stage rates rather than one
global sim clock, because the eye watches movement and the view, not perception.

**Energy is a reserve, sleep is a decision, and collapse is not.** `EcsEnergyComponent`
drains while awake (`drain_idle`, plus `drain_moving` when velocity is non-zero) and
refills while asleep, so all three bars — fullness, energy, health — are reserves and a
short bar is bad news on every one. The brain's sleep rung sits **below the food rungs**:
a tired creature that can see a berry goes for it, and one that keeps finding food can run
itself to collapse, which is the price of food outranking rest. `rest_at` < `wake_at` is
the hysteresis. **A sleeper still gets hungry, at `asleep_drain_scale` of the waking rate** — slower is
the point, and *still* is what keeps waking-on-starving reachable at all; set it to 0 and
that rule quietly stops existing. `EcsHungerSystem` and `EcsEnergySystem` both decide
"asleep" from `EcsAsleepFlag` plus `EcsCollapsedFlag`, and must agree — neither reads the
other or the brain. **Starving outranks tired in both directions** — it wakes a chosen sleep
and stops one being chosen, or a creature woken by its stomach would be put straight back
down while still tired and starve where it lay. At zero, `EcsEnergySystem` adds the
`EcsCollapsedFlag` and takes `collapse_damage` once; **presence of the flag is the
lock**, which is how energy tells the brain "no say" without writing the brain's
component, and it lifts at `collapse_release` — below `wake_at`, so what comes round is an
ordinary sleeper that starving can interrupt. **SLEEP is the module's first real
preemption**: a collapse overrides a live `SEEK_FOOD` commitment, which nothing else is
allowed to do. Animals start at a random energy in the blueprint's `start_min`–`start_max`,
rolled by `EcsEnergySystem` the first time it sees one (so runtime spawns get it too), or the
whole population would sleep at once.

**A destination is a budget, not a standing order.** `EcsMovementSystem` prices each trip
the tick it first sees it — distance over speed, times the component's `timeout_slack`,
plus `timeout_grace` — and when that runs out it drops the destination exactly as if it
had been reached, so the ladder decides again. Without it an entity that soft collision
holds off its target keeps `has_destination` true forever, and the brain above it skips
it *because* it already has somewhere to be: a stuck entity is a livelock across stages,
not a bug inside one. Giving up and arriving are the same event to every other
system.

**Nodes are grouped per entity**, not pooled per kind: `World/Entities/entity_<id>/` holds
that entity's `Sprite2D`, `Area2dForBody` and whatever else its components declare. The
container carries the transform and children sit at local zero, so position is written
once per entity and one container freed takes the whole entity with it. **An `entity_<id>`
node is a container, never an entity** — no script, no data, no state, and nothing read
back off it. That discipline is all that separates this from module 8, where the node
*was* the entity (see its archive); if something hangs state on a container, that line has
been crossed.

**Node lifetime tracks the entity.** Nothing is alive-but-nowhere any more: a picked-up
berry dies and becomes a record, so freeing a node is kill and only kill, and every live
entity has a position to draw.

**It is deliberately stripped to a bare-minimum core**: 15 components, 6 flags, 2
singletons, 17 systems
(`lifecycle > spawner > hunger > energy > health > sensor > low_brain > consume > movement > collision > pickup > drop > selection > node_sync > debug > census > inspect`, where `EcsLowBrainSystem` is named for its
rank in the plan's decision ladder — a planner goes *above* it at step 7 — and not for the
wandering it happens to do), and a world
of 10 entities in 2 types (5 rabbits, 5 monkeys — a grazer and a carrier, differing by one
component and some authored values). `EcsDebugSystem` is a pure
reader feeding one dumb view, `EcsDebugOverlay`, which annotates each entity in world
space: name, a velocity arrow, a dashed line to its destination, **fullness, energy and
health as bars**, a **badge on the sprite's shoulder** when it is carrying something, and
**the sleep icon** (`Global/Asset/Icon/sleep.png`, whitened once and tinted) off that
shoulder while it sleeps — parchment for a chosen sleep, red for a collapse. Shapes
rather than numbers, because these are readings you scan a crowd for rather than read one
at a time — the arrow *is* the velocity, so the figures that used to sit under it said
nothing the picture did not, and the exact numbers live in the inspector for whichever
entity you click. The system sends **ratios and counts, never text or pixels**; what shape
that makes is the view's business, and a sentinel (`-1`) means the entity has no such
reading, so a berry draws no bars and an empty-handed creature no badge.
`EcsBodyComponent` is the entity's body — a radius and `is_solid`, **data not a
CollisionShape2D**, so the sim still runs with no scene tree. Collision is **soft**:
`EcsCollisionSystem` runs after movement and pushes overlapping pairs apart rather than
vetoing the move, which is what lets any future position-writer be corrected for free.
It finds the pairs with an `Area2D` per solid entity — **the one deliberate exception to
"nothing reads back off a node"**: components stay the only truth, the areas are a derived
index, and the only thing read back is which pairs are near each other, never where
anything is. Do not widen that exception. `EcsEntityManager` owns those areas (it builds
one for any entity whose `EcsBodyComponent` declares it) and they ride their entity's
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
*recorded* on the `EcsSelectionSingleton` by `main.gd`, `EcsSelectionSystem`
resolves it on the next tick by a distance query over `EcsPositionComponent` (no physics
pick, no hitboxes), selection is the presence of `EcsSelectedFlag`, and
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
implement any option from §8**; raise it for a decision instead. Steps 3–6 are done — 6
on the stripped core, without combat (`9. EcsSystem/INTENT_PLAN.md`) — and step 7 is not
started; it and any return of combat assume the cut combat layer.

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
