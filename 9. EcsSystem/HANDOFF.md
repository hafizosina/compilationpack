# Module 9 — EcsSystem: state of the build

The living state of module 9, and the only document in this folder besides the roadmap
(`ECS_REFACTOR_PLAN.md`). Read it before touching the folder. It says what exists, why it is
shaped that way, what is settled, what is open, and what has been measured. History —
earlier designs and the reasoning that retired them — is in git; commit hashes are given
where a design is worth recovering.

Module 9 is a hand-rolled ECS and the repo's only live simulation. Module 8 (`8.
SimpleAiSystem`) is a design archive: its code is deleted, and references to it here are to
a recorded design, not something you can run.

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
"$GODOT" --path . "res://9. EcsSystem/main.tscn"                          # run it (also the main scene)
"$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn" # 161 checks, exit 0 = all pass
"$GODOT" --headless --path . "res://9. EcsSystem/tests/stress_test.tscn"    # population ramp, minutes
"$GODOT" --headless --editor --quit --path . 2>&1 | grep -iE "error|invalid|uid"  # after any .tscn/.tres edit
```

In the running game: **F1** toggles the debug overlay, **F5** respawns the world, left-click
selects an entity for the inspector, the wheel zooms, middle-drag pans.

One thing outside this folder belongs to module 9: the main-scene line in `project.godot`.
The shared camera (`Global/Scene/camera_2d.tscn`) and three `EventBus` signals
(`ecs_world_census`, `ecs_entity_inspected`, `ecs_respawn_requested`) are used by it too.

---

## 1. The whole flow, in order

```
world1.tres ──► EcsEntityManager ──► EcsWorld                         (at startup, and on F5)
(placements)    resolves each row     ids + component tables
                against catalog.tres, + each entity's nodes, under
                builds the nodes      World/Entities/entity_<id>/
```

Every physics tick `EcsScheduler` runs seventeen stages. `[20 Hz]` marks the two that run
every third tick (§11); the rest run every tick.

| stage | does | writes |
|---|---|---|
| `lifecycle` | births and deaths — the only stage that creates or frees | the world, the nodes |
| `spawner` | a bush asks for a berry | a note on `EcsLifecycleSingleton` |
| `hunger` | fullness drains; starving costs health, fed mends it | `EcsHunger`, `EcsHealth` |
| `energy` | drains awake, restores asleep; collapse at zero | `EcsEnergy`, `EcsCollapsedFlag`, `EcsHealth` |
| `health` | death at zero | `EcsDyingFlag` |
| `sensor` `[20 Hz]` | what each entity sees and can touch | `EcsSensor.perceived`, `EcsAction.reached` |
| `low_brain` `[20 Hz]` | the FSM: chooses | its own state, a destination, intent flags |
| `consume` | carries out an eat intent | `EcsHunger`, the bag, `EcsDyingFlag` |
| `movement` | walks toward the destination, prices the trip | `EcsPosition`, `EcsMovement` |
| `collision` | pushes overlapping solid bodies apart | `EcsPosition` |
| `pickup` | carries out a take intent | the bag, `EcsDyingFlag` |
| `drop` | a dying carrier's bag goes back into the world | notes on `EcsLifecycleSingleton` |
| `selection` | resolves a click | `EcsSelectedFlag` |
| `node_sync` | mirrors data onto the nodes, one way | each `entity_<id>` container |
| `debug` | reads everything for the overlay | nothing — pure reader |
| `census` | counts the world | `EventBus` |
| `inspect` | snapshots the selected entity | `EventBus` |

The last three are pure readers: pull them out and the simulation does not notice. The
pipeline runs in `_physics_process` — a fixed timestep, and the physics overlap lists are
refreshed once per physics step anyway.

**Three rules are non-negotiable:** components hold data (one display-only exception, §2),
systems hold all behaviour and never call each other, and nothing outside a system mutates
component data. Queries key on the script object — `world.query([EcsPositionComponent])` —
so a typo is a parse error, not a silently empty result.

The world today is 10 animals and 2 bushes (`defs/world1.tres`), spread across a 3200×1680
arena, plus the berries the bushes grow.

---

## 2. Three kinds of data: components, flags, singletons

All three are `EcsComponent`s to the store — `add`, `has`, `remove` and `query` treat them
alike. The difference is what they mean, and it is a **guideline, not an enforced rule**:
break it for a good reason and write the reason down where it breaks.

| | component | flag | singleton |
|---|---|---|---|
| says | what the entity **is** | what is true of it **now** | world-level state |
| present | from spawn to death | added and removed freely | once per world |
| data | authored (`@export`, blueprint or placement) | runtime only, never `@export` | runtime |
| base / folder | `EcsComponent`, `components/` | `EcsFlag`, `flags/` | `EcsSingleton`, `singletons/` |

A wall that gains movement is no longer a wall — that is a kill and a spawn, not an `add()`.
Nothing today adds or removes a component after spawn.

**15 components** — `name`, `position` (both added by the manager from the placement, not the
blueprint), `sprite`, `body`, `movement`, `low_brain`, `sensor`, `action`, `hunger`, `health`,
`energy`, `inventory`, `consumable`, `pickable`, `spawner`.

**6 flags** — `EcsSelectedFlag` (selection owns it), `EcsCollapsedFlag` (energy), and three
brain intents, `EcsEatIntentFlag{target_id | record_uid}`, `EcsTakeIntentFlag{target_id}` and
`EcsAsleepFlag`, plus `EcsDyingFlag` (§3). A flag may carry data — an intent names its target
— but nothing about a flag is decided before the game starts.

**2 singletons** — `EcsLifecycleSingleton` (spawn notes) and `EcsSelectionSingleton` (the
pending click).

**The one method a component may have is `describe()`**, for display only (§10). It reads the
component's own fields and changes nothing. Anything that computes, decides or writes still
belongs in a system — module 8's `describe()` is back for this and nothing else.

**Components declare what they imply rather than being switched on.** `const NODE_KIND`
names the node a component needs, `NODE_LAYER` / `NODE_MASK` its physics layer policy
(§4), and `describe()` how it reads. `EcsEntityManager` and `EcsInspectSystem` read those
and never name a component type; a new node-backed or newly-displayed component edits
neither.

---

## 3. Lifecycle: one owner for structure

**`EcsEntityManager` is the only thing that creates or destroys an entity id, its component
data, or its nodes**, and it does so at one instant — the `lifecycle` stage, first in the
pipeline — so every system in a tick sees the same set of entities. It *creates and
destroys*; it never updates. Per-tick writes onto nodes belong to `EcsNodeSyncSystem`
(sprites, container position) and `EcsCollisionSystem` (body radius and liveness). Hold that
line or the manager becomes the god object the split was meant to avoid.

- **Birth** is a note: a system appends an `EcsSpawnRequest` to `EcsLifecycleSingleton`, and
  reads the new id back off its own note a tick later (`EcsSpawnerSystem` counts its berries
  that way). A note may carry an `EcsItemRecord` instead of a blueprint id, and then the
  manager's `restore()` rebuilds that exact item (§9).
- **Death** is a flag: a system adds `EcsDyingFlag`, and the lifecycle stage destroys every
  entity carrying it, data and nodes together.

**`EcsDyingFlag` is also the claim.** Death waits a tick; the flag lands in the store at
once. Every executor that eats or takes refuses anything carrying it, and the brain does not
commit to it. That is the Valheim/Minecraft duplication fix — one authority checks and
commits in one step — and here the authority is simply the executor, because systems run one
at a time. No entity ever learns another's intent: a brain may decide on a claimed berry,
the executor refuses it, the brain decides again. It closed a real race (a grazer eating a
berry and a carrier pocketing the same berry in one tick), and a test pins it.

### Nodes are grouped per entity

```
World/Entities/
  entity_7/            ← plain Node2D: no script, no data, no state
    Sprite2D
    Area2dForBody
    Area2dForSensor
    Area2dForAction
  entity_11/
    Sprite2D
```

The container carries the transform and its children sit at local zero, so position is
written once per entity however many concerns it grows, and one container freed takes the
whole entity with it. **An `entity_<id>` node is a container, never an entity** — nothing is
read back off it, and deleting every one leaves the simulation complete. That discipline is
all that separates this from module 8, where the node *was* the entity; if something hangs
state on a container, the line has been crossed. `ecs_entity_manager.gd`'s header is where
it was agreed.

**Node lifetime tracks the entity.** Nothing is alive-but-nowhere: a picked-up berry dies and
becomes a record, so freeing a node is kill and only kill.

A new node-backed concern — an audio player, a new area — is a component with the right
constants. `_make_node` is "the sprite, or an area built from what the component declared".

The first tick after a world is built creates every node at once: 5 ms at 100 entities,
345 ms at 1,000, 97% of it `Area2D` creation. Free behind a loading screen; a mid-game spawn
wave would want a per-tick creation cap.

---

## 4. Perception and reach are physics, not arithmetic

| component | area | rabbit | monkey | answers |
|---|---|---|---|---|
| `EcsSensorComponent` | `Area2dForSensor` | 280 | 420 | what can I see — `perceived` |
| `EcsActionComponent` | `Area2dForAction` | 34 | 50 | what can I touch — `reached` |
| `EcsBodyComponent` | `Area2dForBody` | 22 | 36 | where am I, to others |

`EcsSensorSystem` writes both lists. **It and `EcsCollisionSystem` are the only two files that
read anything back off a node**, and that is the whole of the exception: components stay the
only truth, the areas are a derived index, and what is read back is *which ids overlap*,
never where anything is. Every other system reads ids off components.

**Layer policy is declared on the component.** Only `EcsBodyComponent` claims a layer
(`LAYER_BODY`) — a body is the only detectable thing in the world. Sensors and action areas
carry no layer, so no sensor is ever reported to another sensor (without that the n² moves
into the physics server where a profile cannot see it). Body's mask stays `LAYER_BODY`
because soft collision *is* body-vs-body; measured at 3,200 entities, that costs nothing. The
manager derives `monitoring` / `monitorable` from the declaration and has no opinion.

**The overlap list is the verdict on reach**, and that is a decision. Pickup and consume
used to re-check `distance <= reach + radius`, but that is the same condition the physics
server tested, on numbers about one tick — roughly a pixel — fresher. The accepted error is
one tick of motion. What executors still re-ask is whether the thing named is *still
there* (alive, not Dying) — a different, cheap question. A freshly spawned entity perceives
nothing on its first tick, so its opening move is always a wander, preempted the tick after.

Keep a solid entity's action radius above its body radius (rabbit 22 → 34, monkey 36 → 50),
or soft collision stops it before its reach arrives.

---

## 5. Bodies and collision

**Having a body, blocking the way and being movable are three separate questions.**
`EcsBodyComponent` is the body — a radius and an area, so the entity can be perceived and
reached. Its `is_solid` decides whether that body takes part in soft collision.
`EcsMovementComponent` is what lets the resolve move it rather than only push others out.

| | body | solid | movable |
|---|---|---|---|
| bush | 45 | yes | no — walked into, never budged |
| rabbit, monkey | 22, 36 | yes | yes |
| berry | 14 | **no** — walked over | no |

`is_solid` is the module's one authored boolean of this kind, chosen over a tag component
deliberately: radius and solidity are one physical fact about one body.

**Collision is soft.** `EcsCollisionSystem` runs after movement: movement proposes a
position, collision pushes overlapping pairs apart, and neither knows the other. Overlap is
allowed and then undone, never prevented — which is what lets any future position-writer be
corrected for free. Each pair is reported twice (A sees B, B sees A) and each body moves only
itself by half the overlap, so the double report makes it symmetric. One tick of lag, one
pass per tick, converging over a few ticks; `intersect_shape()` is the synchronous
alternative if that ever matters. It costs: a fast mover can tunnel between ticks, a
squeezed body can be pushed through a third, and nothing bounces.

The body is **data, not a physics body** — the sim runs with no scene tree. The overlay does
not draw body circles: the tree holds real `CollisionShape2D`s, so Godot's **Debug > Visible
Collision Shapes** shows what the physics server actually uses.

---

## 6. Movement: a destination is a budget, not a standing order

`EcsMovementSystem` walks an entity toward `EcsMovementComponent.destination` and prices each
trip the tick it first sees it:

```
time_left = distance / speed * timeout_slack + timeout_grace      (defaults 2.5, 0.5)
```

When it runs out the destination is dropped exactly as if reached. **Giving up and arriving
are the same event to every other system.** Without it, an entity that soft collision holds
off its target keeps `has_destination` forever and the brain skips it *because* it already
has somewhere to be — a livelock across stages, not a bug inside one. It does not remember
what it gave up on; a re-target policy belongs in the brain.

The destination is the brain's move instruction. **There is no `MoveIntent` flag yet —
decided and deferred** until the proof of concept has run.

---

## 7. The brain: the only thing that chooses

`EcsLowBrainSystem` is a small FSM, and `EcsLowBrainComponent` holds its `state`, `target` and
pause clock. It is named for its **rank** — the bottom of the plan's decision ladder; a
planner goes above it at step 7 — not for the wandering it happens to do.

**Each tick, per creature:**

1. **Collapsed** → it has no say; SLEEP, any trip called off. This is the one thing allowed
   to override a live commitment.
2. **Asleep by choice** → stays down until rested (`wake_at`) or starving.
3. **Seeking food** → a commitment is not reconsidered: kept until the target is gone
   (eaten, taken, Dying), within reach (fulfilled — the rungs below act this same tick), or
   the trip ends.
4. **Wandering** → interruptible; a creature notices food mid-leg.
5. **Choose, highest rung first:**

```
EAT        hungry enough (fullness <= eat_below), food at hand — bag first, then the ground
TAKE       peckish (<= forage_below), room in the bag, something takeable in reach
SEEK_FOOD  peckish, room (or no bag), food perceived — commit to the nearest
SLEEP      tired (energy <= rest_at) and not starving
WANDER     after a random pause, to a random point within its radius
```

**Why one brain with state**, not a rung per system: the old `EcsForageSystem` ran before the
wanderer and priority was run order. It read well but was stateless — nothing persisted
("I am going to *that* berry"), nothing could interrupt (a rung could only fill an empty
destination slot), and a threshold near its trigger flickered. State fixes all three.

**Rung order is the design.** Food outranks rest, so a creature that keeps finding food can
run itself to collapse — the price of that order, not a bug. **Carrying is provisioning**, so
`EAT > TAKE`: a creature hungry enough to eat, standing over a berry, eats it where it lies
and never pockets it first. That is pinned by a test that watches the bag stay empty,
because the end state cannot tell the two paths apart. **Starving outranks tired both
ways** — it wakes a sleeper and stops the sleep rung choosing, or a creature woken by its
stomach would be put straight back down to starve.

**Decisions go out as flags.** `state` is the brain's memory; the intent flags are its
instructions, raised and cleared in `_set_state()` — the one place `state` is written — so
they cannot disagree (a test watches 400 live ticks). Unchanged state is a no-op, so an idle
creature touches the store not at all. An intent **names its target**, so the brain chooses
*which* berry and the executor only checks it is still there.

| state | instruction | executor |
|---|---|---|
| EAT | `EcsEatIntentFlag` | `EcsConsumeSystem` |
| TAKE | `EcsTakeIntentFlag` | `EcsPickupSystem` |
| SLEEP | `EcsAsleepFlag` | `EcsHungerSystem`, `EcsEnergySystem` (as a rate) |
| SEEK_FOOD, WANDER | a destination | `EcsMovementSystem` |

**No executor reads the brain.** A creature with no brain at all eats, takes and sleeps when a
flag is raised on it — tested. **Do not let the brain grow hands:** executors stayed separate
systems because merging them would have the brain mutating *other entities'* components, the
same argument would swallow every verb after it, and step 7's planner emits action ids that
want one executor each.

The brain reads components that are not its own (sensor, inventory, hunger, energy) through
`get_component`, so a creature lacking one simply never takes that rung — no flags saying
"cannot carry". It is the one place that knows several concerns at once; it still *writes*
only its own state, its intent flags and a destination.

---

## 8. Needs: fullness, energy and health

All three bars are **reserves**: full is good, and a short bar is bad news on every one.

**Hunger is the motive, health is the consequence.** The number is
`EcsHungerComponent.fullness`, not hunger — it drains from `max_fullness` to zero. The class
keeps the name because hunger is what it is *about*. **What being empty or full does to you
is hunger's rule**, so both halves live in `EcsHungerSystem`: at zero it spends health at
`starve_damage`; at or above `heal_above` it gives health back at `heal_rate`; the band
between does neither. Mending is the reward for having eaten, not the absence of starving.
`EcsHealthSystem` owns only the threshold: health at zero adds `EcsDyingFlag`.

**Energy is a reserve, sleep is a decision, and collapse is not.** `EcsEnergySystem` drains
`drain_idle` awake, plus `drain_moving` while velocity is non-zero, and restores `restore`
while asleep or collapsed. `rest_at < wake_at` is the hysteresis. At zero it adds
`EcsCollapsedFlag` and takes `collapse_damage` once; **the flag's presence is the lock**,
which is how energy tells the brain "no say" without writing the brain's component. It
lifts at `collapse_release`, below `wake_at`, so what comes round is an ordinary sleeper that
starving can interrupt.

**A sleeper still gets hungry**, at `asleep_drain_scale` (0.4) of the waking rate — slower is
the point, *still* is what keeps waking-on-starving reachable. Hunger and energy both decide
"asleep" from `EcsAsleepFlag` or `EcsCollapsedFlag`, and must agree; neither reads the other or
the brain.

**Starting energy is rolled**, in `start_min`–`start_max` of `max_energy`, by
`EcsEnergySystem` the first time it sees an animal — not by the manager (it never switches on
type) and not per placement (a runtime spawn would miss it). Without the spread every animal
sleeps at once. A runtime `rolled` bool marks it done — a record keeps it, so a restored
animal does not re-roll — and **a placement that authors its own `value` must set `rolled`
true beside it**, as `world1.tres` does, or the roll overwrites the authored number.

**The two animals differ by one component and authored values** — no `is_grazer` flag, no
branch in any system:

| | rabbit — grazer | monkey — carrier |
|---|---|---|
| `EcsInventoryComponent` | **none** | capacity 1 |
| hunger `drain` /s | 1.2 — it cannot stockpile | 2.6 |
| `forage_below` / `eat_below` | 65 / **70** — eats what it walks to, on arrival | 70 / 40 — gathers, carries, eats later |
| `heal_above` / `heal_rate` | 50 / 5 per s | 50 / 5 per s |
| energy `restore` /s, start | 10, rolled 50–100% | 10, rolled 50–100% |
| speed | 165 (placements 152–176) | 130 (placements 121–136) |
| wander radius / pause | 320 / 0.5–3.0 s | 420 / 0.2–1.2 s |

`eat_below` **above** `forage_below` is what makes a grazer: with nowhere to stockpile, a
rabbit that reached a berry and then had to wait to get hungrier would wander off. With
`restore` at 10/s a nap from `rest_at` 30 to `wake_at` 100 takes 7 s and a collapse lifts in
5 s, so waking-on-starving rarely gets a chance to fire.

---

## 9. Items: eating, taking, carrying, dropping

Food is `EcsConsumableComponent` (`nutrition` 40), not `EcsPickableComponent` — a hungry
animal must not chase a tool. What a bag will hold (`pickable`) is a wider question than what
a mouth will (`consumable`).

**Eating does not require an inventory.** "Hungry, and food within reach" is the condition,
and a pocket is one place reach can mean: a carrier eats out of its bag, a grazer eats what
its action area touches. One berry per decision.

**A carried item is a record, not an entity** — a deliberate reversal of the plan's step 3,
because in most games an item in a bag, chest or shop is not a live entity. Picking up
**kills** the item and puts an `EcsItemRecord` in the bag:

- **every component, `Position` included, no flags** — nobody knows yet what a future item
  will need, and the catalog holds only a type's defaults, not an instance's values. Position
  goes stale in the bag and is overwritten when the item comes back; flags were only true of
  the entity *then*;
- copied **by reflection** over `PROPERTY_USAGE_SCRIPT_VARIABLE`. Measured: `Resource.duplicate()`
  copies only `@export` fields — an energy component at 12.5 came back at its default 100, a
  bag of two ids came back empty. Arrays and dictionaries are deep-copied; a field holding an
  object would be shared (nothing does that yet);
- **`uid`**, on `EcsNameComponent`, is who the thing is — 128 random bits as hex, set by the
  manager at first spawn. The int id is the store's key and changes when an item goes back
  into the world; the uid does not.

Eating from the bag takes the record out and reads its `nutrition` — no kill, it died when
picked up. Eating off the ground is a kill (`EcsDyingFlag`). One record, one slot.

**When a carrier dies, `EcsDropSystem` puts back what it carried**, where it fell, as itself:
one spawn note per record, restored by the manager at the same instant the carrier is
destroyed — same uid, new id, instance values intact, stacked on one spot (berries are not
solid). It runs late, after everything that can kill a carrier; a system that flags a carrier
Dying after it would lose the bag. This also fixed a leak: a dead carrier's berries used to
live forever with no position.

**Deferred on purpose:** what a carried item *does* while carried (durability, rot — a record
does nothing), bag capacity and stacking, voluntary dropping, and corpses — death by health
should later leave a lootable corpse rather than drop.

---

## 10. Observability

**The overlay** (`EcsDebugOverlay`, fed by `EcsDebugSystem`, **F1**) annotates each entity in
world space: name, a velocity arrow, a dashed line to its destination, fullness / energy /
health as bars, a badge on the sprite's top-left shoulder when it carries something, and the
sleep icon (`Global/Asset/Icon/sleep.png`) off that shoulder while it sleeps — parchment for a
chosen sleep, red for a collapse. Shapes rather than numbers, because these are read across a
crowd; the numbers live in the inspector. The system sends **ratios and counts, never text or
pixels**, and `-1` means "has no such reading", so a berry draws no bars. The overlay is drawn
with `_draw()`, not Controls, so it sits outside the theme. Text and bars hold a fixed size on
screen; the badge and sleep icon are sized off each sprite in world units, so they zoom with
the animal — and they sit on the sprite actually drawn, since blueprints scale their own art.

**Selection** is strictly ECS: `main.gd` only *records* a click on `EcsSelectionSingleton`,
`EcsSelectionSystem` resolves it next tick by a distance query over positions (no physics
pick), and selection is the presence of `EcsSelectedFlag`.

**The inspector knows no component.** `EcsInspectSystem` pushes a snapshot of the selected
entity onto the `EventBus`; `ui/ui.tscn` renders it and never touches the world. How each
component reads is its own `describe()`:

```gdscript
func describe() -> Dictionary:
    return {"tab": &"entity",      # or &"own" / &"hidden"
        "lines": {"health": "%d/%d" % [roundi(value), roundi(max_health)]},
        # "title": {"name": ..., "type": ...}   optional: names the panel
    }
```

To change how a component shows, edit its `describe()` — **never the inspect system**; a test
fails if that file names a component type. A component without `describe()` gets its own tab
of every field, by reflection. Today: name, blueprint, position and the three bars read on
the Entity tab; movement and inventory have tabs; body, sprite, brain, sensor and action are
hidden; all flags share one "Flags" tab, the one thing the inspector lays out itself (by base
class). Linked ids (`*_id` fields) show the linked entity's title.

Two input fixes worth knowing: the tab strip takes no keyboard focus (arrow keys used to
switch tabs), and the inspector panel accepts wheel events so scrolling it never zooms the
camera — a `mouse_filter` of STOP does **not** consume the wheel on its own (measured). The
shared camera reads the wheel in `_unhandled_input` and zooms once per notch.

---

## 11. The scheduler: a stage may declare how often it runs

`EcsScheduler.add(system, every, phase)` takes a rate in ticks; `main.gd` runs `sensor` and
`low_brain` at `SLOW` (every 3 ticks, 20 Hz) while everything the eye watches stays at 60.
This is safe because every system takes `delta` and means it: **the scheduler banks delta
per system**, so a stage run a third as often is handed three ticks' worth, and hunger still
drains at its authored points per second. What changes is latency, never rate. **`phase` is
not optional** — two slow stages on the same tick make one heavy frame in three instead of
three even ones; a system runs when `tick % every == phase`, and giving a consumer the phase
after its producer keeps its data one tick old, as at full rate.

---

## 12. Tests

`tests/lifecycle_test.tscn` — **161 checks**, exit code 0 only if all pass. Run it after
touching the manager, collision, pickup, spawner, sensor, node sync, the brain or any
executor. It covers: declared nodes built and undeclared ones not; kill takes data and nodes;
spawn notes fulfilled a tick later; soft collision, immovable and non-solid bodies; seeing is
not reaching; the trip budget; the brain's commitments, preemption and rung order; hunger,
starving, mending and the dead band; energy, sleep, collapse and waking on starving; the
sleeper's slower hunger; the start roll; the eat-and-pocket race; executors with no brain;
state/flag agreement over 400 ticks; records, uid and the reflection copy; the drop on death;
the inspector's layout and its not naming any component; and per-stage tick rates banking
delta.

`tests/stress_test.tscn` — the population ramp and the per-stage bookkeeping split (§14). Knobs after a bare `--`:
`--spacing=180` (grid px), `--n=4000` (one population), `--skip=hunger,health` (leave stages
out, by label).

---

## 13. Where the plan stands, and what is next

`ECS_REFACTOR_PLAN.md` is the roadmap. **Steps 0–6 are done; step 7 is not started.**

**Next, decided 2026-09-27: cut the fetch time first** — about half the tick is component
lookups (§14). The plan, numbers and code sites are in **`FETCH_HANDOFF.md`**: bars at 10 Hz,
the brain fetching each component once per creature, trimming duplicate `has` checks, then
§15's storage question (cached queries returning component references) raised as the
author's decision. Fold the results back here and delete that file when it is done.

- **0–1** core and data-driven factory — done.
- **2, the weapon pain case** — built, proved clean (armour and crit added without touching
  the attack code), then **cut** so the flow reads end to end. It is in git at `928b9d1`.
- **3, inventory and pickup** — done, then reversed on purpose: items are records, not
  entities (§9).
- **4, bars as systems** — done: fullness, health, energy.
- **5, sensor and intents** — done, differently: physics areas rather than a distance query.
  The node-free query is the fallback if areas ever stop paying.
- **6, the brain writes intents** — done on the stripped core, without combat (§7).
  Measured before/after in one sitting at 2,400 entities: the executors dropped ~14 ms
  because they now query intent flags instead of every brain; the brain itself did not get
  dearer. The cost of raising a flag under load is unmeasured — the stress population never
  raises one.
- **7, GOAP** — a pure planner over a symbolic snapshot, run off-frame under a replan
  budget, emitting action ids that the existing executors run. Not started. It and any
  return of combat assume the cut combat layer.

**Open and deferred, by decision:** `MoveIntent`; an attack intent and a state worth
preempting *for* (both wait on combat); what a carried item does while carried; corpses and
looting; bag capacity and stacking. **Do not re-add breadth without being asked** — the small
size is the point.

Smaller, not done: `EcsEntityManager.node_for()` allocates a throwaway dictionary on every
call (`_nodes.get(id, {})`); the brain's food rung re-asks the store about every perceived id
right after the sensor walked the same list; speed variance is per placement, so a runtime
spawn gets the blueprint default; the Respawn button keeps keyboard focus after a click; the
stats panel lets the wheel through to the camera.

---

## 14. Performance

`tests/stress_test.tscn` builds the pipeline `main.gd` builds and calls each stage directly
at full rate (so the 20 Hz saving does not show — it is a worst case), on a jittered grid
that grows with n so the neighbourhood stays the same size. It prints the ramp, each stage's
cost in ms and µs per entity, a census of the work done, and a probe splitting one stage into
query / fetch / arithmetic. Simulation only; nothing is drawn.

**Latest ramp** (after step 6 and the inspector work, 90 px grid):

| n | tick | FPS | | n | tick | FPS |
|---|---|---|---|---|---|---|
| 400 | 21.5 ms | 46.5 | | 2,400 | 144.0 ms | 6.9 |
| 800 | 42.1 ms | 23.8 | | 3,200 | **206.6 ms** | 4.8 |
| 1,600 | 92.0 ms | 10.9 | | 4,000 | 262.9 ms | 3.8 |

**3,200 entities is the last step under the 250 ms budget.** At 4,000: sensor 36%, low_brain
17%, collision 13%, node_sync 9%, energy / hunger / movement ~7% each; pickup and consume
~0.01 ms. Each sensor returns ~53 ids per tick; cost per entity levels off at ~65 µs.

**Measurement rules, learned the hard way:**

- **Never compare numbers from different sittings.** Throughput drifts by up to ~50% across a
  day on this machine — a ramp earlier the same day read 225 ms at 2,400 against 144 ms here,
  with no relevant code changed and every stage moving by the same proportion. Use `--skip`
  and run both arms back to back.
- **Single-shot `--n` numbers are not comparable to ramp numbers**; the process state differs.
- **Repeat before believing.** Run-to-run noise is ±12%; anything under ~15% needs two runs
  at each end. A "70% regression" and a "step 4 cost a third of the ceiling" were both
  retracted on exactly this: measured in one sitting, step 4 cost ~12% of the tick and none
  of the ceiling.

**What the cost is.** The system is **overhead-bound, not interaction-bound.** At 840 px
spacing — no sensor overlaps anything, zero ids, zero pairs — the pipeline still costs
**~41 µs per entity**, and the ceiling moves only to ~6,000. Sensor costs ~39 ms to return
nothing, collision ~40 ms to resolve nothing. Density is a third of the ceiling: at 180 px
spacing (13 ids per sensor instead of 53) the ceiling is 4,800, and the per-entity cost is
flat with population; at 90 px it climbs. In `movement` — two components in, one out — **~70%
of the stage is finding the components**, not using them (`get_component` is a double hashed
lookup plus boxing, ~1 µs a call).

**Bookkeeping vs logic, per stage.** The stress test now ends with a split of every stage's
time at the final population: `query` (timed), `loop` and `fetch` (store calls counted in a
separate pass on `tests/ecs_counting_world.gd`, priced by unit costs measured in the same
sitting) and `logic`, the remainder. At 4,000 entities:

| stage | total ms | bookkeeping | logic | note |
|---|---|---|---|---|
| sensor | 93.3 | ~22% | **72.6** | the real work is the overlap reads |
| low_brain | 44.3 | ~100% | ~0 | 26,000 `get_component` a tick — ~6.5 per creature, the same components re-fetched in each rung |
| collision | 34.0 | ~54% | 15.8 | |
| node_sync | 23.8 | ~50% | 11.9 | the node writes |
| energy, hunger | 18 each | ~100% | ~0 | 8,000 gets + 8,000 `has` each |
| movement | 16.5 | ~97% | ~0.5 | |
| health | 9.1 | ~100% | ~0 | |
| **whole tick** | **257.2** | **~61–63%** | **~96** | three quarters of the logic is the sensor |

The priced columns are estimates and run a few percent high — the simple stages come out
at 104–110%, i.e. "all bookkeeping, within error". The direct movement probe agrees (71%).
**Outside sensor, collision and node_sync, the pipeline is almost pure lookup.** That is the
per-entity floor in another form, and the strongest case yet for the §15 storage question
and for fetching each component once per creature in the brain.

**The levers, ranked by payoff over cost:**

1. **The per-entity floor** — query + component access + area bookkeeping. §15's
   data-structure argument, with a number behind it. **The author's call; not to be
   implemented unasked.**
2. **Per-stage tick rates — taken** (§11): sensor and brain at 20 Hz, roughly a third of the
   largest two stages off the average tick.
3. **Choose the density you design for** — free. Sight radius is the same lever: ids scale
   with πr².
4. **Cache the brain's perception scan** — cheap, shrinks with density.
5. **Stagger the sensor** — worth under 10%: deleting perception outright saves only ~10% of
   the tick, because most of a sensing entity's cost is fixed overhead.
6. **`node_for`'s throwaway dictionary** — small, free.

---

## 15. Open arguments

**The node-structure argument is settled:** one container per entity, children per concern
(§3). Rejected: pools per concern (two pools cross-referenced by id to answer "what does
entity 12 own"), and no nodes at all via server RIDs (cheapest, but the author wants Godot
nodes for collision, sprites, animation and sound). Still unresolved: whether the collision
`Area2D`s should exist, as the one place "nothing reads back off a node" bends.

**The data-structure argument is open, and the author wants to argue it out. Do not
implement any option; raise it for a decision.** What exists: `{ Script : { entity_id :
EcsComponent } }`, components as `Resource` subclasses, queries intersecting tables driven
from the rarest.

- **Dictionary-of-dictionaries or archetype / packed storage?** The API would not change.
  Measured: a stage like `movement` has a ~5× ceiling from packed access; across the whole
  pipeline ~1.6–2× is the honest expectation, since `sensor` is physics queries, not access.
  The win does *not* require dropping `Resource` — the 0.57 µs "pre-gathered" figure was over
  arrays of Resource references; the cost is hashing and boxing, not indirection. The cost
  archetypes carry is moving an entity between tables on add/remove; the component/flag split
  helps there, since flags are what churn and components no longer do.
- **May a node or RID handle live inside a component?** It would make `EcsCollisionSystem`
  pure behaviour, at the cost of the data layer knowing the scene tree exists.
- **Should components be `Resource` at all**, given `.tres` authoring uses only the exported
  half and most components carry runtime fields beside it?

---

## 16. What was removed, and how to get it back

All of it is in git at **`928b9d1`**:

```bash
git show 928b9d1 -- "9. EcsSystem"                                   # see it
git checkout 928b9d1 -- "9. EcsSystem/systems/ecs_attack_system.gd"  # take one file back
```

**The combat pipeline** — 10 components (`aggression`, `armor`, `attack_intent`, `broken`,
`crit_chance`, `damage`, `dead`, `durability`, `equipped`, `health`) and 8 systems
(`aggression`, `attack`, `crit`, `damage`, `death`, `durability`, `equip`, `weapon_carry`),
plus `ecs_event.gd` and `ecs_damage_event.gd`. It was step 2 and it landed clean: armour added
to a live entity without the attack code changing, crits by one new system and one scheduler
line, a broken weapon falling back to fists with no `if weapon.broken` anywhere. **The
evidence for the rewrite is in that commit, not in the working tree.** Restoring it means
reconciling with what came after: health is now hunger's consequence, death is
`EcsDyingFlag`, and a wielded weapon would be a record in a bag unless the record decision is
revisited for items that act while carried.

**Also cut then:** `EcsCommandSystem` and the pipeline panel (they served the combat demo),
the crocodile and dagger blueprints, `EcsWorld.count()` and the frame-event API,
`EcsSystem.enabled`, `EcsScheduler.find()`. The observability layer went too and has since
come back, minus those.
