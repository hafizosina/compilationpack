# Milestone 1 — Data-Driven Factory + GOAP (Implementation Spec)

> Goal: prove the **data-driven ECS foundation** works end to end — one `WorldDef`
> resource → `EntityFactory` spawns 30+ entities → their components advertise actions →
> a **GOAP** brain plans and executes against those actions. Full behavior loop:
> **hunger, sleep, flee/predation**.
>
> Companion to `COLONY_SIM_CONCEPT.md` (the architecture). This doc is the *buildable subset*
> with concrete numbers. Godot 4.x. Optimization is explicitly out of scope.
> Confirmed: **harvest works on both targets — clean when the target can't move, damaging while it can.**

---

## 0. What "done" looks like

Press play and watch, with a debug overlay on each entity showing its current **goal**:
1. 30+ entities spawn from `world1.tres` at their positions, correct sprites/colors per type.
2. Type1/Type3 (herbivores) whose hunger drops path to a **bush**, harvest a berry, eat it → hunger recovers.
3. Any entity whose fatigue drops **sleeps where it stands** (or collapses at 0) → fatigue recovers.
4. Type2 (predator) whose hunger drops hunts a live Type1/Type3: repeated **harvest** deals damage until the prey dies, drops meat, then eats it.
5. A herbivore that senses a Type2 in range **flees** (runs away) until its Danger bar drains.
6. Entities that run out of energy while fleeing **collapse**; starving entities lose health and can **die → become harvestable in place**.

If all six are visible, the foundation (factory + components + actions + GOAP) is proven.

---

## 1. Build order (do it in this sequence — each step runs before the next is added)

> **Progress:** 1 ✅ · 2 ✅ · 3 ✅ · 4 ◐ (Action/Inventory/PickUpAble built; no Eatable, no
> Harvestable, actions not yet `ActionDef` data) · 5 ⬜ · 6 ◐ (collapse built; voluntary Rest goal not) · 7 ◐ (sensor only).
> Steps 4 and 7's sensor were pulled forward ahead of 3 on purpose — see §11.

1. **Bare Entity + Factory + one component.** `Entity.tscn`, `EntityFactory`, `EntityDef`/`ComponentDef`, and a `SpriteComponent`. Spawn 30 from `world1.tres`. Success: 30 colored dots at their positions.
2. **Movement + Wander.** Add `MovementComponent` + a trivial wander so the dots move. Success: 30 dots drifting.
3. **Bars.** Add `HungerComponent`, `FatigueComponent`, `HealthComponent` that drain/tick. Debug overlay shows the numbers. No behavior yet — just draining.
4. **Actions + affordances.** Add `ActionComponent`, `InventoryComponent`, and the target components (`Eatable`, `Harvestable`, `PickUpAble`, `Receiver`). Hard-call one action manually to confirm the perform→receiver→effect handshake.
5. **GOAP — hunger only.** Add `BrainComponent` with the planner and the `[harvest, pickUp, eat]` chain. Success: herbivores feed themselves.
6. **Sleep goal.** Add the Rest goal (brain-chosen, interruptible). Collapse is already built and is NOT a brain concern — `FatigueComponent` owns it. Success: tired entities choose to rest before they drop.
7. **Sensor + Flee + predation.** Add `SensorComponent`, `Danger`, `AttackComponent` do-side, and the live-harvest damage. Success: predators hunt, prey flee.

Ship nothing past step 7 for this milestone.

---

## 2. The factory (the spine — get this exactly right)

```gdscript
class_name EntityFactory
var catalog: EntityCatalog          # id -> EntityDef blueprint

func spawn_world(world: WorldDef) -> void:
    for place in world.entries:
        spawn(place.type, place.position, place.overrides)

func spawn(type_id: StringName, pos: Vector2, overrides := {}) -> Entity:
    var blueprint: EntityDef = catalog.get_def(type_id)
    var e: Entity = ENTITY_SCENE.instantiate()
    e.name = "%s_%d" % [type_id, e.get_instance_id()]
    e.sprite.texture = blueprint.sprite
    e.modulate = blueprint.tint                      # per-type color for the eyeball test
    # DUP defs per instance, apply overrides, THEN build — never mutate shared blueprint resources
    for cdef in blueprint.components:
        var d: ComponentDef = cdef.duplicate(true)   # deep dup — the critical line
        if overrides.has(d.slot):                    # d.slot = e.g. "hunger"
            _apply(d, overrides[d.slot])             # {start: 30} etc.
        d.build_into(e)                              # d.new()s the Component node, configures, add_child
    e.position = pos
    entities_root.add_child(e)
    return e
```

**Two traps that make "30 entities" behave like "1 entity in 30 bodies" — avoid both:**
- **Deep-dup the ComponentDef per instance** (`.duplicate(true)`) before applying overrides, so instance A's override never leaks into instance B via a shared `Resource`.
- Any `Resource` a component holds as *live mutable state* must be `duplicate()`d in `build_into`, not referenced. Immutable config (the sprite texture, an ActionDef) can be shared.

`ComponentDef.build_into(e)` contract: create the Component node, set its exported fields from the def, `e.add_child(node)`, and register it so `e.get_component(type)` works (a `Dictionary` on Entity keyed by component class is fine).

---

## 3. Entity base + component access

```gdscript
class_name Entity extends CharacterBody2D
var components := {}                 # ClassName(String) -> Node
@onready var sprite := $Sprite2D

func get_component(type: String) -> Node: return components.get(type)
func has_component(type: String) -> bool: return components.has(type)

# do/receive aggregation for the interaction resolver
func do_actions() -> Array[StringName]:      # union over components' DO tags
func receive_actions() -> Array[StringName]: # union over components' RECEIVE tags
```

`interactions(a, b) = a.do_actions()  ∩  b.receive_actions()` — the Brain's candidate menu (§7).

---

## 4. Components for this milestone (with starter numbers)

All bars 0–100. Tick from a shared `_process(delta)` per component (self-ticking is fine at this scale — systems are a later milestone).

| Component | DO | RECEIVE | State + starter numbers |
|---|---|---|---|
| `SpriteComponent` | — | — | (texture/tint from def) |
| `MovementComponent` | — | — | `walk=120 px/s`, `run=240` (Type1); gait set by Brain; spends energy per grid; `move_to(pos)` fixed point + `follow(entity)` chase (re-reads target pos each tick, falls back to last-known then emits `lost_target`) |
| `HungerComponent` | eat | — | `hunger=100`, drain **1.0/s**; `<50` → SatisfyHunger goal; `=0` → −**2 hp/s** starvation |
| `FatigueComponent` | sleep | — | `energy=100`, drain **0.5/s** idle + movement cost; `=0` → collapse (no damage), sleep-locked until 50, self-managed |
| `HealthComponent` | — | attack | `hp=100`; regen **+1/s while hunger>50**; `=0` → died → disable Movement+Brain (harvestable in place) |
| `InventoryComponent` | pickUp | — | `items: Array` (item-data, def refs) |
| `ActionComponent` | harvest | — | `reach=40 px`; runs the chosen ActionDef |
| `AttackComponent` | attack | — | `damage=20` (Type2 only) |
| `EatableComponent` | — | eat | `food_type`, `hunger_value=25` → `actor.hunger.feed(25)` + free self |
| `HarvestableComponent` | — | harvest | see §5 for yield/damage numbers |
| `PickUpAbleComponent` | — | pickUp | `item_data` → store in actor inventory + free self |
| `SensorComponent` | — | — | Area2D radius = detection (per type §6); `get_threats/get_prey/get_food` |
| `BrainComponent` | — | — | GOAP; think tick **0.3s** |

Movement energy: `walk 0.5/grid`, `run 2.0/grid`, `GRID=64px` (one painted tile). Exhaustion lock at energy 0 → can't run.

**Follow mode (chase):** `follow(target)` re-reads the target's position every tick and steers straight at it — **no pathfinding** for this milestone. If the target leaves Sensor range, it drives to the **last-known position**, then emits `lost_target` and stops so the Brain replans. Predators use this to chase prey; `move_to(pos)` stays the fixed-point version for bushes.

---

## 5. Actions (ActionDef resources) — the numbers

| Action | mode | input | time | output | notes |
|---|---|---|---|---|---|
| `harvest` | ONE_TIME | 10 energy | 0.5s | SpawnOutput: yield entities at target; **if target Movement enabled → StatOutput −35 hp target** | bush yields 1 berry clean; live prey yields **2 meat + 35 dmg**; dead prey yields remaining meat clean |
| `pickUp` | ONE_TIME | — | 0.1s | ItemOutput: target data → actor inventory; free target | auto-performed on in-reach diet-matching food |
| `eat` | ONE_TIME | 1 food item | 0.5s | StatOutput +25 hunger to actor | diet-gated: `food_type ∈ actor.diet` |
| `sleep` | OVER_TIME | — | until 100 / interrupt | StatOutput +2 energy/s to actor | self-directed, in place; no target |
| `attack` | ONE_TIME | — | 0.5s | StatOutput −`AttackComponent.damage` hp target | pure damage, no yield (predation uses harvest instead) |

**Predation via harvest (confirmed):** Type2 harvests a live Type1 → −10 energy, +2 meat, prey −35 hp. Prey (hp 100) dies in **3 harvests**; predator nets ~6 meat, then eats. On death, Movement disables → subsequent harvests are clean.

---

## 6. Type profiles (`.tres` blueprints)

| Blueprint | Components | Detection | Run | Diet | Tint |
|---|---|---|---|---|---|
| `type1` | full stack, no Attack | **260** | 240 | VEGIE | green |
| `type2` | full stack **+ Attack(20)** | 200 | **336** (1.4×) | MEAT | red |
| `type3` | full stack, no Attack | **140** | **480** (2×) | VEGIE | blue |
| `berrybush` | Harvestable(→berry) only | — | — | — | dark green |
| `berry` | Eatable(VEGIE,25) + PickUpAble | — | — | — | pink |
| `meat` | Eatable(MEAT,25) + PickUpAble | — | — | — | maroon |

Base detection `D=200 px`. Base run `R=240 px/s`. Walk `120 px/s` all types.

> **Rebased on the 64px tilemap.** The module's painted `TileMapLayer` uses 64px tiles over
> roughly 2048×1216 px, so every distance and speed above is 2× the original 32px draft while the
> per-grid energy costs are unchanged — one "grid" is now one visible tile. See `SimConst`.

---

## 7. GOAP (kept minimal but real)

**Utility picks the goal, GOAP plans the route** (one BrainComponent, all creatures).

Goals, scored each 0.3s tick; highest wins, below threshold → Wander:
- **Flee** — score from Danger bar (herbivores only; rises w/ nearest Type2 proximity in detection range, decays ~15/s; Flee active while Danger>0). RUN away.
- **SatisfyHunger** — score rises as hunger drops below 50. Plan: `[harvest(source), pickUp, eat]`, or `[eat]` if food already in inventory.
- **Rest** — score rises as energy drops below 50. Plan: `[sleep]` — self-directed, no travel — or a forced collapse if energy hits 0 first.
- **Wander** — idle fallback, drunkard's walk.

Planner: backward/forward chain over the actor's available actions (from `do ∩ receive` against sensed targets) to reach the goal's desired world-state; **replan on failure** (bush gone, prey fled). Plans here are 1–3 steps — a tiny A* or even a hardcoded chooser is acceptable; the point is proving the *structure* (preconditions from components/inventory, effects, replan), not planner sophistication.

WorldState is read from components + inventory: `has_vegie/has_meat` (inventory), `hunger/energy` (bars), `prey_visible/threat_visible` (sensor).

---

## 8. World file (starter `world1.tres`)

A `WorldDef` covering the painted **2048×1216** map: a flat `entries` list, one `SimPlacement` per
entity (`entity_name`, `type`, `position`, optional `overrides`). 31 rows. Distribution is authored
data, not something the factory generates — a placement algorithm can write this list later, but the
factory only reads it. Current mix:
- 10 × `type1`, 4 × `type3`, 3 × `type2`
- 8 × `berrybush`
- (berries/meat are spawned at runtime by harvest, not placed)

Each entry: `{ name, type, position: Vector2, overrides: {} }`. Scatter positions; give 2–3 herbivores an override like `{hunger: {start: 40}}` so feeding behavior fires immediately on run.

Run ends implicitly when herbivores go extinct (no reproduction this milestone) — that's the expected terminal state and is fine; it also *is* the Type1-vs-Type3 experiment readout (which type lasted longer).

---

## 9. Debug overlay (not optional — it's how you verify)

Each entity draws above itself: current **goal** name, and its **hunger/energy/health/danger** as tiny bars or numbers. Without this you cannot tell a working planner from a stuck one. Cheap `_draw()` or a `Label` child is enough.

---

## 10. Explicitly OUT of scope for Milestone 1
Systems (vs self-ticking), spatial queries, serialization/save-load, event-bus scale, reproduction/equilibrium, production/crafting chains, LOS (sensor is radius-only), tuning polish. All deferred — this milestone only proves: **data → factory → components → actions → GOAP → visible behavior.**

---

## 11. As built

The running prototype, and where it departs from the spec above. For the full current-state
picture — file tree, tuning values, next steps — read `HANDOFF.md`.

### Naming and structure
- **`Sim` prefix on every global `class_name`.** `Entity` and `InventoryComponent` were taken by
  `Global/Scene/`, and `ComponentDef` subclasses need a global `class_name` to be creatable from the
  inspector's resource picker.
- **`SimSpriteDef` adds no node.** It configures the `Sprite2D` the base scene already owns and
  registers it under the `sprite` slot, so the factory has no special cases.
- **The factory `add_child`s before building components**, not after; `@onready` members are null
  until the entity is in the tree.
- **No `Body` Area2D.** An Area2D sensor detects a `CharacterBody2D` directly through
  `body_entered` / `get_overlapping_bodies()`, so the body's own shape is the presence.
- **`SimEntity.components` is keyed by slot**, not class name — the slot is already the override key.
- **`home_position` was removed.** Wander is free-roam now, so nothing referenced it.

### World
- `SimWorldDef` is a flat `entries` list. Bulk scatter rules existed briefly and were removed:
  distribution will come from a purpose-built algorithm, and the factory should only *read* a list.
- World bounds are read off the `TileMapLayer` at startup rather than held as a constant.
- The map is **57 × 35 tiles = 3648 × 2240 px**, not the 1200 × 800 assumed in §8.

### Components that exist
`sprite`, `movement`, `sensor`, `action`, `inventory`, `pickupable`, `brain`, `spawner`, `debug`.

- **Wander lives inside the brain**, not its own component — that removed the need to arbitrate
  between two things driving movement.
- **`ActionComponent` is only the hand.** It answers `in_reach()` and knows no specific action.
  Pick-up belongs to `InventoryComponent`, which asks the hand for reach and the target's
  `PickUpAbleComponent` to resolve. An entity with a hand and no pockets carries no pick-up code.
- **`SimEntitySpawnerComponent` is temporary** — a stand-in for the berry bush until `harvest` and
  its `SpawnOutput` exist.
- **Brain traits.** `SimBrainDef.traits: Array[SimTrait]` are behaviour modifiers consulted at
  defined hooks; no traits means default behaviour. `SimFlockTrait` (same-blueprint boids, applied
  only while wandering) is the first. This is how entities sharing one brain differ without a
  subclass or a branch.

### Inspector
Each component decides how it appears via `describe()` / `describe_label()`; returning `{}` opts out,
which Movement, Sensor and Action do. Tabs are generated from whatever reports, so a new component
gets a tab for free.

### Bars
Health, Hunger and Fatigue exist. They report to the inspector's **main** tab through
`describe_summary()` rather than claiming a tab each, and Health/Hunger draw a small bar under the
sprite (prototype rendering, same caveat as the carry badge).

Couplings run one way and are asked for, never pushed: Health asks Hunger `is_well_fed()`; Fatigue
asks Movement `is_moving()`; Hunger reads the entity's own `is_sleeping` flag. No bar depends on
another bar's component.

**Collapse is owned by `FatigueComponent`**, not the brain — at zero it sleeps the entity, switches
the brain off, and wakes it at 50. No health penalty. Voluntary Rest (a brain decision) is still step 6.

### Not yet built
`Eatable`, `Harvestable`, `Attack`, actions as `ActionDef` data,
GOAP, the utility goal layer, sleep, Danger, flee and predation.

Verify with F1 (toggle the per-entity labels), a left-click on any entity (inspector plus that
entity's sensor and reach circles) and F5 (respawn from `world1.tres`).
