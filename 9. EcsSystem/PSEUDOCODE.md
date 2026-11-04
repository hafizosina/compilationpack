# Module 9 — pseudocode of the core logic

Every component, flag, singleton and system in module 9, as pseudocode, at `1549fa2`
(2026-11-01). It mirrors the code and leaves out the plumbing: casts, null guards that only
skip, and view caching (a cached index rebuilds only when `world.view()` hands back a new
object). Why things are shaped this way is in `HANDOFF.md`; the overview is
`ECS_GOAP_REPORT.md`.

Notation: `has(e, T)`, `get(e, T)`, `add(e, flag)`, `remove(e, T)` are `EcsWorld` calls.
`perceived(e)` is `EcsSensorComponent.perceived`, `reached(e)` is `EcsActionComponent.reached`.
`note(...)` appends an `EcsSpawnRequest` to `EcsLifecycleSingleton`. `dying(e)` is
`has(e, EcsDyingFlag)`.

---

## 1. The core

### EcsWorld — the store

```
alive      : set of id
store      : { Script : { id : component } }
singletons : { Script : component }
versions   : { Script : int }        # bumped by add, remove, destroy

create_entity()       -> next id, mark alive
destroy_entity(id)    -> unmark; erase id from every table; bump each table touched
add(id, c)            -> store[type(c)][id] = c; bump type(c)
remove(id, T)         -> erase; bump T
query(include, exclude):
    driver = smallest table in include        # drive from the rarest
    return [id in driver if id in every include and in no exclude]
view(include, exclude):
    if cached view for the key and every named table's version unchanged: return it
    ids = query(include, exclude)
    columns[T] = [store[T][id] for id in ids]  for T in include
    stamp versions; cache; return
```

A view is an index over the store, never a second store: its columns hold the same component
objects. Field writes need nothing; only `add`, `remove` and `destroy` invalidate it.

### EcsScheduler — order and rate

```
add(system, every = 1, phase = 0)
run_all(world, delta):
    for each system i in order:
        banked[i] += delta
        if tick % every[i] != phase[i]: continue
        system.run(world, banked[i])     # a slow stage gets every tick's delta
        banked[i] = 0
    tick += 1
```

### EcsEntityManager — the only creator and destroyer

```
spawn_world(world_def):  for placement in world_def: spawn(type, position, overrides, name)

drain():                                   # the lifecycle stage
    for request in take_all(lifecycle.spawn_requests):
        request.born = restore(record, pos) if request.record else spawn(type, pos, overrides)
        request.fulfilled = true
    for id in query([Dying]): kill(id)

spawn(type, pos, overrides, name):
    blueprint = catalog[type]
    id = create_entity()
    add Name{name, type, display_name, uid = 128 random bits as hex}
    add Position{pos}
    for template in blueprint.components:
        c = template.duplicate(deep)                # one copy per entity
        apply overrides[c.key()] field by field
        add(id, c)
    build_nodes(id, pos)

restore(record, pos):                     # an item back from a bag, as itself
    id = create_entity(); add every component in record; Position = pos; build_nodes

kill(id): destroy_entity(id); free its container

build_nodes(id, pos):
    for c in components_of(id) with const NODE_KIND:
        wanted[NODE_KIND] = (NODE_LAYER, NODE_MASK)
    container "entity_<id>" at pos, under World/Entities
    for kind in wanted:
        child = Sprite2D if kind == sprite
                else EcsEntityArea{entity_id, layer, mask,
                                   monitoring = mask != 0, monitorable = layer != 0,
                                   circle collider}
```

It never switches on a component type; the constants decide.

### EcsItemRecord — an item in a bag

```
capture(id):  uid, type, and a reflection copy of every non-flag component
copy(c):      new instance; for every script variable (exported or runtime):
                  copy value, deep-copying arrays and dictionaries
component(T): the held component of type T, or null
```

### Shared helpers (`ai/`)

```
EcsNeeds
    FLOOR = 0.6, CRITICAL = 1
    urgency(value, gate)  = 0 if value > gate else FLOOR + (1 - FLOOR) * (gate - value) / gate
    hunger_urgency(h)     = urgency(fullness, min(forage_below, eat_below)) + CRITICAL if fullness <= 0
    thirst_urgency(t)     = urgency(hydration, min(seek_water_below, drink_below)) + CRITICAL if parched
    parched(t)            = hydration <= parched_below

EcsHunting                                  # no prey tag: diet and power only
    power_of(e)           = Health.power
    can_hunt(a, b)        = a != b and a has Damage and a eats meat
                            and b has Health and Position and not dying(b)
                            and power_of(b) < power_of(a)
    threatens(x, me)      = can_hunt(x, me)
    visibility_of(e, watcher):
        not hidden                                    -> 1
        watcher scanning and e within scan radius     -> 1
        else 1 - stealth * (1 - watcher.awareness)
    notices(hunter, prey) = visibility_of(prey, hunter) >= 0.5
    hide_kinds(e)         = kinds of e's hide skill, or []
    cover_of(e)           = best conceal among reached(e) with a kind e hides in, else 0
    is_lure(e)            = e is drinkable or harvestable
    dash_ready(e)         = dash neither cooling nor active
    dash_reach(e)         = dash skill's reach, else 0

EcsMemoryFact          { about, position, radius, kinds bitmask, strength, fear, traffic, kills_seen }
    bits: WATER 1, LURE 2, FOOD 4, BUSH 8, THREAT 16, PREY 32, MATE 64
    score(fact, here, speed, kind):
        cost = 1 + distance(here, fact.position) / speed / 5
        cost += fear_cost * max(fact.fear, strongest THREAT fact within fact.radius + near)
        if kind == LURE: cost += wait_cost / (1 + fact.traffic)
    best(memory, here, speed, kind, in_sight?, seen?) = fact of kind with the lowest score
                                                        (only facts about ids in seen, if in_sight)
```

### Skills (`ai/`, data in `defs/skills/`)

```
EcsSkillDef   { id, cooldown, duration (0 = held while asked) }
    make_effect() -> the flag that is the skill being active
    can_start(world, id) -> true

EcsDashSkill  { speed_scale, reach, stun }   make_effect -> Dashing{speed_scale}
EcsHideSkill  { stealth, kinds }             make_effect -> Hidden{stealth}
                                             can_start   -> cover_of(id) > 0
EcsScanSkill  { radius }                     make_effect -> Scanning{radius}

default_set: dash ×2 0.5 s cd 10 reach 150 stun 2.0 | hide 0.9 in bush | scan 1.5 s cd 8 r 200
crocodile swaps: dash ×3.5 0.6 s cd 12 reach 180 stun 2.0 | hide 0.95 in water
```

### The planner (`ai/ecs_planner.gd`) — pure

```
EcsActionDef { id, preconditions: {fact: bool}, effects: {fact: bool}, cost, patience }
EcsGoalDef   { id, desired: {fact: bool}, need, weight }

plan(facts, desired, actions, costs) -> [action id]:        # forward A*
    open = [{state: facts, g: 0, steps: []}]
    best = {key(facts): 0}
    while open:
        node = pop lowest g + h          # h = 0 if desired holds else 1 (admissible: costs >= 1)
        if holds(node.state, desired): return node.steps
        if len(node.steps) >= 8: continue
        for a in actions where holds(node.state, a.preconditions):
            c = costs.get(a.id, a.cost); skip if INF
            next = node.state merged with a.effects
            g = node.g + c
            if key(next) seen at <= g: skip
            push {next, g, steps + [a.id]}
    return []

holds(facts, wanted) = every wanted fact equals facts.get(fact, false)
key(facts)           = sorted names of the true facts
```

---

## 2. Components — what an entity is

Fields below the line in each row are runtime, written by systems; the rest are authored.

| component | authored | runtime | read by |
|---|---|---|---|
| `Name` | entity_name, type_id, display_name | uid | everything that names; records |
| `Position` | position | — | almost everything |
| `Sprite` `NODE_KIND sprite` | texture, scale_factor, tint, z_index | — | node_sync, selection, corpse |
| `Body` `NODE_KIND body, LAYER body, MASK body` | radius, is_solid | — | collision, sensor (via area), hiding |
| `Movement` | speed, arrive_radius, timeout_slack, timeout_grace | destination, has_destination, velocity, time_left | movement; brain writes the destination |
| `LowBrain` | radius, pause_min, pause_max | state, target, pause_left | brain only (planning reads a threat's state) |
| `Planner` | actions, goals | planned, dirty, goal, steps, facts, ranking, replans, settling | planning writes; brain reads |
| `Sensor` `NODE_KIND sensor, MASK body` | radius, awareness | perceived | sensor writes; everyone reads |
| `Action` `NODE_KIND action, MASK body` | radius | reached | sensor writes; executors read |
| `Hunger` | eats, drain, asleep_drain_scale, max_fullness, forage_below, eat_below, starve_damage, heal_above, heal_rate | fullness | hunger, consume, planning, brain |
| `Thirst` | drain, asleep_drain_scale, max_hydration, seek_water_below, drink_below, parched_below, dehydrate_damage | hydration | thirst, drink, planning, brain |
| `Energy` | max_energy, drain_idle, drain_moving, restore, hide_restore, rest_at, wake_at, collapse_release, collapse_damage, start_min, start_max | value, rolled | energy, planning, brain |
| `Health` | max_health, power | value | health, damage, hunger/thirst/energy write it |
| `Danger` | fill, hit_jump, decay, flee_at | value, threat, threat_at | danger writes; planning, memory, brain |
| `Memory` | capacity, remember_for, near, fear_for, fear_cost, traffic_half_life, wait_cost, kill_traffic | facts | memory writes; planning, brain |
| `Skills` | swaps | skills, resolved, cooldown_left, active_left | skill writes; brain, attack read |
| `Breeding` | ready_above, cooldown, cost, litter | cooldown_left, rolled | breeding only |
| `Inventory` | capacity | items: [EcsItemRecord] | pickup, consume, drop, corpse |
| `Consumable` | nutrition, diet | — | consume; food indexes |
| `Pickable` | — (a marker) | — | pickup |
| `Lootable` | — (a marker) | — | pickup, brain |
| `Harvestable` | yields, diet, stock_max, regrow, harvest_time | stock, regrow_left, stocked | harvest; brain, planning, memory |
| `Drinkable` | rate | — | drink |
| `Cover` | kind, conceal | — | hiding, lures |
| `Damage` | damage, interval, crit_chance, crit_multiplier, bleed_rate, bleed_for, poison_rate, poison_for | cooldown | attack |
| `Armor` | reduction, minimum | — | health |
| `Rot` | lasts | age | rot; memory (a corpse) |
| `Spawner` | spawns, radius, interval, max_loose | cooldown, pending, spawned | spawner (no blueprint uses it) |

The one method a component may have: `describe() -> {tab, lines, title?}`, display only.

## 3. Flags — what is true of it now

| flag | data | raised by | cleared by | read by |
|---|---|---|---|---|
| `EatIntent` | target_id \| record_uid | brain | brain | consume |
| `TakeIntent` | target_id, record_uid | brain | brain | pickup |
| `AttackIntent` | target_id | brain | brain | attack, planning (kill pending) |
| `HarvestIntent` | target_id, progress | brain | brain | harvest |
| `DrinkIntent` | target_id | brain | brain | drink |
| `MateIntent` | target_id | brain | brain | breeding |
| `CastIntent` | skill | brain | brain | skill |
| `Asleep` | — | brain | brain | hunger, thirst, energy |
| `Collapsed` | — | energy | energy | brain, hunger, thirst |
| `Dashing` | speed_scale | skill | skill | movement, attack, brain |
| `Hidden` | stealth | skill | skill | visibility, memory |
| `Scanning` | radius | skill | skill | visibility |
| `Stunned` | left | health (from a hit) | health | brain, attack |
| `Hurt` | by | health (from a hit) | danger | danger |
| `Starving` ¹ | rate, left = INF | hunger | hunger | health |
| `Dehydrating` ¹ | rate, left = INF | thirst | thirst | health |
| `Mending` ¹ | rate, left = INF | hunger (fed and hurt) | hunger | health |
| `Bleeding` ¹ | rate, left | health (a bite's bleed) | health (timed) | health |
| `Poisoned` ¹ | rate, left | health (a bite's poison) | health (timed) | health |
| `Ready` | — | breeding | breeding | breeding, planning, memory, brain |
| `Selected` | — | selection | selection | inspect, debug |
| `Dying` | — | health, consume, pickup, rot | (entity destroyed) | lifecycle, corpse, drop, every executor |

¹ An `EcsHealthOverTimeFlag`: health applies `rate` per second while it is on.

## 4. Singletons

```
EcsLifecycleSingleton { spawn_requests: [EcsSpawnRequest{type_id | record, position,
                                         overrides, entity_name, fulfilled, born}] }
EcsCombatSingleton    { hits: [EcsHit{from, to, amount, critical, stun,
                               bleed_rate, bleed_for, poison_rate, poison_for}] }  # cleared by health
EcsHealthSingleton    { changes: [EcsHealthChange{to, amount, from}] }      # cleared by health
EcsSelectionSingleton { pending, pick_at }                                   # written by main.gd
```

---

## 5. Systems, in pipeline order

`[20 Hz]` = every 3rd tick, `[10 Hz]` = every 6th; the rest run every tick.

### lifecycle

```
manager.drain()      # births from notes, then destroy everything Dying
```

### spawner

```
for e with Position, Spawner:
    move fulfilled notes into spawned
    cooldown -= dt; if > 0: continue
    cooldown = interval
    spawned = those still alive with a position
    if spawned + pending >= max_loose: continue
    note(spawns, random point within radius); keep the note in pending
```

### hunger `[10 Hz]`

```
for e with Hunger:
    rate = drain * (asleep_drain_scale if Asleep or Collapsed else 1)
    fullness = max(fullness - rate * dt, 0)
for e with Hunger, Health:                       # flags only; health applies them
    Starving{rate -starve_damage} while fullness <= 0, else removed
    Mending{rate heal_rate} while fullness >= heal_above and 0 < health < max, else removed
```

### energy `[10 Hz]`

```
for e with Energy:
    if not rolled: value = max * random(start_min, start_max); rolled = true
    if Collapsed or Asleep:           value += restore * dt
    elif hide_restore and Hidden:     value += hide_restore * dt
    else:                             value -= (drain_idle + drain_moving if moving) * dt
    if not Collapsed and value <= 0:  add Collapsed; health inbox += -collapse_damage (once)
    elif Collapsed and value >= collapse_release: remove Collapsed
```

### thirst `[10 Hz]`

```
for e with Thirst:
    rate = drain * (asleep_drain_scale if Asleep or Collapsed else 1)
    hydration = max(hydration - rate * dt, 0)
for e with Thirst, Health:
    Dehydrating{rate -dehydrate_damage} while hydration <= 0, else removed
```

### danger `[20 Hz]`

```
hunters = ids with Damage whose Hunger eats meat
for e with Danger, Position, not Dying:
    threat, seen = nearest x in perceived(e) where x in hunters and threatens(x, e),
                   seen = max visibility_of(x, e) among them
    if threat: value += (fill * seen - decay) * dt; remember threat and threat_at
    else:      value -= decay * dt
    clamp value to [0, 1]
for e with Hurt:
    value = min(value + hit_jump, 1); remember Hurt.by as the threat
    remove Hurt
```

A hidden threat with low visibility can make `fill * seen < decay`, so it is never noticed.

### sensor `[20 Hz]` — one of two systems that read nodes

```
for e with Position, Sensor:  scan(e, sensor area, radius, into perceived)
for e with Position, Action:  scan(e, action area, radius, into reached)
scan: clear list; set the area's circle to radius if changed;
      for area in overlapping_areas: append its entity_id (not e)
```

### breeding `[20 Hz]`

```
count living Breeding entities per type
for e with Name, Breeding, not Dying:
    if not rolled: cooldown_left = random(0, cooldown); rolled = true
    cooldown_left -= dt
    ready = cooldown_left <= 0 and count[type] < 100
            and fullness >= max * ready_above and hydration >= max * ready_above
    add or remove Ready to match
for e with MateIntent, Breeding, not Dying:
    p = intent.target
    require: p != e, p alive and not Dying, both Ready, same type, p in reached(e)
    repeat litter: note(type, midpoint of e and p)
    for parent in (e, p): cooldown_left = cooldown; fullness -= cost; hydration -= cost;
                          remove Ready         # so the partner's own intent fails
```

### memory `[20 Hz]`

```
indexes: water, lures (cover that is water or a bush), crops, food by diet, hunters,
         diets present, living bodies (for power), ready by type, what each eater eats
for e with Memory, Sensor, Position, not Dying:
    for fact in facts:                                  # fade and falsify
        strength -= dt / remember_for
        forget if strength <= 0
              or (fact.position within sight radius and fact.about not in perceived(e))
        fear -= dt / fear_for; traffic *= 0.5 ^ (dt / traffic_half_life)
    if danger >= flee_at: fear = 1 on every WATER fact near danger.threat_at
    if e drinks, eats a diet present, hunts, or anyone is ready:
        for seen in perceived(e):                       # learn
            if e hunts and has lures: count traffic       # prey near a lure: + dt; a corpse: + kill_traffic once
            bits  = WATER  if e drinks and seen is water
                  | LURE   if e hunts and seen is a lure of a kind e hides in
                  | FOOD   if seen is food of e's diet
                  | BUSH   if seen is a crop of e's diet with stock
                  | PREY   if e hunts and seen is weaker and noticed
                  | MATE   if seen is ready and e's type
                  | THREAT kept from the old fact
            bits == 0 ? forget seen : write(seen, bits)  # position copied, strength 1
    if danger.threat is in sight and noticed: add THREAT to its fact
    over capacity: sort by strength, drop the weakest
```

### planning `[20 Hz]` — L2 goal and L3 route

```
for e with Planner, LowBrain, not Dying:
    if e's AttackIntent target is Dying: settling = 1; continue    # wait for the corpse
    if settling > 0: settling -= 1; continue
    facts  = snapshot(e)
    ranked = rank(e)
    if not dirty and (not planned or facts != planner.facts or ids(ranked) != planner.ranking):
        dirty = true; queue e
replan up to 64 from the queue, oldest first:
    planned = true; dirty = false; replans += 1; store facts and ranking
    costs = costs(e)
    for goal in ranked: steps = plan(facts, goal.desired, actions, costs)
                        if steps: goal, steps = that; stop
    (none fits: goal = "", steps = [], and the brain wanders)

score(goal):
    breed      -> weight if Ready
    eat        -> weight * hunger_urgency
    drink      -> weight * thirst_urgency
    provision  -> weight * urgency(fullness, forage_below)     only with a bag
    rest       -> weight * urgency(energy, rest_at)
    flee       -> weight * (FLOOR + (1 - FLOOR) * (danger - flee_at) / (1 - flee_at))  if danger >= flee_at
rank: goals scoring > 0, best first, +0.5 on the current goal

snapshot(e) -> only true facts:
    starving, parched, has_room, food_in_bag (of its diet), dash_ready, ready_to_breed
    water_known / lure_known (hunters) / food_known / bush_known / mate_known   from memory
    threat_near and hunted (the threat is in HUNT/ATTACK/POUNCE on e)  else safe
    over reached(e):   mate_in_reach, food_in_reach (+ item_in_reach if pickable), bush_in_reach,
                       loot_in_reach, prey_in_reach, water_in_reach,
                       in_cover (cover of a kind it hides in; + prey_come_here if a lure and it hunts)
    over perceived(e): mate_in_sight, cover_in_sight (+ lure_in_sight), food_in_sight,
                       bush_in_sight, prey_in_sight (+ prey_close within dash reach), water_in_sight

costs(e):                                            # only when it replans
    if prey_in_sight:
        hunt = min over noticed huntable prey of 1 + distance / (my speed - their speed) / 5
               (INF if no prey is slower)
    for each memory kind known:
        the in-sight go-to (go_to_water, go_to_lure, seek_mate) = score(best fact in sight)
        the recall                                              = score(best fact), INF if none
```

### low_brain `[20 Hz]` — L1, the only thing that chooses

```
for e with Position, Movement, LowBrain:
    step = planner.steps[0] if planned else ""

    # forced
    if Stunned:   stop trip; release; continue
    if Collapsed: stop trip; state = SLEEP; continue

    # holding states
    if SLEEP: stay unless rested, starving, parched, or step is a way of staying safe
    if DRINK: stay while not full, water in reach, and step is not staying safe
    if FLEE and step == escape and dash ready: stop; release
    if planned and state doesn't serve step and not on a retreat leg: stop trip; release
    if ESCAPE and Dashing: state = FLEE               # the dash fired once
    if FLEE or ESCAPE: run_from(threat_at); continue

    # commitments
    SEEK_FOOD:  release if target gone (no food, no stock), in reach, or trip ended; else continue
    SEEK_WATER, RECALL: release if gone, in reach or trip ended; else continue
    SEEK_MATE:  release if not a mate any more or in reach; else follow its position; continue
    MATE:       release if not a mate or out of reach
    POUNCE and Dashing: state = HUNT
    HUNT/ATTACK/POUNCE: if keep_hunting(): continue
    HIDE with a trip: continue
    any trip that isn't a WANDER: continue

    # choose
    if planned:
        try_step(step) or has a trip -> continue
        else wander; continue
    # the ladder (no plan)
    thirst_first = thirsty and thirst_urgency > hunger_urgency
    thirst_first and try_water
    or try_eat or try_take or try_seek_food or try_harvest or try_hunt
    or (thirsty and try_water) or try_sleep
    or wander

try_step(step):   (rung run with its need gate off; the goal already decided the need)
    eat_carried, eat_ground -> try_eat      take, loot     -> try_take
    seek_food               -> try_seek_food seek_bush, harvest -> try_harvest
    hunt, attack            -> try_hunt     sleep          -> try_sleep
    flee                    -> FLEE + run_from
    go_to_cover / go_to_lure-> try_cover(lure_only)
    ambush, hide            -> try_ambush   pounce -> try_pounce   escape -> try_escape
    drink -> try_drink      go_to_water -> try_seek_water
    recall_* -> try_recall(kind)   seek_mate -> try_seek_mate   mate -> try_mate

rungs:
    try_eat:        hungry (fullness <= eat_below); meal = record in bag of its diet, else food
                    of its diet in reached -> stop; EAT(meal)
    try_take:       bag with room, peckish (<= forage_below); pickable in reach, or a record
                    in a lootable bag in reach -> stop; TAKE(item, record)
    try_seek_food:  peckish, room or no bag; nearest food of its diet in sight -> SEEK_FOOD + trip
    try_harvest:    peckish, room; stocked crop of its diet in reach -> HARVEST,
                    else nearest in sight -> SEEK_FOOD + trip
    try_hunt:       has Damage, peckish; nearest huntable, noticed prey -> HUNT + trip
    try_sleep:      energy <= rest_at, not starving, not parched -> stop; SLEEP
    try_drink:      thirsty (<= drink_below), not full, water in reach;
                    try_scan first if ready; else stop; DRINK(water)
    try_seek_water: thirsty (<= seek_water_below); cheapest water in sight by memory score,
                    else nearest -> SEEK_WATER + trip
    try_scan:       in SCAN: count pause down, release when done
                    else scan ready -> stop; SCAN; pause = scan duration
    try_cover:      cover in reach -> HIDE + trip to its middle
                    else (lure_only: cheapest remembered lure in sight) or nearest cover in
                    sight it hides in -> HIDE + trip
    try_ambush:     in AMBUSH: patience -= dt; out of patience -> WANDER(target = the cover)
                    one leg straight away from it (a retreat leg the plan may not cut)
                    else need cover in reach; not in its middle -> HIDE + trip to the middle
                    else stop; AMBUSH(cover); pause = the action's patience (INF if none)
    try_pounce:     dash ready; nearest noticed huntable prey within dash reach -> POUNCE + trip
    try_escape:     has Danger and dash ready -> ESCAPE + run_from
    try_recall:     best remembered fact of kind; in reach -> stop and hold;
                    else RECALL(fact.about) + trip to the copied position
    try_seek_mate:  nearest ready one of its kind in sight -> SEEK_MATE + trip
    try_mate:       ready one of its kind in reach -> stop; MATE(it)
    wander:         IDLE; pause down; then WANDER to a random point within radius

keep_hunting(prey):
    if not can_hunt(prey) or not noticed or (no plan and food of its diet in sight):
        stop; release; return false
    if prey in reach: stop; ATTACK(prey); return true
    if ATTACK: HUNT(prey) + trip; return true          # it got away
    if no trip: release; return false                  # out of time
    destination = prey position (budget kept); return true

run_from:  trip to a point `radius` away from danger.threat_at (random if on top of it)

set_state(state, target, record):          # the one writer of state, target and intents
    if same state and target: refresh the intent's record_uid; return
    remove the old state's flag
    state, target = new
    EAT -> EatIntent   TAKE -> TakeIntent   SLEEP -> Asleep   ATTACK -> AttackIntent
    HARVEST -> HarvestIntent   DRINK -> DrinkIntent   MATE -> MateIntent
    AMBUSH -> Cast(hide)   POUNCE -> Cast(dash)   SCAN -> Cast(scan)   ESCAPE -> Cast(dash)

set_trip(point):     destination = point; has_destination = true; time_left = 0 (fresh budget)
abandon_trip():      has_destination = false; velocity = 0; time_left = 0
```

### skill — the only writer of effect flags

```
for e with Skills, not Dying:
    if not resolved: skills = defaults with swaps replacing by id, plus extra swaps
    skip if nothing cooling and nothing active
    tick cooldowns down, erase at 0
    for each active skill:
        timed: active_left -= dt; end at 0
        held:  end if CastIntent no longer names it or can_start fails   # left cover
for e with CastIntent, Skills, not Dying:
    s = the asked skill; skip if active or cooling
    if s.can_start(e): active_left[s] = duration; add s.make_effect()
end(s): remove its effect flag; cooldown_left[s] = s.cooldown
```

### consume — executor of EatIntent

```
for e with EatIntent, Hunger:
    if record_uid: take that record out of e's bag; fullness += its nutrition (capped)
    else meal = target: require alive, Consumable, not Dying, in reached(e)
         fullness += nutrition (capped); add Dying to meal     # Dying is the claim
```

### drink — executor of DrinkIntent

```
for e with DrinkIntent, Thirst, Action, not Dying:
    water = target; require in reached(e) and Drinkable
    hydration += water.rate * dt (capped)
```

### harvest — executor of HarvestIntent; regrowth

```
for crop in Harvestable:
    if not stocked: stock = stock_max; stocked = true
    if stock >= stock_max: regrow_left = regrow
    else: regrow_left -= dt; at 0: stock += 1, regrow_left = regrow
for e with HarvestIntent, Action, Position, not Dying:
    bush = target; require alive, not Dying, stock > 0, in reached(e)
    progress += dt; if progress < harvest_time: continue
    progress = 0; stock -= 1
    note(yields, a random point half e's reach from e)       # lands in its reach
```

### attack — executor of AttackIntent

```
for e with Damage: cooldown -= dt
for e with AttackIntent, Damage, Action, not Dying:
    skip if cooldown > 0 or Stunned
    t = target; require Health, not Dying, in reached(e)
    hit = {from e, to t, amount damage, bleed_*, poison_*, stun = dash.stun if Dashing else 0}
    if random < crit_chance: amount *= crit_multiplier; critical = true
    combat.hits += hit; cooldown = interval
```

### health — the only writer of health, and where death is decided

```
for e with Stunned: left -= dt; remove at 0
loss = {}, gain = {}                              # only ids with something pending
for kind in [Starving, Dehydrating, Mending, Bleeding, Poisoned]:
    for e with Health, kind: (gain if rate > 0 else loss)[e] += |rate| * min(dt, left)
                             left -= dt; remove the flag at 0 (timed ones only run out)
for hit in combat.hits (target has Health, not Dying):
    taken = amount; with Armor: taken = max(taken - reduction, minimum)
    loss[to] += taken; Hurt{by = from}; Stunned.left = max(left, stun) if stun
    Bleeding / Poisoned: rate = worse of the two, left = longer of the two
clear combat.hits
for change in health inbox: (gain or loss)[to] += amount  # 0 just rechecks
clear inbox
for e in loss ∪ gain, not Dying:
    health = max(health - loss, 0)
    if health <= 0: add Dying; continue           # a body at zero never mends
    health = min(health + gain, max)
```

### movement — a destination is a budget

```
for e with Position, Movement:
    if no destination: velocity = 0; continue
    speed = speed * Dashing.speed_scale if dashing
    if distance to destination <= max(speed * dt, arrive_radius):
        position = destination; release; continue                 # arrived
    if time_left <= 0: time_left = distance / speed * timeout_slack + timeout_grace
    time_left -= dt; if <= 0: release; continue                    # gave up: same event as arriving
    velocity = direction * speed; position += velocity * dt
```

### collision — soft; the other system that reads nodes

```
working set: every Position + Body with its body area; movable = also has Movement
sync: area circle radius = body radius; monitoring = is_solid; monitorable = true
for i movable and solid:
    for other area overlapping i's:
        skip if other not solid
        gap = distance; touching = radius_i + radius_other
        if gap < touching: position_i += away_from_other * (touching - gap) / 2
```

Each pair is reported both ways, so each body moving half makes it symmetric.

### pickup — executor of TakeIntent

```
for e with TakeIntent, Position, Inventory, Action:
    skip if bag full
    if record_uid:                          # loot
        source = target: Lootable, not Dying, in reached(e)
        move the record with that uid from source's bag to e's
    else:
        item = target: alive, Pickable, not Dying, in reached(e)
        bag += EcsItemRecord.capture(item); add Dying to item   # the item dies into a record
```

### rot

```
for e with Rot, not Dying: age += dt; if age >= lasts: add Dying
```

### corpse — a death by health leaves a body

```
for e with Dying, Health, Position where health <= 0:
    note("corpse", e's position,
         overrides = {sprite: e's texture and scale, tint darkened; body: e's radius;
                      inventory: e's records},
         name = "corpse_of_<name>")
    e's bag = []                            # the corpse holds it now, so drop doesn't spill it
```

### drop — a dying bag goes back into the world

```
for e with Dying, Inventory, Position:
    for record in bag: note(record, e's position)     # restored as itself: same uid, new id
    bag = []
```

### selection

```
if selection.pending:
    pending = false
    id = nearest entity with Position + Sprite within half its sprite width of pick_at
    remove Selected from everyone; add it to id
place the marker on the selected entity (radius from its Body)
```

### node_sync — data to nodes, one way

```
for e with Position and a container: container.position = position
for e with Sprite and a sprite node:  texture, scale, modulate = tint, z_index
```

### debug — pure reader

```
for each drawn entity send the overlay: name, position, velocity, destination,
    fullness / energy / health / danger as ratios (-1 = has none), goal, items carried,
    asleep or collapsed, stunned, bitten recently (from attackers' cooldowns)
```

### census — pure reader

```
every 0.5 s: EventBus.ecs_world_census(entity_count)
```

### inspect — pure reader, knows no component

```
every interval, for the Selected entity:
    for c in components_of(e):
        if c is a flag: one line on the "Flags" tab
        elif c has describe(): put its lines on its tab ("entity", "own" or "hidden"), take its title
        else: an own tab listing every script field
    EventBus.ecs_entity_inspected(snapshot)
```

---

## 6. One tick, end to end

A hungry wild dog hidden in a bush and a rabbit walking up to it (`showcase/hunt_showcase.tscn`):

```
sensor     rabbit enters the dog's sight; dog's facts gain prey_in_sight, prey_close
planning   dog: satisfy_hunger ranks first; costs: hunt from speeds; plan pounce > attack > ...
low_brain  dog: step pounce -> POUNCE(rabbit), Cast(dash), trip at the rabbit
skill      dash can start -> Dashing{×2}
movement   dog closes at double speed
(next run) low_brain: Dashing seen -> HUNT; in reach -> ATTACK -> AttackIntent
attack     in reach, off cooldown, Dashing -> hit {15, stun 2.0}
damage     rabbit health -15, Hurt{dog}, Stunned{2.0}
danger     rabbit danger jumps; threat = dog
low_brain  rabbit is stunned: trip stopped, no say; dog keeps biting every 0.9 s
health     rabbit at 0 -> Dying
planning   dog's target is Dying -> settle one run (no replan)
corpse     note("corpse", rabbit's spot)
lifecycle  rabbit destroyed; corpse born
sensor     dog sees the corpse -> food_in_reach
planning   replan: eat_ground
low_brain  EAT(corpse) -> EatIntent
consume    dog fullness += 150; corpse Dying; gone next lifecycle
```
