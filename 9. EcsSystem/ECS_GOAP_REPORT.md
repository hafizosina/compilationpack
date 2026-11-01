# Module 9 — ECS and GOAP: where they stand

A report on the final stage of the module as of **2026-11-01** (`1549fa2`). It is the overview;
`HANDOFF.md` is the detail, and the section numbers below point into it.

**In one line:** a hand-rolled ECS runs 48 animals of 4 kinds in a 6400×3360 world, every
animal deciding through the same utility-scored goals, a pure A* planner over 26 data-defined
actions, and a small FSM that turns each plan's first step into intent flags that separate
executor systems carry out. Steps 0–7 of `ECS_REFACTOR_PLAN.md` and steps 1–5 of the features
roadmap are done; what remains is world balance and a few decisions left open on purpose.

---

## 1. The ECS

### Shape

| | count | what it is |
|---|---|---|
| components | 29 | what an entity **is** — field-only `Resource`s, authored in blueprints |
| flags | 17 | what is true of it **now** — added and removed by the system that owns them |
| singletons | 3 | world-level state: lifecycle notes, the pending click, this tick's hits |
| systems | 30 | all behaviour, run in a fixed order by `EcsScheduler` |
| blueprints | 8 | rabbit, monkey, crocodile, wild dog, berry bush, berry, water, corpse |

`EcsWorld` stores components as `{ Script : { id : component } }`; queries key on the script
object, and cached views (`world.view()`) index that store, rebuilding only when a table they
name changes (§14).

### The rules that held

- **Components hold data; systems hold behaviour and never call each other; only systems
  mutate.** The one exception is `describe()`, display-only, which is how the inspector shows a
  component without knowing it exists (a test fails if the inspect system names a type).
- **One owner for structure.** `EcsEntityManager` alone creates and destroys ids, data and
  nodes, at the `lifecycle` stage. Birth is a note on `EcsLifecycleSingleton`; death is
  `EcsDyingFlag`, which is also the claim that stops two executors taking one thing (§3).
- **Nodes are a view.** One `entity_<id>` container per entity, holding whatever its
  components declare through `NODE_KIND` / `NODE_LAYER` / `NODE_MASK`. Only `EcsSensorSystem`
  and `EcsCollisionSystem` read back off a node, and only which ids overlap (§3, §4).
- **Perception is physics.** Sensor and action areas decide what is seen and touched; three
  deliberate distance checks sit on top (scan radius, `prey_close`, memory falsification).
- **Soft collision**, bodies as data, solidity a property of the body (§5).
- **A destination is a budget** — every trip is priced and times out, so a stuck entity
  re-decides instead of livelocking (§6).
- **Items in a bag are records, not entities**: picking up kills the item, dropping restores
  it with the same `uid` (§9).
- **Per-stage tick rates with banked delta**: perception, memory, planning and the brain at
  20 Hz, the bars at 10 Hz, movement and the view at 60 Hz, each on its own phase (§11).

### The pipeline, by job

```
structure   lifecycle > spawner
needs       hunger > energy > thirst > health
sense       danger > sensor > breeding > memory
decide      planning > low_brain
act         skill > consume > drink > harvest > attack > crit > damage
move        movement > collision
aftermath   pickup > rot > corpse > drop
view        selection > node_sync > debug > census > inspect
```

The last three are pure readers; remove them and the simulation does not notice.

---

## 2. Deciding: three levels

| level | where | job |
|---|---|---|
| L2 — goal | `EcsPlanningSystem` | score goals by utility; pick the best one that has a plan |
| L3 — route | `EcsPlanner.plan` | forward A* over a dictionary of facts, depth 8, pure |
| L1 — act | `EcsLowBrainSystem` | run the rung for the plan's first step; bind its target; raise the intent |

A creature whose planner has never planned falls back to the brain's own ladder, which is why
the ladder tests still pass on pipelines with no planning stage.

### Goals (`defs/goals/`)

| goal | desired | weight |
|---|---|---|
| `satisfy_hunger` | fed | 10 |
| `quench` | hydrated | 10 |
| `flee` | safe | 8 |
| `provision` | bag full | 4 |
| `breed` | bred | 3 |
| `rest` | rested | 2 |

A goal scores `weight × urgency` below its need's gate (urgency 0.6 at the gate, 1 at empty,
from `ai/ecs_needs.gd`, shared with the ladder). The current goal gets a 0.5 bonus against
flicker. **Starving and parched add `CRITICAL`**, so either beats every other goal and every
commitment. Danger fills while a noticed threat is in sight and jumps on a hit; `flee` wins only
on score.

### Actions (`defs/actions/`, 26)

| chain | actions |
|---|---|
| eat | `seek_food`, `eat_ground`, `eat_carried`, `take`, `loot`, `seek_bush`, `harvest` |
| drink | `go_to_water`, `drink` |
| hunt | `hunt`, `go_to_lure`, `ambush`, `pounce`, `attack` |
| stay safe | `flee`, `escape`, `go_to_cover`, `hide` |
| remember | `recall_water`, `recall_food`, `recall_bush`, `recall_lure`, `recall_mate` |
| breed | `seek_mate`, `mate` |
| rest | `sleep` |

Each action id names one brain rung and therefore one executor. Example chains the planner
finds without any hand rule:

```
crocodile, hungry, prey too fast:   go_to_lure > ambush > pounce > attack > seek_food > eat_ground
wild dog, hungry, rabbit in sight:  hunt > attack > seek_food > eat_ground
monkey, peckish, bush remembered:   recall_bush > harvest > take
rabbit, thirsty, no water in sight: recall_water > drink
rabbit, threat near, beside a bush: go_to_cover > hide        (not if it is being hunted)
```

### The decisions that shape it

- **Replans happen on events, not a clock.** A planner is queued only when its facts or goal
  ranking change, at most `MAX_REPLANS` (64) per run. A kill settles for one run before the
  hunter replans, so it sees the corpse and eats instead of walking back to cover.
- **Targets bind at execution.** A step is an action id, never an entity, so the eat after a
  kill binds to the corpse — a new entity.
- **Costs come from the entity.** `hunt` is priced from the closing speed and is impossible
  against prey as fast. That one rule is why the slow crocodile ambushes and the fast dog
  chases, from the same action set.
- **Places are priced, not actions.** Each go-to and recall binds the best place and is priced
  by `EcsMemoryFact.score`: the walk, plus fear near a remembered threat, or the expected wait
  at a lure, lowered by traffic. The planner and brain share that helper.
- **Bets have patience.** `ambush` (60 s) and `hide` (8 s) fail if their effect never comes
  true, and the animal walks a leg away so its facts change.
- **Every animal is the same.** Same skills, planner and actions; behaviour differs by stats,
  diet and goals only. Prey is `EcsHunting.can_hunt` — diet and power — never a tag.

### The brain

`EcsLowBrainSystem` is an FSM of 20 states (IDLE … MATE). It writes only its own state, a
destination and intent flags, raised and cleared in one `_set_state()`, so state and flags
cannot disagree. Executors read the flags, never the brain — a creature with no brain eats,
drinks, takes and sleeps when a flag is raised on it (tested). Collapse and stun are the only
forced overrides.

---

## 3. What the world does now

| kind | role | how it differs |
|---|---|---|
| rabbit (20) | grazer | no bag; eats where it stands; fast (165) |
| monkey (20) | carrier | a bag of 1; gathers, carries, eats later |
| crocodile (4) | ambusher | slow (100), strong dash, hides in water |
| wild dog (4) | chaser | fast (200), hides in bushes |

Around them: 52 berry bushes (harvested, regrow), 16 ponds (water and cover at once).

Seen across headless probe runs of the real scene (`HANDOFF.md` §19–§21):

- **Hunting works by both routes**: 7–10 kills per 300 s, dogs by chase and from a bush,
  crocodiles from water; a pounce stuns for 2 s and the bites follow.
- **Prey survive by choice**: about 150 escapes, 60–100 hides and 100 scans a run; scanning
  before drinking catches hidden crocodiles.
- **Memory pays**: drinkers with no plan went from ~1,500 s a run to 100–220 s; starvation fell
  from 1–5 a run to 0–1.
- **Births sustain the population**: over 900 s, rabbits end at 26–45 and monkeys 8–23, against
  12 and 8 and falling without births. No deaths of thirst.

---

## 4. Tests and cost

- `tests/lifecycle_test.tscn` — the acceptance suite, **388/388** passing at `1549fa2`.
- `showcase/hunt_showcase.tscn` — one dog, one bush, one rabbit: ambush, pounce, stun, bites.
- `tests/stress_test.tscn` — the population ramp at the game's rates with 40 hunters. The last
  full ramp (2026-10-31) held the 250 ms tick budget to **6,400 entities fed and 4,800 hungry**.
  Births since then cost +5% at 6,400 fed (233 ms). The planner's own A* is noise; its cost is
  the per-run fact snapshot.

---

## 5. Not done, by decision

| item | state |
|---|---|
| world balance | next: in some 900 s runs all crocodiles or all dogs starve; monkeys breed far less than rabbits |
| combat planning | a kill is many attacks; choosing skills from the enemy's skills and stats is open |
| prey fighting back | open |
| weapons, durability | wait on what a carried record may *do* |
| bag capacity, stacking | deferred |
| `MoveIntent` | deferred; the destination stays on `EcsMovementComponent` |
| power as a derived value | authored today; `EcsHunting.power_of()` is the one read |
| crocodiles exploring for ponds | open; each knows only the pond it sits at |
| relations / graph memory | later; memory is a component for now |
| component storage (archetypes, `Resource` or not) | **an open argument — do not implement** (§15) |
| planner on worker threads | ready (the planner is pure); only when the profiler asks |

The small size is the point: no breadth is added without being asked.
