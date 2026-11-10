# What Songs of Syx does to scale (study notes, 2026-11-10)

Read from the demo's own sources jar (`info/SongsOfSyx-sources.jar`, licensed for modding; studied
at the author's choice), its `data.zip` configs and the developer's Steam forum replies.
Patterns only — no Gamatron code copied.

**The idea everywhere: one thread, and very little work per person per tick. Only one town is real.**

## 1. Threads: one, plus a path worker
- One `updater` thread runs update and render. Ticks are capped at 1/32 s.
- One extra thread, the path finder. It is paused while the path graph rebuilds, then resumed.
- Developer: "multi threading is a huge invitation to bugs"; a world sim "is dependant on what has
  happened previously". Players report slowdown at 12–15k citizens, one core busy.
- **For us:** thread path search, not decisions (cf. the TODO to put the planner on a thread).

## 2. Half the entities per tick
- A fixed array of 40,000 entity slots with a free list. Each tick updates one half and gives it
  twice the delta.

## 3. Two clocks per person
- **Every tick:** movement and the current state's step (a walk, an animation timer).
- **16 times a game day** (a day is 1,152 s, so every ~72 s), at a random start offset: needs,
  stats, boosts recomputed, and the next module chosen. Each person also has a random daybreak.
- **For us:** module 9's bars run at 10 Hz. The scheduler banks delta, so they could run far
  slower with the same rates; only latency changes.

## 4. Decide only when the step ends
- Three layers: plan (eat) → sub (walk to the eatery, sit) → state. Each tick runs only the state.
  A state ending resumes the sub, a sub ending resumes the plan, and only a plan ending picks a new one.
- "Is this plan still worth it?" is checked once every 30 state changes, not every tick.
- Modules (needs, work, danger, home…) score a priority on the slow clock; the winner is stored and
  taken when the current plan ends. Which modules a person has depends on their class.
- **For us:** same lesson as ONI §1. `low_brain` visits everyone each SLOW tick.

## 5. One round-robin helper runs most of the game
- `IUpdater(N, T)`: visit N items over T seconds, a slice per tick, each handed T as its delta.
- Used by regions (1,023 over 16 s), factions, nobles, stats, corpses, rubbish, immigration,
  blocked jobs (every tile over a day), animal spawning, army divisions.
- **For us:** this is the stashed slicing. Finish it as one reusable helper.

## 6. Totals are kept, never counted
- Setting a person's stat removes their old value from the class × race total and adds the new one.
  City totals cost nothing to read, with a short daily history for graphs.
- **For us:** census and module 12's economy.

## 7. Bit-packed per-entity data
- Each person's stats and AI data are one `long[]`, with typed fields of 1, 2, 4, 8, 16 or 32 bits
  registered by key. Small for 40,000 people; saving writes the array.
- **For us:** input to the storage argument (HANDOFF §15) only. Not to implement.

## 8. "Nearest X" by counts per cluster
- The map splits into 8×8-tile clusters by connectivity, then levels ×8 (64, 512…).
- Each cluster counts the findables in it (food, jobs, storage, beds), as a byte plus an overflow bit.
- A search starts at the top level and goes down only into clusters whose count is above zero, then
  floods tiles in the chosen cluster.
- **For us:** module 10's pathfinding and `EcsWorldIndexSingleton` at colony scale.

## 9. Fast-forward and lag
- A fast frame runs more steps of at most 1/16 s, never one bigger step, so nothing tunnels.
- A frame longer than 1/40 s lowers the actual speed; it climbs back by one per frame. The sim slows,
  the frame rate holds. Speed is capped at 25× while enemies are on the map.
- **For us:** modules 10 and 12's speed-up, when there is one.

## 10. Many towns: only the capital is real
- Every other town, the player's own conquered ones included, is a region record, also bit-packed:
  population per race (grows toward a cap by a formula), a level 0–15 per building type, loyalty,
  health, devastation.
- All region slots are visited over 16 s by the round-robin helper. AI regions apply their formulas
  each quarter day, and build and ship goods every 2 days, from random start offsets.
- Up to 64 AI factions, each a stockpile per resource with a price that drifts back to balance;
  player trade pushes it away. Output is costed from the same industry recipes the player's rooms use.
- At world creation the factions are simulated 50 days, so day one's economy is already settled.
- **For us:** module 12. A town the player isn't in is a record (population, building levels,
  stockpile) from step 5's building list; L1 entities only where the player is. This answers the
  "simulate by chunk" TODO more strongly than slowing far entities: far towns have none.

## 11. From the data files
- **Calendar** (`Time.txt`): 4 days a season; night ratio per season (summer 0.25, winter 0.40) and
  a light tint; crops carry a `SEASONAL_OFFSET` into the year.
- **Culture as data:** a race lists preferred foods, road and building materials with weights, and
  how it likes each other race.
- **Fields from buildings:** rooms declare `ENVIRONMENT_EMIT` (noise: value, radius); each field has
  its own fall-off; a race can mark one inverted (less is better). For module 12's site rules.
- **Room quality from furniture:** a room lists items (costs, stats added) and upgrades.
- **Crowding:** often-walked tiles cost more, so wide roads form (developer, Steam forum).
- **Boosts:** every stat is a named key; race, tech, events and needs add `KEY>ADD` / `KEY>MUL`,
  with wildcards (`ROOM_FARM*`). Techs are levels of boosts. Same as ONI §7.
- **Needs:** a need is just a rate; a service room declares its radius and who uses it.
- **Capability by folder:** an empty `resource/edible/MEAT.txt` is what makes meat edible.

## 12. Why 5,000 at 60 FPS, measured against module 9 (2026-11-10)
Same loop in three forms: move to a destination, re-file in a 16 px tile grid on tile change, push
apart neighbours in 3×3 tiles. ms per tick:

| Entities | Java 21, flat arrays | GDScript, packed arrays | GDScript, `EcsWorld` Resources |
|---|---|---|---|
| 600 | 0.035 | 0.83 | 1.9 |
| 1,000 | 0.039 | 1.2 | 3.4 |
| 5,000 | 0.31 | 6.9 | 24 |
| per entity | 40–85 ns | ~1.3 µs (×20–30) | ~3.2–4.9 µs (×55–80) |

- **Language:** the same loop costs ×20–30 in GDScript and ×55–80 through component Resources.
- **Frequency:** Syx decides ~once per frame for 5,000 people (16 a day each). Module 9 runs sensor,
  danger, memory, planning and brain on every animal at 20 Hz: ~7.3 ms at 432 animals (Nov 7
  audit), ~17 µs per animal per tick, so ~85 ms at 5,000.
- **Seeing:** Syx's people don't perceive; they ask the cluster counts when they need something.
- **Drawing:** one vertex buffer and one draw call; module 9 has a node and areas per entity.
- **The 12k complaints are at 25×:** 25 ticks of sim per frame ("10k at 25× is like 250,000 at ×1").
  Syx lowers its speed past 1/40 s a frame; at 1× it holds.
- **For us:** GDScript alone can't hold 5,000 (packed-array movement is already 6.9 ms). In order of
  cost: AI on slow clocks, reacting at once only to events (20 Hz → ~1 Hz is ×20); half the movers
  per tick with double the delta (×2 on movement); hot loops in packed arrays or C++ via GDExtension,
  which is a §15 storage argument; MultiMesh drawing (not measured). The first two look like enough
  for 1,000–2,000; 5,000 needs the third.

## Suggested order
1. Module 12: towns out of sight as records, from the step 5 building list.
2. The round-robin helper (finish the stash); slower need bars.
3. Decide only when the step ends (with ONI's brain budget).
4. Module 10: counts per cluster for "nearest X"; path search on a worker thread.
5. Calendar and day/night from §11; environment fields for site rules.
