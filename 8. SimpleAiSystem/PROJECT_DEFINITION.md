# Colony Sim — Project Definition

> **A data-driven ECS foundation for a Godot 4 colony sim.**
> Not the game — the *groundwork* the game will be built on. The goal is a solid,
> expandable base where new content is authored as **data** (resource files), not code.
> Project folder: `project/godot/compilationpack`

Companion docs: `COLONY_SIM_CONCEPT.md` (full architecture reference) · `MILESTONE_1_SPEC.md` (buildable spec + numbers) · `HANDOFF.md` (**what is actually built right now**).

> **Status:** Phase 1 is complete. Phase 2 is under way but deliberately out of order — the
> component interaction layer (sensor, action, inventory, pick-up, a simple brain) was built before
> the bars, so the loop could be exercised before GOAP. See `HANDOFF.md` §2.

---

## Why this project exists

The eventual colony sim will have many entity kinds, many behaviors, and will grow for a
long time. That only stays maintainable if the foundation is **data-driven**: adding a new
creature, prop, item, or behavior should mean writing a `.tres` file — not a new scene, not
new branching code. This project builds and proves that foundation on a small, honest slice
before the real game is layered on top.

**Design philosophy (the rules the foundation must uphold):**
- **Everything is an Entity** — creatures, props, items alike. One bare base, one factory.
- **What a thing *is* = which components it has.** No type hierarchy, no `if is_a_plant`.
- **Capability = component presence.** No Hunger component → never seeks food. No Health → can't be hurt.
- **Content is data.** Entities are authored as `EntityDef` blueprints; worlds as a `WorldDef` placement list.

---

## The two focuses

Everything in this project serves one of two pillars. If a task doesn't advance one of these,
it's out of scope.

### Focus 1 — EntityFactory (the spine)
A factory that reads a resource file (a long list of entity placements) and spawns every
entity from data, attaching each one's components per its blueprint. This is what makes the
foundation "data-driven." If this is solid, all future content is just more `.tres`.

### Focus 2 — GOAP AI (the proof it composes)
A goal-oriented planner that reasons over the components and actions the factory produced —
proving the entity/component/action structure actually *feeds* real behavior, not just spawns
inert objects. GOAP is the stress test: if a planner can plan against these components, the
structure is sound.

---

## Phase 1 — Make the EntityFactory work

**Objective:** one `WorldDef` resource → `EntityFactory` → 30+ live entities on screen, each
assembled from its blueprint's component list.

**In scope:**
- `Entity.tscn` bare base (Sprite2D + body Area2D).
- `ComponentDef` hierarchy, `EntityDef` blueprints, `EntityCatalog`, `WorldDef` placement list.
- `EntityFactory.spawn_world()` — deep-dup defs per instance, apply per-instance overrides, build components.
- A handful of trivial components (Sprite, Movement + wander) so spawned entities are visibly distinct and alive.
- Simple debug overlay (which components an entity has).

**Done when:**
1. 30+ entities spawn from `world1.tres` at their positions, correct sprite/tint per type.
2. Editing the `.tres` (add/remove an entry, change a number, add Type4) changes the result with **no code change**.
3. No shared-state bug — 30 entities behave as 30 independent entities (per-instance overrides don't leak).
4. A trivial component (wander) runs, proving components attach and tick.

**Phase 1 is the priority.** It must be rock-solid before Phase 2 — GOAP has nothing to plan
against until the factory reliably produces component-bearing entities.

---

## Phase 2 — Finish with GOAP AI

**Objective:** a working planner drives entities through real multi-step behavior using the
components and actions from Phase 1. Full loop: **hunger, sleep, flee/predation.**

**In scope:**
- Action system: `ActionDef` resources (input / time / output / mode), advertised by affordance components.
- The **do ∩ receive** interaction resolver (what actor A can do to target B).
- **Actions vs Plans:** primitive actions (`attack`, `harvest`, `eat`, `pickUp`, `sleep`) + macro operators (`kill` = chain-damage-until-dead, postcondition unlocks `harvest`).
- GOAP planner: preconditions/effects over a simulated world-state, replans on failure.
- Utility layer to pick the goal (hunger / rest / flee / wander); GOAP plans the route.
- Both food chains proven:
  - **static chain** (herbivore): `harvest(bush) → pickUp → eat` — readable by scanning.
  - **conditional chain** (carnivore): `kill → harvest(corpse) → eat` — the planner sees through the kill via `kill`'s declared postcondition.

**Done when:**
1. Herbivores feed themselves from bushes; hunger recovers.
2. Predators execute `[kill, harvest, eat]` against live prey — the conditional chain plans correctly.
3. Tired entities sleep in place (voluntarily, or a forced collapse); threatened prey flee until safe.
4. Debug overlay shows each entity's current **goal**, so a working planner is visibly distinguishable from a stuck one.

---

## Explicit non-goals (deferred — protect the scope)

Not in Phase 1 or 2. These are real foundation topics, but proving the two focuses comes first:
- Optimization / performance (self-ticking components are fine for now; true ECS *systems* later).
- Spatial queries beyond the Sensor's Area2D.
- Serialization / save-load.
- Event-bus scale, reproduction / population equilibrium, production & crafting chains.
- Line-of-sight (sensor is radius-only), tuning polish, art.

---

## Success for the whole project

The foundation is proven when: **a new entity or a new world is authored entirely in `.tres`,
the factory spawns it, and a GOAP brain plans correct multi-step behavior against its
components — with no engine code touched.** At that point the real colony sim can be built on
top with confidence that the base is solid and expandable.
