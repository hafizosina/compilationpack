# Refactor Plan — Hand-Rolled ECS Rewrite

> Greenfield rebuild of the data-driven foundation as **real ECS** (data-only components,
> behavior in systems), hand-rolled and minimal. Godot 4.x, GDScript.
>
> **Why:** the node-composition model is fighting the design — de-noded stateful items
> (weapon durability) and hand-enforced "each resolves what it knows" are *manufactured*
> problems that ECS dissolves structurally. This rewrite's job is to prove that.
>
> **Not driven by performance.** At 5–40 entities the cache wins are irrelevant. The win is
> *structural cleanliness of interactions*. If interactions don't get cleaner, the rewrite failed.

Companion: `COLONY_SIM_CONCEPT.md`, `MILESTONE_1_SPEC.md`, `PROJECT_DEFINITION.md`,
`HANDOFF.md` (the node-composition build — kept as a running reference, not deleted).

---

## 0. The one rule that defines success

**A new interaction (attack, eat, ride, wield-a-weapon) is added by writing a system that
queries the components it cares about — touching no other system, and reaching into no
entity's private logic.** If adding "armour" ever forces an edit to the attack code, the ECS
is wrong. That is the whole reason for the rewrite; it's the acceptance test for every step.

---

## 1. Strategy: greenfield, parallel, reference-kept

- New module: **`9. EcsSystem`** (or rename later). Built beside `8. SimpleAiSystem`, which
  **keeps running** as the behavioral reference — same loop, so you can diff behavior, not guess it.
- **Port concepts, not code.** The three refactor rounds' *lessons* carry over (claim, each-side-
  resolves, entity-mediates); the *node classes* do not.
- Module 8 is retired only when module 9 reproduces its loop (hungry→seek→eat) *and* has done
  the thing 8 couldn't: a stateful wielded weapon with durability, clean.

---

## 2. The hand-rolled ECS core (build this first, ~5 small scripts)

Minimal. No addon. Just enough to get data-only components + systems + queries.

```
EcsWorld          # owns entities + component storage; the query engine
  create_entity() -> int (id)
  destroy_entity(id)
  add(id, component)                 # component = a Resource/struct, DATA ONLY
  get(id, CompType) -> component
  remove(id, CompType)
  query(include: Array, exclude := Array) -> Array[id]    # entities with ALL include comps
  add_singleton(component) / get_singleton(CompType)      # world-level state (e.g. events)

EcsComponent      # base: extends Resource, NO methods with logic — fields only
EcsSystem         # base: run(world, delta) -> void
EcsScheduler      # ordered list of systems; run_all(world, delta) each _process
EcsEvent          # transient component-like records, cleared each frame (DamageEvent, etc.)
```

**Storage:** for this scale, `components: Dictionary  { CompType : { entity_id : component } }`.
Query = intersect the id-sets of the requested types. Naive, fine at hundreds. A packed/archetype
store is a later optimization the query API hides — do **not** build it now.

**Hard rules (these are the ECS discipline, enforce them in review):**
- Components hold **data only**. No `apply()`, no `use()`, no behavior. A field-only Resource.
- Systems hold **all** behavior. A system reads components via `query`, writes components/events.
- Systems never call each other. They coordinate only through shared components/events + run-order.
- Nothing outside a system mutates component data during the frame.

---

## 3. Entity representation

An entity is an **integer id**, not a node. But it still needs to render and be clicked, so:

- A `Transform2D`/position lives in a `PositionComponent` (data).
- One thin **`RenderSystem`** syncs positions → a pool of `Sprite2D`s (or a single `_draw`).
  Nodes become a *view* of the data, not the entities themselves.
- Click-picking / selection is a system querying `PositionComponent` for nearest to the mouse.

This is the biggest mental shift from module 8: **the scene tree is a rendering view; the
world is data.** Decide early: sprite-pool + RenderSystem (recommended) vs. one node per entity
kept dumb. Recommended = pool, because it commits to "entity = id, node = view."

---

## 4. Port order — PAIN FIRST

Deliberately front-load the weapon/interaction problem. If ECS doesn't make *that* clean, stop
and reconsider before porting the rest. Don't rebuild the easy stuff first and discover the hard
thing still hurts.

**Step 0 — Core + one system + render.** `EcsWorld`, scheduler, `PositionComponent`,
`MovementComponent`(data: velocity/target), `MovementSystem`, `RenderSystem`. Spawn 30 ids with
positions, a `WanderSystem` drifts them. Success: 30 sprites drift. (This is Phase-1's proof, ECS-style.)

**Step 1 — Factory from data, ECS-style.** `EntityDef`/`WorldDef` unchanged in spirit, but
`spawn` now = `world.create_entity()` + `world.add(id, comp)` per def. Deep-dup still applies
(component data per instance). Success: `world1.tres` → 30 entities, edit-`.tres`-no-code holds.

**Step 2 — THE PAIN CASE, immediately: weapon + durability + attack.** Before bars, before AI.
Build the three-system attack pipeline against a stateful wielded item:
```
components (data only):
  Health {hp}                 Armor {reduction}          Damage {amount}
  Durability {current, max}    Equipped {weapon_id}        AttackIntent {target_id}
systems (in order):
  AttackSystem     query[AttackIntent, Equipped] -> read wielder + weapon Damage
                   -> emit DamageEvent{from, to, weapon_id, amount}; clear intent
  DamageSystem     query DamageEvent -> read target Armor -> write target Health
  DurabilitySystem query DamageEvent -> decrement Durability on weapon_id
  DeathSystem      query[Health hp<=0] -> mark dead / make harvestable
```
**The weapon is just an entity id with a `Durability` component.** In inventory = an
`Equipped{weapon_id}` relationship, NOT a de-noded resource. Durability is mutated by a system
that queries it — nobody "reaches into" the weapon. **This is the exact thing module 8 couldn't do
cleanly; if it's clean here, the rewrite is validated.** Acceptance: add an `Armor` component to a
target and the attack code does not change; add a `CritChance` component to a wielder and the
defender code does not change.

**Step 3 — Inventory + pickup as relationships.** `Inventory{item_ids: []}`; pickup = a system
that moves an id from world to an entity's inventory (reparent the *view*, not the data). Items
stay entities with their components (durability, food value) intact — the de-noding problem is
simply gone. Eat = `ConsumeSystem` querying intent + a `FoodValue` component, applying to `Hunger`.

**Step 4 — Bars as systems.** `Hunger/Fatigue/Health` become data components; `HungerSystem`,
`FatigueSystem` (owns collapse via a `Sleeping` component), `HealthRegenSystem`. One loop each
over all matching entities — the ECS-native version of self-ticking bars.

**Step 5 — Sensor + intents.** `SensorSystem` writes a `Perceived{ids}` component (or a spatial
singleton). No node areas needed — it's a distance query over `PositionComponent`. This is where
ECS pays off again: perception is just a query.

**Step 6 — Brain (FSM first, then GOAP) — the one thing that is NOT a pure system.** The brain
reads components and **writes intent components** (`MoveIntent`, `AttackIntent`, `EatIntent`);
downstream systems execute them. FSM version first to reproduce module 8's loop. Keep per-entity
brain logic — do not force GOAP into a homogeneous system loop.

**Step 7 — GOAP, off-frame.** Planner is a **pure function over a symbolic `WorldState` snapshot
→ `Array[action_id]`**, touching no live components. A `PlanningSystem` builds the snapshot,
runs the planner under a **per-frame budget** (N replans/frame queue), and writes the resulting
`Plan` component. Execution systems follow the plan. Snapshot-purity is what makes it non-blocking,
testable, and thread-ready later without a rewrite.

---

## 5. What carries over from module 8 (concepts, not code)

- **Claim / "leaving the world is one route"** → in ECS this is a system moving an id between
  world and inventory; the race is resolved by *one system owning the move*, run once per frame.
  The discipline becomes structural — only PickupSystem moves items, so no double-claim is possible.
- **"Each side resolves what it knows"** → becomes automatic: AttackSystem reads attacker data,
  DamageSystem reads defender data, DurabilitySystem reads weapon data. Separation *is* the queries.
- **Actor asks / target resolves** → dissolves. There's no asking; systems query. The distinction
  that was hard to hold by hand stops needing to be held.
- **`do ∩ receive`** → becomes "does the entity have the components this system's action needs."
  Availability is a query, not an intersection you compute.
- **Brain-is-a-type** → survives as "the FSM system and the GOAP planner both write the same intent
  components," so swapping them changes no downstream system.

---

## 6. Explicit non-goals (same discipline as before — protect the rewrite)

- Archetype/packed storage, parallelism, threading the planner (budget-queue is enough now).
- Serialization (but note: ECS makes it *easier* later — the world is already all data).
- The full three-creature experiment, production chains, timed stat modifiers.
- Performance tuning. **The rewrite is judged on interaction cleanliness, not FPS.**

---

## 7. Kill criteria — when to abandon the rewrite

Be willing to stop. Abandon and return to module 8 if:
- Step 2 (weapon/durability/attack) is **not** visibly cleaner than the module-8 attempt — that was
  the whole premise; if it's a wash, the rewrite isn't buying what you came for.
- The hand-rolled query layer grows past ~150 lines to stay usable at this scale (means you needed
  an addon, or ECS is overkill here).
- Two weeks in, the loop (hungry→seek→eat) isn't reproduced — momentum lost for architecture's sake.

If Step 2 lands clean, none of these trigger and you proceed with confidence.

---

## 8. First session's concrete target

Steps 0–2 only: core (~5 scripts), factory, and the weapon/attack pipeline with a durability that a
system decrements. End state: two entities, one attacks the other with a wielded weapon, target
loses HP through armour, weapon loses durability — and you can add an `Armor` or `CritChance`
component without editing the attack or damage systems. That single result answers the only question
that matters: **does ECS dissolve the pain that drove this rewrite.**
