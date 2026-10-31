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
"$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn" # 354 checks, exit 0 = all pass
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

Every physics tick `EcsScheduler` runs twenty-nine stages. `[20 Hz]` and `[10 Hz]` mark the
ones that run every third or sixth tick (§11); the rest run every tick.

| stage | does | writes |
|---|---|---|
| `lifecycle` | births and deaths — the only stage that creates or frees | the world, the nodes |
| `spawner` | a spawner asks for what it spawns (no blueprint has one now; tests do) | a note on `EcsLifecycleSingleton` |
| `hunger` `[10 Hz]` | fullness drains; starving costs health, fed mends it | `EcsHunger`, `EcsHealth` |
| `energy` `[10 Hz]` | drains awake, restores asleep; collapse at zero | `EcsEnergy`, `EcsCollapsedFlag`, `EcsHealth` |
| `thirst` `[10 Hz]` | hydration drains; at zero it costs health | `EcsThirst`, `EcsHealth` |
| `health` `[20 Hz]` | death at zero | `EcsDyingFlag` |
| `danger` `[20 Hz]` | fills on a threat in sight, jumps on a hit, decays | `EcsDanger`, clears `EcsHurtFlag` |
| `sensor` `[20 Hz]` | what each entity sees and can touch | `EcsSensor.perceived`, `EcsAction.reached` |
| `memory` `[20 Hz]` | remembers water and lures seen; fades and falsifies (§20) | `EcsMemory` |
| `planning` `[20 Hz]` | scores goals, replans on events, under a budget (§18) | `EcsPlanner` |
| `low_brain` `[20 Hz]` | runs the plan's first step, or its own ladder | its own state, a destination, intent flags |
| `skill` | carries out a cast intent; runs skill timers (§19) | `EcsSkills`, the effect flags |
| `consume` | carries out an eat intent | `EcsHunger`, the bag, `EcsDyingFlag` |
| `drink` | carries out a drink intent while the water is in reach | `EcsThirst` |
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

The world today is 48 animals — 20 rabbits, 20 monkeys, 4 crocodiles, 4 wild dogs — 52 bushes, 1.3 per
plant-eater, and 16 ponds (`defs/world1.tres`), on a 6400×3360 arena. The arena was doubled each
way on 2026-10-31 to make room for more kinds; doubling it alone left food 4× sparser and 2–5
of 10 plant-eaters starved per 300 s run (≈0 before), so every count was then multiplied by 4
to restore the old density. The 28 original placements kept their (doubled) spots; the rest
were spread by a seeded script with minimum spacings. A berry exists only once
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

**Three distance checks sit on top of perception, all deliberate** (§19, §20): a scanning
watcher sees a hider within its scan radius, the planner's `prey_close` is prey within dash
reach, and memory forgets a fact whose spot is within sight radius but whose thing is not in
`perceived`. The first two run only over `perceived` and the third only over the memory's own
facts — the area still decides *whether* something is seen.

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

## 8. Needs: fullness, hydration, energy and health

All four bars are **reserves**: full is good, and a short bar is bad news on every one.

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

**Thirst** (2026-10-31, roadmap step 2) is hunger's twin. `EcsThirstComponent.hydration`
drains from `max_hydration` (100) at `drain`, slower asleep at `asleep_drain_scale`, and at
zero `EcsThirstSystem` spends health at `dehydrate_damage` — so a death of thirst leaves a
corpse like any death by health. Its gates are `seek_water_below` (65, go looking) and
`drink_below` (70, drink what is in reach — a grazer's order, since nobody carries water), and
**`parched_below` (15) mirrors starving**: a parched creature won't sleep, a parched sleeper
wakes, and the planner's `sleep` needs `parched` false. Thirst does not mend health; mending
stays the reward for having eaten. Drain: rabbit 0.6, monkey 0.5, crocodile 0.25, wild dog 0.4
per second.

**Water is drinkable as well as cover**, and the two are separate components:
`EcsDrinkableComponent{rate}` (hydration per second while drinking, 25) sits beside
`EcsCoverComponent` on `water.tres`. A bush could be cover and not drinkable; a well the other
way round. "In reach of water" is the same physics test as cover — the action area touches the
body. The brain raises `EcsDrinkIntentFlag{target_id}`, and `EcsDrinkSystem` fills hydration
while that water is drinkable and in reach. It never reads the brain, so a creature with no
brain drinks when the flag is raised (tested). **Drinking is a commitment**: DRINK holds until
full, unless the plan is to flee — not until the need drops under its gate, or a creature
would leave at 66 and be back a minute later.

**Thirst against hunger: the more urgent need wins** (the author's decision, 2026-10-31).
Starving and parched each outrank sleep; below that, both are scored by one curve,
`EcsNeeds.urgency` (`ai/ecs_needs.gd`) — 0 above the need's gate, 0.6 at it, 1 at empty — and
the higher wins. The planner gets it for free: `quench` {hydrated} has weight 10, the same as
eating, so its scores compare directly. The ladder makes the same comparison by hand: the
water rungs (drink, then seek water) go above the food rungs when thirst is the more urgent,
below them otherwise, and on a tie food goes first. Both read `EcsNeeds`, so they cannot
disagree, and neither system calls the other.

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

`tests/lifecycle_test.tscn` — **354 checks**, exit code 0 only if all pass. Run it after
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
eating; thirst draining, slower asleep, and a death of thirst leaving a corpse; a drink refused
on land and at cover that isn't drinkable, and working with no brain; a thirsty rabbit seeking
water and drinking until full with the flag up exactly while it drinks; the more urgent of
thirst and hunger going first, on the ladder and in utility; being parched waking a sleeper; the
water chains; a thirsty rabbit walking to a pond where a hidden crocodile pounces and bites;
every animal resolving the default skills and the crocodile's swaps; a chase priced from
speeds (the crocodile can't, the dog can), the same actions making one ambush and the other
chase, and a dog ambushing at a bush; each kind hiding only in its own cover; hunters passing
over hidden prey and dropping a chase when it hides; a frightened rabbit hiding beside a bush,
escaping with a ready dash or fleeing with it cooling; a rabbit scanning before it drinks,
running when the scan shows a crocodile; and memory learning water and lures by kind, fading,
falsified on sight and capped, a thirsty rabbit planning and walking to a remembered pond and
forgetting it on arrival when it is gone, and a dog walking to a remembered bush to wait; a
pond feared where a threat was met, priced dearer until the fear fades and still better than
none; a lure gaining traffic from prey seen there and winning though farther, a corpse counted
once, and traffic halving.

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
- **7, GOAP** — done (2026-10-29, `cf53229` to `ae1ef52`): harvesting first, then a pure A*
  planner over a symbolic snapshot, utility goal choice, a budgeted replan queue that replans
  on events, and fleeing. Single-threaded; the planner is pure, so moving it to
  `WorkerThreadPool` is a dispatch change, to make only when the profiler asks (§14, §18).
- **Features roadmap** (`FEATURES_ROADMAP.md`, kept outside the repo), 2026-10-31: **1** skills,
  water and the ambush, **2** thirst, **3** every animal the same — costs from stats, cover
  kinds, the wild dog, staying safe (§8, §19) — **4** memory, first slice, and **5** places
  priced by fear and traffic (§20) are done. **Queued next, in order:** hiders go to the middle
  of their cover and bushes stop being solid; memory widened to whatever matters to the animal
  (water, food, threats, prey, lures); a pounce that stuns, attacks until dead, a stun
  indicator and a small showcase scene; births.

**Open and deferred, by decision:** combat planning (a kill is many attacks; the planner
should choose skills from the enemy's skills and stats, §19); births — nothing is born, so
hunters empty the world given time; `MoveIntent`; weapons, durability and broken (they wait on
what a carried record may *do*); prey fighting back; bag capacity and stacking; **power as a
derived, tweakable value** (today it is authored). **Do not re-add breadth without being
asked** — the small size is the point.

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

**Latest ramp** (2026-10-31, `2876967`: skills, thirst, the dog, memory), game rates
(`sensor:3:0,memory:3:1,danger:3:1,planning:3:2,low_brain:3:1,health:3:2,hunger:6:2,energy:6:5,thirst:6:3`),
40 hunters. Average tick in ms, heaviest in brackets:

| entities | fed | hungry |
|---|---|---|
| 800 | 40.3 (65) | 40.8 (66) |
| 1,600 | 61.9 (95) | 69.1 (114) |
| 3,200 | 138.0 (188) | 144.4 (197) |
| 4,000 | 170.8 (251) | 176.7 (220) |
| 4,800 | 195.9 (255) | 212.8 (275) |
| 6,400 | 243.4 (299) | 268.7 (333) ✗ |
| 8,000 | 316.0 (400) ✗ | — |

**The ceiling is 6,400 fed and 4,800 hungry** (6,400 hungry misses by 7%). Down from the
10-29 table below, but not measured in one sitting with it, and this machine read slower that
day: `dac563e` alone ran 190–234 ms at 6,400 fed in one hour. Each feature step measured
within 6% of its parent in one sitting (§19, §20), so no single step is the drop. The grid has no water
or bushes, so it never loads thirst's or memory's real lookups.

**The planner's ramp** (2026-10-29, `ae1ef52` against `86d6028` in one sitting, from a
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
  `go_to_lure`, `ambush`, `pounce`, `hide`, `escape`, `go_to_water` and `drink`. `attack`'s effect is
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

## 19. Skills, cover and the ambush; every animal the same

Features roadmap steps 1–3 (2026-10-31; `6622924`, `a8fe73e`, `dac563e`). **Every animal is the
same**: the same skills, planner and actions, and behaviour differs only through stats, diet
and goals. Removing an action from one kind to force a route is a script in disguise — change a
stat or a cost instead.

### Skills

**A skill is a def that says its own effect.** `ai/ecs_skill_def.gd`, `EcsSkillDef`: `id`,
`cooldown`, `duration` (0 = held: it lasts while asked for), and two overridable methods —
`make_effect()`, the flag that *is* the skill being active, and `can_start(world, id)`, its
requirement. `EcsDashSkill` (`speed_scale`, `reach`), `EcsHideSkill` (`stealth`, `kinds`;
`can_start` is "in cover it hides in"), `EcsScanSkill` (`radius`). Data in `defs/skills/`. The
system never switches on skill type — `NODE_KIND`'s idea again.

**Only `EcsSkillSystem` writes effect flags** (`EcsDashingFlag`, `EcsHiddenFlag`,
`EcsScanningFlag`). The brain asks with `EcsCastIntentFlag{skill}`, raised and cleared in
`_set_state()` like every intent. Each tick the system ticks cooldowns, ends a timed skill when
its time is up and a held one when its intent is gone or `can_start` stops holding (that is how
hiding ends on leaving cover), and starts a cast that is known, ready, not active and allowed.
The cooldown starts when a skill ends. It skips any entity with no timer running and starts
casts from a view of `EcsCastIntentFlag`.

**A timed skill fires once.** POUNCE and ESCAPE raise the dash intent; the tick the brain sees
`EcsDashingFlag` it moves to HUNT or FLEE, which raise nothing, so the dash can't restart when
its cooldown clears.

**One default set, swapped per kind.** `defs/skills/default_set.tres` (`EcsSkillSet`): dash (×2
for 0.5 s, cooldown 10 s, reach 150), hide (0.9, in `bush`) and scan (1.5 s, cooldown 8 s,
radius 200). `EcsSkillsComponent.swaps` replaces a default with the same id, or adds one;
`EcsSkillSystem` resolves the set the first time it sees an animal, as energy rolls its start,
so a runtime spawn gets it too. Only the crocodile swaps: `dash_crocodile.tres` (×3.5 for
0.6 s, cooldown 12 s, reach 180) and `hide_water.tres` (0.95, in `water`). Attack stays
`EcsDamageComponent`.

### Cover, lures and being seen

**Cover has a kind.** `EcsCoverComponent{kind, conceal}`: water (`water.tres`, a gradient sprite
and a non-solid body of radius 140, also `EcsDrinkableComponent` — §8) is `water`, a berry bush
is `bush`. **In cover means the action area touches a cover body** of a kind the hide skill
lists (`EcsHunting.cover_of`, `hides_in`), so a hider stands at the edge nearest where it came
from. The crocodile refuses bushes and the dog water; nobody branches on species.

**A lure is cover prey must visit** — drinkable or harvestable (`EcsHunting.is_lure`). Hunters
bet only at a lure: `prey_come_here` is true in usable cover that is a lure.

**Visibility** (`EcsHunting.visibility_of`): 1 unless hidden; hidden,
`1 − stealth × (1 − awareness)`. Danger rises at `fill × visibility − decay`, so something faint
enough is never noticed: the crocodile's 0.95 is 0.05 to an unaware monkey, below the floor;
a rabbit (`awareness` 0.3) sees 0.34 and notices about four times later than a plain threat. A
scanning watcher sees a hider within its scan radius plainly — a distance on top of perception,
run only over `perceived` (§4). **Hunters notice**: `EcsHunting.notices` (visibility ≥ 0.5)
gates every choice of prey — the brain's hunt and pounce, a running chase, the planner's prey
facts and chase cost — so hiding protects prey exactly as it hides a crocodile.

### Planning: costs come from the entity

| action | needs | gives | cost |
|---|---|---|---|
| `hunt` | prey_in_sight | prey_in_reach | from speeds, below |
| `go_to_lure` (hunters) | lure_in_sight | in_cover, prey_come_here | 2 |
| `ambush` | in_cover, prey_come_here | prey_close | 1, `patience` 60 s |
| `pounce` | prey_close | prey_in_reach | 1 |
| `go_to_cover` (prey) | cover_in_sight | in_cover | 2 |
| `hide` | threat_near, in_cover | safe | 1.0, `patience` 8 s |
| `escape` | threat_near, dash_ready | safe | 1.2 |
| `flee` | threat_near | safe | 1.5 |

`EcsPlanner.plan` takes a `costs` override, `INF` ruling an action out, and stays pure.
`EcsPlanningSystem._costs` builds it only when it replans, so moving prey never cause a replan:
**`hunt` costs `1 + gap / closing speed / TRAVEL_SECONDS` (5 s)** against the cheapest noticed
prey, and is impossible against prey at least as fast. So the crocodile (100) never chases a
rabbit (165) or a monkey (130) and ambushes; the wild dog (200) chases, and ambushes at a bush
when no prey is in sight. The full ambush chain is `go_to_lure > ambush > pounce > attack >
seek_food > eat_ground`; `MAX_DEPTH` is 8. Every action costs at least 1, which keeps the A*
estimate admissible.

**`ambush` predicts its effect.** A lure advertises no food; `prey_close` after `ambush` is a bet
that prey will come — grounded because prey must come to drink or harvest, but still a bet.
**`EcsActionDef.patience`** is the general form: an action whose effect hasn't come true within
it has failed. The brain counts it down in `pause_left`; out of patience it walks one leg
straight away from the cover (WANDER with the cover as `target`, a leg a plan may not cut
short), which changes its facts, and the planner decides again. `hide` has 8 s of it: without,
a rabbit hiding where a dog lay in ambush could see the dog faintly forever while the dog could
not see it, and plant-eaters died of thirst holding still.

**Staying safe.** The `flee` goal ({safe}) has three routes: a rabbit beside a bush hides, one in
the open dashes (ESCAPE: a trip away plus a dash, then FLEE), one whose dash is cooling runs. A
plain flee gives way to an escape when the dash comes ready.

**Scan before drinking.** `_try_drink` scans first when the scan is ready, then drinks once it
is cooling. A rabbit scanning beside a hidden crocodile fills danger fast and — unless thirst
outranks it — runs.

**The brain's states for this**: HIDE (walk to cover, stop at the edge), AMBUSH (stand still,
cast hide, wait out patience; serves `ambush` and `hide`), POUNCE (dash at the nearest prey in
reach), SCAN (stand still, cast scan), ESCAPE.

### The hunters

| | crocodile — ambusher | wild dog — chaser |
|---|---|---|
| speed / sight / reach / body | 100 / 500 / 50 / 32 | 200 / 420 / 46 / 26 |
| health, power | 150, 60 | 100, 35 (a crocodile can hunt it) |
| bite | 20 every 1.2 s | 15 every 0.9 s |
| hunger | meat, `max_fullness` 300, drain 0.3, gates 180/225/150 | meat, 150, drain 0.5, gates 90/110/75 |
| thirst drain | 0.25 | 0.4 |
| skills | swaps: strong dash, hides in water; `hide_restore` 2.0 | the defaults: hides in bushes |

Both carry the same planner actions. A corpse's `nutrition` is 150.

**A kill is not one action** (the author, 2026-10-31). It is attacks until the target is dead.
One bite does not kill a rabbit, and a bitten rabbit outruns a crocodile. That is left for
combat planning, where the planner should choose skills from the enemy's skills and stats —
not patched with a one-shot kill or a guaranteed stun. Tests assert a pounce that bites.

### Measured

**Behaviour** (probe, the real scene, 5 runs of 300 s, 48 animals, at `dac563e`): 7–9 kills a
run, almost all by dogs, about half by chase and half from a bush; the crocodiles about one, from
water. Crocodiles ambushed 20–37 times a run and dogs about 10; prey escaped about 150 times, hid
60–100 and scanned about 100, 8–17 of those scans ending in a run. All 40 plant-eaters drank,
about every 75 s, all 16 ponds used. No plant-eater died of thirst; 0–4 starved; 29–32 of 40 were
alive at the end. Nothing is born, so the dogs empty the world given time. Memory's numbers are
in §20.

**Cost** — each step measured against its parent in one sitting (6,400 fed, 40 hunters, game
rates). Each landed level after one fix, and the fixes are the lesson:

- `skill` 18 → 6 ms: it fetched the cast flag for every entity with skills; now it skips
  idle ones and starts casts from a view.
- thirst +11% → +5.7%: the ladder read hunger every run to order its rungs; now only when
  thirsty.
- step 3 +45% → level (190.9 vs 194.4 ms): every planner walked its perceived list for cover;
  now planning skips it when the world has none, and reads the skills component once.

The stress grid has no water or bushes, so the cover and lure lookups the real world pays are
not in those numbers.

**Open, to decide:** combat — choosing skills to kill from the enemy's skills and stats, and
whether prey fight back. Births.

---

## 20. Memory: remembered water and lures

Roadmap step 4, first slice (2026-10-31). Without it, a thirsty animal with no water in sight
had no plan and wandered. Now it walks to a pond it remembers.

**Storage is a component**, by decision: `EcsMemoryComponent` holds `facts`, an id → `EcsMemoryFact`
record (`about`, the `position` it was seen at, `water`, `lure`, `strength`), capped at
`capacity` (32). Graph-shaped relations are a separate, later question. **`EcsMemorySystem`** is
its only writer, at 20 Hz on the tick after the sensor and before planning:

1. **Fade.** Strength drops by `delta / remember_for` (180 s); at 0 the fact is forgotten.
2. **Learn.** From `perceived`: drinkable water, for an animal with thirst; a lure it hides in
   (`EcsHunting.is_lure` and its hide kinds), for one that attacks. Seen means strength 1 and
   the position copied. Prey don't remember cover — a far bush is no use to hide in.
3. **Falsify.** A fact whose spot is within sight radius but whose thing isn't perceived is
   forgotten at once (the third distance check in §4). It runs before planning in the same
   tick, so an animal that arrives to find a pond gone has dropped it before it replans — no
   retry loop.
4. **Cap.** Past `capacity`, the weakest fact goes.

**Planning.** Facts `water_known` and `lure_known`; actions `recall_water` (→ `water_in_sight`)
and `recall_lure` (→ `lure_in_sight`), which feed the existing `go_to_water` and `go_to_lure`
chains. Their cost is the walk: `1 + distance to the nearest fact / speed / TRAVEL_SECONDS` (5,
the constant the chase cost used, renamed), so a pond in sight (2) beats one remembered, and a
near remembered bush can beat a long chase. The brain's **RECALL** state walks to the fact's
copied position — never the live entity's — and is dropped like any step once the plan moves on
(the thing comes into sight and the plan becomes `go_to_water` or `go_to_lure`).

**Measured** (probe, 5 runs of 300 s, 48 animals, against `dac563e`): drinkers spent
1,466–1,672 s a run with `quench` on top and no plan; with memory 97–220 s. 70–119 recalls to
water and 0–5 to a lure a run. No fact was falsified — nothing in this world moves or dies
that memory holds — so the falsify path is pinned by tests only. Kills (6–8), thirst deaths
(0) and starvation (1–4) stayed in step 3's range.

**Cost**: the memory stage is 4 ms of a ~216 ms tick at 6,400 fed (40 hunters, game rates).
Totals in one sitting were 217.7 / 216.2 ms against 190.7 / 233.6 for `dac563e`, which is this
machine's noise. A first version cost 71 ms: every animal asked the world whether each thing it
saw was drinkable. It now indexes water and lures from views, like planning, and skips the walk
when there is nothing to learn. The stress grid has no water, so the per-sighting lookups the
real world pays are not in that number.

### Step 5: places are priced by fear and traffic (2026-10-31)

**Price places, not actions.** A penalty belongs to a place, but the planner prices actions; with
`recall_water → go_to_water` the second step would carry the penalty of whatever pond was in
sight. So each go-to action binds its own set of places and is priced by its binding:
`go_to_water` / `go_to_lure` the best place **in sight**, `recall_water` / `recall_lure` the best
place **remembered**, and the recalls now give `water_in_reach` / `in_cover, prey_come_here`
directly. One helper does both the pricing and the binding — `EcsMemoryFact.score` (`1 + walk /
TRAVEL_SECONDS`, plus `fear_cost × fear` for water, or `wait_cost / (1 + traffic)` for a lure) and
`EcsMemoryFact.best` — so the planner and the brain cannot disagree. RECALL ends in reach; on
arrival it holds still until the replan names the next step.

**Fear** (prey avoidance, graded by decision): when an animal's danger is at or over `flee_at`,
every water fact within `radius + near` (200) of `danger.threat_at` gets fear 1, fading over
`fear_for` (60 s). It reuses danger's notion of meeting a threat, so a hidden crocodile nobody
noticed causes none and a scan or a bite does. A feared pond costs up to `fear_cost` (4, about
20 s of walking) more: a near feared pond can still win, and one is better than none.

**Traffic**: a hunter adds `delta` to each lure fact near noticed prey it sees, and
`kill_traffic` (10) once for a corpse seen near one; traffic halves every 120 s. The expected
wait at a lure is `wait_cost` (2) with no traffic and tends to 0 at a busy one.

**Measured** (probe, 5 runs of 300 s, against `8ff4bc1`): prey marked a pond feared 119–217
times a run and still drank at a feared pond 10–26 times; ambushes paid 15–25 a run (13–22
before); kills 5–8, no deaths of thirst, 0–5 starved. **The crocodiles did not switch ponds** —
each ambushed at exactly one, before and after. Not the costs: a crocodile only knows the pond it
sits at. Its sight is 500 px on a 6,400 px map and a failed ambush walks it 360 px away, so no
second pond is ever remembered to switch to. Switching needs a crocodile that has seen more
ponds — exploration, or memory shared some other way — which is left open.

**Cost**: the memory stage went from 3.9 to 8 ms at 6,400 fed (it now reads each animal's
danger); totals level, 241.6 / 226.2 ms against 237.5 / 227.7 for `8ff4bc1`.
