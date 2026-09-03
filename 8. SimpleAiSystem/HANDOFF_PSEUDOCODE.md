# Module 8 — Component Pseudocode Handoff

> **Purpose:** a self-contained, paste-able description of every component in
> `8. SimpleAiSystem`, written as pseudocode rather than GDScript, so the design
> can be argued about away from the editor.
>
> Companion docs in the same folder: `HANDOFF.md` (state of the build, locked
> decisions) · `PROJECT_DEFINITION.md` (why / scope) ·
> `COLONY_SIM_CONCEPT.md` (target architecture) · `MILESTONE_1_SPEC.md` (spec + numbers).
>
> **Matches commit `0b7424f` (3 Sep 2026)** — the end of a three-round refactor
> of the affordance layer (§11). If the code has moved on, this doc has not.
>
> §12 is a **proposal, not built code**. It is the argument this doc most wants
> to have.

---

## 0. How to read this

Pseudocode, not GDScript — types are elided, `?` marks a nullable, `->` marks a
return. What matters is **who calls whom**, because every design argument in this
module is about direction of dependency, not about algorithms.

Three symbols are used to mark the seams:

| Mark | Meaning |
|---|---|
| **[SEAM]** | A deliberate decoupling point. Breaking it is the design failing. |
| **[TEMP]** | Prototype scaffolding with a removal plan. |
| **[OPEN]** | Unresolved — a fair target for challenge. |

---

## 1. The five rules everything obeys

1. **Everything is an Entity.** Creature, berry, bush — one base class, one scene.
2. **What a thing *is* = which components it has.** No type hierarchy, no per-type scene.
3. **Capability = component presence.** No movement slot → it physically cannot move.
   Nothing asks "is this a berry?"; things ask "does this have a `consumable` slot?"
4. **Content is data.** A new creature is a new `.tres`, never new code.
5. **Components never hard-path to siblings.** They go through the entity by slot key.

---

## 2. Vocabulary: slots and stubs

**Slot** = the key a component occupies on an entity. One component per slot.
Chosen over class name because the slot is already the override key in a placement.

```
sprite  movement  sensor  action  inventory  pickupable  consumable
equipment  placeable  health  hunger  fatigue  brain  spawner  debug
```

**Stub** = an inventory verb a component advertises. A holder asks *"what can I
do with this?"* and never checks a type.

| Verb | Declared by | Implemented? |
|---|---|---|
| `consume` | ConsumableComponent / ConsumableDef | yes — `HungerComponent.eat_snapshot()` |
| `throw_item` | PickUpAbleComponent / PickUpAbleDef | no |
| `equip` | EquipmentComponent / EquipmentDef | no — vocabulary only |
| `place_item` | PlaceAbleComponent / PlaceAbleDef | no — vocabulary only |

**[SEAM] Stubs are declared TWICE — on the component and on the def.** A thing in
the world is a live entity; a thing in a pocket is a blueprint snapshot. The same
question has to be answerable of both, so `stubs()` exists on both sides.

---

## 3. Core — the spine

### SimEntity  (Node2D)

The bare base. Carries no behaviour; holds the component registry and mediates
between components that must not know each other.

```
SimEntity extends Node2D:

    # --- scene layout -------------------------------------------------
    #   SimEntity (Node2D)
    #   +-- Sprite2D          configured by SpriteDef
    #   +-- Body (Area2D)     this entity's PRESENCE
    #       +-- BodyShape     [SEAM] monitorABLE, not monitorING:
    #                         it exists to be found, never to find.

    velocity     = (0,0)     # written by Movement, read by FlockTrait
    def_id       = ""        # blueprint id, e.g. "animal"
    is_sleeping  = false     # [SEAM] set by Fatigue, read by Hunger,
                             #        so the two bars never reference each other
    _components  = {}        # slot -> component node
    _source_defs = []        # the per-instance defs it was actually built from

    signal thing_used(verb, target)
        # [SEAM] THE central decoupling. A component that finishes using
        # something announces it here. Whoever HOLDS the target listens and
        # disposes of it. Hunger never references Inventory; Inventory never
        # references Hunger.

    static of(area) -> SimEntity?:
        # physics gives back an Area2D; callers need the entity that owns it
        return area.parent as SimEntity

    register_component(slot, node):
        warn if slot already taken
        _components[slot] = node

    get_component(slot) -> node?         # cast at the call site
    has_component(slot) -> bool          # <- "capability = component presence"
    component_slots()   -> [slot]

    remember_def(component_def):
        _source_defs.append(component_def)      # the OVERRIDDEN copy, not the type

    to_resource() -> SimEntityDef:
        # A blueprint of itself. The carrier keeps this, the world node
        # destroys itself, no hidden nodes linger.
        blueprint = new SimEntityDef
        blueprint.id = def_id
        blueprint.components = deep_copy_each(_source_defs)
        return blueprint

    _claimed = false
    is_claimed() -> bool

    claim_snapshot() -> SimEntityDef?:
        # [SEAM] THE ONE ROUTE OUT OF THE WORLD, shared by every affordance
        # that takes a thing. One flag, on the entity, because the claim is
        # about the entity's EXISTENCE rather than about any one affordance:
        # a berry that is both pick-up-able and edible must not be winnable
        # twice by asking through two different doors.
        if _claimed: return null
        _claimed = true
        snapshot = to_resource()
        parent.remove_child(self)   # detach IMMEDIATELY (see below)
        queue_free()
        return snapshot
        #
        # Callers must do all their own failing FIRST. Once this returns the
        # entity is gone, so a caller that then discovers it cannot accept the
        # snapshot has destroyed something and stored nothing.

    find_with_stub(verb) -> node?:
        first component whose stubs() contains verb
    offers(verb) -> bool

    describe() -> {name, type, fields, components}:
        # [SEAM] the entity AGGREGATES; it never decides how a component
        # presents itself.
        for each component:
            if it has describe()          -> gets its own inspector tab
            if it has describe_summary()  -> merged into the main tab
            returning {} opts out entirely

    do_actions()      -> []   # [OPEN] declared interface for the future
    receive_actions() -> []   #        do-intersect-receive resolver. NOT dead code.
```

### SimComponent  (Node2D) — base of every runtime component

```
SimComponent extends Node2D:
    entity = null

    _ready():
        entity = parent if parent is SimEntity else error
        # subclasses MUST call super()

    slot()            -> ""      # override; must match its def's slot()
    stubs()           -> []      # inventory verbs offered
    describe()        -> {}      # own tab; {} = stay out
    describe_label()  -> slot name, capitalised
    describe_summary()-> {}      # merged into main tab; {} = stay out
```

### SimComponentDef  (Resource) — base of every blueprint

```
SimComponentDef extends Resource:
    slot()  -> ""
    stubs() -> []               # mirrors the component's, for snapshots

    build_into(entity):
        # CONTRACT:
        # - the factory has ALREADY deep-duplicated this def for this one
        #   entity, so mutating self here is safe and local
        # - instantiate, configure, add as child, register under slot()
        # - any Resource held as LIVE MUTABLE STATE must be duplicate()d here.
        #   Immutable config (a Texture2D) may be shared freely.
        error "not implemented"
```

### SimEntityDef / Catalog / Placement / WorldDef

```
SimEntityDef extends Resource:
    id, display_name
    components = [SimComponentDef]        # order is build order

    component_def(slot) -> def?           # "capability = presence", asked of a
    has_component_def(slot) -> bool       #  BLUEPRINT instead of a live node
    find_with_stub(verb) -> def?
    offers(verb) -> bool

SimEntityCatalog extends Resource:       # the blueprint book, id -> def
    defs = [SimEntityDef]                 # setter invalidates the index
    _index, _index_built                  # Resources get no _ready(), so the
                                          # index is built lazily on first use
    get_def(id) -> def?                   # errors, never crashes the spawn loop
    add_def(def)                          # [OPEN] no caller yet — exists so a
    has_def(id)                           #        runtime menu can author types

SimPlacement extends Resource:            # ONE entity in the world
    entity_name, type, position
    overrides = { "brain": { "wander_radius": 200.0 } }   # keyed BY SLOT

SimWorldDef extends Resource:
    entries = [SimPlacement]
    # Flat list only. Scatter rules were built and REMOVED: distribution will
    # come from a purpose-built algorithm later, and the factory should only
    # ever READ a placement list.
```

### SimEntityFactory  (Node)

```
SimEntityFactory extends Node:
    catalog, world, entities_root
    GROUP = "sim_factory"        # [SEAM] found by group, never by node path

    _ready(): add_to_group(GROUP)

    spawn_world():
        clear()
        for placement in world.entries:
            spawn(placement.type, position, overrides, name)

    spawn(type_id, pos, overrides={}, name="") -> SimEntity?:
        blueprint = catalog.get_def(type_id)  or return null
        entity = ENTITY_SCENE.instantiate()
        entity.def_id = type_id
        entity.position = pos

        entities_root.add_child(entity)
            # BEFORE building components, so the entity's @onready
            # sprite/body are resolved when build_into() touches them

        for component_def in blueprint.components:
            instance_def = component_def.deep_duplicate()
                # WITHOUT this, every entity of a type shares one def object
                # and a single override rewrites all of them —
                # 30 entities behaving as 1 entity in 30 bodies
            apply(overrides[instance_def.slot()], instance_def)
            entity.remember_def(instance_def)
            instance_def.build_into(entity)

        if DEBUG: SimDebugComponent.attach(entity)
        return entity

    clear():
        for child: remove_child(child) THEN queue_free(child)
        # detach first — a queued node stays parented until end of frame,
        # so a respawn in the same frame would double-count

    live_count() -> entities_root.child_count
    debug_report()  # one line per entity: slots + key tunables

    # [SEAM] The factory NEVER switches on component type. A new component kind
    # is a new SimComponentDef subclass and this file is untouched.
```

---

## 4. Locomotion and perception

### SimMovementComponent — *the legs*

```
SimMovementComponent extends SimComponent:      slot = "movement"

    signal arrived(target)      # [OPEN] no listeners; brain polls is_moving()
    walk_speed, run_speed, arrive_radius = 8
    _target, _has_target, _gait

    move_to(pos, gait=WALK)     # replaces any destination in progress
    stop()                      # cancels; velocity = 0
    is_moving() -> bool
    target() -> Vector2
    current_speed() -> run or walk

    _physics_process(dt):
        if no target: velocity = 0; return
        to_target = target - position
        if |to_target| <= arrive_radius:
            _has_target = false; velocity = 0; emit arrived; return
        velocity = normalize(to_target) * current_speed()
        position += velocity * dt
            # integrated by hand: with nothing to collide against there is no
            # sweep or depenetration, which is all move_and_slide() would add
        sprite.flip_h = velocity.x < 0

    # Decides NOTHING. Something else picks the destination.
    # describe() -> {} : where a thing is going is already visible on screen.
```

### SimSensorComponent — perception

```
SimSensorComponent extends SimComponent:        slot = "sensor"

    radius = 360
    _area                       # a monitorING Area2D, built in _ready()

    _build_area(r, name):       # shared with Action
        area.collision_layer = 0            # finds, is never found
        area.collision_mask  = ENTITY_LAYER
        circle shape of radius r

    get_detected() -> [SimEntity]:
        for presence in _area.overlapping_areas:
            e = SimEntity.of(presence)
            if e and e != entity: collect e

    nearest_with(slot) -> SimEntity?:
        # [SEAM] how the brain asks for "food" without naming a type:
        # it asks which COMPONENTS a candidate has
        closest detected candidate having that slot

    nearest_with_stub(verb) -> SimEntity?:
        # world-side counterpart of Inventory.find_with_stub() —
        # same question, asked of what is in range rather than what is carried
        closest detected candidate whose offers(verb)

    # describe() -> {} : SelectionMarker draws this radius, which beats a number.
```

### SimActionComponent — *the hand*

```
SimActionComponent extends SimSensorComponent:  slot = "action"

    in_reach(target) -> bool:
        return get_detected().has(target)

    # That is the WHOLE component. Reach is just a much smaller detection radius.
    #
    # [SEAM] It knows NO specific action. Picking up lives on Inventory,
    # attacking would live on Attack; both ask this whether they can reach, and
    # neither is referenced from here. An entity with a hand but no pockets
    # simply cannot pick anything up, and no code here has to care.
```

---

## 5. Needs — the three bars

### SimBarComponent — base

```
SimBarComponent extends SimComponent:

    signal changed(value)
    signal emptied()
    max_value = 100, value = 100, drain_per_second = 0
    bar_row = -1, bar_colour        # [TEMP] see _draw()

    _process(dt):
        rate = (drain_per_second + extra_drain()) * drain_scale()
        if rate != 0: spend(rate * dt)

    extra_drain() -> 0.0        # Fatigue overrides: charge for movement
    drain_scale() -> 1.0        # Hunger overrides: slow down while asleep

    fraction() -> value / max
    is_empty() -> value <= 0
    spend(amount)   -> _set_value(value - amount)
    restore(amount) -> _set_value(value + amount)

    _set_value(next):
        clamp to [0, max]; return if unchanged
        emit changed
        emit emptied ONCE on the way down (re-arms above zero)

    describe_summary() -> { label: "72 / 100" }
        # [SEAM] bars report to the MAIN tab, not one tab each — three tabs
        # holding one number apiece would bury what actually needs a tab

    _draw():   # [TEMP] PROTOTYPE ONLY — a small bar under the sprite.
               # A component holding state should not also render it.
```

### SimHealthComponent

```
SimHealthComponent extends SimBarComponent:     slot = "health"

    regen_per_second = 1.0
    _dead = false

    _process(dt):
        super(dt)
        if dead or no regen: return
        hunger = entity.get_component("hunger")
        if hunger and hunger.is_well_fed():
            restore(regen_per_second * dt)
        # [SEAM] eating is the ONLY healing lever, so Hunger pays for regen.
        # Health asks is_well_fed() rather than reading the number — the
        # threshold lives with the bar that owns it.

    on emptied:
        _dead = true
        switch OFF process+physics on the "brain" and "movement" components
        movement.stop()
        sprite.modulate = darkened
        # death is a STATE CHANGE, not a scene swap. The body stays;
        # it just stops deciding and stops moving.
```

### SimHungerComponent — fullness, not emptiness (100 = sated)

```
SimHungerComponent extends SimBarComponent:     slot = "hunger"

    well_fed_above = 50            # the pivot: above it Health regens,
                                   # at or below it the food goal activates
    starve_damage_per_second = 2.0
    sleep_drain_scale = 0.25

    is_well_fed() -> value >  well_fed_above
    is_hungry()   -> value <= well_fed_above

    drain_scale() -> sleep_drain_scale if entity.is_sleeping else 1.0
        # [SEAM] reads the ENTITY's flag, never FatigueComponent,
        # so the two bars stay independent

    eat_snapshot(snapshot: SimEntityDef) -> bool:
        # THE ONE PLACE nourishment is ever applied. Pocket food arrives here
        # directly; ground food arrives through eat_entity() below.
        if snapshot == null: return false
        def = snapshot.find_with_stub("consume")   or return false
        restore(def.nourishment)             # amount lives ONLY on the def
        entity.thing_used.emit("consume", snapshot)
        return true
        # [SEAM] Hunger never touches Inventory. It ANNOUNCES. If an inventory
        # happens to hold that snapshot, that inventory drops it.

    eat_entity(target: SimEntity) -> bool:
        # Wins it out of the world, then delegates. Same actor-asks/
        # target-resolves shape as Inventory.try_pick_up().
        if target == null: return false
        c = target.find_with_stub("consume")   or return false
        return eat_snapshot(c.claim(entity))
        #
        # [SEAM] TWO ENTRY POINTS, ONE IMPLEMENTATION. GDScript has no
        # overloading, and the caller always knows which case it is in, so the
        # two sources are named rather than sniffed. An adapter with no logic
        # of its own cannot drift from what it delegates to — the danger was
        # never two entry points, it was two implementations reached by
        # throwing away what the caller knew.
        #
        # No race guard needed: a lost race makes claim() return null, and
        # eat_snapshot(null) is false.

    _process(dt):
        super(dt)
        if is_empty(): health.spend(starve_damage_per_second * dt)
```

### SimFatigueComponent — owns collapse

```
SimFatigueComponent extends SimBarComponent:    slot = "fatigue"

    wake_at = 50, recover_per_second = 1.0, move_drain_per_second = 1.5
    _collapsed = false

    extra_drain():
        movement = entity.get_component("movement")
        return move_drain_per_second if movement and movement.is_moving() else 0
        # [SEAM] Fatigue ASKS Movement, Movement never reports to Fatigue.
        # An entity with no movement component simply never pays travel cost.

    _process(dt):
        if _collapsed:
            restore(recover_per_second * dt)      # recovering, not draining
            if value >= wake_at: _wake()
            return
        super(dt)

    on emptied:                     # COLLAPSE
        _collapsed = true
        entity.is_sleeping = true
        brain.set_process(false)
        movement.stop()             # drop the stale target

    _wake():
        _collapsed = false; entity.is_sleeping = false; brain.set_process(true)

    # [SEAM] Collapse is NOT a decision, so the brain never gets to weigh it
    # against other goals. Fatigue puts the entity to sleep itself, switches the
    # brain off wholesale, watches its own value, and switches it back on. The
    # brain holds no sleep code and never learns this happened.
    #
    # [OPEN] Voluntary sleep — the Rest GOAL, which the brain does choose —
    # is step 6 and does not exist.
```

---

## 6. Carrying and affordances

### SimInventoryComponent — pockets, and the owner of pick-up

```
SimInventoryComponent extends SimComponent:     slot = "inventory"

    signal changed(total)       # [OPEN] no listeners; the seam a real carry
                                # indicator should use instead of the badge
    capacity = 1
    _held = [SimEntityDef]      # BLUEPRINTS, not nodes

    _ready():
        entity.thing_used.connect(_on_thing_used)

    _on_thing_used(verb, target):
        if target is SimEntityDef and _held.has(target): release(target)
        # [SEAM] "nobody disposes of someone else's item". We are not told who
        # did the using — only that something we hold was used.

    try_pick_up(target) -> bool:
        if is_full(): return false                     # MY capacity
        action = entity.get_component("action")   or return false
        if not action.in_reach(target): return false   # MY reach
        pickable = target.get_component("pickupable")  or return false
        return store(pickable.claim(entity))           # ITS availability
        #
        # [SEAM] EACH SIDE RESOLVES ONLY WHAT IT ALONE CAN KNOW. Every reason
        # THIS entity might refuse is checked here, before the target is asked,
        # because asking destroys it. The target has no opinion about pockets
        # and cannot see them.
        #
        # store() refuses a null snapshot, which is what a lost race returns.

    is_full()  -> _held.size >= capacity
    total()    -> _held.size

    store(snapshot) -> bool:
        return false if null or full         # caller must NOT destroy a thing
        _held.append(snapshot)               # it could not hand over
        emit changed

    find_with_stub(verb) -> SimEntityDef?:
        first held snapshot whose offers(verb)
        # the pocket's version of sensor.nearest_with().
        # The inventory implements NONE of those verbs itself.

    release(snapshot): _held.erase(snapshot); emit changed

    describe() -> { slots: "1 / 1", <id>: "<its slot names>" }

    _draw():   # [TEMP] PROTOTYPE carry badge — one dot per held blueprint in
               # the sprite's top-right, tinted from the held thing's SpriteDef.
               # Removal checklist is in the source. Nothing else refers to it.
```

### SimPickUpAbleComponent — target side of pick-up

```
SimPickUpAbleComponent extends SimComponent:    slot = "pickupable"

    signal picked_up(actor)     # [OPEN] no listeners
    stubs() -> ["throw_item"]   # what could be picked up can be thrown back out

    is_available() -> not entity.is_claimed()   # agrees with every other door

    claim(actor) -> SimEntityDef?:
        snapshot = entity.claim_snapshot()
        if snapshot: emit picked_up(actor)
        return snapshot

    # It asks the actor NOTHING. Room to carry and nearness to take are the
    # actor's facts, checked by the actor before it asks.
    #
    # Note this is now byte-for-byte the shape of Consumable.claim() — an
    # affordance is only ever A VERB PLUS A CLAIM.
```

### SimConsumableComponent — target side of eating

```
SimConsumableComponent extends SimComponent:    slot = "consumable"

    signal consumed(actor)
    stubs() -> ["consume"]

    is_available() -> not entity.is_claimed()   # agrees with every other door

    claim(actor) -> SimEntityDef?:
        snapshot = entity.claim_snapshot()
        if snapshot: emit consumed(actor)
        return snapshot

    # [SEAM] Also a DOOR. It deliberately does NOT apply nourishment —
    # ground-eating and pocket-eating must be identical, so both hand the same
    # snapshot to Hunger.eat_snapshot(), and the number comes from
    # SimConsumableDef either way.
```

### Declared but not implemented

```
SimEquipmentComponent  slot="equipment"  stubs=["equip"]       body_slot="hand"
SimPlaceAbleComponent  slot="placeable"  stubs=["place_item"]

# Both exist so the verb vocabulary is in ONE place rather than being invented
# later. No blueprint carries either. Placing has a clear home: the snapshot an
# inventory holds is already enough to respawn one through the factory.
```

---

## 7. The brain

### SimBrainComponent — the TYPE, not an implementation

```
SimBrainComponent extends SimComponent:         slot = "brain"

    is_thinking() -> is_processing()
        # Fatigue switches the brain off during collapse WITHOUT knowing
        # which brain it is switching off.

    # [SEAM] `brain` is a component TYPE — the slot. Each concrete brain is one
    # way of filling it: FSM now, a GOAP planner later. Nothing that talks to
    # "the brain" changes when the planner arrives.
```

### SimBrainDef — where "one brain per entity" is enforced

```
SimBrainDef extends SimComponentDef:            slot = "brain"

    _make() -> SimBrainComponent     # subclasses pick which brain

    build_into(entity):
        if entity.get_component("brain") != null:
            error "'X' already has a brain (a.gd); an entity may hold only
                   one, so b.gd was not built"      # names BOTH scripts
            return
        component = _make()
        _configure(component)
        add + register

    # The check lives on the BASE def, so every future brain kind inherits it,
    # including ones that do not exist yet. Two brains sharing one set of legs
    # would fight over every move_to.
```

### SimBrainFSMComponent — the simple AI

```
SimBrainFSMComponent extends SimBrainComponent:

    states: WANDER | SEEK | FEED
    think_interval = 0.25
    wanted = "pickupable"           # which affordance it goes after
    traits = [SimTrait]             # behaviour modifiers
    wander_radius = 420, wander_pause_min = 0.3, wander_pause_max = 1.2

    cached: _sensor _action _inventory _hunger _movement
    _target, _state, _clock, _wander_wait, _collected

    _ready():
        cache the five components by slot
        require sensor + movement, else warn and switch self off
        _clock = random * think_interval    # stagger, so a whole population
                                            # never thinks on the same frame

    _process(dt):
        countdown _clock -> _think() every think_interval
        if state == WANDER: _step_wander(dt)

    _think():
        1.  if _feed_if_hungry(): return             # hunger has priority
        2.  if inventory and inventory.is_full():
                _target = null; enter WANDER; return # nowhere to put anything
        3.  if not _target_is_valid(): _target = null
        4.  nearest = sensor.nearest_with(wanted)
            if nearest: _target = nearest
        5.  if _target == null: enter WANDER; return
        6.  if action and action.in_reach(_target):
                if inventory and inventory.try_pick_up(_target): _collected += 1
                _target = null; enter WANDER; return
                # taken by us, or beaten to it — either way this target is done
        7.  enter SEEK; movement.move_to(_target.position, WALK)

        # Step 3 is what makes LOSING A RACE harmless: if another animal got
        # there first the target stops being valid, and the next tick retargets
        # to the nearest remaining one, or falls back to wandering.
        #
        # Reach is asked of the HAND; the pick-up is asked of the INVENTORY,
        # which owns that action.

    _feed_if_hungry() -> bool:
        if no hunger or not hunger.is_hungry(): return false

        # pocket FIRST — it costs no travel
        if inventory:
            carried = inventory.find_with_stub("consume")
            if carried:
                hunger.eat_snapshot(carried)   # nothing to walk to, already won
                enter WANDER; return true

        # then the world
        found = sensor.nearest_with_stub("consume")
        if not found: return false
        _target = found
        if action and action.in_reach(found):
            hunger.eat_entity(found)         # eaten where it lies; never
            enter WANDER; return true        # enters the inventory
        enter FEED; movement.move_to(found.position, WALK)
        return true

        # [SEAM] Inventory is a PREFERENCE, not a requirement. An entity with no
        # inventory just skips the first half — which is also what happens when
        # its pocket is empty.

    _target_is_valid():
        target exists, still instance-valid, has `wanted`, and is_available()

    _step_wander(dt):
        return if already moving
        countdown _wander_wait; on expiry:
            _wander_wait = random(pause_min, pause_max)
            movement.move_to(_wander_point(), WALK)

    _wander_point():
        angle    = random(0, TAU)
        distance = sqrt(random()) * wander_radius   # sqrt stops points bunching
        offset   = direction(angle) * distance      # at the centre
        for t in traits: offset = t.adjust_wander(self, offset)
            # each trait gets a say; NO traits means the plain random walk
            # survives untouched
        return clamp(position + offset, world_bounds shrunk by EDGE_MARGIN)

    describe() -> {state, target, collected, wander step, thinks every, traits}
                  + whatever each trait merges in

    # [SEAM] Wander lives INSIDE the brain. It used to be its own component
    # driving movement, which meant arbitrating with the brain. Folding it in
    # deleted the problem instead of solving it.
```

### SimTrait — behaviour as data

```
SimTrait extends Resource:
    trait_name() -> "Trait"
    adjust_wander(brain, offset) -> offset      # return untouched to abstain
    describe(brain) -> {}                       # merged into the Brain tab

    # The brain calls each hook on every trait it carries, in order. A trait
    # that does not care about a hook simply does not override it, so adding a
    # hook never breaks existing traits.
    #
    # `brain` is deliberately UNTYPED: the brain holds an Array of these, so
    # annotating it would make the two scripts reference each other in a cycle.
```

### SimFlockTrait — the first one

```
SimFlockTrait extends SimTrait:

    weight = 0.55           # 0 = plain random walk
    separation = 110
    cohesion_pull = 0.7, separation_pull = 1.3, alignment_pull = 0.5

    _mates(brain):
        detected entities whose def_id == brain.entity.def_id
        # SAME BLUEPRINT — rabbits herd with rabbits, never with berries,
        # and it stays true for any future type without naming one

    _steer(brain):
        classic boids over _mates:
            cohesion  = toward the group centre
            separation= away from anyone closer than `separation`,
                        weighted so closer neighbours push harder
            alignment = with the group's summed velocity
        blend by the three pulls, clamp to unit length

    adjust_wander(brain, offset):
        steer = _steer(brain)
        return offset if steer == 0
        return lerp(offset, steer * brain.wander_radius, weight)

    # Applied ONLY while wandering: an animal that spots food breaks off.
```

---

## 8. World and tooling

### SimEntitySpawnerComponent  [TEMP]

```
SimEntitySpawnerComponent extends SimComponent: slot = "spawner"

    entity_id = "berry", radius = 220, cooldown = 1.0, max_alive = 40
    _clock, _spawned = [], _factory

    _process(dt):
        countdown; on expiry _spawn_one()

    alive():
        _spawned = filter(_spawned, still valid)   # prunes as it goes, so
        return _spawned.size                       # eaten berries free a slot

    _spawn_one():
        _factory ??= tree.first_node_in_group("sim_factory")
            # [SEAM] never a hard node path
        return if alive() >= max_alive
            # without a cap a one-per-second spawner grows without bound, and
            # every one is a body every sensor query must consider
        spawned = _factory.spawn(entity_id, _spawn_point())
        _spawned.append(spawned)

    _spawn_point(): random point in radius, clamped to world bounds

    # [TEMP] Stands in for a berry bush. The real bush is a HarvestableComponent
    # whose ActionDef carries a SpawnOutput — which needs the action system
    # first. The spawner itself is generic (any catalog blueprint) and may well
    # survive as a nest or resource node.
```

### SimDebugComponent

```
SimDebugComponent extends SimComponent:         slot = "debug"

    static mode: OFF | LABELS       # shared, cycled by main.gd on F1
    static attach(entity)           # injected by the FACTORY under DEBUG —
                                    # a dev tool, not content, so no blueprint
                                    # carries it

    _draw():
        entity name, its slot list, and a line to the current destination
        # Sensor and reach radii are NOT here — SelectionMarker draws those for
        # the SELECTED entity only, because a circle per creature is unreadable
        # with a whole population on screen.
```

---

## 9. The def layer, in one table

Every def follows the same shape: `slot()`, optional `stubs()`, and a
`build_into(entity)` that instantiates → configures → adds → registers.

| Def | Builds | Notable |
|---|---|---|
| `SimSpriteDef` | *nothing* | configures the Sprite2D the bare scene already owns, then registers it. Lives in `components` anyway so **everything** about an entity is in one list and the factory keeps zero special cases. |
| `SimMovementDef` | Movement | walk / run / arrive radius |
| `SimSensorDef` | Sensor | radius |
| `SimActionDef` | Action | reach radius |
| `SimInventoryDef` | Inventory | capacity |
| `SimPickUpAbleDef` | PickUpAble | `stubs = [throw_item]` |
| `SimConsumableDef` | Consumable | **`nourishment` lives here and only here** |
| `SimEquipmentDef` | Equipment | `stubs = [equip]` |
| `SimPlaceAbleDef` | PlaceAble | `stubs = [place_item]` |
| `SimBarDef` | *abstract* | every bar tunable; subclasses only pick which component via `_make()` |
| `SimHealthDef` | Health | regen |
| `SimHungerDef` | Hunger | well_fed_above, starve damage, sleep scale |
| `SimFatigueDef` | Fatigue | wake_at, recover, move drain |
| `SimBrainDef` | *abstract* | **the one-brain-per-entity guard** |
| `SimBrainFSMDef` | BrainFSM | think interval, `wanted`, `traits[]`, wander tuning |
| `SimEntitySpawnerDef` | Spawner | entity_id, radius, cooldown, max_alive |

---

## 10. Three flows end to end

### A. Spawn

```
main -> factory.spawn_world()
        for each placement row:
            catalog.get_def(type)              -> blueprint
            instantiate bare entity, add to tree
            for each component def:
                deep-duplicate  -> apply slot overrides
                entity.remember_def(copy)
                copy.build_into(entity)        -> node added + registered
            attach debug overlay if DEBUG
```

### B. Pick up (a race, resolved by the target)

```
brain._think()
  sensor.nearest_with("pickupable")   -> berry
  action.in_reach(berry)?             -> yes
  inventory.try_pick_up(berry)
      is_full()?           no      <- my fact, and every reason I might
      action.in_reach()?   yes        refuse is settled BEFORE I ask,
                                      because asking destroys the target
      berry.pickupable.claim(animal)
          berry.claim_snapshot()
              _claimed?  -> if already true, returns null. Race lost,
                            harmlessly, no matter WHICH door won it.
              detach + free the berry node, hand back the snapshot
      inventory.store(snapshot)      <- store(null) is false, so a lost
                                        race costs nothing
  brain: _target = null, enter WANDER
```

### C. Eat — pocket and ground, one path

```
brain._feed_if_hungry()
  hunger.is_hungry()?  yes

  POCKET:  inventory.find_with_stub("consume") -> snapshot
           hunger.eat_snapshot(snapshot)              # already won
  GROUND:  sensor.nearest_with_stub("consume") -> berry entity
           walk to it, then hunger.eat_entity(berry)
               -> berry.consumable.claim(animal) -> claim_snapshot()
               -> delegates to eat_snapshot()

  hunger.eat_snapshot(snapshot):     # the one implementation
      def = snapshot.find_with_stub("consume")
      restore(def.nourishment)                   # SAME number both ways
      entity.thing_used.emit("consume", snapshot)
          -> inventory hears it; if it holds that snapshot, it releases it
          -> if nothing held it (ground case), nothing happens
```

**Verified identical at +35.0 on both routes.**

---

## 11. The refactor arc — three rounds on one shape

Three consecutive passes over the affordance layer. Each fixed a different symptom
of the same root cause: **knowledge being reconstructed somewhere it did not live.**

### Round 1 — the double-claim bug  (`c3459d5`)

A berry carried two independent claim flags — `PickUpAbleComponent._taken` and
`ConsumableComponent._used` — and nothing linked them:

```
frame N:  animal A -> consumable.claim()   # _used  = false -> passes
          animal B -> pickupable.take()    # _taken = false -> ALSO passes
          => to_resource() ran twice, queue_free() ran twice,
             two animals got a berry that existed once
```

**Fix.** The claim moved onto `SimEntity` as `claim_snapshot()` — one flag, one route
out of the world, shared by every affordance. `PickUpAbleComponent` and
`ConsumableComponent` became **doors**: each adds only its own verb and signal, and
both report availability from `entity.is_claimed()`, so they cannot disagree.

*Root cause:* the fact "this entity has been won" is about the **entity's existence**,
and it was being stored on the affordances instead.

### Round 2 — the type switch in `eat()`  (`e133baa`)

```
# BEFORE
eat(target):
    if target is SimEntityDef: snapshot = target
    if target is SimEntity:    snapshot = target.consumable.claim(self)
    ...
```

That `is` ladder re-derived at runtime something **the caller already knew** — the brain
has separate pocket and ground branches and is never in doubt about which it holds.

**Fix.** Two named entry points, `eat_snapshot(def)` and `eat_entity(target)`, the second
a thin adapter delegating to the first. GDScript has no overloading (a second
`func eat` is a parse error), so the split has to be by name — and by name is the better
shape anyway, because it puts the choice where the knowledge already is.

*The danger was never two entry points; it was two **implementations** reached by
throwing away what the caller knew.* An adapter with no logic of its own cannot drift.

### Round 3 — the inversion  (`0b7424f`)

`PickUpAbleComponent` was reaching into the actor:

```
# BEFORE — the target asking about the actor's pockets
take(actor, inventory) -> bool:
    if _taken: return false
    if inventory.is_full(): return false     # <- the TARGET, reasoning about pockets
    if _taken already ... order matters ...  # <- and a comment warning about it
```

**Fix.** Every actor-side check moved to `SimInventoryComponent.try_pick_up()`, and
`take(actor, inventory)` collapsed to `claim(actor) -> SimEntityDef?` — the same four
lines as `SimConsumableComponent.claim()`.

Two things fell out of it:

- **`PickUpAbleComponent.claim()` and `ConsumableComponent.claim()` are now the same
  shape**, differing only in verb and signal. An affordance is only ever
  **a verb plus a claim**.
- **The ordering hazard was designed out, not managed.** The old code needed a comment
  warning that capacity had to be checked before the irreversible claim. That comment no
  longer exists, because every reason to refuse is now an actor-side fact checked before
  the actor asks. You cannot get the order wrong from inside the target — the target has
  nothing to order.

*The rule this produced:* **each side resolves only what it alone can know.** The message
between them describes an *attempt*, never an outcome. See §12b — this is the rule combat
inherits.

### Verification

**57 assertions across three throwaway headless harnesses** (21 / 19 / 17), each written,
run, and deleted in the round that needed it — never committed, because the repo has no
test toolchain (`CLAUDE.md`: the editor *is* the toolchain).

Between them they cover: both doors report the same availability; a second claim returns
null; an eat and a take in the same frame produce exactly one winner and nothing stored
for the loser; a full inventory refuses **without destroying the target**; out of reach
refuses without destroying it; a non-pickupable target refuses; pocket and ground restore
exactly +35.0 and agree; a claimed entity is detached from the tree in the same frame and
invisible to sensors immediately, freed by the next; `eat_entity` refuses null, a non-food
entity and an already-claimed one; `eat_snapshot` refuses null and a non-food snapshot; no
refusal moves the bar; and an animal built **with no inventory def at all** still eats off
the ground (hunger 10.0 -> 44.3).

**Still true, unchanged:** `remove_child()` before `queue_free()` is load-bearing. A queued
node stays in the tree until end of frame, so without the detach every sensor would keep
reporting a berry that is already spoken for.

---

## 12. PROPOSAL — effects as data, and the mouth

> **Nothing in this section is built.** It is the next design step, written out so it
> can be attacked before it is code.

### The problem, in one sentence

`SimConsumableDef` holds a single `nourishment: float`, and `SimHungerComponent` applies
it — so the day a mushroom restores stamina, poisons for 5 health, or grants +20% speed
for 30 seconds, there is nowhere for that to go.

Three separate faults, worth keeping apart:

1. **One number cannot describe an effect.** `nourishment: float` can only ever mean hunger.
2. **A bar owns an action.** `Hunger` is otherwise a dumb state holder that drains and
   reports; `eat_snapshot()` / `eat_entity()` are the only decisions in the whole bar
   layer, and they sit on the one bar that happens to benefit today.
3. **The wrong component would answer.** If a consumable restores health, does
   `HealthComponent` grow an `eat()` too? That is the same method on three bars.

### The proposal

```
SimEffect extends Resource:               # base — one effect, applied to one actor
    apply(actor: SimEntity) -> void:
        error "not implemented"
    describe() -> ""                      # for the inspector / debug label

SimBarEffect extends SimEffect:           # the only concrete one needed today
    bar    = &"hunger"                    # ANY bar slot: health, hunger, fatigue, ...
    amount = 35.0                         # negative = damage / drain

    apply(actor):
        b = actor.get_component(bar)
        if b: b.restore(amount)           # restore(-x) already spends

SimConsumableDef:
    effects = [SimEffect]                 # REPLACES nourishment: float
                                          # a berry = [SimBarEffect{hunger, +35}]

SimConsumerComponent extends SimComponent:    slot = "consumer"     # "the mouth"

    eat_snapshot(snapshot) -> bool:
        def = snapshot.find_with_stub("consume")   or return false
        for e in def.effects: e.apply(entity)      # <- the ONE place effects land
        entity.thing_used.emit("consume", snapshot)
        return true

    eat_entity(target) -> bool:               # unchanged adapter, moved wholesale
        c = target.find_with_stub("consume")  or return false
        return eat_snapshot(c.claim(entity))

SimHungerComponent:
    # eat_snapshot / eat_entity DELETED. Back to being a bar: drains, reports
    # is_hungry(), slows while asleep, damages health at zero. Nothing else.

SimBrainFSMComponent._feed_if_hungry():
    # _hunger.eat_*  ->  _consumer.eat_*
    # _hunger stays, but only to ask is_hungry(). Deciding to eat and being able
    # to eat become two different questions asked of two different components —
    # which is correct: a creature can be hungry and have no mouth.
```

### Why it fits what already exists

- `SimBarComponent.restore()` is **already generic** and bars **already** register under
  their own slots, so `SimBarEffect` is a slot lookup plus one call. One class covers
  health, hunger, fatigue and any future stamina or mana bar **with no new code**.
- Effects are Resources, so they are authored in the inspector like everything else —
  rule 4, *content is data*, holds.
- The claim layer is untouched. Round 3's shape survives exactly: the target still just
  hands itself over; only what the actor *does* with the snapshot changes.
- `capability = component presence` gets sharper, not weaker: no `consumer` slot → the
  entity physically cannot eat, which is a thing a real design needs (a plant, a rock, a
  sleeping infant).

### What it deliberately does NOT solve

**Timed stat modifiers** — "+20% speed for 30 s", "+5 attack until dawn". `SimBarEffect`
cannot express these and should not be stretched to, because they need **two** systems
that do not exist:

1. a **status system** — something must hold the modifier, count it down, and remove it;
2. a **stat pipeline** — `move_speed` is currently a plain field on `SimMovementComponent`
   read directly every frame. There is no `base` vs `current`, and no place for a
   multiplier to live.

That is its own design step, after this one. Building it *into* effects now would put a
timer system inside a Resource.

### Argue with this

1. **Should `SimEffect` just BE the concept doc's `StatOutput`?** `COLONY_SIM_CONCEPT.md`
   §4 already specifies `StatOutput {bar, amount, to: actor|target}` as one of `ActionDef`'s
   three output forms. `SimBarEffect` is that, minus the `to:` field, arriving early. If
   actions-as-data (step 4) is coming anyway, building a second vocabulary for the same
   idea is a mistake — but building `StatOutput` now means importing `ActionDef`'s whole
   actor/target direction concept before there is an action system to need it.
   **This is the most important question in this document.**
2. **Does the actor apply the effect, or does the effect apply itself?** Written above,
   `effect.apply(actor)` — the data reaches into the actor. The alternative is
   `consumer.apply(effect)`, where the component switches on effect type, which is the
   type switch of Round 2 all over again. Is a Resource that mutates a live entity the
   right dependency direction, or is it the concept doc's `EatableComponent` (target
   resolves, calls `actor.hunger.feed()`) wearing a different hat?
3. **Is the mouth a component at all**, or should `consume` dispatch generically —
   the entity finds *whichever* of its components implements the verb, the way
   `find_with_stub()` already works on the target side? That would make the actor side
   symmetric with the target side, at the cost of a second dispatch mechanism.
4. **Does `SimBarEffect.bar` being a `StringName` cost too much safety?** A typo
   (`&"hungr"`) silently does nothing, and it is authored in the inspector. The
   alternative — each bar advertising which effects it accepts — is more code for a
   mistake the debug labels would show immediately.
5. **Where does diet go?** `COLONY_SIM_CONCEPT.md` §4 gates eating on
   `FoodType ∈ actor.diet`. Under effects-as-data nothing gates anything: any creature
   can eat any consumable. Is diet an actor-side check in `SimConsumerComponent` (an
   actor fact — §12b says yes), or a `[SEAM]` too far?

### 12b. The damage question, stated so it can be argued about

The same question — *where does logic live* — but with a case where **both** sides have
real facts to contribute. Two rules are currently on the table, and they are not the same:

| | Rule | Source |
|---|---|---|
| **A** | "Actor declares, target resolves." The actor component is a thin capability marker with no effect logic; the target owns the resolution. | `COLONY_SIM_CONCEPT.md` §2 (the target design) |
| **B** | "Each side resolves only what it alone can know." The message describes an *attempt*; each end computes its own half. | as built, `0b7424f` (§11 Round 3) |

For **pick-up** they agree. For **damage** they come apart:

```
# Under B — the shape the working code is already in
SimDamage extends Resource:               # a value object, not a component
    amount, type, source

attacker side  (AttackComponent):         # facts only the attacker can know
    weapon damage, strength, crit roll, whether it is a backstab
    -> builds a SimDamage and offers it

target side    (HealthComponent):         # facts only the target can know
    armour, resistance to `type`, dodge chance, "graze" reduction, invulnerability
    -> decides what actually lands, then spends it

# Adding a new defence NEVER touches the attacker. Adding a new weapon NEVER
# touches the defender. Neither computes the other's half.
```

Open, and genuinely undecided:

- **Where does the crit roll live?** It is an attacker fact (crit chance is on the
  weapon), but a target with "cannot be critically hit" needs a say. Does the attacker
  roll and send `is_crit`, and the target is free to ignore it? That is rule B — but it
  means the message carries a partial *outcome*, which is exactly what B forbids.
- **Is eating an exception to B, or does B just say something uncomfortable?** Under
  rule A, `EatableComponent` would call `actor.hunger.feed(value)`. As built, the target
  is a door and the *actor* applies the nourishment — even though the amount is target
  data. B's answer: nourishment is a fact only the food knows, and *what a body does with
  it* is a fact only the body knows, so the number travels and the actor applies it. Does
  that generalise, or is it a story told after the fact?
- **The interface is already waiting.** `SimEntity.do_actions()` / `receive_actions()`
  exist and return `[]`, listed as intentionally-unused API. The concept doc's
  `do ∩ receive` intersection is what fills them, and it needs `ActionDef` first.

---

## 13. Open questions worth challenging

**Architecture**

1. **Does GOAP replace `SimBrainComponent`, or sit behind it** — planner in
   front, the current FSM as executor? Decide before more brain code is written.
2. **Actions are still hardcoded.** Step 4 is not finished until
   `ActionDef {input, time, output, mode}` exists, because that is what a
   planner reads preconditions and effects from. See §12 question 1 — the effects
   proposal and `ActionDef.StatOutput` may be the same thing and should probably not
   be built twice.
3. **Items are not data.** Pick-up stores a whole entity blueprint. A small
   `SimItemDef` (id, colour, food value) was specified in
   `COLONY_SIM_CONCEPT.md §2` and never built. It would also remove the carry
   badge's colour parameter. Note the tension: §12 wants `effects` on the
   *consumable def*, which is the thing a `SimItemDef` would replace.
4. **`stubs()` is duplicated on component and def.** Justified by the
   live-vs-snapshot split — but is a snapshot that can answer questions about
   itself the right model, or should a snapshot be inflatable back into a
   throwaway entity instead?
5. **Bars poll in `_process`.** Fourteen entities is fine; a colony is not.
   Tick-batching or a shared needs system is unexplored.
6. **Sensor queries are recomputed per call.** `get_detected()` runs up to three times
   per think tick, rebuilding the identical list from `get_overlapping_areas()`. Two
   candidate fixes: memoise per frame (cheap, self-correcting), or have the sensor keep
   a list maintained by `area_entered` / `area_exited` (faster, but hand-maintained
   state that can go stale, and the codebase depends on entities vanishing *immediately*).
   At ~45 entities neither is worth doing; at colony scale the real answer is a spatial
   hash replacing N per-entity Area2Ds. `area_entered` **is** the right shape for
   *reactive* sensing, which step 7 (flee / predation) will want.

**Tuning — unresolved numbers**

- Hunger / energy drain rates; starvation damage per tick.
- Passive fatigue drain, or only movement and actions?
- Do berry bushes deplete (give them a `HealthComponent`) or stay infinite? Regrowth timer?
- Live-harvest numbers (10 energy / 2 meat / 35 dmg) — defaults?
- `Hunt` instant vs damage-over-work-time.
- Danger rise/decay rates; the danger → flee curve shape.
- Does extreme hunger wake a safe sleeper?
- **Chase balance:** predators run 1.4× prey, so a committed chase always wins.
  Aggro/give-up mechanic, or rely on prey's 1.3× detection as the counterweight?

**Deferred**

- The three-creature design (vigilant vs fast prey, one predator) still stands
  in the concept doc. The current two-type world exists to test component
  interaction, not to replace it.
- Wander is a pure random walk with no memory of where an entity has already
  searched. The last berry on a large map can take minutes to find.

---

## 14. The world as it stands

| | `animal` | `berry` | `berry_spawner` |
|---|---|---|---|
| Components | sprite, movement, sensor, action, inventory, brain, health, hunger, fatigue | sprite, pickupable, consumable | sprite, spawner |
| Tuning | walk 130 / run 260, sensor 420, reach 56, capacity 1, think 0.25 s, wander step 420 | nourishment 35 | berry, radius 1000, every 5 s, max 40 alive |
| Bars | health 100 (regen 1/s when fed), hunger 100 (drain **1.0/s**), fatigue 100 (drain **0.5/s** idle, +1.5/s moving) | — | — |
| Traits | `SimFlockTrait` (0.55 / 110) | — | — |

`world1.tres`: 5 × `animal`, 1 × `berry_spawner`. No pre-placed berries.

**Controls:** left-click an entity to inspect (+ its sensor and reach circles) ·
click bare ground to clear · **F1** debug labels · **F5** respawn.
