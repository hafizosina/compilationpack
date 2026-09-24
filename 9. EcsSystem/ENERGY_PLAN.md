# Plan — EcsEnergyComponent (the remainder of step 4)

Scope: energy, sleep, and collapse — nothing else. It lands on the stripped 15-stage core
and follows the rules the module already keeps: data-only components, one system per
consequence, the brain decides and systems execute, capability is component presence.

**Out of scope, deliberately:** Danger, predators, beds, health regen, wake-to-flee. Each
sits on top of this without changing it.

---

## 1. Direction of the bar

`EcsEnergyComponent.value` is a **reserve**: `max_value` = rested, 0 = exhausted. The name
decides it — a bar called energy that fills as you tire reads wrong in the inspector. This
matches the concept doc's Fatigue exactly (collapse at 0, lock to 50, auto-wake at 100).

Hunger stays a need (climbs toward starving). Two conventions is acceptable as long as
each bar is named for what its number means; thresholds stay authored per bar either way.

---

## 2. Data

### `EcsEnergyComponent` (new)

| field | kind | default | meaning |
|---|---|---|---|
| `max_value` | export | 100 | full |
| `value` | runtime | = `max_value` | current reserve |
| `drain_idle` | export | 0.5 /s | cost of being awake |
| `drain_moving` | export | 1.0 /s | extra while velocity is non-zero |
| `restore` | export | 1.0 /s | gain while asleep |
| `rest_at` | export | 30 | at or below, the brain may choose SLEEP |
| `wake_at` | export | 100 | voluntary sleep ends on its own |
| `collapse_release` | export | 50 | collapse lock lifts here |
| `collapse_damage` | export | 20 | one-shot, at the moment of collapse |

`rest_at` < `wake_at` is the hysteresis: a creature never flickers between sleeping and
waking around one line. Passive drain answers the concept doc's open question for now —
without it an idle, well-fed creature never tires. Both drains are authored, so "only
movement tires" is a `.tres` edit (`drain_idle = 0`), not a code change.

### `EcsCollapsedComponent` (new, tag)

No fields. **Presence is the lock.** Added at energy 0, removed at `collapse_release`. It
is how the energy system tells the brain "you have no say right now" without writing the
brain's component — the same line `EcsHungerSystem` keeps by writing health, never the brain.

### `EcsLowBrainComponent` (changed)

One new state value: `SLEEP`. No new fields.

### Blueprints

Rabbit and monkey get `EcsEnergyComponent`. Berries and bushes do not, so they never sleep
and nothing had to tell them not to. Rabbit/monkey can share defaults for the first pass.

---

## 3. Who does what

### `EcsEnergySystem` (new) — owns the consequences of energy

Per entity with `EcsEnergyComponent`:

1. **Drain or restore.** If `low_brain.state == SLEEP` (or it is collapsed): `+restore * delta`.
   Otherwise `-(drain_idle + drain_moving if moving) * delta`. Clamp to `[0, max_value]`.
   Reading the brain's `state` is the executor pattern already used by `EcsConsumeSystem`
   for `EAT`: the brain decides SLEEP, this system makes sleep *mean* something.
2. **Collapse.** Crossing into 0 without `EcsCollapsedComponent`: add it, and subtract
   `collapse_damage` from `EcsHealthComponent` **once**. No health component → collapses
   without damage, as a creature without health starves forever today.
3. **Release.** Collapsed and `value >= collapse_release`: remove the tag.

It writes `value`, the tag, and health. It never writes the brain or movement.

### `EcsLowBrainSystem` (changed) — decides, as now

New rung order, top wins:

```
collapsed?                           → SLEEP, clear destination, nothing else runs
SLEEP and not (rested or starving)   → stay SLEEP
hungry enough to eat?                → EAT        (unchanged)
peckish, bag has room?               → TAKE       (unchanged)
hungry, sees food?                   → SEEK_FOOD  (unchanged)
energy <= rest_at?                   → SLEEP, clear destination
otherwise                            → IDLE / WANDER (unchanged)
```

- **rested** = `value >= wake_at`. **starving** = hunger pinned at `max_value` — the
  existing definition, no new tunable. That is the design's "wake to eat if starving".
- **Food outranks rest.** A tired, hungry creature with food in sight goes for it; one with
  nothing in sight sleeps. Entering SLEEP is only from IDLE/WANDER — a `SEEK_FOOD`
  commitment is not reconsidered, which keeps §1's rule. A creature that keeps finding food
  can therefore run itself to collapse; that is the price the design wants, not a bug.
- **Entering SLEEP goes through the one destination helper** so the trip clock is zeroed.
  Movement then has no destination and zeroes velocity by itself — movement learns nothing.

### Pipeline position

```
lifecycle > spawner > hunger > energy > health > sensor > low_brain > consume > movement > …
```

`energy` sits beside `hunger` for the same reason: a collapse's damage and a resulting
death land in the same tick. It reads last tick's `state`, so restoring starts one tick
after the brain chooses SLEEP — invisible, and the reason is written down here so no one
"fixes" it by moving the stage.

---

## 4. Tests — `tests/lifecycle_test.gd`

- awake creature drains at `drain_idle`, faster while moving
- at `rest_at` with no food rung firing, the brain enters SLEEP; destination cleared,
  velocity zero next tick
- asleep restores at `restore`; wakes on its own at `wake_at`
- hovering around `rest_at` does not flicker (hysteresis)
- a voluntary sleeper wakes when hunger pins at max
- hungry creature with food in sight seeks it instead of sleeping; a `SEEK_FOOD` trip is
  not cut short by tiredness
- at 0: tag added, health down by exactly `collapse_damage` **once** over many ticks
- collapsed + starving: stays asleep (the lock holds)
- at `collapse_release`: tag removed, and it is now an ordinary sleeper that starvation
  can wake
- no health component → collapse without error; no energy component → never sleeps

## 5. Stress test — the lesson from last session

- **Add `energy` to the stress test pipeline in the same commit.** Last time three stages
  were missing and a day of numbers measured a program that was not shipped.
- Price it with `--n=4000 --skip=energy` against `--n=4000`, back to back, two runs each.
  Expect roughly one `hunger`-sized stage.
- Note that sleeping entities skip movement and most brain work, so a sleeping population
  may measure *cheaper*. Report it; do not bank it.

## 6. Visible

The inspector picks up `Energy` and `Collapsed` tabs by reflection — no edit. One optional
addition to `EcsDebugOverlay`: a small "z" on entities in SLEEP, a different mark for
collapsed. Nice to have, not required to land.

## 7. Open, decide before or during

- **Synchronised sleep.** Every animal spawns at full energy with the same drain, so the
  whole population naps together. Options: an authored start range on the blueprint, or
  per-placement values like speed variance. Pick one before judging how it looks.
- **Does hunger rise while asleep?** Plan says yes (hunger system is untouched), which is
  what makes "starving wakes you" reachable. Confirm that is wanted.
- **Defaults are a first guess.** 1.0/s drain, 30 → 100 gives ~70 s awake and ~70 s asleep
  per cycle. Tune by watching, not by arithmetic.

## 8. What this unlocks

SLEEP is the first state worth preempting *for*: collapse overrides everything, and
starvation interrupts voluntary sleep. That is step 6's preemption machinery getting its
first real consumer — and the slot the Danger bar drops into later, as one more wake
condition, with nothing above rewritten.
