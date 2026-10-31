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
"$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn" # 288 checks, exit 0 = all pass
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

Every physics tick `EcsScheduler` runs twenty-six stages. `[20 Hz]` and `[10 Hz]` mark the
ones that run every third or sixth tick (§11); the rest run every tick.

| stage | does | writes |
|---|---|---|
| `lifecycle` | births and deaths — the only stage that creates or frees | the world, the nodes |
| `spawner` | a spawner asks for what it spawns (no blueprint has one now; tests do) | a note on `EcsLifecycleSingleton` |
| `hunger` `[10 Hz]` | fullness drains; starving costs health, fed mends it | `EcsHunger`, `EcsHealth` |
| `energy` `[10 Hz]` | drains awake, restores asleep; collapse at zero | `EcsEnergy`, `EcsCollapsedFlag`, `EcsHealth` |
| `health` `[20 Hz]` | death at zero | `EcsDyingFlag` |
| `danger` `[20 Hz]` | fills on a threat in sight, jumps on a hit, decays | `EcsDanger`, clears `EcsHurtFlag` |
| `sensor` `[20 Hz]` | what each entity sees and can touch | `EcsSensor.perceived`, `EcsAction.reached` |
| `planning` `[20 Hz]` | scores goals, replans on events, under a budget (§18) | `EcsPlanner` |
| `low_brain` `[20 Hz]` | runs the plan's first step, or its own ladder | its own state, a destination, intent flags |
| `skill` | carries out a cast intent; runs skill timers (§19) | `EcsSkills`, the effect flags |
| `consume` | carries out an eat intent | `EcsHunger`, the bag, `EcsDyingFlag` |
| `harvest` | regrows stock; carries out a harvest intent | `EcsHarvestable`, a note on `EcsLifecycleSingleton` |
| `attack` | carries out an attack intent, on cooldown | `EcsDamage.cooldown`, hits on `EcsCombatSingleton` |
| `crit` | rolls each hit against the attacker's crit chance | the hits |
| `damage` | applies the hits less armour, clears them | `EcsHealth`, `EcsHurtFlag` |
| `movement` | walks toward the destination, prices the trip; faster while dashing | `EcsPosition`, `EcsMovement` |
| `collision` | pushes overlapping solid bodies apart | `EcsPosition` |
| `pickup` | carries out a take intent: an item off the ground, or a record looted from a bag | the bags, `EcsDyingFlag` |
| `rot` | ages corpses; flags them dying when their time is up | `EcsRot`, `EcsDyingFlag` |
| `corpse` | a death by health asks for a corpse holding the bag | a note on `EcsLifecycleSingleton` |
| `drop` | a dying entity's bag goes back into the world | notes on `EcsLifecycleSingleton` |
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

The world today is 11 animals — 5 rabbits, 5 monkeys, 1 crocodile — 13 bushes, 1.3 per
plant-eater, and 4 ponds (`defs/world1.tres`), spread across a 6400×3360 arena, doubled each way
on 2026-10-31 to make room for more kinds. A berry exists only once
something harvests one (§9).

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

**23 components** — `name`, `position` (both added by the manager from the placement, not the
blueprint), `sprite`, `body`, `movement`, `low_brain`, `sensor`, `action`, `hunger`, `health`,
`energy`, `inventory`, `consumable`, `pickable`, `spawner`, `harvestable`, for combat and
corpses `damage`, `armor`, `crit_chance`, `lootable`, `rot`, and for planning `planner` and
`danger` (§18).

**9 flags** — `EcsSelectedFlag` (selection owns it), `EcsCollapsedFlag` (energy), five
brain intents, `EcsEatIntentFlag{target_id | record_uid}`, `EcsTakeIntentFlag{target_id,
record_uid}`, `EcsAttackIntentFlag{target_id}`, `EcsHarvestIntentFlag{target_id, progress}`
and `EcsAsleepFlag`, `EcsHurtFlag{by}` (damage raises it, danger reads and clears it), plus
`EcsDyingFlag` (§3). A flag may carry data — an intent names its target
— but nothing about a flag is decided before the game starts.

**3 singletons** — `EcsLifecycleSingleton` (spawn notes), `EcsSelectionSingleton` (the
pending click) and `EcsCombatSingleton` (this tick's hits, §17).

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

**Two distance checks sit on top of perception, both deliberate** (§19): a scanning watcher
sees a hider within its scan radius, and the planner's `prey_close` is prey within dash reach.
Both run only over `perceived` — the area still decides *whether* something is seen; the
distance only decides how near it is.

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
pause clock. It is named for its **rank** — the bottom of the plan's decision ladder, with
the planner now above it (§18) — not for the wandering it happens to do.

**Three levels.** L1 is this brain: its rungs, its commitments and the collapse reflex. L2
is utility goal choice and L3 the route to the goal, both in `EcsPlanningSystem` (§18). A
creature with an `EcsPlannerComponent` that has planned runs **only the rung for its plan's
first step**, with the rung's need gate skipped (the goal already decided the need). One
without a planner, or whose planner has never planned, keeps the ladder below. That second
case is why the ladder tests still pin the ladder: their pipelines have no planning stage.

**Each tick, per creature:**

1. **Collapsed** → it has no say; SLEEP, any trip called off. This is the one *forced*
   override of a live commitment.
2. **Asleep by choice** → stays down until rested (`wake_at`) or starving, or until its plan
   is to flee.
3. **Planned, and the state no longer serves the plan's step** → dropped (trip called off).
4. **Fleeing** → re-aims away from the danger's last threat every brain tick.
5. **Seeking food** → a commitment is not reconsidered: kept until the target is gone
   (eaten, taken, Dying, or a bush out of stock), within reach (fulfilled — the rungs below
   act this same tick), or the trip ends.
6. **Wandering** → interruptible; a creature notices food mid-leg.
7. **Choose.** Planned: the step's rung, else wander. Otherwise highest rung first:

```
EAT        hungry enough (fullness <= eat_below), food at hand — bag first, then the ground
TAKE       peckish (<= forage_below), room in the bag, something takeable in reach
SEEK_FOOD  peckish, room (or no bag), food perceived — commit to the nearest
HARVEST    peckish, room, a bush whose yield it eats: in reach → harvest, in sight → SEEK_FOOD to it
HUNT       peckish, can attack, prey perceived (§ below)
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
| ATTACK | `EcsAttackIntentFlag` | `EcsAttackSystem` |
| HARVEST | `EcsHarvestIntentFlag` | `EcsHarvestSystem` |
| SEEK_FOOD, HUNT, FLEE, WANDER | a destination | `EcsMovementSystem` |

**Hunting** (2026-10-29). A hungry creature with an `EcsDamageComponent` chases the nearest
perceived prey as a commitment like SEEK_FOOD. **Who is prey is diet and power**, through
`ai/ecs_hunting.gd`: A can hunt B when A eats meat and can attack, and B has health, is not
dying, and has less `EcsHealthComponent.power` (rabbit 10, monkey 15, crocodile 60). There is
no prey tag and no blueprint-type check, so a stronger crocodile hunts a weaker one.
`EcsHunting.power_of()` is the one place power is read, so it can become derived later. Each
brain tick it follows the prey's position *without* resetting the trip budget, so a chase it
cannot win times out. In reach it switches to ATTACK (raising the flag); out of reach again,
back to HUNT. The commitment ends when the prey is dead or gone or the budget runs out. **On
the ladder only, food it eats coming into sight ends it too** — without that a hunter that
had just killed picked new prey in the one tick before the corpse appeared, and killed twice
before eating. A planned hunter does not need the rule: the corpse coming into sight is a
fact change, and the cheapest plan from there is to eat (§18).

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

**Bushes are harvested, not spawners** (2026-10-29). A berry exists only once something
harvests one. `EcsHarvestableComponent` on the bush holds `stock` (starts at `stock_max`, 3),
regrows one unit per `regrow` (10 s) and names what it `yields` and that yield's `diet`, so the
brain needs no catalog lookup. The brain raises `EcsHarvestIntentFlag` on a bush in reach;
`EcsHarvestSystem` works it, and each `harvest_time` (1 s) takes one unit and asks for the
yield **on the ground beside the harvester, inside its reach**. The existing rungs finish the
job — a grazer eats it, a carrier pockets it — so there is no new eating path. Plant-eaters
now have a chain of their own, `seek bush → harvest → eat | take`, beside the meat one.
`EcsSpawnerComponent` and its system stay as generic code that no blueprint uses. The world
has 13 bushes for 10 plant-eaters (1.3 each); over 180 s headless, before fleeing existed,
no plant-eater's fullness went below 28.

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

**Death by health leaves a corpse** (2026-10-29). `EcsCorpseSystem` runs before drop: for a
dying entity at zero health it writes a spawn note for the `corpse` blueprint where it fell,
with overrides for its look (the dead sprite, darkened), its body radius and its bag's records.
The creature dies by the ordinary kill; the corpse is a new entity — nothing changes kind. A
corpse is a non-solid body, `EcsConsumableComponent` meat, `EcsLootableComponent`, an
inventory, and `EcsRotComponent` (40 s). **Looting is TAKE**: the brain names a record in a
lootable bag in reach (`EcsTakeIntentFlag.record_uid`) and `EcsPickupSystem` moves it. A
corpse eaten or rotted is an ordinary dying entity with a bag, so `EcsDropSystem` spills what
is left.

**Diet.** `EcsConsumableComponent.diet` (`&"plant"`, `&"meat"`) and `EcsHungerComponent.eats`.
The brain's food index keeps each food's diet and every food rung filters on it, so rabbits
and monkeys walk past corpses and the crocodile past berries. The executor does not check
diet — choosing is the brain's.

**Deferred on purpose:** what a carried item *does* while carried (durability — a record does
nothing), bag capacity and stacking, voluntary dropping.

---

## 10. Observability

**The overlay** (`EcsDebugOverlay`, fed by `EcsDebugSystem`, **F1**) annotates each entity in
world space: name, a velocity arrow, a dashed line to its destination, fullness / energy /
health as bars (and danger while there is any; the planner's goal under the name), a badge
on the sprite's top-left shoulder when it carries something, and the
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

`EcsScheduler.add(system, every, phase)` takes a rate in ticks; `main.gd` runs `sensor`
(phase 0), `danger` and `low_brain` (1), `planning` and `health` (2) at `SLOW` (every 3
ticks, 20 Hz), `hunger` (2) and `energy` (5) at `BARS` (every 6, 10 Hz), while everything the
eye watches stays at 60. Planning sits on its own phase rather than sensor's because the two
together made the heaviest tick (§14).
This is safe because every system takes `delta` and means it: **the scheduler banks delta
per system**, so a stage run a third as often is handed three ticks' worth, and hunger still
drains at its authored points per second. What changes is latency, never rate. **`phase` is
not optional** — two slow stages on the same tick make one heavy frame in three instead of
three even ones; a system runs when `tick % every == phase`, and giving a consumer the phase
after its producer keeps its data one tick old, as at full rate.

---

## 12. Tests

`tests/lifecycle_test.tscn` — **288 checks**, exit code 0 only if all pass. Run it after
touching the manager, collision, pickup, spawner, sensor, node sync, the brain or any
executor. It covers: declared nodes built and undeclared ones not; kill takes data and nodes;
spawn notes fulfilled a tick later; soft collision, immovable and non-solid bodies; seeing is
not reaching; the trip budget; the brain's commitments, preemption and rung order; hunger,
starving, mending and the dead band; energy, sleep, collapse and waking on starving; the
sleeper's slower hunger; the start roll; the eat-and-pocket race; executors with no brain;
state/flag agreement over 400 ticks; records, uid and the reflection copy; the drop on death;
the inspector's layout and its not naming any component; per-stage tick rates banking
delta; a view rebuilding on every structural change it can see, and only then; hits
less armour on cooldown, crits and death by hits; a corpse holding the bag, looted, ignored
by a plant-eater and eaten by a meat-eater; rot spilling a corpse's bag; and a hungry
crocodile hunting prey but not its own kind, attacking in reach, killing and eating; a bush
yielding only when harvested, one unit per harvest into reach, regrowing, and rabbits and
monkeys harvesting then eating or pocketing; the planner's chains over the authored actions
(bag, ground, sight, bush, the meat chain through a kill, rest not while starving, flee, no
plan); power and diet deciding who hunts whom; utility picking the ladder's rung over a grid
of fullness and energy for each kind; a planned crocodile killing once and eating the corpse
with no hand rule on its path; planned harvesting with flags matching state; replans only on
a fact or ranking change, at most `MAX_REPLANS` a run; hunger against danger both ways; and a
rabbit fleeing a crocodile it sees, calming once it is gone, waking to flee, and fleeing a bite
from something unseen; skills starting on intent, ending on time, refused while cooling, hide
holding only in water and while asked, dash speed, hiding restoring energy; a hidden
crocodile noticed never, late or plainly by awareness and scan, and never past `perceived`;
the ambush chains by cost; an ambush giving up after its patience and coming back; and a
planned crocodile ambushing from water, letting a far monkey pass, pouncing once, killing and
eating.

`tests/stress_test.tscn` — the population ramp and the per-stage bookkeeping split (§14). Knobs after a bare `--`:
`--spacing=180` (grid px), `--n=4000` (one population), `--skip=hunger,health` (leave stages
out, by label), `--fullness=50` (start every animal hungry — the default world is fed, so the
brain's food search never runs), `--every=sensor:3:0,...` (run stages at the game's rates),
`--hunters=40` (make that many of the animals crocodiles, spread over the grid). The ramp
prints replans per second beside each tick. The grid has no bushes, so the harvest chain is
not loaded there.

`tests/fetch_bench.tscn` — what component fetching costs on its own: skeleton systems over a
random world, timed as query + has + get, and through a kept and a rebuilt view.

---

## 13. Where the plan stands, and what is next

`ECS_REFACTOR_PLAN.md` is the roadmap. **Steps 0–7 are done.** Step 7, the planner, is §18.

**The fetch-time job is done** (2026-09-27 to 2026-10-29): bars at 10 Hz, cached views, the
brain's food index. The ceiling went from 4,800–6,400 to over 9,600 entities (§14).

**Combat is back** (2026-10-29), rebuilt rather than restored, in `01fbc53`, `45113d0` and
`1533581` — see §17.

- **0–1** core and data-driven factory — done.
- **2, the weapon pain case** — built, proved clean (armour and crit added without touching
  the attack code), then **cut** so the flow reads end to end. It is in git at `928b9d1`.
- **3, inventory and pickup** — done, then reversed on purpose: items are records, not
  entities (§9).
- **4, bars as systems** — done: fullness, health, energy.
- **5, sensor and intents** — done, differently: physics areas rather than a distance query.
  The node-free query is the fallback if areas ever stop paying.
- **6, the brain writes intents** — done on the stripped core, without combat (§7); combat
  has since been rebuilt on it (§17).
  Measured before/after in one sitting at 2,400 entities: the executors dropped ~14 ms
  because they now query intent flags instead of every brain; the brain itself did not get
  dearer. The cost of raising a flag under load is unmeasured — the stress population never
  raises one.
- **Features roadmap, step 1: skills, water and the ambush** — done (2026-10-31, §19). The
  roadmap (`FEATURES_ROADMAP.md`, kept outside the repo) goes on: 2 thirst, 3 uniform skills
  with costs from stats, pounce and stun, 4 memory, 5 traffic-based ambush.
- **7, GOAP** — done (2026-10-29, `cf53229` to `ae1ef52`): harvesting first, then a pure A*
  planner over a symbolic snapshot, utility goal choice, a budgeted replan queue that replans
  on events, and fleeing. Single-threaded; the planner is pure, so moving it to
  `WorkerThreadPool` is a dispatch change, to make only when the profiler asks (§14, §18).

**Open and deferred, by decision:** `MoveIntent`; weapons, durability and broken (they wait on
what a carried record may *do*); prey fighting back; bag capacity and stacking; **power as a
derived, tweakable value** (the author's stated next step — today it is authored). **Do not re-add breadth without being asked** — the small
size is the point.

Smaller, not done: `EcsEntityManager.node_for()` allocates a throwaway dictionary on every
call (`_nodes.get(id, {})`); speed variance is per placement, so a runtime
spawn gets the blueprint default; the Respawn button keeps keyboard focus after a click; the
stats panel lets the wheel through to the camera.

---

## 14. Performance

`tests/stress_test.tscn` builds the pipeline `main.gd` builds and times each stage, on a
jittered grid that grows with n so the neighbourhood stays the same size. It prints the ramp,
each stage's cost, a census of the work done, and a split of every stage into query / loop /
fetch / logic. Simulation only; nothing is drawn. Flags: `--every=label:every:phase` (the
game's rates), `--fullness=50` (every animal hungry), `--hunters=N`, `--n=`, `--skip=`,
`--spacing=`. Each ramp row also prints replans per second.
`tests/fetch_bench.tscn` prices the store calls on their own.

**Latest ramp: the planner** (2026-10-29, `ae1ef52` against `86d6028` in one sitting, from a
worktree). Game rates, with `danger:3:1,planning:3:2` added on the new build and 40
crocodiles mixed into the grid (`--hunters=40`). Average tick in ms, heaviest in brackets:

| entities | fed, `86d6028` | fed, now | hungry, `86d6028` | hungry, now |
|---|---|---|---|---|
| 800 | 13.6 (31) | 26.2 (34) | 14.6 (22) | 27.6 (37) |
| 1,600 | 27.7 (46) | 44.5 (52) | 31.4 (45) | 49.6 (58) |
| 3,200 | 60.2 (101) | 108.5 (154) | 71.3 (103) | 109.8 (153) |
| 4,000 | 76.9 (139) | 121.9 (158) | 89.2 (152) | 136.1 (170) |
| 4,800 | 94.2 (161) | 147.7 (192) | 108.0 (149) | 165.4 (205) |
| 6,400 | 126.6 (209) | 192.5 (255) | 147.7 (238) | 211.8 (258) |
| 8,000 | 159.8 (268) | 244.1 (276) | 191.8 (296) | 270.9 (342) ✗ |
| 9,600 | 202.1 (345) | 298.5 (351) ✗ | 234.1 (336) | — |

**The ceiling fell from over 9,600 to 8,000 fed and 6,400 hungry.** Per entity the tick went
from about 0.020 to 0.031 ms fed, and 0.024 to 0.034 hungry. The new cost is the snapshot,
not the search: `planning` is about 6.5 µs and `danger` about 2.9 µs per entity at every size.
A run with `MAX_REPLANS` at 0 cost the same as one at 64, so A* itself is noise. Planning
gathers facts for every planner every run, which is the same perception scan the brain makes.
At 9,600 fed: sensor 26%, planning 21%, low_brain 13%, danger 9%.

**Replans are at the cap from 2,400 up**: 1,280 a second is 64 per run at 20 Hz. At 400
entities it was 696 fed and 946 hungry, about 2 per creature per second: on a dense grid with
hunters, sight facts (prey, threat, food) change that often as creatures move. Saturation
means a replan waits a run or more; the brain re-validates targets, so a late plan is stale
and not wrong. Before this commit planning and danger cost 62 ms each at 4,000 hungry. Three
things cut that: danger indexes who can hunt instead of asking every perceived id, planning
skips the sight scan when there is nothing to look for and fetches each component once for
both facts and scores, and planning got its own phase instead of sharing sensor's. Together
they took the average tick at 4,000 hungry from 203 to 119 ms and the heaviest from 297 to
142 ms.

If the planner needs to get cheaper, the levers are, in order: snapshot only planners whose
sensor or reach lists changed; run planning at 10 Hz; then move `EcsPlanner.plan` to
`WorkerThreadPool`, which only pays once replans rather than snapshots dominate.

**Previous ramp**, 2026-10-29, `86d6028`, game rates
(`--every=sensor:3:0,low_brain:3:1,hunger:6:2,energy:6:5,health:3:2`), against `6ee5529`
(before the views) in the same sitting. Average tick in ms, heaviest tick in brackets;
budget 250 ms:

| entities | fed, before | fed, after | hungry, before | hungry, after |
|---|---|---|---|---|
| 800 | 21.9 (36) | 12.5 (20) | 33.2 (62) | 14.6 (20) |
| 1,600 | 45.2 (59) | 27.1 (59) | 72.2 (141) | 32.2 (55) |
| 3,200 | 100.4 (170) | 61.8 (107) | 158.8 (264) | 74.8 (115) |
| 4,000 | 123.3 (173) | 76.9 (132) | 201.1 (344) | 94.5 (138) |
| 4,800 | 153.3 (218) | 93.9 (177) | 244.3 (427) | 114.4 (166) |
| 6,400 | 208.5 (296) | 127.4 (217) | 341.1 (645) ✗ | 157.0 (219) |
| 8,000 | 269.0 (377) ✗ | 162.5 (275) | — | 209.0 (370) |
| 9,600 | — | 201.6 (354) | — | 249.7 (364) |

✗ = first step over budget. **The ceiling is now over 9,600 fed and hungry** (the ramp's top
step; neither crossed), up from 6,400 fed and 4,800 hungry. At 9,600: **fed** sensor 40%,
node_sync 16%, collision 16%, low_brain 15%, movement 7%; **hungry** sensor 35%, low_brain
27%, node_sync 14%, collision 13%.

**How it got there** — about half the tick used to be component lookups, not work:

| commit | change | measured, 4,000 entities |
|---|---|---|
| `2a3fe52` | hunger/energy at 10 Hz, health at 20 Hz (§11) | tick 137 → 108 ms fed |
| `3338517` | `EcsWorld.view()` / `EcsView`; movement on it | |
| `ca092d8` | hunger, energy, health on views | health 8.6 → 1.4, hunger 16.5 → 9.4, energy 17 → 13 ms (every tick) |
| `4c3149c` | low_brain's main loop on a view | low_brain fed 18.5 → 14.2 ms |
| `1200078` | the brain's food index (id → position, from a view) | low_brain hungry 102 → 33 ms; `has` per tick 147,000 → 3,500 |
| `d349d8d` | collision's working set from views | 31 → 10 ms |
| `86d6028` | node_sync's working set from views | 20.4 → 9.2 ms |

**Views.** `world.view(include, exclude)` returns the matching ids plus one column of
component references per included type. Every table has a version, bumped by `add`,
`remove` and `destroy_entity`; a view is handed back as the same object until a table it
names changes. Field writes need nothing — the columns hold the same objects as the store,
which stays the only truth; a view is an index. Because components are fixed from spawn to
death, a view naming only components rebuilds only on births and deaths. Rules:

- Read a view, never change its arrays. A rebuild makes new arrays, so a loop over an old
  view finishes on the snapshot it started with, as with `query()`.
- Only included types have columns. Optional components stay `get_component()`.
- Don't name a flag that changes every tick (intents): the view rebuilds every tick, which
  costs more than `query()`. Rare flags (`EcsDyingFlag`) are fine.
- Something derived from a view can be cached on the view's identity: the brain's food
  index, collision's and node_sync's working sets rebuild only when `world.view()` hands
  back a different object.
- Systems that query on churning flags stay on `query()`: consume, pickup, drop, selection,
  inspect. Spawner, debug and sensor's two queries were not worth it.

**Measurement rules, learned the hard way:**

- **Never compare numbers from different sittings.** Throughput drifts by up to ~50% across a
  day on this machine. Run both arms back to back — for a whole-ramp comparison, check the
  old commit out into a worktree and run the two ramps one after the other.
- **Single-shot `--n` numbers are not comparable to ramp numbers**; the process state differs.
- **Repeat before believing.** Run-to-run noise is ±12%; anything under ~15% needs two runs
  at each end, interleaved.
- **Measure fed and hungry**, at the game's rates. A fed run never exercises the food search.
- The split's `logic` column includes engine calls (`node_for`, node writes, overlap reads),
  so a view can save more than the `fetch` column shows — collision and node_sync both did.

**What is left:**

1. **The heaviest tick.** It runs ~75% above the average (354 vs 202 ms at 9,600 fed): the
   tick the 20 Hz stages land on. Splitting sensor and brain work across their three ticks
   would flatten it.
2. **The sensor**, the biggest stage. Most of it is overlap reads off the physics server,
   which no view touches; the lever is reading less (fewer sensors, smaller radius, density).
3. **The brain's optional components** — hunger, energy, bag, reach, sensor — are still
   fetched per rung. A few ms; fetch once per creature after the mid-trip early-out.
4. **node_sync writes texture, scale, tint and z-index every tick** though they almost never
   change. Measure before skipping unchanged writes.
5. Past views, the per-entity floor is §15's storage argument.

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
from the rarest, and — since 2026-10-29, approved — cached views over that store (§14),
which are an index, not a second store.

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

**The combat pipeline** — rebuilt on the current architecture on 2026-10-29 (§17); the
original is still here for reference and for weapons. It was 10 components (`aggression`, `armor`, `attack_intent`, `broken`,
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

---

## 17. Combat, rebuilt

Rebuilt on the current architecture rather than checked out from `928b9d1`, whose
`EcsAggressionSystem` was a second decider measuring to every entity, whose hits went through
a frame-event API that was cut, and whose death and weapon model predate flags and records.

- **Deciding** is the brain's ATTACK state (§7). `EcsAttackIntentFlag{target_id}` is the
  instruction.
- **`EcsAttackSystem`** ticks every `EcsDamageComponent`'s cooldown and, for each attack
  intent off cooldown whose target has health, is not dying and is in the attacker's
  `EcsActionComponent.reached`, adds an `EcsHit` to `EcsCombatSingleton.hits`.
- **`EcsCritSystem`** multiplies hits whose attacker's `EcsCritChanceComponent` rolls.
- **`EcsDamageSystem`** applies each hit to the target's health less `EcsArmorComponent`
  (`reduction`, floored at `minimum`), then clears the inbox. Death stays `EcsHealthSystem`'s,
  and a death by health leaves a corpse (§9).
- **The crocodile** (`defs/blueprints/crocodile.tres`) is the hunter: eats meat, 150 health,
  20 damage every 1.2 s, 15% crit, speed 160, sight 500, fullness drain 0.8 a second. One is
  placed in `world1.tres`.

Seen headless over 180 s of the shipped world: four kills, each followed by eating the
corpse. Animals also starve in that world (2–4 per 180 s), but they did before combat too —
measured on `a71ff0c` with the same probe — so that is world balance, not combat.

**Not back:** weapons, `EcsEquipSystem`, durability and broken. A weapon is a carried item that
acts, which needs a decision on what a record in a bag may do (§9). `EcsArmorComponent` and
`EcsCritChanceComponent` exist; no blueprint authors armour yet.

---

## 18. Planning: utility goals, a pure planner, replans on events

Step 7 (2026-10-29). The brain's ladder chose the goal and the route in one hand-written
order, and got the meat chain right only through a hand rule (§7). Now
`EcsPlanningSystem` chooses the goal and plans the route; the brain still writes every
state, flag and destination.

- **Actions** are data: `ai/ecs_action_def.gd`, one `.tres` per action in `defs/actions/`
  (`id`, `preconditions`, `effects`, `cost`). Each `id` names a brain rung, so one action is
  one existing executor: `eat_carried`, `eat_ground`, `take`, `loot`, `seek_food`,
  `seek_bush`, `harvest`, `hunt`, `attack`, `sleep`, `flee`, and since §19 `go_to_cover`,
  `ambush`, `pounce` and `scan`. `attack`'s effect is
  `food_in_sight` — a kill leaves a corpse — which is the predicted effect the meat chain
  reasons over. `take` sets `has_room` false, so Provision means "fill the bag".
- **Goals** are data too: `ai/ecs_goal_def.gd`, in `defs/goals/` — `satisfy_hunger`
  {fed}, `provision` {bag full}, `rest` {rested}, `flee` {safe}. Each names a `need` and a
  `weight`.
- **`EcsPlanner.plan(facts, desired, actions)`** is forward A* over a dictionary of true
  facts, depth 8 (6 until §19, whose ambush chain is 6 steps long). It is pure — it reads only its arguments — so it can run on a worker
  thread later without being rewritten.
- **`EcsPlannerComponent`** carries a kind's `actions` and `goals`, and the runtime plan:
  `goal`, `steps`, the `facts` and goal `ranking` it was made from, and `replans`. Its
  `describe()` shows the goal and the plan in the inspector; the overlay prints the goal
  under the name.

**Goal choice is utility.** Below its gate a need scores `weight × urgency`, where urgency
runs from 0.6 at the gate to 1 at empty; above the gate it scores 0. The gates are the
hunger and energy fields the ladder used (`eat` uses the lower of `eat_below` and
`forage_below`). The weights — eat 10, flee 8, provision 4, rest 2 — keep the ladder's order
when there is no danger, pinned by a test over a grid of fullness and energy for each kind,
so plant-eaters choose as before. The current goal gets a 0.5 bonus so near-ties don't
flicker. Planning walks the goals best first and takes the first that has a plan, which is
the ladder's fall-through: hungry with nothing to eat in sight, it rests or wanders. Rest
shows as the goal only until energy passes `rest_at`; the brain's own sleep-until-rested
holds the creature down after that, so a sleeper often shows no goal.

**Replans happen on events, not on a clock.** Each run snapshots every planner's facts (the
same tests the rungs make: food in bag, reach or sight by diet, a bush with stock, prey by
`EcsHunting.can_hunt`, room, starving, threat) and ranks its goals. A planner is queued only
when its facts or its ranking differ from what its plan was made from. A settled creature is
never replanned, and a need crossing its gate, a target appearing or vanishing, a hit or a
kill each replan once. At most `MAX_REPLANS` (64) are planned per run, oldest first; the rest
keep their plan a run longer, and the brain re-validates every target when it acts. Because
the plan is always made from the current facts, "advancing a step" is just the next replan.

**Targets bind at execution.** A step is an action id, never an entity. The brain's rung
picks and checks the concrete target when it runs, so the eat step after a kill binds to the
corpse — a new id spawned a tick after the death — not to the prey.

**The meat chain without the hand rule.** A hungry crocodile with prey in sight plans
`hunt > attack > seek_food > eat_ground`. When the kill lands its facts change; when the
corpse appears they change again, and the cheapest plan is now to eat. Tested: two rabbits in
range, one killed, the corpse eaten. Live over 300 s it left five corpses (a starved animal
leaves one too, so that counts deaths by health, not kills).

**Danger and flee.** `EcsDangerComponent.value` (0–1) fills at `fill` per second while
anything that `EcsHunting.threatens` it is in sight, jumps by `hit_jump` on an `EcsHurtFlag`
(raised by `EcsDamageSystem`, read and cleared by `EcsDangerSystem`), and decays otherwise; it
remembers the last threat and where it was. At `flee_at` the `flee` goal scores, and that
crossing is the replan. Flee wins only by score: starving still outranks it, merely hungry or
fed does not. The FLEE state re-aims a trip away from the threat each brain tick, and a
sleeper whose plan is to flee wakes. Collapse is still the only forced override. Live, about
8% of creature-time is spent fleeing. Once prey fled, the shipped crocodile (speed 130,
sight 380, drain 1.5) starved to death in 3 of 3 headless runs of 300 s: rabbits outran it
and monkeys saw it first. Retuned on the crocodile alone to speed 160, sight 500 and drain
0.8, it survived 5 of 5 runs, never starving, at full health, killing about 4 in 300 s and
leaving 6 of the 10 plant-eaters. Sight alone saved it in 1 of 2 runs; speed or drain alone
in none or 1 of 2. Nothing is born yet, so any hunter that lives long enough empties the
world in the end.

**Layer, and why at this scale.** The design doc puts GOAP at L3, for day-scale projects.
This one plans over need-level actions, at L2 scale, because those are the actions that
exist and the meat chain is real multi-step reasoning over a predicted effect. The planner
is a pure function over plain facts, so promoting it to longer projects or a worker thread
is a change around it, not to it. Cost and replan rates are in §14.

---

## 19. Skills, water and the ambush

Step 1 of the features roadmap (2026-10-31). The crocodile hunts by ambush: it is slow, it
hides in water, and when prey comes close it dashes. Prey can scan, which reveals what is
hidden near them. All three are one mechanic, so another skill is data plus an effect.

**A skill is a def that says its own effect.** `ai/ecs_skill_def.gd`, `EcsSkillDef`: `id`,
`cooldown`, `duration` (0 = held: it lasts while asked for), and two overridable methods —
`make_effect()`, the flag that *is* the skill being active, and `can_start(world, id)`, its
requirement. Subclasses override only those: `EcsDashSkill` (`speed_scale`, `reach`),
`EcsHideSkill` (`stealth`; `can_start` is "in cover"), `EcsScanSkill` (`radius`). Data in
`defs/skills/`. This is `NODE_KIND`'s idea again: the def says what it does, so the system
never switches on skill type.

**Only `EcsSkillSystem` writes effect flags** (`EcsDashingFlag`, `EcsHiddenFlag`,
`EcsScanningFlag`); everything else reads them. The brain asks with `EcsCastIntentFlag{skill}`,
raised and cleared in `_set_state()` like every intent. Each tick the system ticks cooldowns,
ends a timed skill when its time is up and a held one when its intent is gone or `can_start`
stops holding — which is how hiding ends on leaving the water — and starts a cast that is
known, ready, not active and allowed. A refused cast does nothing. The cooldown starts when a
skill ends. `EcsSkillsComponent` holds the authored list and the timers, and its `describe()`
shows each skill as ready, active or cooling.

**A timed skill fires once.** POUNCE raises the dash intent; the tick the brain sees
`EcsDashingFlag` it moves to HUNT, which raises nothing. The intent is gone, so the dash can't
restart when its cooldown clears, and the flags still match the state.

**Water is cover.** `EcsCoverComponent{conceal}`; `defs/blueprints/water.tres` is a gradient
sprite under everything and a non-solid body of radius 140, so it is seen and walked through.
**In water means the action area touches a cover body** — `EcsHunting.cover_of`, the best
`conceal` in `reached`. So a hider stands at the edge nearest where it came from.

**Visibility** (`EcsHunting.visibility_of`, read by `EcsDangerSystem`): 1 unless hidden;
hidden, `1 − stealth × (1 − awareness)`. Danger rises at `fill × visibility − decay`, so
something faint enough is never noticed: hide stealth 0.95 is 0.05 to an unaware monkey,
below the floor; a rabbit with `awareness` 0.3 sees 0.34 and notices about four times
later than a plain threat (62 ticks against 16). A scanning watcher sees a hider within its
scan radius plainly. That check is a distance, on top of perception — the deliberate
exception noted in §4: it runs only over `perceived`, so scanning never reaches past sight.

**The crocodile**: speed 100 (rabbit 165), Dash (×3.5 for 0.6 s, cooldown 12 s, reach 180)
and Hide; `EcsEnergyComponent.hide_restore` 2.0 makes waiting a slow rest. Its hunger was
retuned in the same change: `max_fullness` 300, drain 0.3, gates 180/225/150, and a corpse's
`nutrition` 150.

**Planning.** Three facts for hunters — `cover_in_sight`, `in_cover`, `prey_close` (prey
within dash reach) — and three actions:

| action | needs | gives | cost |
|---|---|---|---|
| `go_to_cover` | cover_in_sight | in_cover | 2 |
| `ambush` | in_cover | prey_close | 1, `patience` 60 s |
| `pounce` | prey_close | prey_in_reach | 1 |

The crocodile **keeps `hunt` (3)**; no action is taken away to force a route, the costs
choose. On land with prey in sight, chasing (3) beats going to water and waiting (4); in the
water, waiting and pouncing (2) beats leaving to chase (3); with nothing in sight only the
ambush route exists; prey already close is a pounce. These are hand costs — roadmap step 3
replaces them with costs from speed. The full chain is six steps
(`go_to_cover > ambush > pounce > attack > seek_food > eat_ground`), which was exactly the
old depth cap, so `MAX_DEPTH` is now 8.

**`ambush` predicts its effect.** Water advertises no food. `prey_close` after `ambush` is a
bet that prey will come, the same kind of predicted effect as `attack → food_in_sight`, but
one that may never pay. **`EcsActionDef.patience`** is the general form: an action whose effect
hasn't come true within it has failed. The brain counts it down in `pause_left`; out of
patience it walks one leg straight away from the pond (WANDER with the pond as `target`, a
leg a plan to ambush may not cut short), which changes its facts, and the planner sends it
back to water.

**The brain's new states**: HIDE (walk to the nearest cover, stop at the edge), AMBUSH (stand
still, cast hide, wait out patience), POUNCE (aim at the nearest prey in reach, cast dash;
HUNT once the dash starts), SCAN (stand still, cast scan, for its duration). Prey carry Scan
(1.5 s, cooldown 8 s, radius 200) and a `scan` action, but **no goal wants `scanned` yet**, so
nobody scans in play until what triggers it is decided.

**Measured** (throwaway probe, the real scene, 5 runs of 300 s): the crocodile survived 5 of
5, hid about half the time, timed out 2 ambushes a run, dashed 0–1 times a run and **killed
nothing**. Each run it hid at one pond only — the one nearest it, returned to after every
timeout. That is expected and is the next step's reason: nothing brings prey to water, so
the bet does not pay, and the doubled arena makes passing prey rarer still. Thirst (roadmap
step 2) makes it true; memory (step 4–5) would let a pond's traffic set its cost and spread
the crocodile across ponds. Don't tune this before then — the stealth, awareness and dash
numbers will move once scan has a trigger.

**Cost**: level with its parent. Against `162c27a` in one sitting, 6,400 entities, game rates,
40 hunters: 293.5 ms fed against 292.9. `MAX_DEPTH` 8 costs nothing measurable (planning
63.7 ms on both). `skill` costs 6 ms there: it skips any entity with no timer running and starts
casts from a view of `EcsCastIntentFlag`. A first version that fetched the cast flag for every
entity with skills cost 18 ms. The machine read slower that day — the parent itself measured
293 ms where §14's table, from 10-29, has 192 — so compare only within one sitting.

**Open, to decide:** what triggers scan (a timer, scanning while eating near water, an alarm
when a neighbour flees, a faint threat in sight); thirst against hunger on the ladder.
