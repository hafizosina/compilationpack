# Ideas from Better Towns — plan for review (2026-11-22)

What to take from the RimWorld mod `~/Project/Rimworld-Mod/BetterTowns` into modules 10 and 12,
kept medieval. Decided with the author 2026-11-22/23, section by section; **Decide** lines record each answer.

Status: ☐ proposed · ✅ agreed · ❌ dropped

---

## 0. The two generators side by side

| | Better Towns (C#, RimWorld) | Ours (modules 10 + 12) |
|---|---|---|
| Town shape | a centre and a growth radius, no plots | site, main roads, then plots placed by role (step 5b), lanes routed to them |
| Where things go | **districts as points**: each district gets a point, scored by likes and dislikes; buildings are pulled toward it | each role scores spots by its own `sites` rules; it doesn't see other roles except through `apart` |
| A building | **grown**: a core room, then rooms attached to its walls, each sized by its role | **split**: the plot's rectangle cut into rooms (BSP), sometimes shaped L/T/U |
| Long buildings | **hallway wings**: rooms in a row on one or both sides of a hallway, entrance at its end | none |
| Furniture | **laid out from the door**: back wall, side walls, the aisle in from the door, rows | required and optional pieces, `against_wall`, random spots, never cutting the room in two |
| Defence | wall built last, hugging the town, gates where roads cross | none ("later" in PLAN.md) |
| Outside | farms, pastures, a fenced graveyard | fields, pens, docks, outdoor works (7a) |

**Approach:** keep our pipeline. Replacing it would undo steps 4–6. Take the ideas one at a time,
each behind a test, using only medieval content.

**Not taken:** power, tech levels, turrets and traps, DLC rooms, ideology colours (they belong to
the culture-styled TODO), mountain digging, town life (module 9), claims plus audit (module 10
already refuses rather than overwrites, and module 12 marks what each cell is used for).

---

## C. The census — decide the town's people before placing anything ☐

Like RimWorld's faction base (pawns first, then beds and benches for them), the town is planned
as **people before buildings**. Today step 5 goes the other way: roles come from the character's
core set × `trade_scale`, and each role brings its `residents`. The census turns that round:
**families → needs → jobs → workplaces and houses**, and only then plots.

It runs after step 5's survey and character, before step 5b's plots. Pure and seeded, like
`EcsTownEconomy`. The result goes on `site.census`.

### C.1 What it answers, in order

| # | Question | Where the answer comes from | Status |
|---|---|---|---|
| 1 | What town is this? | step 5: character, tier, survey | done |
| 2 | How many families? | the tier's population range ÷ family size | new |
| 3 | How many in each family? | a seeded roll per family (see C.2) | new |
| 4 | What does the town need? | each person's yearly need per resource (C.3) | new |
| 5 | What can it make itself? | survey facts → which resources have a local source | new (facts exist) |
| 6 | Is that enough, or must it import more? | local capacity from the survey vs need | new |
| 7 | What can't it make at all? | needs with no local source → import all of it | new |
| 8 | Each family's job | workers needed per resource, handed out to families (C.4) | new |
| 9 | Each family's wealth | by job, with a roll (C.5) | new (today wealth comes from position) |
| 10 | Where each family lives | its own house, or living at its workplace (C.6) | new |
| 11 | How big its house is | by wealth and family size → rooms (C.7) | new |
| 12 | How much land it gets | density: less yard near the plaza, more further out (C.8) | new |
| 13 | Which workplaces the town needs | workers ÷ places per workplace (C.9) | new |

### C.2 Families and members

- Population, rolled by seed from the tier's range (decided 2026-11-22, close to today's sizes):
  hamlet 30–70, village 120–250, town 350–700.
- Each family is rolled from this list (decided 2026-11-22), until the population is reached; the
  last family is trimmed to fit:

  | Household | People | Weight |
  |---|---|---|
  | single | 1 adult | 10% |
  | couple | 2 adults | 20% |
  | couple with children | 2 adults + 1–4 children | 50% |
  | extended | 2–3 adults + 1–3 children + 1 elder | 20% |

  About 4 people and 1.9 workers a family: a village of 200 is ~50 families, ~95 workers.
- A member is only an **age group** (adult, child, elder). No names, no individuals yet; module 9
  can make them villagers later.
- Workers are the adults. Children and elders count toward needs and beds, not jobs.

### C.3 Resources: need, make, import

**Theme (decided 2026-11-22): maritime Indo-Malay, Majapahit and Srivijaya.** The list below
replaces the European one first drafted here (grain, wool, ale…).

New data, `EcsResourceDef` in `economy.tres`: key, need per person per year, the facts that give
a local source, the role that makes it and how much one worker makes.

**Needs** — everyone uses them; they make local workplaces (decided 2026-11-22):

| # | Resource | Local source | Workplaces |
|---|---|---|---|
| 1 | **food**: rice first, then fish, sago, coconut | sawah (flat land, river water); sea or river; swamp; coast | sawah farm + lumbung (rice barn), rice pounding shed; fishing hut + perahu; sago shed |
| 2 | **salt** | sea | salt pans + boiling house; inland towns import |
| 3 | **drink**: tuak (palm wine), rice wine | palms, rice | palm tapper, wine maker, drinking house (kedai) |
| 4 | **wood**: timber, bamboo, firewood | forest, river banks | woodcutter, bamboo grove, carpenter, boat builder |
| 5 | **thatch** (nipa / attap) | mangrove, swamp | thatch maker |
| 6 | **clay**: pots, bricks, tiles | river clay | potter, brick kiln |
| 7 | **metal**: iron tools, blades | iron deposit (rare) | smelter, smith (pandai besi), keris maker; usually imported |
| 8 | **cloth** | cotton (dry fields) | weaver, dyer |

**Trade goods** — made for export, workplaces only where the source is:

| # | Resource | Source | Workplaces |
|---|---|---|---|
| 9 | **spice** | **pepper:** a land rule, hills near forest. **Cloves and nutmeg:** a rare **spice deposit** on the region, like gold | pepper garden, drying yard, spice store |
| 10 | **forest goods**: camphor, sandalwood, resin, beeswax, rattan | deep forest | gatherers' hut, sorting shed |
| 11 | **gold, tin** | deposits, river panning | mine, panning camp |

**Imported only:** porcelain and silk (China), fine cloth (India), cloves and nutmeg where there is
no deposit. They appear in the market by traffic (C.3c).

**Livestock** (decided 2026-11-22):
- **Water buffalo are livestock, and a farm's upgrade needs one.** A sawah farm without a buffalo
  works a small field by hand; with one it ploughs a bigger field and makes more rice, and has a
  buffalo pen beside or under the house.
- Buffalo come from **buffalo herders** (pasture or swamp grazing, a pen), or are **bought from
  traders** when the town breeds none.
- **Which farms get one (decided 2026-11-22): wealth and supply.** Middling and rich farmers want
  one; as many get one as the town breeds or buys; the rest stay hand farms. An upgraded farm has a
  bigger sawah and a pen, and makes more rice, so a town with buffalo needs fewer farming families.
- **Chickens are for eggs only:** a coop in a house yard, part of the household, not a resource and
  not a job.

For each resource:
- **Capacity:** how much the land in reach can give (survey share × catchment, e.g. arable cells
  ÷ cells a farm needs). That caps the workers.
- **Made locally** = min(need, capacity). **Import** = need − made. No source → import all.
- **Export:** the main trade makes more than the town needs (its surplus is the town's living).
- Imports and exports both go through the town's market (C.3b), so nothing is ever left short.

### C.3b Every town has a market; traders carry the difference

**Scope (decided 2026-11-22): this is a building generator, not a simulation.** Only what
places or sizes a building is kept; trade itself (prices, balance, what traders carry) is for the
simulation later.

No town is good at everything; traders bring what it lacks and take its surplus. For generation
that means only:

- **Every town has a market**, sized by tier (and traffic, C.3c): a hamlet a couple of stalls on
  the plaza, a village a small market, a town a market square. It is a base role of every tier.
  Today `market` has `min_tier = 1` and is a base role only of the town tier; both change.
- **What is imported is not made locally**, so it creates no workplace. What is exported adds
  workers to the main trade (C.4).
- **Every town exports something:** its main trade, or its best resource by survey.
- **Trading towns** (step 5's `trading` character) have a bigger market, inns and warehouses.

### C.3c Traffic — how many pass through

Each town gets a **traffic** level: how many travellers and traders pass through it. **For now
it is rolled at random** (seeded). Later it comes from the town's place: main road exits, roads
meeting, a river or the sea, how far the next town is (survey `trade` already counts some of
this).

| Traffic | Travellers a day (to tune) | Roll weight |
|---|---|---|
| quiet | 0–5 | 35% |
| steady | 5–20 | 35% |
| busy | 20–60 | 20% |
| crossroads | 60+ | 10% |

A trading town (step 5's `trading` character) rolls one level higher, at least `busy`.

**What traffic changes** (only what places or sizes a building):

- **Market size:** more stalls the busier the town.
- **Inns:** beds for the travellers staying the night.
  - beds needed = travellers a day × the share who stay.
  - **inn size** from beds: small (common room + 2–3 guest rooms), medium (a guest wing, §3),
    large (two wings, a cart yard).
  - **inn count** = beds ÷ the largest inn's beds, rounded up. A quiet hamlet may have none.
  - From busy up, an inn has a **cart yard** for carts and buffalo.
- **Taverns (drinking houses):** one per N people, counting travellers.
- **Entertainment buildings** by traffic (and tier):

| Building | Needs | What it is |
|---|---|---|
| drinking house | steady | a small one besides the tavern |
| gaming house | busy | dice tables |
| performance pavilion | busy, town | an open pavilion for music and shadow plays, by the plaza |
| bathing place | busy, town | a walled pool with spouts (as at Trowulan) |
| cockfighting ring | busy | a ring with benches (outdoor work) |

- **Jobs:** innkeepers, cart hands and performers come from the census like any job (C.4), so more
  traffic means more families living from travellers.
- **Wealth:** in a busy town, innkeepers and merchants start a step richer (a bigger house).

Left for the simulation: what the market sells, trade volume, trade balance, prices, travellers
eating the town's food, and traders as agents walking between towns.

### C.4 Jobs

*Accepted as a first pass, numbers to review later (2026-11-22).*

- Workers per resource = ceil(made ÷ per worker).
- **The main trade makes a surplus to export:** hamlet 1.5×, village 2×, town 3× the town's need.
  Side lines make just the town's need.
- **Service jobs by population, not by resource:**

  | Job | One per | Building | From |
  |---|---|---|---|
  | village head | the town | head's compound | hamlet |
  | temple priest | 80 people | temple (shrine in a hamlet) | hamlet |
  | tavern keeper | 60 people, counting travellers | tavern | village |
  | innkeeper | traffic (C.3c) | inn | traffic |
  | healer | 100 people | healer's house | village |
  | guard | 50 people | guard post | village |
  | harbour master | the port | harbour office | port towns |
  | merchant | 40 people, more with traffic | merchant's house + warehouse | village |

- Each family gets **one main job** (its head). A big job (a mine, a farm) takes extra adults
  from the same family first, then labourers from poor families.
- Unemployed adults become labourers (they work where most help is short).

### C.5 Wealth

- **Levels (decided 2026-11-22): poor, middling, rich**, module 10's three. A 4th, noble, comes
  with City tier and the palace.
- **By job (decided 2026-11-22)**, then a roll: ~20% a step up, ~20% a step down.

  | Starts | Jobs |
  |---|---|
  | poor | labourer, hand farmer, fisher, gatherer, woodcutter, thatcher, palm tapper, salt worker |
  | middling | buffalo farmer, buffalo herder, potter, weaver, carpenter, boatwright, smith, tavern keeper, pepper grower |
  | rich | merchant, village head, harbour master (ports), temple priest, bladesmith, spice trader, mine owner |

- **Names are English** (decided 2026-11-22): jobs, roles and buildings in data and code use
  western names; the Indo-Malay names come later, through translation.
- **Today wealth comes from where a plot stands** (rich by the plaza). The census turns this round:
  wealth is the family's, and a rich family **looks for** a spot by the plaza.

### C.6 Where each family lives

- **One level only:** the game has no z levels, so no upper floors and nothing under a stilt house.
  Living at work means **one building on one floor**: the family's living rooms (bedrooms, a
  kitchen) beside the work rooms. A stilt house can only *look* raised.
- Each role says `lives_at_work` (decided 2026-11-22):

  | Lives | Who | Building |
  |---|---|---|
  | at work | rice farmer, buffalo herder | farmhouse + rice barn and pen beside it |
  | at work | fisher | house by the water + boat landing |
  | at work | tavern keeper, innkeeper | living rooms at the back |
  | at work | temple priest | priests' quarters in the temple compound |
  | at work | harbour master (ports) | harbour office with living rooms |
  | at work | potter, weaver, carpenter, basket maker, thatcher | a house with a work room or open porch; a potter's kiln in the yard |
  | separate | smith, bladesmith (the forge is a fire risk), salt worker, woodcutter, gatherer, labourer, palm tapper | a house, and a workplace apart where they have one |
  | separate, always | every rich family: merchant, village head, spice trader, mine owner | a house by wealth; the workplace apart |

- **A rich family always has a separate house**, even when its job has a workplace.
- Everyone else gets a house of their own: one family, one house (shared houses and tenements are
  for City tier, later).

### C.7 House by wealth and size

| Wealth | House | Rooms |
|---|---|---|
| poor | one-room house | 1 main room (live, sleep, a cooking corner), an open porch at the front |
| middling | house | main room, 1–2 sleeping rooms, a kitchen at the back, a porch |
| rich | walled compound | main house (3–5 rooms), reception pavilion, kitchen house, storehouse |
| village head | the biggest compound | as rich, with a larger pavilion for village meetings, by the plaza |

- **Working at home adds rooms, at any wealth** (decided 2026-11-22): a family that lives at its
  workplace gets a **work area** (a work room or open porch) and a **store room** beside its living
  rooms. So a poor potter has main room + work porch + store; a middling weaver has main room,
  sleeping room, kitchen, work room and store.
- **Rich families live in compounds (decided 2026-11-22), after grown buildings (§2):** a plot
  holding several small buildings, a wall or fence round it with a gate on its lane (7a's fence
  code), and an open pavilion. Each building is a small grown building. Needs: plots with more than
  one building, and a pavilion.
- **Pavilion, for now (decided 2026-11-22):** posts and a floor, no roof, laid as an outdoor work
  (like 7a). No module 10 change. **Review later:** an `open` building that module 10 roofs whole
  (recommended then), or posts as a kind of wall.
- Sleeping rooms: poor families sleep in the main room; middling 1, or 2 above 4 people; rich 1 per
  couple plus a children's room.
- The room list goes straight into grown buildings (§2): the census says *which* rooms, the
  generator says *how* they fit.

### C.8 Density — land is dear by the plaza ⏸ (pending, 2026-11-22)

**Open:** compounds now need room, which clashes with "small yards by the plaza". Options:
A compounds exempt (fixed size by wealth, still near the plaza); B compounds squeezed by density
too; C compounds in the middle ring, density for houses only. Also: does density change only the
yard (proposed), or the plot too? The draft below stands until then.

- A density curve on `EcsSettlementDef`: plot size and yard depth by distance from the plaza.
  - Near the plaza: narrow frontage, yard 0–1 (a back court at most).
  - Middle: yard 2–4.
  - Edge: yard 6–10, even for a poor family (a vegetable plot, a pig).
- Wealth buys position, not land: a rich family by the plaza has a bigger house but a small yard;
  a poor family at the edge has a small house and a big yard.
- Farmhouses and works keep their own sizes and annexes.

### C.9 Workplaces match the people

- Each workplace room says how many work in it (a forge 2, a loom 1, a tavern 3, a rice farm the
  family itself). Workplaces needed = ceil(workers ÷ places). Tuning data.
- **Check:** every worker has a place, no workplace stands empty, every family has a bed for each
  member.

### C.10 What it changes downstream

- Step 5's role list comes from the census instead of `core × trade_scale`.
- Step 5b places plots for: each workplace, each house (by its family's wealth and the density
  curve).
- Step 6 builds each plot with its room list (§2 grown buildings for houses).
- Later, module 9: each family is a household of villagers with a home and a job (PLAN.md "a living
  town").

### C.11 Viewer and tests

- **Viewer:** a census panel: families by job and wealth, and a resource table (need, made,
  imported, exported), with the trade balance.
- **Tests (`census_test`):** over N seeds per tier:
  - everyone has a bed;
  - every adult has a job or is a labourer, and every workplace is staffed;
  - made + imported = needed for every resource;
  - every town has a market, and exports something;
  - inn beds cover the travellers who stay, and busier towns never have fewer inns, taverns or
    entertainment buildings than quieter ones of the same tier;
  - nothing is made without a local source;
  - every rich family has its own house;
  - yards grow with distance from the plaza;
  - same seed, same census.

**Decide:**
- [x] People first (2026-11-22): the census drives the role list, replacing step 5's
      `base_roles` counts and `core × trade_scale`; survey, character, side lines, `requires` and
      tiers stay
- [x] Members as age groups only (2026-11-22): only what generating the town needs; names,
      skills and the rest come when module 9 spawns villagers
- [x] The resource list in C.3: 8 needs, 3 trade goods, Indo-Malay (2026-11-22)
- [x] Pepper by land, cloves and nutmeg from a rare spice deposit (2026-11-22)
- [x] Buffalo are livestock; a farm's upgrade needs one; chickens are eggs in a yard (2026-11-22)
- [x] Every town has a market sized by tier; traders buy the surplus and sell what is lacking (C.3b)
- [x] Traffic, random for now, sets trade goods, inns, taverns and entertainment (C.3c)
- [x] The traffic levels and the entertainment list in C.3c (2026-11-22)
- [x] Trade balance dropped: not about placing buildings (2026-11-22)
- [x] Wealth: 3 levels now, noble with City tier; starting wealth by job (2026-11-22)
- [x] One family, one house below City tier; shared longhouses maybe later (2026-11-22)
- [x] The `lives_at_work` table in C.6, one level only (2026-11-22)
- [ ] ⏸ Density and compounds (C.8): pending

---

## 1. Quarters — roles that want to be near or away from each other ✅

**Mod:** `Districts.cs` `PlaceAnchors`, `Affinity`. Each district gets one point, placed in
priority order. A point's score rewards being near districts it likes and far from ones it
dislikes, keeping room to grow and open ground. Military goes near a gate, homes away from gates.

**Ours:** module 12, step 5b (`EcsPlotPlanner`).

**Decided (2026-11-22): affinity leads, the district is a weak suggestion.**

**Affinity (the main rule).**
- A likes/dislikes table between groups, in `economy.tres`.
- When a role scores a spot, each plot already placed pulls it closer (a group it likes) or pushes
  it away (a group it dislikes), by distance from door to door.
- Its weight is set like any other site rule, so a role's own rules (`must`, a resource) still win.

**District (a weak rule).**
- After the main roads, one point per group (home, food, craft, faith, trade, works), placed by
  the same table plus the plaza and the gates.
- A `district` rule pulls a role toward its group's point at a **low weight**: a tie-breaker that
  seeds where a group starts, never a border.
- The viewer draws the points.

**The likes/dislikes table (Indo-Malay; a first pass, review later — 2026-11-22):**

| Group | Buildings | Likes | Dislikes |
|---|---|---|---|
| elite | village head's compound, rich compounds | plaza, faith | works, entertainment |
| home | poor and middling houses | trade, faith, the well | works |
| faith | temple, shrine, priests' quarters | plaza, elite | works, entertainment |
| trade | market, merchant houses, warehouses, harbour office | plaza, main road, harbour | — |
| food and drink | tavern, drinking house, inn | main road, trade | faith |
| entertainment | gaming house, cockfighting ring, performance pavilion, bathing place | trade, food and drink | faith, elite |
| craft | potter, weaver, carpenter, basket maker | see "selling" below | — |
| works | smith, smelter, brick kiln, salt boiling, fish drying | water, outskirts | home, elite, faith, food and drink |
| farming | rice farms, herders | outskirts, river | — |

- Works are kept apart for **fire** (a town of timber and thatch) and **smell** (fish drying). No
  wind.
- **Entertainment has no fixed spot** (decided 2026-11-22): its district point is placed by the
  table like any other, so it lands wherever its likes and dislikes balance out.
- Rich families end up by the plaza because elite likes the plaza and faith; homes have no pull to
  it.

**Selling: at home or at the market** (decided 2026-11-22). A crafter either sells from home or
at the market.
- **People prefer to sell at home.** Whether a family does is rolled from its stats: a chance by
  job (a potter or food seller often, a weaver less) and by wealth (middling and up more often).
- **A home seller** gets a **shop front**: its work porch faces the lane or road, and it likes the
  main road (passing trade). Placement-wise: it pulls toward roads and the centre.
- **Far from the centre, always the market:** a home seller whose house lands further than a set
  distance from the plaza sells at the market instead.
- **Heavy goods are always sold where they are made**, however far out (decided 2026-11-22): wood,
  ore, stone, bricks can't be carried to a stall, so buyers come to them. A resource says `heavy`
  in its def. A woodcutter, miner or brick maker gets a **stockpile in its yard** by the lane (log
  pile, ore pile, brick stack) and never a market stall; its lane must reach a road a cart can use.
- **A market seller** adds a **stall** to the market. So the market's stall count is worked out
  **after** the plots are placed: its footprint is reserved at its tier's largest size, and its
  stalls are laid for the sellers it actually has.

**Test:** over N seeds, the average distance between buildings of the same group against
different groups, and the distance from homes to the tannery.

**Decide:**
- [x] Affinity first, district as a weak rule
- [x] Entertainment placed by affinity; crafters sell at home or at the market (2026-11-22)
- [x] Heavy goods sold at home, with a yard stockpile (2026-11-22)
- [x] The likes/dislikes table, as a first pass; review later (2026-11-22)

---

## 2. Grown buildings — rooms attached to each other ✅ (review on results)

**Mod:** `Layout.cs` `Seed`, `Attach`, `ValidRect`. It seeds the main room, then attaches each
next room to an existing wall:
- the new interior must be free;
- walls overlap only walls of the same building;
- it never leaves a 1-cell gap beside another building;
- the door goes through the shared wall;
- slightly off-centre offsets are preferred, for a less boxy outline.

Each room's size comes from its role (a hall is 9–12, a kitchen 6–8).

**Ours:** module 10 (`EcsBuildingGenerator`), which module 12 step 6 calls per plot.
- `EcsBuildingTypeDef.layout`: `split` (today) or `grow`.
- `EcsRoomTypeDef.size_min` and `size_max`.
- Grow puts the main room on the front with its door at the plot's door cell, then attaches the
  rest inside the plot's bounds.
- **The output has the same form as today's** (rooms, walls, doors, cells), so room detection,
  roofs, furniture, `EcsBuildingCheck` and chunk clipping don't change. Step 6's shapes already
  showed that open ground inside a footprint is handled.
- The cells the building doesn't use become yard.

**Test:** `generator_test` at 1,000 seeds per growing type: every building sound, every room
typed, the same seed giving the same building, plus the share of outlines that aren't
rectangles.

**Indo-Malay, decided 2026-11-22 (to review on the results):** houses here were mostly simple
rectangles; variety came from a front porch, a kitchen at the back (often a separate small building
on a covered walkway) and several buildings in one yard (compounds). So growth is modest:
- **every building of 2+ rooms grows** from its room list (the census gives houses theirs); a
  1-room building is its room;
- each room type says **where it goes relative to the main room**: `front` (porch), `back`
  (kitchen), `side` (sleeping rooms, store, work room), `any`;

| Building | How it grows |
|---|---|
| poor house | main room + porch at the front |
| poor, working at home | main room + work porch + store at a side |
| middling house | main room, sleeping rooms at the sides, kitchen at the back, porch at the front |
| compound buildings | each small, grown like a house |
| temple, market hall, inn | rooms round a main room; the inn's guest wing (§3) |

**Decide:**
- [x] Every 2+ room building grows, rooms placed by `front`/`back`/`side` — judge on the results
- [x] The plot stays the upper bound; unused cells become yard (2026-11-22)
- [x] Before 7b (2026-11-22)

---

## 3. Hallway wings ❌ skipped for now (2026-11-22) — maybe later for a castle or palace

**Mod:** `Wings.cs`. A hallway 1–3 wide, with rooms evenly spaced on one or both sides and doors
centred on the hallway. The entrance is at the end of the hallway, and a second wing can join
the first to make an L.

**Why skipped:** at hamlet, village and town tier, Indo-Malay buildings have no enclosed
hallways. Rooms open onto the main room, a porch or a courtyard:
- an inn's guest rooms each open onto a long front porch, which grown buildings (§2) already do;
- a monastery's cells sit round a courtyard (a courtyard layout, its own idea if wanted);
- barracks, cells and palace wings come with City tier.

**When it comes back** (a castle or palace): room detection can't type an empty hallway. Either a
long, narrow room with no key piece is typed as a hallway (a module 10 rule), or hallways get a
key piece (a wall lamp or bench) — the latter was recommended.

---

## 4. Furniture placed relative to the door ✅

**Mod:** `RoomFrame.cs`. Each room is laid out as seen from its main door, in a local frame:
x across the room, z from the door wall (0) to the back wall. "Back wall", "left wall", "the
aisle" (the column straight in from the door) and "rows facing the back" mean the same in every
room however it is turned, and are turned to the grid at the end. Which way a piece faces is
worked out in one place, from the piece's own data.

**Ours today:** module 10 `_furnish` draws a random spot, turns an `against_wall` piece's back to
the nearest wall, and refuses a spot that cuts the room's free cells in two. Rooms are valid but
not laid out: a nave's altar can land on a side wall with pews facing anywhere.

**Plan:** an optional `place` setting per piece in a room type, read in the door's frame.

| `place` | Meaning |
|---|---|
| `back` | centred on the back wall, facing the door |
| `side` | against the left or right wall, facing in |
| `rows` | repeated in rows facing the back, the aisle left clear |
| `beside_door` | just inside the door, beside it, not in the aisle |
| `corner` | in a back corner |
| `centre` | in the middle, off the aisle |
| *(not set)* | random, as today |

| Room | Pieces |
|---|---|
| nave | altar `back` · pew `rows` · candle `side` |
| hall | high seat `back` · long table `centre` · chair `side` |
| common room | bar counter `side` · table `centre` · barrel `corner` |
| bedroom | bed `back` · chest `beside_door` |
| dormitory (new) | bed `rows`, along both side walls |
| forge | forge `back` · anvil `centre` · quench barrel `side` |

- The main door is the entrance, or the door leading toward it.
- The free-cells rule still holds; a placement that would break it falls back to random.
- Room types move over one at a time; nothing downstream changes (same commands).
- After §2, so rooms have sizes that suit their role (a nave long enough for rows).

**Test (`generator_test`):** for room types that use it, the `back` piece is on the wall opposite
the main door, the aisle is free, every `rows` piece faces the back; plus today's checks.

**Decide:**
- [x] Agreed (2026-11-22)

---

## 5. Content — rethemed to Indo-Malay ✅ (review in action)

**Decided (2026-11-22): retheme, don't keep both.** Today's module 10 content and module 12's 48
roles are European. They are renamed and redrawn where an Indo-Malay equivalent exists, dropped
where none does, and what is missing is added, listed **from the census**: every job a workplace,
every house room a room type. English names (§C.5). Tests and 7a's outdoor objects are rethemed
step by step, as each building type comes up.

### 5.1 What happens to today's content

| Today | Becomes |
|---|---|
| chapel, church; nave, pew, altar | **temple, shrine**: sanctum (statue), offering hall (offering table, incense, bell) |
| bakery; oven, kneading table, flour sack | **dropped** (rice is pounded and cooked at home) |
| watermill, windmill; millstone | **rice pounding shed**: pounding trough and pestles |
| barn, hay store; haystack | **rice barn** on posts; rice drying rack. Scarecrow stays |
| herder, stable, stalls, trough | **buffalo herder** and **buffalo pen** (trough stays) |
| weaver | stays, with a cotton **loom** |
| tannery, cobbler, dairy | **dropped** for now |
| goldsmith, stonemason, lime kiln | goldsmith stays (gold deposits); stonemason and lime kiln dropped (brick and timber towns) |
| manor, hall, high seat, study | **village head's compound**: main house, reception pavilion, kitchen house, storehouse |
| house, hut; bed, chest, chair | **poor house, house**: sleeping mat, storage jar, low table |
| tavern, inn; bar counter, barrel | stay: serving counter, wine jars |
| smokehouse, net maker, fishery | **fish-drying yard** (outdoor), **net rack** in the fisher's work porch |
| lumber camp, sawmill, carpentry | **woodcutter** (yard stockpile), **carpenter** (work room); sawmill dropped |
| stone and brick walls | **timber, bamboo, woven-bamboo** walls; brick for temples and rich compounds |
| fence | **bamboo fence**; a compound gets a **brick or earth wall** with a gate |

### 5.2 Building types (proposed)

Grouped as in §1. "At home" = the family lives there (§C.6).

| Group | Building | Rooms / pieces | Notes |
|---|---|---|---|
| home | poor house | main room, porch | + work porch and store when working at home |
| home | house | main room, sleeping rooms, kitchen, porch | + work room and store when working at home |
| elite | compound | main house, reception pavilion, kitchen house, storehouse, wall + gate | rich families |
| elite | village head's compound | as compound, bigger pavilion | by the plaza |
| farming | rice farm | house + rice barn + buffalo pen, sawah annex | at home |
| farming | buffalo herder | house + pen, grazing annex | at home |
| food | rice pounding shed | pounding trough | village and up |
| food | fisher's house | house by the water + landing, net rack | at home |
| food | fish-drying yard | drying racks (outdoor) | works |
| food | sago shed | sago trough | swamp towns |
| food | coconut grove, oil press | grove (outdoor), press room | coast |
| drink | palm tapper's house | house, jars | separate |
| drink | wine maker | fermenting room (jars) | |
| drink | tavern, drinking house | serving room, kitchen | at home |
| salt | salt pans + boiling house | pans (outdoor), boiling room | sea towns |
| wood | woodcutter's house | house + log stockpile in the yard | heavy goods |
| wood | bamboo grove | outdoor | |
| wood | carpenter | work room (carpenter's bench) | at home |
| wood | boat shed | boat frame, by water | |
| thatch | thatcher | work porch (thatch frame) | at home |
| clay | potter | work porch (potter's wheel), kiln in the yard | at home |
| clay | brick kiln | kiln, brick stack | works, heavy goods |
| metal | smithy | forge, anvil | works, separate |
| metal | smelter | bloomery | works |
| metal | bladesmith | blade bench, forge | rich |
| metal | goldsmith | jeweller's bench | gold deposits |
| cloth | weaver | work room (loom) | at home |
| cloth | dyer's yard | dye vats (outdoor) | |
| spice | pepper garden | outdoor annex | hills |
| spice | spice store | spice sacks, scales | trade |
| forest goods | gatherers' hut, sorting shed | sorting table | deep forest |
| mining | mine, panning camp | mine entrance (outdoor), panning trough | deposits |
| faith | temple | sanctum, offering hall, priests' quarters | at home (priest) |
| faith | shrine | statue, offering table (outdoor) | hamlet |
| service | healer's house | herb room (herb jars, mortar) | |
| service | guard post | guard room (weapon rack) | |
| trade | harbour office | office (ledger desk) + living rooms | ports, at home |
| trade | merchant's house + warehouse | counting room (strongbox, scales), storeroom | rich, so a compound + warehouse |
| trade | market | stalls (outdoor) | every town |
| trade | inn | common room, guest rooms on a front porch, cart yard | at home |
| entertainment | gaming house | dice tables | busy |
| entertainment | cockfighting ring | ring, benches (outdoor) | busy |
| entertainment | performance pavilion | posts, floor (outdoor for now) | busy, town |
| entertainment | bathing place | pool, spouts, wall (outdoor) | busy, town |

### 5.3 Room types and key pieces (proposed)

Each room type needs a key piece no other room type uses (room detection names rooms by it).

| Room | Key piece | Other pieces |
|---|---|---|
| main room | family mat | low table, storage jar, cooking hearth (poor) |
| sleeping room | sleeping platform | mat, chest |
| kitchen | clay stove | water jar, shelf |
| store | storage jars | baskets, sacks |
| porch | bench | — (open, at the front) |
| work porch / room | by job: potter's wheel, loom, carpenter's bench, thatch frame, net rack | |
| rice barn | rice baskets | |
| pounding shed | pounding trough | pestles, baskets |
| fermenting room | fermenting jars | |
| boiling room | salt boiler | salt baskets |
| serving room | serving counter | low tables, wine jars |
| guest room | guest mat | — |
| sanctum | statue | offering bowls |
| offering hall | offering table | incense burner, bell |
| herb room | herb jars | mortar, drying rack |
| guard room | weapon rack | mat, drum |
| office | ledger desk | chest |
| counting room | strongbox | scales |
| smithy | forge | anvil, quench trough |
| smelting room | bloomery | ore pile, bellows |
| blade room | blade bench | forge |
| goldsmith room | jeweller's bench | small furnace |
| oil press room | oil press | jars |
| sago room | sago trough | |
| spice room | spice sacks | scales |
| sorting room | sorting table | baskets |
| gaming room | dice table | mats |

About 27 room types and 45 pieces, most new art.

### 5.4 What each item costs

- **A piece:** a blueprint `.tres`, a placeholder tile in `make_placeholders.py`, an entry in the
  catalog.
- **A room type:** its `.tres`, a unique key piece, `size_min` and `size_max`, and its `front`,
  `back` or `side` place (§2).
- **A building type:** its `.tres`, plus 1,000 seeds in `generator_test`.
- **A role:** an entry in `economy.tres` (tier, site rules, group, `lives_at_work`, wealth).

**Decide:**
- [x] Retheme, not both (2026-11-22); tests and outdoor objects step by step
- [x] The building list in 5.2 — review in action (2026-11-23)
- [x] The room list and key pieces in 5.3 — review in action (2026-11-23)
- [x] Furniture by wealth: today's optional chance by wealth first; poor/middling/rich pieces when
      the results ask for it (2026-11-23)
- [x] Art: placeholder tiles (2026-11-23)

---

## 6. Cremation ground ✅ (review in action)

Majapahit and Srivijaya were Hindu-Buddhist and mostly cremated their dead, so the mod's graveyard
becomes a **cremation ground** (2026-11-23): an outdoor work at the town's edge, by the river where
there is one, with a pyre platform and a small shrine, a bamboo fence and a gate. Reuses 7a's
outdoor rule and fence code. It goes into 7b.

---

## 7. Town wall ⏸ later, after step 8 (2026-11-23)

**Mod:** `Perimeter.cs`. The wall is built last. It hugs what was built, uses buildings' outer
walls as part of it, puts a gate where a road crosses, and never runs along a road.

**Indo-Malay:**

| Tier | Defence |
|---|---|
| hamlet | none |
| village | thorny bamboo hedge or bamboo palisade, a gate where a road enters |
| town | earth rampart or brick wall (as at Trowulan), gatehouses on the main roads |
| capital (City tier) | brick walls round the palace |

**Blocked by:** module 10 only allows walls inside a building. Hedges and palisades can be objects,
like 7a's fence; brick town walls may want module 10's rule changed. Decide when the step comes.

**Moat:** to discuss later.

---

## 8. Order ✅ (2026-11-23)

Each step ends in the viewer, to be reviewed on its results before the next.

| # | Work | Module |
|---|---|---|
| 1 | **The census** (§C), with the roles in `economy.tres` rethemed (jobs, resources, `lives_at_work`, wealth, groups); today's module 10 types stand in until 3 and 4 | 12 |
| 2 | **Quarters** (§1): affinity, weak district points, selling at home or at market, heavy goods | 12 |
| 3 | **Grown buildings** (§2): room `size` and `front`/`back`/`side`, the house rooms, compounds | 10 + 12 |
| 4 | **Content retheme** (§5), building by building, each with its tests and placeholder art | 10 |
| 5 | **Furniture placed relative to the door** (§4) | 10 |
| 6 | **Step 7b**: plaza, yards, paths, cremation ground (§6), density (§C.8, pending) | 12 |
| 7 | **Step 8**: the whole-town check | 12 |
| 8 | **Town wall** and moat (§7) | 10 + 12 |

Step 1 replaces step 5's role list, so `economy_test`, `plot_test` and `building_test` change with it.
