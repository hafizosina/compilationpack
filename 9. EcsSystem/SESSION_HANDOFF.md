# Session handoff — 2026-09-23/24

Written at commit `80d9a30`. Companion to `HANDOFF.md`, which is the living
state-of-the-build; this file is only what *this* session changed, decided and got wrong,
so the next session does not re-derive or re-litigate any of it.

---

## Where the project stands

Module 9 is the only live simulation and the main scene. **17 components, 15 systems**,
**95/95 checks** in `tests/lifecycle_test.tscn`, headless validation clean.

```
lifecycle > spawner > hunger > health > sensor > low_brain > consume >
movement > collision > pickup > selection > node_sync > debug > census > inspect
```

Plan status: **steps 3, 4 and 5 done; step 6 half done** (the FSM exists, intent components
and a state worth preempting for do not); step 7 untouched. Fatigue is the one piece of
step 4 deliberately skipped — it needs sleep to mean anything, and sleep is a brain state
with no consumer.

**Git: 11 commits this session, 3 not yet pushed to `origin/main`.** Tree clean.

---

## What changed, in order

| commit | what |
|---|---|
| `28d5ae9` | a trip is a budget; a body is not always solid |
| `6c8ffbc` | one brain with state, replacing the run-order ladder |
| `990f1d6` | hunger and health, and eating with or without a bag |
| `5fb9e38` | reach is whatever physics last reported |
| `7830f17` | the overlay shows shapes, not sentences |
| `329fbdb` | rabbits outrun monkeys, and every animal its own pace |
| `e662570` | taking is a decision too, and carrying is provisioning |
| `107033c` | the stress test was measuring a pipeline we do not ship |
| `f1affa3` | grid spacing is a knob; what crowding costs |
| `bb56732` | the floor — what an entity costs before it interacts |
| `80d9a30` | retract the 70% regression |

The session began as a bug report — "entities get stuck" — and the through-line of
everything after it is the same move: **something was acting without anything having
decided it.** A destination that never expired, a body that blocked because it happened to
be visible, a pickup that fired on proximity alone.

---

## Decisions settled — do not reopen without the author

1. **One brain, not a rung per behaviour.** `EcsForageSystem` was deleted into
   `EcsLowBrainSystem`. The run-order ladder read well but was *stateless*: nothing could
   persist, nothing could interrupt, and a threshold near its trigger flickered. State and
   target live on `EcsLowBrainComponent`.

2. **The brain decides; systems execute.** `state` is the intent component in miniature —
   `TAKE` → `EcsPickupSystem`, `EAT` → `EcsConsumeSystem`, a destination →
   `EcsMovementSystem`. The executors stayed separate systems on three grounds: the brain
   would begin mutating *another entity's* components, the same merge argument would
   swallow every verb after it, and step 7's planner emits action ids that want one
   executor each. **Do not let the brain grow hands.**

3. **Carrying is provisioning**, not a step on the way to a meal — so `EAT` outranks
   `TAKE`, and `EcsConsumeSystem` looks in the bag before the ground. A test watches the
   bag stay empty during a meal, because the end state cannot tell the two paths apart.

4. **Eating requires no inventory.** The condition is "hungry, and food within reach"; a
   pocket is one place reach can mean. Rabbit = grazer (no `EcsInventoryComponent`,
   `eat_at` **below** `forage_at`); monkey = carrier. That ordering is load-bearing: a
   grazer with the thresholds the other way round starves beside its food.

5. **Reach is the physics server's verdict**, accepted to within one tick of motion. The
   old distance re-check was the same condition on numbers ~1 px fresher. What systems
   still re-ask is whether the thing is *still in the world*.

6. **`is_solid` is an authored boolean on `EcsBodyComponent`** — the module's one
   deliberate exception to "capability is component presence", chosen because radius and
   solidity are one physical fact about one body.

7. **Reaching the target ends a commitment.** A `SEEK_FOOD` trip aims at the item's centre,
   so waiting for the trip to end walks a creature onto the thing before it grabs it.

---

## Retracted — and why it matters that it stays retracted

**The "70% regression" does not exist.** An earlier reading had every pre-existing stage
getting ~70% slower when step 4 landed. It came from comparing a ramp run in the morning
against ramps run that afternoon; the machine's throughput drifted ~50% in between. The
same 12-stage configuration measured 194.73 ms in the morning and 300.31 ms that evening.

Measured properly — both arms back to back, one sitting, at n=4,000:

| | 12 stages | 15 stages | diff |
|---|---|---|---|
| tick | 300.31 ms | 335.08 ms | **+11.6%** |
| sensor | 130.66 ms | 132.25 ms | +1.2% |
| crossing | 3,200 | 3,200 | none |

The delta is exactly `consume` + `hunger` + `health`. **Step 4 cost ~12% of the tick and
none of the ceiling.** The companion claim that "step 4 cost a third of the ceiling" is
withdrawn with it — the 4,800 figure for a 12-stage pipeline was that same morning run.

**The memory hypothesis built on it is withdrawn**, and was wrong on its own terms:
`EcsHungerComponent` and `EcsHealthComponent` were already on the blueprints during *both*
ramps, so the component count per entity never changed.

The probe nearly confirmed the wrong answer twice: adding the three stages one at a time
appeared to localise the slowdown to `EcsHealthSystem`, reproducibly, in both forward and
reverse order — until repeated runs at a *fixed* configuration came back 287 and 322 ms.
**±12% run-to-run noise, the same size as the effect being chased.**

---

## Measurement rules, learned the hard way

- **Never compare numbers from different sittings.** `--skip=<labels>` exists so both arms
  run back to back.
- **Single-shot `--n` numbers are not comparable to ramp numbers.** The same configuration
  reads ~260 ms alone and 300 ms at the same population inside a ramp.
- **Repeat before believing.** Anything under ~15% needs two runs at each end.

Knobs on `tests/stress_test.tscn`, all after a bare `--`:

```bash
-- --spacing=180        # grid spacing in px; arena is sqrt(n) columns wide
-- --n=4000             # one population instead of the whole ramp
-- --skip=hunger,health,consume   # leave stages out, by label
```

Fixed along the way: `_build_pipeline()` was adding a fresh `EcsDebugOverlay` and
`EcsSelectionMarker` to the tree per population without freeing them, so a 13-step ramp
finished with 13 of each.

---

## Current performance, all from one window

| | |
|---|---|
| ceiling, 90 px grid | **3,200** entities under 250 ms (4,000 crosses) |
| ceiling, 180 px grid | 4,800 (6,400 crosses) |
| floor, 840 px — nothing perceives anything | **41 µs/entity**, hard ceiling near 6,000 |
| stage shares at n=4,000 | sensor 39%, collision 16%, low_brain 14%, node_sync 10% |
| access overhead in `movement` | 56% of the stage |

**The system is overhead-bound, not interaction-bound.** Sensor costs 39 ms to return
nothing and collision 40 ms to resolve nothing. Deleting every interaction in the world
moves the ceiling from 3,200 to ~6,000 and no further — which prices the sensor-stagger
lever at ≤10% of the tick, not the ~32% the old per-id arithmetic suggested.

Full report (private artifact): <https://claude.ai/artifact/S8FFDw6szJLdDRYLSxhN1V>

---

## What's next

1. **Attack the per-entity floor.** 41 µs before anything interacts. That is query + component
   access + per-entity area bookkeeping — `HANDOFF.md` §8's packed-storage argument, now
   with a number behind it. **Still the author's decision, not to be implemented unasked.**
2. **Decouple sim tick from frame rate.** 10–20 Hz is a 3–6× headroom multiplier and the
   scheduler already takes `delta`. The only lever that multiplies a floor.
3. **Decide the density you are designing for.** Free, and worth half again as many
   entities. Sight radius is the same lever from the other end.
4. **Step 6 proper** — intent components, and a state worth preempting *for*. The
   preemption machinery is built and unused; the first predator is what earns it.
5. **Cache the brain's perception scan.** The food rung asks three store questions of every
   perceived id, every tick, after the sensor already walked the same list.

Smaller, flagged not done:

- Speed variance is hand-authored per placement, so runtime-spawned animals come out at the
  blueprint default. Only matters once something spawns animals.
- The bag badge sits at the *nominal* sprite corner from `EcsConst.SPRITE_SCALE`, but
  blueprints set their own `scale_factor`. Worth an eyeball in the editor.
- Three commits unpushed.
