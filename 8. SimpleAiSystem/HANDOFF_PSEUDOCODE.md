# Module 8 — Component Pseudocode Handoff

> **Purpose:** a self-contained, paste-able description of every component in
> `8. SimpleAiSystem`, written as pseudocode rather than GDScript, so the design
> can be argued about away from the editor.
>
> Companion docs in the same folder: `HANDOFF.md` (state of the build, locked
> decisions) · `PROJECT_DEFINITION.md` (why / scope) ·
> `COLONY_SIM_CONCEPT.md` (target architecture) · `MILESTONE_1_SPEC.md` (spec + numbers).
>
> Matches the working tree as of the `claim_snapshot()` refactor. If the code has
> moved on, this doc has not.

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
| `consume` | ConsumableComponent / ConsumableDef | yes — HungerComponent.eat() |
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

    eat(snapshot: SimEntityDef) -> bool:
        # ONE eating path, because there is ONE kind of argument. Whoever calls
        # this already resolved the thing into a snapshot: a pocket holds one
        # outright, something on the ground is won via claim_snapshot() first.
        # The caller always knows which case it is in — the brain has separate
        # branches for exactly that — so nothing here asks what it was handed.
        # No type switch, no Variant.
        if snapshot == null: return false
        def = snapshot.find_with_stub("consume")   or return false
        restore(def.nourishment)             # amount lives ONLY on the def
        entity.thing_used.emit("consume", snapshot)
        return true
        # [SEAM] Hunger never touches Inventory. It ANNOUNCES. If an inventory
        # happens to hold that snapshot, that inventory drops it.

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
        if is_full(): return false
        action = entity.get_component("action")   or return false
        if not action.in_reach(target): return false
        pickable = target.get_component("pickupable")  or return false
        return pickable.take(entity, self)
        # [SEAM] "actor asks, target resolves". The dependency runs ONE way:
        # inventory needs a hand; the hand knows nothing about inventories.

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

    take(actor, inventory) -> bool:
        if inventory == null or inventory.is_full(): return false
            # capacity FIRST: claim_snapshot() is irreversible, so a full
            # inventory that claimed first would destroy the thing and
            # store nothing
        snapshot = entity.claim_snapshot()   or return false
        inventory.store(snapshot)
        emit picked_up(actor)
        return true

    # A DOOR, not a mechanism. Winning the entity belongs to
    # SimEntity.claim_snapshot(); this adds only what is specific to carrying.
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
    # snapshot to Hunger.eat(), and the number comes from SimConsumableDef
    # either way.
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
                hunger.eat(carried)          # nothing to walk to
                enter WANDER; return true

        # then the world
        found = sensor.nearest_with_stub("consume")
        if not found: return false
        _target = found
        if action and action.in_reach(found):
            c = found.find_with_stub("consume")
            hunger.eat(c.claim(self.entity)) # WON first, then eaten. What comes
            enter WANDER; return true        # back is exactly what a pocket
                                             # holds, which is why eat() needs
                                             # only one path. Never enters the
                                             # inventory.
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
      is_full()?           no
      action.in_reach()?   yes
      berry.pickupable.take(animal, inventory)
          inventory.is_full()?  -> capacity checked BEFORE anything is
                                   destroyed, because the next line cannot
                                   be undone
          berry.claim_snapshot()
              _claimed?  -> if already true, returns null. Race lost,
                            harmlessly, no matter WHICH door won it.
              detach + free the berry node, hand back the snapshot
          inventory.store(snapshot)
  brain: _target = null, enter WANDER
```

### C. Eat — pocket and ground, one path

```
brain._feed_if_hungry()
  hunger.is_hungry()?  yes

  POCKET:  inventory.find_with_stub("consume") -> snapshot
           hunger.eat(snapshot)                       # already won
  GROUND:  sensor.nearest_with_stub("consume") -> berry entity
           walk to it, then
           hunger.eat(berry.consumable.claim(animal)) # win it, THEN eat

  hunger.eat(snapshot):        # ONE argument type; the caller resolved it
      def = snapshot.find_with_stub("consume")
      restore(def.nourishment)                   # SAME number both ways
      entity.thing_used.emit("consume", snapshot)
          -> inventory hears it; if it holds that snapshot, it releases it
          -> if nothing held it (ground case), nothing happens
```

**Verified identical at +35.0 on both routes.**

---

## 11. Fixed: the double-claim bug

**What it was.** A berry carried two independent claim flags —
`PickUpAbleComponent._taken` and `ConsumableComponent._used` — and nothing linked them:

```
frame N:  animal A -> consumable.claim()   # _used = false -> passes
          animal B -> pickupable.take()    # _taken = false -> ALSO passes
          => to_resource() ran twice, queue_free() ran twice,
             two animals got a berry that existed once
```

**The fix.** The claim moved onto `SimEntity` as `claim_snapshot()` — one flag, one
route out of the world, shared by every affordance. `PickUpAbleComponent` and
`ConsumableComponent` became doors: each adds only its own verb and signal, and both
report availability from `entity.is_claimed()`, so they cannot disagree.

The same change removed the type switch from `Hunger.eat()`. It had been taking an
untyped `target` and re-deriving with `is` checks whether it was a snapshot or a world
entity — information the **caller already had**, since the brain has separate pocket
and ground branches. `eat()` now takes a `SimEntityDef` and nothing else; the ground
branch wins the entity first and passes the snapshot.

**Verified** with a throwaway headless harness (21 assertions), covering: both doors
report the same availability; a second claim returns null; an eat and a take in the
same frame produce exactly one winner and nothing stored for the loser; a full
inventory refuses without destroying the berry; pocket and ground both restore exactly
+35.0; a claimed entity is detached from the tree in the same frame and invisible to
sensors immediately, freed by the next; `eat()` refuses null and refuses a non-food
snapshot without touching the bar.

**Still true, unchanged:** `remove_child()` before `queue_free()` is load-bearing. A
queued node stays in the tree until end of frame, so without the detach every sensor
would keep reporting a berry that is already spoken for.

---

## 12. Open questions worth challenging

**Architecture**

1. **Does GOAP replace `SimBrainComponent`, or sit behind it** — planner in
   front, the current FSM as executor? Decide before more brain code is written.
2. **Actions are still hardcoded.** Step 4 is not finished until
   `ActionDef {input, time, output, mode}` exists, because that is what a
   planner reads preconditions and effects from.
3. **Items are not data.** Pick-up stores a whole entity blueprint. A small
   `SimItemDef` (id, colour, food value) was specified in
   `COLONY_SIM_CONCEPT.md §2` and never built. It would also remove the carry
   badge's colour parameter.
4. **`stubs()` is duplicated on component and def.** Justified by the
   live-vs-snapshot split — but is a snapshot that can answer questions about
   itself the right model, or should a snapshot be inflatable back into a
   throwaway entity instead?
5. **Bars poll in `_process`.** Fourteen entities is fine; a colony is not.
   Tick-batching or a shared needs system is unexplored.

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

## 13. The world as it stands

| | `animal` | `berry` | `berry_spawner` |
|---|---|---|---|
| Components | sprite, movement, sensor, action, inventory, brain, health, hunger, fatigue | sprite, pickupable, consumable | sprite, spawner |
| Tuning | walk 130 / run 260, sensor 420, reach 56, capacity 1, think 0.25 s, wander step 420 | nourishment 35 | berry, radius 1000, every 5 s, max 40 alive |
| Bars | health 100 (regen 1/s when fed), hunger 100 (drain **1.0/s**), fatigue 100 (drain **0.5/s** idle, +1.5/s moving) | — | — |
| Traits | `SimFlockTrait` (0.55 / 110) | — | — |

`world1.tres`: 5 × `animal`, 1 × `berry_spawner`. No pre-placed berries.

**Controls:** left-click an entity to inspect (+ its sensor and reach circles) ·
click bare ground to clear · **F1** debug labels · **F5** respawn.
