# Colony Sim — Concept Model

> Simple colony sim built to prototype AI (Utility + GOAP) on a shared entity model.
> Godot 4 · node-composition ECS · **concept only, no optimization yet**
> Project folder: `project/godot/compilationpack`
>
> **This document describes the TARGET design, not what is built.** The running prototype has two
> entity types (`animal`, `berry`) and a temporary spawner, and exists to exercise component
> interaction before GOAP lands. The three-creature experiment, predation, bars and the planner
> below are all still ahead. For what actually exists today, read `HANDOFF.md`.
>
> Two places where the build has already diverged, deliberately, are flagged inline as
> **[AS BUILT]**: how eating resolves (§2) and where per-effect data lives (§4). Both are
> argued out in `HANDOFF_PSEUDOCODE.md` §11–§12.

---

## 0. Design Intent

A minimal ecosystem with three creature types on one map:

- **Type1 (herbivore, vigilant)** — eats berries (VEGIE). 10 on the map. Flees Type2. High detection (1.3×), slow run.
- **Type2 (carnivore, predator)** — eats meat (MEAT). Kills prey (Type1/Type3), carries an `AttackComponent`, runs 1.4× faster.
- **Type3 (herbivore, fast)** — same as Type1 (VEGIE, flees Type2), but **low detection, much faster than Type2**. A data-only variant (inherited scene + two constants) to test the theory below.

**The theory under test:** is *awareness* or *speed* the stronger survival trait? Type1 (early warning, slow) vs Type3 (late warning, fast) on the same map, same predator. Hypothesis: Type1 survives ambushes but dies cornered; Type3 survives chases but dies to surprise.

Both creatures are **gather-then-eat** (multi-step), so they share one brain (see §7). The prototype's real purpose: build one shared entity/component/action model, and exercise **Utility for need-arbitration + GOAP for planning** on top of it.

**Framing note:** Godot's node tree is not a true data-oriented ECS. This is *node-composition ECS* — entity = container node, components = child nodes. Right choice for a concept model. Revisit only if entity counts blow up.

---

## 1. Scene Structure

Rule: **everything is an Entity** — creatures, props (bush), *and* items (berry, meat). There is one bare base scene, one factory, and one def format. No Interactable or Item families.

```
Main.tscn                     ← entry point / world root
└── Entities (Node2D)         ← EVERYTHING (creatures, props, items) spawned by
                                 EntityFactory from EntityCatalog blueprints + a WorldDef list

Entity.tscn                   ← BARE BASE (no per-type scenes)
└── Node2D  (class_name Entity)
    ├── Sprite2D                  ← texture set from def
    └── Body (Area2D + CollisionShape2D) ← the entity's PRESENCE: how OTHER
                                       sensors detect it, and what OTHER actions
                                       reach. The base is a plain Node2D — nothing
                                       collides, so a physics body earned nothing;
                                       movement integrates position itself. The
                                       area is monitorABLE but not monitorING: it
                                       exists to be found, not to find.
    # ALL behavior components (Health, Hunger, Fatigue, Inventory, Movement,
    # Sensor, Action, Brain, [Attack]) are added AT RUNTIME by EntityFactory,
    # per the EntityDef's component list. Sensor's own detection radius and
    # Action's own reach are their own areas on the ACTOR (they vary per def),
    # NOT this shape.
    # Even a berry uses this same base: Sprite2D + Body + EatableComponent + PickUpAbleComponent.
```

**Everything is an entity** — creatures, props, and items alike — assembled from an `EntityDef` by a factory. What a thing *is* = which components its def lists:

### Entity definitions & factory (data-driven)

The bare `Entity.tscn` above carries no behavior. `EntityFactory` builds each entity at runtime from an `EntityDef`'s component list. New creature = new `.tres` — no scene, no code.

`ComponentDef` is a small Resource hierarchy; each subclass holds one component's config and knows how to build + configure its Node:

```gdscript
class_name ComponentDef extends Resource   # abstract
func build_into(entity: Entity) -> void     # instantiate + configure + add_child

# subclasses (each with its config fields):
HealthDef {max}   HungerDef {max, drain}   FatigueDef {max, drain}
InventoryDef {}   MovementDef {walk, run}  SensorDef {detection}
ActionDef {reach} AttackDef {damage}       # prey omit AttackDef
BrainDef {diet, actions: Array[Action], goals}

class_name EntityDef extends Resource
var id: String
var sprite: Texture
var components: Array[ComponentDef]
```

The factory stays dumb — it never switches on component type (open/closed: a new component = a new `ComponentDef`, factory untouched):

```gdscript
func spawn(id: String, pos: Vector2) -> Entity:
    var def := catalog.get(id)
    var e := ENTITY_SCENE.instantiate()
    e.sprite.texture = def.sprite
    for cdef in def.components:
        cdef.build_into(e)                  # polymorphic
    entities.add_child(e); e.position = pos
    return e
```

The three creatures become **pure data** — "basically the same" made literal:
- `type1.tres`: Sensor `1.3D`, Move run `R`, Brain diet `[VEGIE]`, actions `[GetBerry, Eat, Sleep]`, goals incl. Flee
- `type2.tres`: Sensor `D`, Move run `1.4R`, **+ AttackDef**, Brain diet `[MEAT]`, actions `[Hunt, HarvestMeat, Eat, Sleep]`
- `type3.tres`: = `type1` with Sensor `0.7D`, Move run `2R`

Props and items are just entities with small component sets:
- `berrybush.tres`: `HarvestableComponent` (harvest → spawns berry) — no Health/Movement/Brain (always clean-harvest; add Health later to deplete it)
- `berry.tres` / `meat.tres`: `EatableComponent` (eat) + `PickUpAbleComponent` (pickUp) — no Health/Movement/Brain

Adding Type4 = copy a `.tres`, change two fields. **Tradeoff:** no per-type scene to open/tweak in the editor (all wiring in code) and a little more scaffolding before first pixel — the right trade when the variation *is* data.

### Blueprints vs placements — two lists, not one flat file
So 10 Type1s don't each repeat their component block (edit-once, no drift):
- **EntityCatalog** — the *blueprints*: `id → EntityDef {texture, components + default settings}`. One per **type** (creature types, berry, meat, bush).
- **WorldDef** — the *placement list* (the "long list"): each entry `{name, type, position, overrides?}`. References a blueprint by `type`, specifies only what's unique — position, plus any per-instance tweak (e.g. one Type1 starting at `{hunger: 30}`).

```gdscript
func spawn_world(world: WorldDef):
    for place in world.entries:
        var def := catalog.get(place.type)          # blueprint
        var e := build(def)                          # bare Entity + its components
        apply_overrides(e, place.overrides)          # per-instance tweaks
        e.position = place.position
        entities.add_child(e)
```
Component settings live once in the blueprint; a placement overrides only when it differs. (Everything-inline-per-entity also works if you want zero indirection — just more to maintain.)

---

## 2. Components

Entity is the **mediator**. Components are dumb state holders; the Brain is the only smart one. They talk via signals (state changes) or through the entity (commands) — never hard-path to siblings.

| Component | Holds | Key signals | Key methods |
|---|---|---|---|
| `HealthComponent` | `hp` (0–100) | `died`, `health_changed(v)` | `take_damage(x)`, `regen(x)` — **target logic for `attack`** (reduce/die) |
| `HungerComponent` | `hunger` (fullness 0–100) | `hunger_changed(v)`, `starving` | `feed(points)`; **actor marker for `eat`** (no logic) |
| `FatigueComponent` | `energy` (0–100) | `energy_changed(v)`, `collapsed`, `rested` | `spend(e)`, `restore(e)` |
| `InventoryComponent` | `items: Array[ItemData]` (def refs, not nodes) | `inventory_changed` | `add(data)`, `take(food_type)` — pairs with `PickUpAbleComponent` |
| `MovementComponent` | walk/run speed, gait, `follow_target`, `last_known` | `arrived(target)`, `lost_target` | `move_to(pos, gait)`, `follow(entity, gait)`, `stop()` |
| `ActionComponent` | `action_reach` (radius) | `action_done(action)` | `in_reach(target)`, `perform(id, target)`, `auto_pickup(diet)` |
| `EatableComponent` *(target logic)* | `food_type`, `hunger_value` | `eaten(actor)` | resolves **eat**: `actor.hunger.feed(hunger_value)` + self-destroy; pairs with actor `HungerComponent` |
| `HarvestableComponent` | `harvest: ActionDef` (drops which entity, count, damage, cost) | `harvested(actor)` | advertises **harvest** — spawns another entity |
| `PickUpAbleComponent` | `item_data` | `picked_up(actor)` | advertises **pickUp** — pairs with actor `InventoryComponent`; destroys self, stores data |
| `SensorComponent` | perceived bodies | `perception_updated` | `get_interactables()`, `get_prey()`, `get_threats()` |
| `BrainComponent` | current goal + plan | — | `_on_think()` |
| `AttackComponent` *(actor capability)* | `action_id="attack"`, `damage` | `attacked(target)` | declares capability + damage; **no logic** — target's `HealthComponent` resolves |

**Perceive / travel / act split:** `SensorComponent` finds things, `MovementComponent` travels, `ActionComponent` owns `action_reach` and runs the chosen action on a target.

**Do vs receive — actions have a direction.** Each component tags its actions as **do** (this entity can perform it) and/or **receive** (this can be done to this entity). The entity aggregates two sets across its components:

| Component | do | receive |
|---|---|---|
| `AttackComponent` | attack | — |
| `HealthComponent` | — | attack |
| `HungerComponent` | eat | — |
| `EatableComponent` | — | eat |
| `InventoryComponent` | pickUp | — |
| `PickUpAbleComponent` | — | pickUp |
| `ActionComponent` | harvest* | — |
| `HarvestableComponent` | — | harvest |
| `FatigueComponent` | sleep | — |

\* harvest's do-side is the generic performer (`ActionComponent`) for now — promote to a `HarvesterComponent` if it ever needs its own data.

**Interaction = do ∩ receive.** When A's sensor detects B, A computes `A.do_actions() ∩ B.receive_actions()` — the actions A can perform that B will accept. That intersection is the entire A→B menu; the Brain scores it (utility §7) and picks. Type2 `do {attack, eat, pickUp, harvest, sleep}` vs live Type1 `receive {attack, harvest}` → `{attack, harvest}` → picks harvest. Type1 vs berry bush `receive {harvest}` → `{harvest}`. The entity exposes `do_actions()` and `receive_actions()`; the old `get_advertised_actions()` *is* `receive_actions()`.

**Pairing rule:** an action fires only if the **target** advertises it (has the affordance component) AND the **actor** has the paired component — eat needs actor `HungerComponent`, pickUp needs actor `InventoryComponent`, attack needs actor `AttackComponent`. No type checks, only components.

> **[AS BUILT — diverged]** The rule the code follows is narrower: **each side resolves only what
> it alone can know.** The actor checks *its* facts (reach, capacity, and eventually weapon and
> crit), the target checks *its* own (availability, and eventually armour and dodge); the message
> between them describes an **attempt**, never an outcome. For pick-up the two rules agree. For
> eating they do not: `ConsumableComponent` is a pure door that hands over a snapshot, and the
> **actor's** `SimHungerComponent` applies the nourishment — the number is target data, but what a
> body does with it is a body fact. See `HANDOFF_PSEUDOCODE.md` §11 Round 3 and §12b.

**Actor declares, target resolves.** Each action is two-sided. The **actor** component is a thin capability marker (+ actor data like `damage`) with no effect logic; the **target** component owns the *resolution* — mutate a bar, spawn, or self-destroy (+ target data like `hunger_value`). `AttackComponent(damage)` → `HealthComponent` reduces hp/dies; `HungerComponent`(marker) → `EatableComponent` feeds the actor + frees itself. Add a new attackable = give it `HealthComponent`; a new food = give it `EatableComponent` — the actor side never changes.

**Capability = component presence.** The Brain builds its goal set by introspecting its own components — no `HungerComponent` → no food goal, no `FatigueComponent` → no rest goal. On the target side an action's component requirements gate its effect: damage (attack, or damaging-harvest) needs the target to have a `HealthComponent` (no Health → can't be hurt); clean harvest needs the target's Movement absent or disabled. You never test "is this a plant / a corpse" — you test which components exist.

### The four bars (0–100)

**Hunger — fullness.**
- Drains over time (rate TBD). Eating one food item → **+5**.
- `> 50` → Health regenerates **+1/sec** (well-fed heals — the only healing lever).
- `= 0` → **starvation**: damages Health over time.

**Fatigue — how rested** (high = good; this *is* the "energy" that movement and actions spend).
- Drained by movement (walk 0.5/grid, run 2/grid) and costed actions.
- `= 0` → **collapse**: **forced sleep in place**, no health penalty. The cost of exhaustion is the helpless window itself, not damage.
- Sleeping restores **+1/sec**, always in place. There is no bed: sleep is self-directed, so it needs no target and no travel.
- `= 100` → **auto-wake**.

**Health.**
- `= 100` → healthy (max). `= 0` → `died` → becomes a **Corpse**.
- Damaged by: starvation and `AttackComponent` hits. Collapse costs no health.
- Regenerates **+1/sec whenever Hunger > 50**.

**Danger — threat awareness** (Type1 only for now; Type2's input is empty → stays 0).
- **Rises** with the nearest enemy's proximity inside detection range (closer → higher). Type1's enemy = Type2.
- **Decays** toward 0 when no enemy in range — the inertia gives hysteresis (no sleep/wake flicker when a predator hovers at the edge).
- Feeds the **Flee** consideration in the utility layer (§7) — it competes, it doesn't hard-override.

**Sleep state:** the entity carries `is_sleeping`. **There is no Bed entity — an animal sleeps wherever it stands.** Sleep is self-directed: `FatigueComponent` is the only component involved, there is nothing to path to and nothing to advertise it. What separates the two kinds is the *price*, not the place:
- **Voluntary** (chose to Rest): interruptible every tick — the Brain compares *continue sleeping* (remaining Rest need) vs the best *waking* goal (Flee from Danger, or eat if starving) and wakes if a waking goal wins. Restores +1/sec, auto-wakes at 100. Has energy on hand → can run when it bolts.
- **Collapse** (Fatigue hit 0): **sleep-locked** — Danger and hunger **cannot** wake it — until Fatigue recovers to **50**. ~50s of true helplessness. That lost control *is* the price; there is no health penalty. The difference that matters between the two kinds is authorship: voluntary rest is a choice the brain makes and can interrupt, collapse is not a decision at all.

  **Collapse is owned by `FatigueComponent`, not the Brain.** Running out of energy is not something to weigh against other goals, so the component puts the entity to sleep itself, switches the Brain off, watches its own value, and switches the Brain back on at 50. The Brain holds no sleep code and never learns it happened.

**The 50 line is the pivot:** a need `< 50` activates its goal (§7); Hunger `> 50` enables Health regen. So sub-50 hunger both drives eating *and* halts regen — a starving creature can't heal until it eats back above 50.

---

## 3. Communication Pattern

Two channels: **signals** for state changes (`died`, `starving`, `arrived`), **direct method calls** for commands (`movement.move_to`, `attack.attack(target)`). Cross-entity events go through the **`EventBus` autoload** — no entity references another directly.

### Think loop (Brain on a Timer, ~0.3s)
```
Brain._on_think():
    needs = { hunger, energy }; threats = sensor.get_threats()
    # for each sensed B: candidates = self.do_actions() ∩ B.receive_actions()   (§2)
    goal  = select_goal(needs, threats)         # UTILITY  (§7), scores those candidates
    if plan_invalid(goal): plan = build_plan(goal)   # GOAP (§7)
    step = plan.front()
    if not action.in_reach(step.target):
        movement.move_to(step.target.position, goal.gait)   # travel
    else:
        action.perform(step.action, step.target)            # ActionComponent gates + runs
    # ActionComponent auto-picks diet-matching Items in reach every tick
    # on failure → replan
```

---

## 4. Actions, Receivers & Food

Actions are **advertised by components** and are themselves **resource data**. Each affordance component carries one `ActionDef`; the base `Entity.get_advertised_actions()` scans components and returns the list an actor can attempt.

### ActionDef — an action is a resource
```gdscript
class_name ActionDef extends Resource
var id: StringName
var input:  Dictionary       # what it consumes: {energy: 10, ingredients: [...], tools: [...]}
var time:   float            # how long it takes (seconds)
var output: Array[Output]    # what it returns (below)
var mode:   Mode             # ONE_TIME | OVER_TIME
```
- **ONE_TIME** (eat, harvest, pickUp, attack): pay `input` once → wait `time` → apply `output` once.
- **OVER_TIME** (sleep): while active, each second pays `input` (if any) and applies `output` — runs until the bar fills or it's interrupted.

**Three output forms:**
- `StatOutput {bar, amount, to: actor|target}` — move a bar. eat → +hunger to actor; attack → −health to target; sleep → +energy/sec to actor.
- `SpawnOutput {def_id, count, at: world_pos}` — spawn new entities in the world. harvest → drop berry/meat entities.
- `ItemOutput {item_data, to: actor_inventory}` — store item data in the actor's inventory. pickUp.

### Handshake
`ActionComponent.perform(action, target)` → checks reach → confirms the target advertises `action` (has the affordance component) and the actor has the paired component → runs the `ActionDef` (consume input, honour `time`/`mode`, apply outputs). Validated by components, never by type.

### The food loop in these terms
```
BerryBush.HarvestableComponent --harvest--> SpawnOutput: berry entities at bush   (ONE_TIME, cost 10 energy)
Berry.PickUpAbleComponent      --pickUp-->  ItemOutput:  berry data → inventory, world entity freed
Berry.EatableComponent         --eat-->     StatOutput:  +5 hunger to actor        (ONE_TIME, diet-gated)
```
Harvesting a **living** target adds a `StatOutput {−damage to target Health}` (see §5); a bush/dead body has no Movement, so no damage — same `harvest`, mobility decides.

```gdscript
enum FoodType { VEGIE, MEAT }
# Type1.diet = [VEGIE]   Type2.diet = [MEAT]   # eat allowed only if EatableComponent.food_type ∈ diet
```

> **[AS BUILT — pending]** `StatOutput {bar, amount, to}` is not built; a consumable currently
> carries a single `nourishment: float`. The queued next step (`HANDOFF_PSEUDOCODE.md` §12) replaces
> it with `effects: Array[SimEffect]`, whose only concrete form — `SimBarEffect {bar, amount}` — is
> `StatOutput` minus the `to:` field. **Open question:** whether that step should simply build
> `StatOutput` itself, so this document's vocabulary is not duplicated.

**Eat checks inventory first.** Before pathing anywhere, the entity checks its inventory for diet-matching item-data. If present it just eats (see §7 — GOAP: `has_vegie`/`has_meat` already true, plan collapses to `[eat]`).

**Auto-pickup within reach.** `harvest` spawns food entities at the source; `ActionComponent` then auto-performs `pickUp` on any in-reach food entity whose `EatableComponent.food_type ∈ diet`. A harvester at the bush is in reach → grabs instantly (feels like auto-collect); loose berries a Type1 walks over get scavenged the same way.

---

## 5. Predation — harvest in place (no Corpse entity)

Death no longer swaps in a Corpse scene. A dead entity keeps its body, Receiver, and Health (=0); death just **disables Movement and Brain**. That single state change flips its `harvest` from the damaging variant to the clean variant, in place.

```
1. Live Type1 has a `HarvestableComponent`; Movement enabled → harvest adds the damage StatOutput.
2. Type2 harvests it:  input −10 energy,  SpawnOutput +2 Meat,  StatOutput −35 HP target.  Repeat.
3. Type1 HP → 0 → `died` → Movement + Brain disabled (body stays in place).
4. Movement now disabled → harvest is the CLEAN variant (full yield, no damage).
5. Yield exhausted → free the body.
```

So "attack → corpse → harvest" collapses into one repeated `harvest` (the `HarvestableComponent`'s ActionDef). A pure `attack` (from `AttackComponent`, damage only, no yield) still exists for killing without harvesting. A bush never has Movement → always clean; give it a `HealthComponent` later to make bushes depletable.

---

## 6. Movement, Speed & Energy

Movement is gait-based. The brain requests a gait; MovementComponent applies speed and deducts energy per grid moved.

```
# GlobalConstant.gd — all tunable
WALK_SPEED         = W          # px/sec — SAME for ALL types
RUN_SPEED_TYPE1    = R
RUN_SPEED_TYPE2    = 1.4 * R    # predator faster on the run
RUN_SPEED_TYPE3    = 2.0 * R    # "much faster than Type2" (tunable) — fast prey
ENERGY_PER_GRID_WALK = 0.5
ENERGY_PER_GRID_RUN  = 2.0      # running = 4× walk cost per grid
GRID_SIZE            = 64       # px, one painted tile; for per-grid → per-sec conversion
NEED_THRESHOLD       = 50
DETECTION_RANGE_TYPE2 = D                  # baseline sensor radius
DETECTION_RANGE_TYPE1 = 1.3 * D            # vigilant prey — sees farthest
DETECTION_RANGE_TYPE3 = 0.7 * D            # oblivious prey — sees least (tunable)
DANGER_RISE          = ...                 # per sec, scaled by enemy proximity (TBD)
DANGER_DECAY         = ...                 # per sec, always draining — Flee persists until Danger = 0 (TBD)
```

### Type profiles (the experiment)
| Type | Role | Detection | Run | Survives by |
|---|---|---|---|---|
| Type1 | prey — vigilant | 1.3× | R (slow) | early warning |
| Type2 | predator | 1× | 1.4× R | — |
| Type3 | prey — fast | 0.7× | ~2× R | outrunning |

**Follow mode** (`follow(entity, gait)`): re-reads the target entity's position each tick and steers toward it — no pathfinding, just walk/run straight at it. Used by the predator to chase prey. If the target leaves the follower's sight (out of Sensor range / destroyed), Movement falls back to the **last known position**, drives there, then emits `lost_target` and stops (the Brain replans from there). `move_to(pos)` remains the fixed-point version for going to a bush.

Rules:
- **Walk speed is equal** for all types; only **run speed** differs (Type2 = 1.4× Type1).
- `energy_drain_per_sec = (speed_px_per_sec / GRID_SIZE) * energy_per_grid`. Running drains far faster per second (higher speed *and* higher per-grid cost).
- **Exhaustion lock:** at energy 0 the entity **cannot run** — forced to walk. A creature that flees too long gets caught.
- Gait by goal: Flee / Hunt → **run**; Wander / travel-to-food → **walk**. Rest needs no travel.

### Chase balance (open decision — see §9)
Type2 run (1.4×) > Type1 run, so a committed predator **always wins a straight chase** in the open. Fleeing only buys time. Type1 survives only via: Type2 exhausting its own energy and giving up, lost line of sight, or an early head start. **Counterweight (Danger + detection):** Type1 detects at **1.3× Type2's range**, so a vigilant prey spots the predator first and gets a head start. Predator-dominance becomes *situational* — the 1.4× speed edge only pays off if Type2 closes before Type1 notices, or while the prey is distracted (eating, sleeping, exhausted).

---

## 7. AI — Hybrid (Utility selects goal, GOAP plans route)

**All creatures share ONE `BrainComponent`.** Type1/2/3 differ only by their `EntityDef` data — available actions, `diet`, detection, speeds; Type2 additionally carries an `AttackDef`. No per-type brain code.

### Layer 1 — Goal selection (Utility)
Score each goal by need curves + threat; pick the max. If the winner is below an activation threshold, **Wander**.

| Goal | Score driver | Competes as | Gait |
|---|---|---|---|
| **Flee** *(prey)* | **Danger bar** — active while `> 0` (persists after enemy leaves sight) | high danger → high score — **weighed, not absolute** | RUN |
| **SatisfyHunger** | hunger (lower → higher) | critical hunger can out-score low danger | WALK to food |
| **Rest** | fatigue (lower → higher); while asleep = "continue sleeping" | vs waking goals during sleep | none — sleeps in place |
| **Wander** *(idle)* | low constant | wins only when nothing urgent | WALK (drunkard's) |

The interesting arbitration lives here: *hungry AND threatened* → Hunger score vs Flee score, higher wins; *asleep AND threat nearing* → continue-Rest vs Flee, higher wins (this is how the sleeper decides to bolt).

```gdscript
func select_goal(bars) -> Goal:
    var best; var best_score = ACTIVATION_MIN
    for g in [Flee, SatisfyHunger, Rest]:           # Flee scores from bars.danger
        var s = g.score(bars)                        # danger_curve ; hunger^2 ; inverse(energy)
        if s > best_score: best_score = s; best = g
    return best if best else WanderGoal.new()        # nothing urgent → wander

# while is_sleeping: compare best_score above against "continue sleeping"
# (the Rest value). Wake only if a waking goal wins.
```

**Wander (drunkard's walk):** every interval (or on arrival) pick a random point within `WANDER_RADIUS` and walk to it. Textbook version = fresh random direction each step; smoothed = perturb current heading by ±random angle (less jittery). Always WALK gait so idling is cheap.

**Flee:** RUN, driven by the Danger bar. Danger **fills** from enemy proximity and **drains over time**, and Flee stays active **while Danger > 0** — not just while the enemy is in sight. So the entity keeps bolting after the predator breaks line of sight, until the bar empties (unless a higher goal interrupts, or it collapses):
- Enemy **visible** → run along `(self - threat).normalized()`.
- Enemy **gone but Danger > 0** → keep the **last flee heading** (momentum) until Danger = 0.

Its score competes with Hunger/Rest — usually wins when danger is high, can yield to near-starvation when danger is low. Running drains energy fast → feeds the exhaustion lock.

### Layer 2 — Planning (GOAP)
For non-trivial goals, A*-chain the entity's available actions to reach the goal's desired state; replan on failure.

**Starting state is read from inventory:** the `WorldState` snapshot sets `has_vegie`/`has_meat` from current inventory, so if food is already on hand the plan for `hunger_satisfied` collapses to `[Eat]` and the entity never walks to a source. Only an empty (of valid food) inventory forces the gather steps below.
```gdscript
class_name GOAPAction extends Action
var preconditions: Dictionary   # {"has_vegie": true}
var effects: Dictionary         # {"hunger_satisfied": true}
```
- **Type1 actions:** `harvest` (bush→berry), `eat` (VEGIE), `sleep` → hunger plan `[harvest, pickUp, eat]`
- **Type2 actions:** `harvest` (prey→meat, damaging while alive), `eat` (MEAT), `sleep` → plan `[harvest ×n, pickUp, eat]`

An actor's available actions are whatever its target entities *advertise* (via their affordance components) and it has the paired component for. The target's `HarvestableComponent` decides the yield; mobility decides clean vs damaging.

Flee and Wander skip the planner (single-action goals); Hunger/Rest use it.

### Why hybrid
Builds *both* paradigms, each doing what it's best at; Type1/Type2 stay one brain (data-only difference); scales to StrategyGame villagers. **Cost:** loses a clean head-to-head Utility-vs-GOAP comparison. Flip to separate brains if that comparison is the goal.

---

## 8. Class / File Map

**Target layout** (below). The built layout is `Sim`-prefixed and lives under
`8. SimpleAiSystem/`; see `HANDOFF.md` §4 for the real tree.

```
autoload/
  EventBus.gd  GlobalConstant.gd  SystemCore.gd  Settings.gd

entities/
  Entity.tscn / Entity.gd            # bare base: Sprite2D + body Area2D
  EntityFactory.gd                   # spawn(id, pos) → assembles from EntityDef
  defs/
    EntityDef.gd  EntityCatalog.gd
    componentdefs/  ComponentDef.gd (base: build_into)
      HealthDef  HungerDef  FatigueDef  InventoryDef  MovementDef  SensorDef
      ActionCompDef  AttackDef  EatableDef  HarvestableDef  PickUpAbleDef  ReceiverDef  BrainDef
    type1.tres  type2.tres  type3.tres        # creatures
    berrybush.tres  berry.tres  meat.tres              # props + items

components/
  HealthComponent.gd  HungerComponent.gd  FatigueComponent.gd
  InventoryComponent.gd  MovementComponent.gd
  ActionComponent.gd  AttackComponent.gd
  EatableComponent.gd  HarvestableComponent.gd  PickUpAbleComponent.gd  ReceiverComponent.gd
  SensorComponent.tscn / .gd
  BrainComponent.gd
  goap/  Planner.gd  WorldState.gd  Goal.gd
  utility/  Consideration.gd  FleeGoal.gd  WanderGoal.gd

actions/
  ActionDef.gd                       # resource: input, time, output[], mode
  Output.gd  StatOutput.gd  SpawnOutput.gd  ItemOutput.gd
  # concrete ActionDefs are .tres assigned to affordance components in each blueprint
  harvest.tres  eat.tres  pickup.tres  sleep.tres  attack.tres

goap/
  GOAPAction.gd    # planning wrapper (preconditions/effects) over catalog action ids

world/  Main.tscn / Main.gd
  WorldDef.gd  world1.tres        # the placement list (names, types, positions, overrides)
```

---

## 9. Open Questions
- **Chase balance:** give Type2 an aggro/give-up (energy or timeout) mechanic, or keep predator-dominance? (§6)
- Hunger/energy drain rates; starvation damage per tick.
- ~~Energy-0 softlock~~ → resolved: Fatigue 0 = −20 HP + forced collapse-sleep in place.
- BerryBush finite vs infinite; regrowth timer.
- ~~Sensor radius per type~~ → resolved: Type1 detection = 1.3× Type2 (prey vigilance / fairness).
- `Hunt` instant vs damage-over-work_time (must out-pace +1/sec regen — burst is fine).
- ~~Collapse-sleep helpless window~~ → resolved: collapse is sleep-locked (un-wakeable) until Fatigue 50 (~50s helpless), then normal interruptible sleep with ≥50 energy on wake.
- Danger rise/decay rates; danger→flee curve shape; does extreme hunger also wake a safe sleeper?
- **Experiment to watch:** Type1 vs Type3 survival on one map — does awareness or speed win?
- ~~Bed vs collapse~~ → resolved: **no Bed at all.** Animals sleep where they stand.
- ~~Collapse penalty~~ → resolved: **no health penalty.** Collapse is forced sleep, locked until energy reaches 50; the helpless window is the whole cost. Triggered by `FatigueComponent`, not the Brain.
- ~~Does hunger keep draining while asleep?~~ → resolved: yes, at a reduced rate. Sleep state lives on the entity (`is_sleeping`) so Hunger reads it without depending on Fatigue.
- Passive Fatigue drain, or only movement/actions? (idle well-fed entity otherwise never tires)
- Wander radius/interval; smoothed vs pure random heading.
- ~~Pickup model~~ → resolved: harvest spawns Items in-world, ActionComponent auto-picks diet-matching Items in reach.
- ~~Interactables & Items as separate scenes~~ → resolved: **everything is an entity** (bush/dead-body/berry/meat), built from defs.
- ~~Generic Receiver for everything~~ → resolved: common affordances are typed components (Food/Harvestable/PickUpAble); Receiver holds only not-yet-promoted actions (sleep, ride).
- Actions are `ActionDef` resources (input/time/output/mode); ONE_TIME vs OVER_TIME; output = stat-bar / spawn / inventory.
- Two-sided actions: actor component = capability marker (+ actor data), target component = resolution logic. (`FoodComponent` renamed `EatableComponent`.)
- Interaction resolver = `actor.do_actions() ∩ target.receive_actions()`; each component tags its actions do/receive.
- World authored as EntityCatalog (blueprints) + WorldDef (placement list with per-instance overrides).
- **CONFIRM harvest rule:** works on both (clean when immobile/dead, damaging while alive) — or dead-only with Attack killing? Built as the former.
- Live-harvest numbers (10 energy / 2 meat / 35 dmg) tunable per def; do bushes deplete (need Health) or stay infinite?
