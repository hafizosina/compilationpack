# Plan — flags, intents, and items as records (step 6 on the stripped core)

Scope: finish step 6 without the combat layer. The brain stops being read by the systems
that act on its decisions; they read **flags** instead. On the way, carried items stop
being live entities and become **records**, and a carrier's death puts them back into the
world.

**Out of scope, deliberately:** combat and `AttackIntent`, predators, corpses and looting,
bag capacity, stacking, durability or anything else ticking on a carried item, and step 7.
Each sits on top of this without changing it.

---

## 1. Vocabulary — components and flags

| | Component | Flag |
|---|---|---|
| Says | what the entity **is** | what is true of it **now** |
| Present | from spawn to death | added and removed freely |
| Data | authored (`@export`, from blueprint or placement) | runtime only, never `@export` |
| Examples | Hunger, Movement, Body, Inventory, Position | Selected, Collapsed, Asleep, EatIntent, Dying |

A wall that gains movement is no longer a wall; that is a kill and a spawn, not an `add()`.

**It is a guideline, not an enforced rule.** Break it when there is a good reason, and
write the reason down where the break happens. Nothing in `EcsWorld` rejects it.

Flags extend a new `EcsFlag` (itself an `EcsComponent`, so the store, queries and
`has()` treat them identically). Class names use the `Flag` suffix.

**Singletons are a third kind.** They belong to the world, not an entity. A new
`EcsSingleton` base (an `EcsComponent`, so `add_singleton`/`get_singleton` are unchanged),
and `EcsLifecycleComponent` → `EcsLifecycleSingleton`, `EcsSelectionComponent` →
`EcsSelectionSingleton`.

---

## 2. Flags

| flag | data | added by | removed by | read by |
|---|---|---|---|---|
| `EcsSelectedFlag` | — | selection | selection | selection, inspect, debug |
| `EcsCollapsedFlag` | — | energy | energy | brain, hunger, energy |
| `EcsAsleepFlag` | — | brain | brain | hunger, energy |
| `EcsEatIntentFlag` | `target: int`, `record_uid: String` (one set) | brain | brain | consume |
| `EcsTakeIntentFlag` | `target: int` | brain | brain | pickup |
| `EcsDyingFlag` | — | consume, pickup, health | — (entity destroyed) | lifecycle, drop, every executor |

Selected and Collapsed are renames of the existing tag components (`.gd` + `.gd.uid`
moved together, then the headless validation).

### Intent flags and brain state

`EcsLowBrainComponent.state` stays: it is the FSM's memory and the overlay's label. The
flags are the brain's **instructions**, and every state change goes through one helper,
`_set_state()`, that writes `state` and adds/removes the matching flag together, the same
way `_set_trip()` is the only place a destination is written.

| state | flag |
|---|---|
| EAT | `EcsEatIntentFlag` |
| TAKE | `EcsTakeIntentFlag` |
| SLEEP | `EcsAsleepFlag` |
| IDLE, WANDER, SEEK_FOOD | none; their only instruction is the destination |

**No `MoveIntent` flag yet — decided, deferred.** The destination stays a field on
`EcsMovementComponent` until this proof of concept has run; revisit after.

An intent **names its target**, so the brain chooses *which* berry and the executor only
checks it is still there. Bag-before-ground moves from `EcsConsumeSystem` into the brain;
the test that watches the bag stay empty still pins the behaviour.

The brain owns an intent's lifetime, so EAT stays up across the ticks between 20 Hz brain
runs and the bite rate is unchanged.

### After this, who reads `EcsLowBrainComponent`

Only the brain, the debug overlay and the inspector. Consume, pickup, hunger and energy
stop importing it.

---

## 3. Dying is the claim

`EcsLifecycleComponent.kill_requests` goes. A system that wants something dead adds
`EcsDyingFlag`; the lifecycle stage destroys everything carrying it at the top of the next
tick. Death is still deferred, so every system in a tick sees the same set of entities.

The flag lands in the store **instantly**, so it is also the claim: an item is available
only if it is alive **and not Dying**. Every executor that takes or eats asks exactly
that, and the brain's `_is_food` / `_is_takeable` ask it too, so nothing commits to a
berry that is already gone.

This is the Valheim/Minecraft duplication fix: one authority checks and commits in one
step. Systems run one at a time, so the executor *is* that authority, and no entity
learns another's intent. A brain may still decide on a claimed berry; the executor
refuses it, and the brain decides again next tick.

**It fixes a bug that exists today.** Consume runs before pickup. A rabbit eating a berry
off the ground writes a kill note but leaves the berry's position; a monkey touching the
same berry that tick takes it anyway, and carries a dead id that `_from_bag` silently
skips.

---

## 4. Carried items are records

Picking up **kills** the item and puts an `EcsItemRecord` in the bag. This reverses step
3's "items stay entities" (and `EcsInventoryComponent`'s header). The reason: in most
games an item in a bag, chest or shop is not a live entity, and what a carried item should
*do* (durability, rot) is deferred.

```
EcsItemRecord (RefCounted)
  uid:        String                # survives pickup and drop
  type_id:    StringName
  components: Array[EcsComponent]   # snapshot: every component (Position included), no flags
```

**Copy every component, no flags.** Position included: it goes stale in the bag and
nothing reads it there; the drop overwrites it with the new spot. Flags are what is true
*now* of an entity that is about to stop existing, so none are kept: one `is EcsFlag`
check, and a dropped berry does not come back selected.

**Snapshot, not a catalog lookup.** The catalog only holds a type's defaults, not the
per-placement overrides; nobody knows yet what a future item will need, so the record
copies everything. Consume reads `nutrition` from the snapshot's `EcsConsumableComponent`.

**Snapshot copies by reflection — measured, not assumed.** A headless probe showed
`Resource.duplicate()` (deep or not) copies only `@export` fields: an energy component at
`value = 12.5` came back at the default 100, a bag holding `[4, 5]` came back empty. The
snapshot therefore walks `PROPERTY_USAGE_SCRIPT_VARIABLE`, the same walk the inspector
does, and deep-copies Arrays and Dictionaries; the same probe confirmed exported and
runtime fields both survive and the copy's arrays are independent. Limit: a field holding
an object (a record inside a copied bag) is shared, not copied. Nothing does that yet.

**`uid`**: a new runtime field on `EcsNameComponent`, generated by the manager at first
spawn from `Crypto.generate_random_bytes(16)` (hex), and carried by the record. The int
id is the store's key and may change; the uid is who the thing is.

One record = one slot. `capacity` counts records. Stacking and a capacity system are later.

Pickup becomes: target is takeable and not Dying → snapshot → append record → add
`EcsDyingFlag`. Position is never removed, so `EcsNodeSyncSystem`'s "has nodes but no
position" branch goes.

---

## 5. Death puts items back

New `EcsDropSystem`: for each entity with `EcsDyingFlag` + `EcsInventoryComponent` +
`EcsPositionComponent`, write one spawn request per record at the entity's position. The
lifecycle stage builds them from the record's components instead of from the blueprint,
setting the copied Position to the drop spot. Nodes come out of `NODE_KIND` as always, so
the manager gains a spawn path but no knowledge of item types.

Berries are not solid, so several dropping on one spot stack there. They belong to no
bush, so they do not count against any litter cap.

Runs late in the pipeline (after pickup), so anything that kills a carrier earlier in the
tick is covered.

**This also fixes a leak that exists today.** Nothing handles a bag on death, so a dead
monkey's berries stay alive forever with no position and no holder.

Later, for a real game: death by health leaves a corpse that can be looted instead of
dropping. The record and the drop path are what that will build on.

---

## 6. Inspector

Components keep one tab each, built by reflection. **One "Flags" tab** lists every flag
the entity carries, one line each, data inline (`EatIntent → berry #42`). The inventory
tab lists records as `type_id (uid prefix)`.

---

## 7. Tests — `tests/lifecycle_test.gd`

- Existing `State.` assertions move to flags where they are really asserting an instruction.
- Executors without a brain: an entity with `EcsEatIntentFlag` and no brain eats; the
  same for take.
- `EcsAsleepFlag` alone slows hunger and refills energy.
- Every brain state change leaves exactly the matching flag, or none.
- Claim: two takers on one berry in one tick → one record, one Dying berry.
- Race: a grazer eats and a carrier touches the same berry in one tick → the berry is
  eaten, and the bag stays empty.
- Snapshot: an overridden `nutrition` survives pickup and is what eating adds.
- Drop: a carrier with two records dies → next tick two berries at its spot, same uids,
  new ids, snapshot values intact, and a hungry grazer can eat them.
- Bag-stays-empty (eat over take) still passes unchanged.

## 8. Measure

Stress ramp before and after, same spacing. A state change is now a store add/remove
instead of a field write; report the number, do not claim it is free.

## 9. Order of work — one commit each, tests green at every step

1. The `SIZES` edit on its own.
2. `EcsFlag` and `EcsSingleton`; Selected and Collapsed become flags, Lifecycle and
   Selection become singletons; inspector Flags tab. No behaviour change.
3. `EcsDyingFlag` replaces `kill_requests`; the claim check; race test.
4. Intent flags and `_set_state()`; executors, hunger and energy read flags.
5. Records, uid, snapshot; pickup kills.
6. `EcsDropSystem` and the drop tests.
7. Docs: HANDOFF §1/§4/§7, CLAUDE.md (counts, pickup, the component/flag guideline).
8. Energy start variance (separate from step 6, below).

## 10. Energy start variance — unrelated, same session

Answers `ENERGY_PLAN.md` §7: every animal spawns full with the same drain, so the whole
population sleeps at once.

`EcsEnergyComponent` gets `@export start_min` / `start_max`, fractions of `max_energy`
(default 1.0 / 1.0, so nothing changes unless a blueprint authors it). `value` starts at a
`-1` sentinel and **`EcsEnergySystem` rolls it the first time it sees the entity**. It is
not rolled in the manager, which never switches on component type, and not per placement,
because a runtime-spawned animal would miss it (the speed-variance problem). Energy runs
before the brain and the overlay, so nothing reads the sentinel. Rabbit and monkey
blueprints get e.g. 0.5–1.0. Test: two animals of one blueprint start at different energy.

