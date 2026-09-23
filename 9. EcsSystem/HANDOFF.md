# Module 9 — EcsSystem: state of the build

Greenfield hand-rolled ECS, built beside `8. SimpleAiSystem` per `ECS_REFACTOR_PLAN.md`.
**Module 8's code has since been deleted** — its folder is a design archive of five `.md`
files, so the references to it below are to a recorded design, not to something you can
run and compare against. Module 9 is the only live simulation in the repo.

**The module has been deliberately stripped to its bare minimum** — one world, one
scheduler, thirteen systems — so the flow reads end to end without hunting. What was cut is
listed in §6 and is recoverable from git; nothing was lost, only set aside.

`project.godot`'s main scene is module 9 (`uid://daecsmain0001`), so a plain run opens it,
or run it directly:

```bash
GODOT="/home/zhenzhu/.local/share/Steam/steamapps/common/Godot Engine/godot.x11.opt.tools.64"
"$GODOT" --path . "res://9. EcsSystem/main.tscn"

# 66 checks over the entity lifecycle, the sensor/action layer, solidity, the
# movement trip clock and the brain's commitments; exit 0 only if all pass
"$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn"
```

One thing outside this folder belongs to module 9 and would be lost if the folder were
moved alone: the main-scene line in `project.godot`. (The four `ecs_*` signals that used
to live in `System/EventBus.gd` went with the observability layer — module 9 now touches
the `EventBus` not at all.)

---

## 1. The whole flow, in order

```
world1.tres  ──►  EcsEntityManager ──►  EcsWorld          (once, at startup)
(placements)      resolves each row       ids + component
                  against catalog.tres,   tables
                  builds the nodes        + the nodes they declare

every frame, EcsScheduler runs thirteen systems over that world:

  lifecycle  births and deaths     → the only stage that creates or frees
  spawner    asks for a berry      → writes a note to the lifecycle inbox
  sensor     what it sees/reaches  → writes EcsSensor/EcsActionComponent
  low_brain  FSM: idle/wander/seek  → writes EcsMovementComponent
  movement   walks toward it       → writes EcsPositionComponent
  collision  unstacks the bodies   → writes EcsPositionComponent
             (the Area2Ds it reads overlaps off are a derived index)
  pickup     takes what it reached → removes EcsPositionComponent
  selection  resolves a click      → writes EcsSelectedComponent
  node_sync  draws where it ended  → writes each entity_<id> container
  debug      reports all of it     → writes the on-entity overlay
  census     counts the world      → emits on the EventBus
  inspect    reflects the selected → emits on the EventBus
```

The last three are pure readers: pull `debug`, `census` or `inspect` out of the chain and
the simulation does not notice.

Read `systems/ecs_low_brain_system.gd`, `ecs_movement_system.gd` and
`ecs_node_sync_system.gd` in that order and you have seen every behaviour in the module.
Each is under 60 lines.

`EcsLowBrainSystem` / `EcsLowBrainComponent` are named for their **rank, not their
behaviour** — they are the bottom of the decision ladder, and what they happen to do
today is wander. The plan's step 6 puts an FSM above them and step 7 a planner; all three
do the same single thing, write a destination into `EcsMovementComponent`, so a smarter
brain replaces this one without movement, render or debug changing a line. Carrying the
component is the whole of "this entity decides for itself".

`EcsDebugSystem` is the odd one out and deliberately so: it is a **pure reader**. It
writes no component and creates no entity, so pulling it out of the scheduler changes the
simulation not at all — which is the cleanest possible demonstration that a system is just
something the scheduler calls. It feeds one dumb view, `EcsDebugOverlay`, which draws on
the entities themselves: name, position, the velocity vector with its heading, and a
dashed line to the ring marking the spot the low brain picked. **F1** toggles it.

It used to draw the `EcsBodyComponent` body as a green circle too. That is gone: since
§5 every solid entity carries a real `CollisionShape2D` in the tree, so Godot's own
**Debug > Visible Collision Shapes** draws it, and a hand-rolled copy could only ever
disagree with the shape the physics server is actually using.

That body is **data, not a `CollisionShape2D` under a `PhysicsBody2D`** — one radius in a
component table. Putting a real physics body there would move the truth back inside nodes
and force every system to read it out of the view, which is the thing this module exists
to avoid.

### Collision is soft, and leans on Godot's broadphase

`EcsCollisionSystem` runs straight after movement: movement proposes a position, collision
corrects it, and neither knows the other exists. Overlap is **allowed to happen and then
undone**, never prevented — no sweep test, no veto inside movement. Applying it as a
constraint after the fact is what makes it compose: anything else that ever writes a
position (knockback, a spawner, a debug teleport) gets cleaned up for free.

**It reads overlaps off an `Area2D` per solid entity, and that is a deliberate exception
to "nothing reads back off a node".** Be precise about what it is: `EcsPositionComponent` is
still the only truth, the areas are a *derived index* — every tick the system writes each
body's position and radius out of the components — and the only thing read back is
**which pairs are near each other**, never where anything is.
Delete the pool and the simulation is still complete. That is a different thing from
module 8, where the node *was* the entity. If a future system starts reading state off
these areas, that line has been crossed.

Why bend the rule at all: finding which circles overlap is a spatial-index problem and
Godot ships one in C++. Measured on this machine, per tick:

| n | Area2D | the GDScript O(n²) it replaced | 60Hz tick |
|---|---|---|---|
| 100 | 1.56 ms | 3.82 ms | 9% |
| 200 | 3.24 ms | 13.61 ms | 19% |
| 400 | 6.56 ms | 52.12 ms | 39% |
| 800 | 11.38 ms | 201.84 ms | 68% |
| 1600 | 21.33 ms | ~800 ms | 128% |

Near-linear instead of quadratic. Note where the time actually goes: the physics
broadphase is only ~0.2 ms at 100 entities. The rest is GDScript — which is why `_sync`
gathers component references into parallel arrays once per tick and `_resolve` then never
touches the world. That gather is worth ~30%, and is the reason the system is shaped the
way it is rather than calling `get_component` in the inner loop.

**The pipeline runs on the physics tick**, not the render frame. A simulation wants a
fixed timestep, and `get_overlapping_areas()` is refreshed once per physics step, so
running faster would re-read the same answer.

**One tick of lag.** The overlap list reports what the server saw at the end of the last
step, so a correction always trails the positions that caused it — about two pixels at
walking speed, invisible. It also means the relaxation passes the GDScript version used
are gone: the list cannot be refreshed mid-tick, so it is one pass per tick, converging
over a handful of ticks instead of instantly.
`PhysicsDirectSpaceState2D.intersect_shape()` is the synchronous alternative if that ever
matters — it works same-tick from `_physics_process`, at the cost of a query per body.

Carrying an `EcsBodyComponent` gives an entity a body; that component's `is_solid` is what
makes the body block. Anything without one never gets a body at all, and a body with
`is_solid = false` exists purely to be seen and reached — it is gathered only so its
radius reaches its area, and skipped at both ends of the resolve.

Solidity was briefly a separate tag component, `EcsSolidComponent`, on the argument that
presence beats a flag everywhere else in this module. It was merged back in by decision:
a radius and whether that radius blocks are one physical fact about one body, and an
author tuning a `.tres` sets them in one block rather than remembering to attach a second
resource. It is the module's one authored boolean of its kind — the rule it bends is
worth knowing it bent.
Every pair is reported twice, A sees B and B sees A; rather than deduplicating,
each body moves only *itself* by half the overlap, so the double report is what makes the
correction symmetric.

Verified: the ten entities spawn piled within ~60 px and separate from 46.6 px of overlap
to under 1 px in ten ticks; **F5** rebuilds without leaking bodies.

**What soft costs:** a fast enough mover can pass through something between ticks, a body
squeezed by two others can be pushed through a third, and there is no bounce — separation
is positional only, velocity is untouched.

### The berry spawner

`EcsSpawnerComponent` is the settings — blueprint id, radius, interval, `max_loose` — and
`EcsSpawnerSystem` is the doing. It no longer spawns anything itself: it writes a note to
`EcsLifecycleComponent` and `EcsEntityManager` fulfils it at the top of the next tick (§5),
then the spawner reads the new id back off its own note. One tick between asking and
appearing. The property that ordering used to protect still holds — the berry is built at
the very start of a frame, so every system in that frame sees it and draws it, and there
is no moment where an entity exists without its nodes.

Two things it does differently from module 8's `SimEntitySpawnerComponent`:

- **The component holds no behaviour.** Module 8's ran its own `_process` and did the
  spawning itself.
- **It tracks entity ids, not node references.** Module 8 kept nodes and pruned with
  `is_instance_valid()`. Ids are never reused, so a harvested berry's id goes permanently
  false through `world.is_alive()` and can never alias a later entity. The factory and
  catalog arrive through `_init` rather than a group lookup, so the dependency is visible
  in `main.gd`'s pipeline and cannot go missing at runtime. Notes already in flight count
  against the cap too, or the spawner would re-ask every tick until the first one landed
  and sail past `max_loose`.

**A berry is a sprite and nothing else** — no shape, no movement, no brain. So it is not
solid, cannot move, and never enters the collision query: 36 entities in the world, 12
`Area2D` bodies. No `is_item` flag, no layer mask, no branch. That is the same trick the
deleted dagger prop showed, arriving again for free.

Nothing harvests berries yet, so each bush fills to `max_alive` (12) and stops. That is
the cap working, not a bug.

Verified: 14 entities at t=0 → 36 by t=25s, holding steady, 12 per bush, bodies constant
at 12 throughout.

### Deciding: one brain with state, after a ladder made out of run order

**What it was.** `EcsForageSystem` had the *same shape* as `EcsLowBrainSystem` — look at
an entity with nothing to do, write a destination — and it ran **before** it. That was the
entire priority mechanism: forage got first refusal, an entity it declined fell through to
aimless wandering, and a third rung would have been one file and one scheduler line with
no existing rung changed. It read beautifully and it is worth understanding why it went.

**Why it went.** It was stateless. A creature's only memory between ticks was
`EcsMovementComponent.has_destination` — one borrowed boolean — and three things follow
from that, none of them fixable by adding rungs:

- **No persistence.** "I am going to *that* berry" had nowhere to live, so it was
  re-derived every tick from whatever the sensor happened to report.
- **No preemption.** A rung could fill an *empty* destination slot and never take a full
  one, so nothing could interrupt anything. A wolf appearing mid-forage could not cut in,
  because every rung politely skips an entity that already has somewhere to be.
- **No hysteresis.** A threshold sitting near its trigger flickers the creature between
  rungs on consecutive ticks, because nothing remembers which side it was on. Step 4's
  hunger thresholds are exactly that shape, which is what forced the issue.

**What it is now.** One `EcsLowBrainSystem` holding a small state machine, with `state`
and `target` on `EcsLowBrainComponent`:

```
IDLE  ──pause elapsed──►  WANDER  ──sees food──►  SEEK_FOOD
  ▲                         │                        │
  └─────────── trip ended, or target gone ───────────┘
```

The ladder is now the order of the branches inside one function rather than the order of
two lines in `main.gd`. That is no less explicit — arguably more, since the whole decision
reads top to bottom in one place — and it buys the three things above. Concretely:

- **A commitment is not reconsidered; a wander is.** `SEEK_FOOD` runs to its end.
  `WANDER` is interruptible, so a creature drifting aimlessly notices a berry on the tick
  it perceives it rather than when its leg happens to finish.
- **A dead target is dropped immediately.** If the berry is eaten or taken by someone
  else, the brain calls off the trip that tick instead of walking to empty grass.
- **Every destination write goes through one helper** that also zeroes `time_left`.
  Overwriting a live trip would otherwise inherit the previous one's budget and time out
  early — the hazard that arrives the moment preemption is possible at all.

It still says exactly one thing to the rest of the pipeline: a destination. Movement,
collision and node_sync never learn that any of this exists, and the planner that goes
above this at step 7 will not change them either.

**The cost, stated plainly.** This system reads components that are not its own — sensor,
inventory, and hunger next — through `get_component` rather than naming them in its query,
so a creature lacking one simply never takes that rung. It is the one place in the module
that knows about several concerns at once. That is what a brain is; the line it must not
cross is *doing* anything with them, and it still writes only `state`, `target`,
`pause_left` and a destination.

**One behaviour worth knowing:** a freshly spawned entity perceives nothing on its very
first tick, because `sensor.perceived` is written from physics overlaps that have not been
reported yet. Its opening move is therefore always a wander, preempted the tick after.
`tests/lifecycle_test.gd` pins that down rather than papering over it.

### A destination is a budget, not a standing order

The ladder above has a hole in it that only shows up once something gets in the way.
Soft collision corrects a position *after* movement proposes it, so an entity held off
its target — wedged in a crowd, or walking at the middle of a bush it cannot stand in —
proposes the same step forever. `has_destination` stays true, and both rungs above skip
it **because** it already has somewhere to be. That is the stuck entity: a livelock
between stages, not a fault in any one of them, and nothing downstream of an intent can
tell "still walking" from "wedged".

So `EcsMovementSystem` prices every trip the tick it first sees it — the cost of a walk
is its length over its speed — and holds the result in `time_left`:

```
time_left = distance / speed * timeout_slack + timeout_grace
```

Both tunables are exported on `EcsMovementComponent` (2.5 and 0.5 by default), so a
patient hauler and a twitchy scout differ by authored values, not by code. Pricing from
the distance is the point: a trip across the map gets proportionally longer to make than
a trip next door, and one budget does not have to fit both.

When it runs out the destination is dropped exactly as if it had been reached — same
`has_destination = false`, same zeroed velocity, clock back to zero for the next trip.
**Giving up and arriving are the same event to every other system**, which is why nothing
else in the pipeline learned a field. The entity falls back down the ladder and decides
again with what it knows now.

What this deliberately is *not*: it does not remember what it gave up on. A forager that
times out on a berry may pick the same berry again next tick, and if the obstruction is
permanent it will loop. That is a re-target policy and it belongs in the brain, not in
the legs — the note here is that the entity is free to choose, where before it was not.

### Picking up is removing a component

`EcsPickupSystem` takes anything within the picker's own body radius. The whole of
"leaving the world" is `world.remove(berry, EcsPositionComponent)`:

- the node_sync query stops matching, so the sprite stops being drawn — nothing was told
  to hide it, and the node itself survives, because losing a position is not dying (§5)
- the brain stops seeing it, so nobody walks toward a berry in someone's pocket
- the spawner stops counting it against `max_loose`, so the bush resumes producing

One removed component, three consequences, no `is_carried` flag to keep in step.

**The berry stays a live entity.** This is the inventory version of the weapon pain case.
Module 8's `SimInventoryComponent` could not hold a live entity, so picking something up
took a **blueprint snapshot** of it and destroyed the world entity in the same breath — a
carried thing was a recipe for itself rather than itself. Here nothing is snapshotted and
nothing is destroyed: verified, a held berry reads `alive=true, has position=false,
has sprite=true, has pickable=true`.

Having an `EcsInventoryComponent` is what lets the food rung run, so a berry bush never
goes looking for berries and nothing had to tell it not to. `EcsPickableComponent` is what
separates a berry from the bush — both are sprites sitting in the world, only one answers
the forager's query.

Verified over 50 s: 14 entities → 54, held berries 0 → 30, 6 of 10 bags full, and **54
entities with only 24 drawn** — the held ones have no position. Each animal's `items`
array is its own (the manager's deep copy holds); every entity carries one slot.

Two known roughnesses, both fine at this scale: two animals can target the same berry and
the loser simply re-targets next tick (module 8 needed an explicit one-claim-per-entity
rule for this; here it self-corrects because the berry stops matching the query), and the
nearest-berry search is O(foragers x berries) with no range cap.

## 5. Lifecycle: one owner for structure

Applied from `DESIGN_CHANGE_HANDOFF.md`: §1, §2, §3 and §4 of that document. **§5 (the
Area2D sensor) was not**, and the reason is at the end of this section.

**`EcsEntityManager` replaced `EcsEntityFactory` and is now the only code that creates or
destroys an entity id, its component data, or its nodes.** Node creation used to be
smeared across two systems: `EcsRenderSystem` made a `Sprite2D` the tick an id started
matching its query, `EcsCollisionSystem` made an `Area2D` the same way. Two implicit
lifetimes, each with its own copy of the detach-before-free subtlety, and no kill path at
all — nothing in the module ever called `destroy_entity`.

Three pieces:

- **`EcsEntityManager`** (`ecs/ecs_entity_manager.gd`) — spawn, kill, and the node
  structure. It is a *service*, not an `EcsSystem`, so the systems that look nodes up on
  it are not reaching into another system. It creates and destroys; it never updates.
- **`EcsLifecycleComponent`** — a singleton inbox of `spawn_requests` / `kill_requests`,
  the same shape as `EcsSelectionComponent`. A system that wants something born or killed
  writes a note; it never acts itself.
- **`EcsLifecycleSystem`** — twenty lines that drain the inbox, **first** in the pipeline,
  so every birth and death in a frame lands at one instant and no system changes the
  shape of the world while another is walking it.

**Components declare the node they imply.** `EcsSpriteComponent` and `EcsBodyComponent`
each carry `const NODE_KIND: StringName`, naming a kind from `EcsConst`. The manager reads
that constant at spawn and builds exactly those children — it never switches on a
component *type*, the same reflective spirit as the inspector reading
`PROPERTY_USAGE_SCRIPT_VARIABLE`. A **constant, not a method**: the component states what
it implies and still does nothing, which is the `describe()` argument from §6a settled the
other way. A new node-backed component is one constant and no edit to the manager.

**`EcsRenderSystem` is retired**, split in two: node creation went to the manager, and the
per-tick mirror became **`EcsNodeSyncSystem`**, which writes texture, scale, tint, z-index
and position out of the components onto the sprite. (The design document's §4 only
mentioned position; the other four still need a writer.)

### Nodes are grouped per entity

`World/Entities` holds one `entity_<id>` container per entity, and that entity's nodes
hang under it:

```
World/Entities/
  entity_7/
    Sprite2D
    Area2dForBody
  entity_11/
    Sprite2D
```

`World/Bodies` is gone. The container carries the transform and its children sit at local
zero, so **position is written once per entity** however many concerns it grows —
`EcsNodeSyncSystem` moves the container, and `EcsCollisionSystem` no longer writes a body
position at all. One container freed takes the whole entity with it.

**The line this is one step away from, and does not cross:** in module 8 the node *was*
the entity. Here `entity_7` is a container — no script, no data, no state, nothing read
back off it, and deleting every one of them leaves the simulation complete. That is the
whole of the objection recorded in §8, and it is now a discipline rather than a structural
impossibility, so it is written into `ecs_entity_manager.gd`'s header as the place it was
agreed.

A new node-backed concern — `Area2dForSensor` for step 5, an action area, an
`AudioStreamPlayer2D` — is one `const NODE_KIND` on its component plus one branch in
`_make_node`. No pool to add, no parent to register, and nothing in `main.gd` changes.

### Perception and reach are areas, not arithmetic

Step 5, built on the structure above. Two components, two more areas under each
forager's container:

| component | area | radius | what it answers |
|---|---|---|---|
| `EcsSensorComponent` | `Area2dForSensor` | rabbit 280, monkey 420 | what can I see |
| `EcsActionComponent` | `Area2dForAction` | rabbit 34, monkey 50 | what can I touch |

`EcsSensorSystem` writes both lists — `sensor.perceived` and `action.reached` — and it is
the **only system besides `EcsCollisionSystem` that reads anything back off a node**.
`EcsForageSystem` and `EcsPickupSystem` read a list of ids off a component like any other
input; the exception stays two files wide.

The lists live on the components that own the radius (`radius` authored, list runtime),
the same shape as `EcsSpawnerComponent`'s `interval` / `cooldown`. The plan described a
separate `Perceived{ids}`; folding it in halves the component count per capability and
matches how every stateful component here is already written.

**The layer policy is declared on the components, not chosen by the manager.** Alongside
`NODE_KIND`, a component states `NODE_LAYER` (what others can detect of it) and
`NODE_MASK` (what it looks for), read the same reflective way:

| component | layer — findable as | mask — looks for | monitorable | monitoring |
|---|---|---|---|---|
| `EcsBodyComponent` | `LAYER_BODY` | `LAYER_BODY` | yes | yes |
| `EcsSensorComponent` | `LAYER_NONE` | `LAYER_BODY` | no | yes |
| `EcsActionComponent` | `LAYER_NONE` | `LAYER_BODY` | no | yes |

**A body is the only thing in the world that is detectable.** Sensors and action areas
carry no layer at all, so no sensor is ever reported to another sensor — without that the
n² does not go away, it moves into the physics server where you cannot see it in a
profile. Declaring a mask is what makes a node a looker and declaring a layer is what
makes it findable, so `EcsEntityManager` derives `monitoring` and `monitorable` from the
declaration and has no opinion of its own.

That also removed the last per-kind branch: `_make_node` is now "the sprite, or else an
area built from what the component declared". **A new area kind is a component with three
constants and no edit to the manager at all.**

**Why the body's mask is not `LAYER_NONE`:** soft collision *is* two bodies overlapping,
and nothing else in the module detects bodies at a body's own radius, so a body that looks
for nothing leaves `EcsCollisionSystem` with no pairs. Measured at 3,200 entities, that
mask costs nothing anyway — 158.0 ms/tick with it, 162.0 ms without (collision 25.8 ms vs
25.1 ms), i.e. inside the noise. The body-body broadphase is free; what is not free is
perception, and that is already layered.

**The cull is physics; the decision is arithmetic.** `reached` is what the server saw at
the end of the last step, so it can name something that has since moved. Acting on the
list alone re-took a berry that had been dropped 400 px away — a real bug, caught by the
test. So `EcsPickupSystem` confirms each of the handful the broadphase handed it against
the components, which are the only truth. What must not be O(n) is the cull, not the
confirmation of three items.

**Two consequences worth knowing:**

- **A berry now has an `EcsBodyComponent`** (radius 14). It has to: a sensor can only see
  a body, and reach is the berry's body meeting the action area. "A berry is a sprite and
  nothing else" is no longer true.
- **Solid and movable became different questions.** A berry has a body but no
  `EcsMovementComponent`, and `EcsCollisionSystem` moves only what can move. Without that
  a forager shoves the berry it is walking toward and chases it across the arena. No
  `is_static` flag — component presence, and the same rule holds for a tree.
  **Since extended: blocking became a third question**, `EcsBodyComponent.is_solid` — see
  "Collision is soft" in §1. A berry has a body and is not solid at all.

Keep each forager's action radius above its own body radius, or soft collision stops it at
body-touch before its reach arrives. Rabbit: body 22, reach 34. Monkey: body 36, reach 50.

### The thing this refactor had to get right

Node lifetime used to be **inferred** from a query and is now **commanded**, and those two
models disagree in exactly one place: an entity that stops matching without dying.

`EcsPickupSystem` removes a berry's `EcsPositionComponent`. The berry is alive — it is in
someone's bag — it is simply not anywhere. The old render system freed its `Sprite2D` as a
side effect of the query no longer matching. Correct, but *accidental*: it welded node
lifetime to component presence, and there was no way to put the berry back down.

So the split is now stated. **Node lifetime tracks the entity; what a node does tracks the
components.** The manager frees nodes only on kill. `EcsNodeSyncSystem` hides a sprite
whose entity has no position and shows it again when one returns; `EcsCollisionSystem`
switches a body's monitoring off and on the same way, so a held berry does not go on
shoving whatever walks over the spot it was picked up from.

### Its test

`tests/lifecycle_test.tscn` — 66 checks, re-runnable, exit code 0 only if all pass:

```bash
"$GODOT" --headless --path . "res://9. EcsSystem/tests/lifecycle_test.tscn"
```

It exists because `DESIGN_CHANGE_HANDOFF.md` §9 proposed re-running the Step-2 combat
acceptance test as proof the refactor disturbed nothing, and that test left the tree with
the combat layer at `d50aaf9`. This covers the divergence above instead: declared nodes
get built and undeclared ones do not, pickup hides a sprite without freeing it, dropping
shows *the same node* again, a body with no position stands down and comes back, kill
takes data and nodes together, a spawner note is fulfilled on the next tick and harvested,
and two stacked bodies still push apart (2.0 → 44.0 px) through areas the collision system
no longer creates.

It then covers the sensor layer: a forager sees a berry 100 px away and not one at 900,
seeing is not reaching, an immovable bush is not shoved by the walker it stops, a berry on
the ground is walked over rather than bumped into, a trip that cannot finish is given up
on rather than pushed at forever, and — end to end, with forage and movement driving — a rabbit spots a berry 200 px
off, walks to it, and takes it on arrival, stopping at arm's length rather than on top
of it.

### Not yet measured

`DESIGN_CHANGE_HANDOFF.md` §5 justifies the sensor by 500-entity scaling, and **that claim
is still unmeasured here**. The world is 12 entities. A 420-px sensor covers ~135× the area
of a 36-px body, so §9's collision table does not predict sensor pair counts, and the layer
split above is what keeps it from being quadratic — not a guarantee that it is cheap. Worth
a bench before anything depends on the number.

---

## 6. What was removed, and how to get it back

Everything below was built, worked, and was cut to keep the core readable. It is all in
git at **`928b9d1`**:

```bash
git show 928b9d1 -- "9. EcsSystem"                  # see it
git checkout 928b9d1 -- "9. EcsSystem"              # take the whole module back
git checkout 928b9d1 -- "9. EcsSystem/systems/ecs_attack_system.gd"   # or one file
```

**The combat pipeline** — 10 components (`aggression`, `armor`, `attack_intent`, `broken`,
`crit_chance`, `damage`, `dead`, `durability`, `equipped`, `health`) and 8 systems
(`aggression`, `attack`, `crit`, `damage`, `death`, `durability`, `equip`,
`weapon_carry`), plus `ecs/ecs_event.gd` and `events/ecs_damage_event.gd`.

It was the plan's step 2 and it landed clean. Armour was added to a live entity without
the attack code changing; crits were added by writing one system and appending one line to
the scheduler; a broken weapon fell back to fists with no `if weapon.broken` anywhere;
"attackable" was never a flag, only the target query asking for `EcsHealthComponent`.
**The evidence for the rewrite is in that commit, not in the working tree.**

**The observability layer — RESTORED, see §6a.** What went out was the
`selection`/`selected`/`commands` components, `EcsSelectionSystem`, `EcsInspectSystem`,
`EcsCensusSystem`, `EcsCommandSystem`, `ecs_selection_marker.gd`, `ui/ui.tscn` + `ui.gd`,
and the four `ecs_*` signals in `System/EventBus.gd`. Two pieces of it were evidence
rather than scaffolding: picking was a distance query over `EcsPositionComponent` rather
than a physics hit, and the inspector's tabs were built by reflection over
`PROPERTY_USAGE_SCRIPT_VARIABLE` with nothing in the file naming a component type.

**Also trimmed from files that stayed:** `EcsWorld` lost singletons, the frame-event API
and `components_of()`/`count()` (the enumeration accessors the inspector needed —
singletons and `components_of()` came back with §6a, `count()` and the event API did not);
`EcsSystem` lost `enabled`; `EcsScheduler` lost `find()` and the end-of-frame
`clear_events()`. The crocodile and dagger blueprints were deleted and the monkey
rewritten as a plain wanderer, leaving two entity types; `world1.tres` went from 33
placements to 10 — 5 rabbits and 5 monkeys.

Note one demo went with the dagger: it was the only entity with **no**
`EcsMovementComponent`, so it showed "capability is component presence" — a prop that
cannot move, with no `is_static` flag and no branch. Both current types move. Bringing it
back is one blueprint plus a placement, no code.

## 6a. The observability layer, brought back

Restored from `928b9d1` on request. What came back verbatim: `EcsSelectionComponent`
(the click inbox singleton), `EcsSelectedComponent` (the tag), `EcsSelectionSystem`,
`EcsInspectSystem`, `EcsCensusSystem`, `EcsSelectionMarker`, `ui/ui.tscn` + `ui.gd`, and
three of the four EventBus signals. `EcsWorld` got `add_singleton()`/`get_singleton()`
and `components_of()` back, and nothing else.

Three deliberate differences from what was cut:

- **`EcsCommandSystem` and `EcsCommandsComponent` did not come back.** They existed to
  queue the F3 "give the crocodile armour" demo, which needs the combat layer.
- **The pipeline panel did not come back.** It reported the run order and the F2 crit
  toggle, and it depended on `EcsScheduler.find()` and `EcsSystem.enabled` — both removed
  in the strip. `ecs_pipeline_changed` was dropped with it.
- **The marker's ring shows `EcsBodyComponent.radius`, not an attack reach.**
  `EcsAggressionComponent` is gone; the body radius is the reading that still exists. An
  entity with no body gets the centre dot alone.

The pipeline is now thirteen stages: `selection` sits after `pickup` and before `node_sync`,
and `census > inspect` run last, after `debug`. All three added stages are pure readers or
write only the selection tag, so the simulation is unchanged by their presence.

**The restore is its own evidence for reflection.** The inspector was written when the
world had `name/position/sprite/movement/wander` and a combat layer. Clicking a monkey
now yields tabs for `shape`, `low_brain` and `inventory` — components that did not exist
when `EcsInspectSystem` was written — with no edit to the inspector, the panel, or the
components:

```
NAME: monkey_0 (monkey)
ENTITY  { id: #6, blueprint: Monkey,
		  components: name, position, shape, sprite, movement, low_brain, inventory, selected }
  Shape      { radius: 36.00 }
  Movement   { speed: 130.00, arrive_radius: 6.00, destination: (-761, -418),
			   has_destination: true, velocity: (-115, -60) }
  Low Brain  { radius: 420.00, pause_min: 0.20, pause_max: 1.20, pause_left: 0.00 }
  Inventory  { capacity: 5, items: [] }
  Selected   { }
```

**That last line is the open question made concrete.** `EcsSelectedComponent` is a pure
tag, so reflection gives it a tab with no fields in it. Module 8 would have hidden it by
returning `{}` from `describe()` — but that is a *method on a component*, which module 9's
first rule forbids. If the fix is wanted, the option that keeps components method-free is
a `const` block read via `get_script_constant_map()` (verified to work in 4.7), which is
data rather than behaviour and can say tab / merge-into-entity / hide. **Not implemented
— it is a presentation-policy decision that belongs with §8.**

## 7. Next, per the plan

**Where the plan actually stands: steps 3 and 5 are done, 6 is half done, 4 is next.**

**Step 3 is most of the way done.** The plan asked for "inventory and pickup as
relationships (`Inventory{item_ids}`, one system owning the move, so double-claim is
structurally impossible)" — that is exactly what `EcsInventoryComponent` and
`EcsPickupSystem` are. Double-claim is not merely prevented, it stopped being a category:
the berry drops out of the query the moment it is taken, so the second forager re-targets
without anything arbitrating. What step 3 still wants is **eating** — a
`EcsConsumableComponent` and a `ConsumeSystem`, which needs step 4's bars to be worth
doing.

Before starting any of the rest, decide whether it builds on this stripped core or on
`928b9d1`'s fuller one — steps 6 and 7 assume the combat layer that was cut.

- **Step 3 (remainder)** — eat via `ConsumeSystem`, once there is a hunger bar to feed.
- **Step 4** — hunger/fatigue/health as components with a system each. This is the
  natural next step: the forage loop currently has no *reason*, and hunger is the reason.
- **Step 5 — done, and not the way the plan said.** `EcsSensorSystem` writes
  `perceived`/`reached`, but off physics areas rather than a distance query: the
  broadphase does the culling in C++, which is why the brain's nearest-berry scan ranks a
  handful of neighbours instead of every berry in the world. The plan's node-free version
  is the fallback if areas ever stop paying, not a regression to make.
- **Step 6** — FSM brain writing move/eat/attack intents. Note the decision ladder is
  **already built** — `EcsLowBrainSystem` became that FSM when the stateless
  `forage > low_brain` run-order ladder was folded into it. What step 6 still wants is
  intent components, and states above wandering and eating.
- **Step 7** — GOAP planner as a pure function over a symbolic snapshot, run off-frame
  under a replan budget.

## 8. Open arguments — node structure and data structure

**These are unsettled and deliberately so.** Claude made recommendations during the
session that built this; they were **not accepted**, and the author has said explicitly
that both questions are still to be argued out. Nothing below is a plan. Treat it as the
state of a disagreement, so the argument can resume with its context rather than be
re-derived — and do not quietly implement any of it.

### The node-structure argument — **SETTLED, see §5**

The author chose **one container per entity, children per concern**, and it is built. Kept
here for the reasoning, not as a live question.

- **Pools per concern** — what existed before. Each system owned exactly what it needed
  and a concern could be deleted in one piece. Rejected: two parallel pools have to be
  cross-referenced by id to answer "what does entity 12 own", and position was written
  separately by each.
- **One container per entity, children per concern** — **chosen.** Position written once
  and inherited, one lifetime, one thing to free, and the remote scene tree reads as a
  list of entities. The recorded objection was that a per-entity node carrying sprite,
  area and audio is one step from module 8, where the node *was* the entity. The answer
  held to in §5: the container holds no script, no data and no state, and nothing is read
  back off it — so it stays a discipline, and `ecs_entity_manager.gd`'s header is where
  that was agreed. If something ever hangs state on a container, that is the line.
- **No nodes — `PhysicsServer2D` / `RenderingServer` RIDs.** Cheapest, and an RID is
  honest data rather than a Node reference. Costs editor visibility and manual lifetimes.
  The author wants Godot nodes for collision, sprite drawing, animation and sound, which
  argues against it — never argued *through*, and now moot for the foreseeable structure.

Still unresolved: whether the collision `Area2D`s should exist at all, given they are the
one place the "nothing reads back off a node" rule is bent. The debug overlay no longer
draws the body circle — with real `CollisionShape2D`s in the tree, Godot's **Debug >
Visible Collision Shapes** shows the shape the physics server actually uses.

### The data-structure argument

What exists: `_store = { Script : { entity_id : EcsComponent } }`, components as
field-only `Resource` subclasses, queries intersecting tables driven from the rarest.

Open questions, none settled:

- Should a node or RID handle ever live **inside a component** (the `EcsBodyComponent`
  idea)? It would make `EcsCollisionSystem` pure behaviour and split lifecycle from
  resolution — at the cost of the data layer knowing the scene tree exists.
- Should storage stay dictionary-of-dictionaries, or become archetype/packed arrays? The
  API would not change (`ecs_world.gd`'s header already says so). **This one now has a
  number — see below.**
- Should components be `Resource` at all, given `.tres` authoring only ever uses the
  exported half and every component now carries runtime-only fields beside them?

Nothing here is blocking step 4. It is blocking a decision about what module 9 *is*, which
is a different thing and worth taking the time over.

#### Measured: 81% of a system is finding its components, not using them

The argument ran on the assertion that "the measured bottleneck is `get_component` call
overhead" without anything measuring it. `tests/stress_test.tscn` now probes it, on
`EcsMovementSystem` because it is the purest per-entity stage in the pipeline — two
components in, one position out, no neighbours. At 2,000 entities (**measured before
the trip clock went in** — the stage now prices and decrements a budget per entity, so
re-run before leaning on the absolute numbers; the 25/67/19 split is the durable part):

| | ms | µs/entity | share of the stage |
|---|---|---|---|
| `query()` alone | 1.49 | 0.745 | 25% |
| the two `get_component` calls | 4.03 | 2.017 | **67%** |
| the identical arithmetic, refs pre-gathered | 1.15 | 0.573 | 19% |
| **the stage as it runs** | **6.05** | **3.024** | 100% |

**Finding the components costs four times what using them costs**, and `get_component` is
~1.0 µs per call — a double hashed lookup (`_store[Script]` then `[id]`) plus Variant
boxing, paid by every system for every component it reads, every tick.

**What that says for archetypes.** The ceiling on a stage like this is **~5x** (3.024 →
0.573 µs/entity): packed arrays hand a system its components already in iteration order,
which is precisely the 25% + 67% above. Across the whole pipeline it is smaller, because
`sensor` — 42% of the frame — is physics queries rather than component access; the
non-sensor stages are roughly 47% of the tick and mostly access-bound, so a whole-tick win
of ~1.6–2x is the honest expectation.

**The finding that changes the shape of the argument:** that 0.573 µs was measured over
pre-gathered arrays of `Resource` **references**, pointer chase included. So the third
bullet above is *not* upstream of the second — **you do not have to stop using `Resource`
to get most of the win.** The 2.0 µs is hashing and boxing, not object indirection. Packed
arrays of Resource refs capture nearly all of it, and dropping `Resource` stays a separate,
larger, later question.

**The cost archetypes carry**, unmeasured: adding or removing a component mid-life moves an
entity between archetypes, and this module does that on every berry pickup
(`world.remove(berry, EcsPositionComponent)`) and every selection change. That is a handful
of entities per tick against thousands iterated, so amortisation looks favourable — but it
is the thing to measure before committing, not after.

**Still not a recommendation to build it.** Staggering the sensor is worth ~32% off the
tick for a few lines and no architectural commitment; caching the area in
`EcsCollisionSystem` is free (§9). Those are the same order of payoff for a tiny fraction
of the cost, and they should be spent first — the measurement above keeps.

## 9. Measured performance, on the machine that built this

### How many entities before it falls over

`tests/stress_test.tscn`, re-runnable, same pipeline main.gd builds. It reports four
things: the population ramp, every stage's cost at every population (in ms and in
µs/entity), a census of the work the pipeline actually chewed on, and a probe splitting one
stage into query / fetch / arithmetic (§8).

```bash
"$GODOT" --headless --path . "res://9. EcsSystem/tests/stress_test.tscn"
```

**~4,450 entities is where a tick costs 250 ms — 4 FPS.** Half rabbits, half monkeys, on a
jittered 90 px grid so the neighbourhood each entity sees stays the same size as the
population grows; crowding a fixed arena would measure the stacking, not the population.

| n | tick | implied FPS | ms/entity |
|---|---|---|---|
| 100 | 3.80 ms | 263 | 0.038 |
| 400 | 17.12 ms | 58.4 | 0.043 |
| 1600 | 75.58 ms | 13.2 | 0.047 |
| 3200 | 156.74 ms | 6.4 | 0.049 |
| 4000 | 215.18 ms | 4.6 | 0.054 |
| **4400** | **249.67 ms** | **4.0** | 0.057 |
| 4600 | 261.26 ms | 3.8 | 0.057 |

Three consecutive ramps put 4,400 at 247.39, 248.40 and 249.67 ms — under 1% apart — so the
curve is reproducible; call the crossing **4,450 ± 100**. Useful reference points interpolated off
it: **60 FPS at ~400 entities, 30 FPS at ~750, 10 FPS at ~2,150.**

Both of those ramps are ~6–7% faster than the ramps taken before `EcsEntityArea` and the
module 8 deletion, and **that gain is not attributed to either**: the isolated A/B below
puts the typed id at ~1%, and a cross-ramp delta is not evidence of anything — which is
the same trap documented in the next section. Machine state accounts for differences this
size.

Cost is near-linear — 0.038 ms/entity at 100 rising only to 0.057 at 4,600 — so nothing
here is quadratic. The layer split (only bodies are detectable) is what bought that;
sensors reported to each other would bend this curve upward hard.

**Every stage at every population**, same run. The stress test prints both tables; the
second is the one that says something.

Milliseconds per tick:

```
     n    sensor collision node_sync    pickup  movement    forage low_brain     other      TICK
   100      1.40      0.69      0.48      0.45      0.29      0.27      0.19      0.04      3.80
   400      7.07      3.02      2.10      1.89      1.17      1.04      0.77      0.05     17.12
  1600     31.50     12.84      9.19      9.12      5.08      4.40      3.38      0.06     75.58
  3200     65.22     27.73     18.03     18.27     10.74      9.35      7.34      0.08    156.74
  4000     92.86     35.98     25.65     23.87     14.59     12.24      9.92      0.07    215.18
  4400    108.04     42.84     29.09     27.96     16.71     13.65     11.30      0.07    249.67
  4600    110.99     45.44     31.03     29.12     18.53     14.24     11.84      0.07    261.26
```

Microseconds **per entity** — the same numbers divided by n, which is where the shape is:

```
     n    sensor collision node_sync    pickup  movement    forage low_brain      TICK
   100    13.974     6.931     4.803     4.521     2.856     2.668     1.863    37.985
  1600    19.689     8.022     5.745     5.702     3.178     2.751     2.111    47.235
  4600    24.127     9.878     6.745     6.330     4.029     3.096     2.574    56.795
```

**Roughly 40% of the per-entity rise is memory, not algorithms.** `movement` has no
neighbour dependency at all — two components in, one position out — and still went 2.86 →
4.03 µs. `node_sync` (+40%), `pickup` (+40%) and `low_brain` (+38%) match it. That is the
working set outgrowing cache, and no algorithmic change moves it.

**Only `sensor` rises faster than that baseline** (+73%), and that part is a rig artifact,
not the system: at n=100 the grid is 900 px across, so most entities are edge cases with
truncated neighbourhoods, and the edge fraction shrinks as the grid grows. Per *id
returned* the cost is flat.

`low_brain` is the least stable stage across runs — 11.8 ms here, 18.8 ms in an earlier
6400 run — because it only works on entities with no destination, and how many that is
depends on where the berries landed. Read it as a band.

### What each stage is actually paying for

The stress test also counts the work, so a stage can be read per unit of work instead of
per entity. At 4,600, per tick: sensor areas returned **245,955** ids (53.5 each), action
areas **8,230** (1.8 each), body areas **5,052** overlap pairs (1.1 per body).

- **`sensor` — 111.0 ms, 42.5%.** Almost exactly *ids returned*: 53.5 x 0.437 µs ≈ 23.4 of
  its 24.1 µs/entity. **97% of those ids come from the sight area, 3% from the reach area**,
  and ids scale with πr² — the monkey's 420 px radius covers 2.25x the rabbit's 280. Cost
  here is a radius decision as much as a code one.
- **`collision` — 45.4 ms, 17.4%.** Not the 5,052 pairs; it is the per-entity walk. It
  still calls `_manager.node_for()` **every tick per entity** — the exact lookup that was
  cached out of the sensor and was worth 14% there — and `node_for` builds a throwaway
  dictionary on every call (`_nodes.get(id, {})` evaluates `{}` eagerly). ~4,600 wasted
  allocations a tick from this stage alone. **Unfixed; it is the cheapest win left.**
- **`node_sync` — 31.0 ms.** Pure per-entity: a container lookup, two components, five
  property writes across two nodes. Its curve is the cache baseline and nothing else.
- **`pickup` — 29.1 ms, 11.1%** to pick up nothing. Not the pickups — the walk: 4,600
  entities, two components each, then one `world.has()` per id in reach (8,230, all false
  here). It costs about what `node_sync` costs while doing far less, which is the tell
  below.
- **`movement` — 18.5 ms.** The floor for "query and read two components". See §8.
- **`forage` / `low_brain` — 14.2 and 11.8 ms.** Cheapest per unit of work (forage is
  0.058 µs per perceived id) because both bail early for most entities.
- **Everything else — 0.07 ms combined.** lifecycle, spawner, selection, debug, census and
  inspect together are 0.03% of the tick: drained-empty or early-outs.

### Two attempts at the sensor cost, measured properly

**On method first, because it bit.** Comparing a stage across two *ramp* runs is not valid:
a run that reaches 4,300 after building and tearing down nine smaller worlds is slower at
4,300 than a run that starts there, and the gap shows up in **every** stage, including ones
the change never touched. A first pass at this claimed 29% off the sensor from caching, on
exactly that confound. The numbers below are isolated runs — one population per process —
which is the only way a stage-level delta means anything.

Isolated, n = 4,300, one variable at a time:

| variant | sensor | ms/entity | tick |
|---|---|---|---|
| no cache, typed id | 100.13 ms | 0.0233 | 219.96 ms |
| cached, `get_meta` id | 86.64 ms | 0.0201 | 206.53 ms |
| **cached, typed id** (current) | **86.04 ms** | **0.0200** | **204.44 ms** |

**Caching the area and shape: −14% on the sensor stage, −7% on the tick.** It used to
resolve each area through the manager and walk to its `CollisionShape2D` by NodePath every
tick — at 4,300 animals that is 8,600 dictionary lookups and 8,600 path resolutions a tick
— and hand each component a freshly allocated array. Now the area and its circle are
resolved once per entity and the arrays are filled in place. The 4 FPS crossing moved
3,900 → ~4,250, which is the same ~7% expressed in a different unit.

**`EcsEntityArea` replacing `get_meta(&"entity_id")`: ~1%, inside noise.** The hypothesis
was that a hashed metadata read, once per neighbour per sensing entity per tick, would be
costing real time. Measured, it was not. The class was kept anyway — a typed field beats a
magic string and it costs nothing — but **it is not a performance feature and should not be
described as one.**

**`sensor` is still ~42% of the frame**, and what is left is real work: one
`get_overlapping_areas()` per entity carrying an `EcsSensorComponent`, one more per entity
carrying an `EcsActionComponent`, and one field read per neighbour each call returns.

Note what does *not* pay. It is component presence, not foraging: a rabbit and a monkey
carry both components and cost two calls each, while a berry and a bush carry neither and
cost nothing — they are only ever detected, never detectors. So the stress world, which is
all animals, runs 2 x 4,600 = 9,200 calls a tick, while the shipped world charges only its
10 animals and nothing for the 12 berries and bushes. (The two sets coincide today only
because `EcsForageSystem` requires a sensor and `EcsPickupSystem` requires an action area.
A guard that watches but never forages would still pay for its sensor.)

The structural lever is untouched: **every sensing entity pays every tick**, and nothing
needs that. Slicing the query so a quarter of the entities are scanned per tick is
a ~4x cut to the dominant cost for four ticks of perception latency, which timer-based AI
never notices. That is lever 1 in §9 below, and it is still the biggest single win available.

**Two caveats.** This is the **simulation only** — headless draws nothing, so a windowed
run is lower, never higher. And spawning is not free: 4,000 entities take ~600 ms to
build, because each forager gets four nodes.

### The older numbers, from before the sensor layer

Intel Iris Xe, GDScript, per tick. Stale the moment the systems change; the shape is the
durable part.

| n | collision (Area2D) | collision (the O(n²) it replaced) |
|---|---|---|
| 100 | 1.56 ms | 3.82 ms |
| 400 | 6.56 ms | 52.12 ms |
| 1600 | 21.33 ms | ~800 ms |

A simple linear system costs **~4–6 µs per entity per tick** (`low_brain` 4.0,
`movement` 4.4, `render` 5.8, `debug` 13.5 — turn the overlay off when measuring anything
else). Budget at 60 Hz: ~30–40 such systems at 100 entities, ~15–20 at 200.

### The levers, ranked by payoff over cost

**None of these are taken.** Ordered so the cheap ones get spent before anything
architectural is committed to.

1. **Stagger the sensor across ticks.** `sensor` is 42% of the frame and every sensing
   entity re-scans every tick. Slice the query so a quarter run per tick: **~4x off the
   dominant stage, ~32% off the tick**, for four ticks of perception latency that
   timer-based AI cannot notice. A few lines, no architectural commitment.
2. **Shrink the monkey's sight radius.** Sensor cost is ids returned and ids scale with
   πr². 420 → 280 px would cut ~38% of all ids — sensor ~111 → ~68 ms — with **no code at
   all**, if the gameplay tolerates it.
3. **Cache the `Area2D` in `EcsCollisionSystem`, and fix `node_for`.** It still resolves
   the body through the manager every tick — the lookup that was worth 14% in the sensor —
   and `node_for`'s `_nodes.get(id, {})` allocates a throwaway dictionary on every call,
   which every caller pays. Small, free, uncontroversial.
4. **Decouple sim tick from frame rate.** A colony sim does not need 60 Hz simulation.
   Running the scheduler at 10–20 Hz is a 3–6x headroom multiplier and costs nothing —
   the scheduler already takes `delta`.
5. **Archetype storage.** ~1.6–2x on the tick, and the only lever that touches the
   per-entity access floor. It is also a rewrite of `EcsWorld`'s storage and an open
   argument — §8 has the measurement and the case. Last, not first.

The first tick after a world is built creates every pooled node at once: 5 ms at 100
entities, 70 ms at 400, 345 ms at 1000 — 97% of it `Area2D` creation. Behind a loading
screen this is free; for a mid-game spawn wave it would need a per-tick creation cap.
