# TODO

Plans noted for later across modules 9 to 12.

## Module 9 — EcsSystem
- [ ] Review the core GOAP logic yourself (`ai/ecs_planner.gd`, `systems/ecs_planning_system.gd`). Paused 2026-11-01.
- [ ] Move the planner onto its own thread (planned 2026-11-06; measured A* is only ~0.1 ms per run).
- [ ] Combat planning: a kill is many attacks; GOAP picks skills from the enemy's skills and stats.
- [ ] Advanced combat AI for complex entities, for 5 vs 5 team fights. It weighs items, weapons,
      armour, base stats, the environment and skills.
- [ ] Entity relations, maybe as a graph DB (undecided).
- [ ] `EcsProficiencyComponent`: base levels for builder, farming, blacksmith, fishing, carpenter,
      cooking and trading. Having it is what separates humans from animals. Its purpose is long
      plans with several routes to one goal. For a meal:
  - Do it all: build a farm, grow wheat, mill it for flour at a miller, cook.
  - Hire someone to build, farm or cook.
  - Buy a meal from a vendor.
- [ ] Argue out the storage question (HANDOFF §15).
- [ ] Resume the live FPS work (paused 2026-11-07):
  - Drop the slicing `git stash`, or keep it on a branch.
  - Pick the next lever: planning on changes, planning at 10 Hz, timers as end times, or danger skipping idle animals.
- [ ] Continue after the AI walkthrough (paused 2026-11-08).
- [ ] ONI study notes (`9. EcsSystem/ONI_STUDY.md`), kept as a note for now.

## Module 10 — Town Generator
- [ ] Discuss your plan for the "closed" building flag (`CLOSE_BUILDING`).
- [x] Pathfinding system (2026-11-08, HANDOFF §12).
- [x] A real town generator: moved to module 12 (`12. Settlement Generator/PLAN.md`).
- [x] Resource nodes, rock and forest terrains, the Resources tool (2026-11-08, HANDOFF §13).
- [ ] Per-entity pathfinding: a cell's cost depends on who walks it. Decide whether Godot's A* is
      enough or it needs a custom C++ GDExtension.
  - Doors: open if it has access; a solid wall if not; with a lockpick, a path at a high cost
    set by its lockpicking skill and morale.
  - Walls: a weapon that can break walls makes them walkable at a cost (morale, war, enemies near).
  - Water: some never enter it, some prefer it over land.

## Module 12 — Settlement Generator
- [x] Step 1: terrain and resource nodes, on an L2 region with L1 streamed in chunks; cell detail
      panel (2026-11-08).
- [x] Step 2: the town's site, plaza and well; moved by right-click (2026-11-08).
- [x] Step 3: main roads to the region's edge, organic lanes, bridges (2026-11-08).
- [x] Step 4: plots placed first, lanes routed from their doors, yards grown to meet them
      (2026-11-10).
- [ ] Steps 5–9 on L1 (`PLAN.md`): zoning, buildings, outdoors, whole-town check, viewer and
      measurements.
- [ ] Open plan questions: crops on tilled soil (a module 10 rule
      change, or soil as a terrain), fences as objects or a structure with gates.
- [ ] L3 world map, and height-based water: heightmap, Priority-Flood lakes, D8 rivers (the
      September L3/L2/L1 notes). The world is finite.
- [ ] Tributaries: L1 rivers of its own beyond the L2 river.
- [ ] Chunks: a cap on chunks kept in memory; objects that can cross a chunk edge.
- [ ] Faster L1 chunks if they are streamed while playing (the blend and the command lists).
- [ ] The coast's sand is thin on big maps.

## Module 11 — EcsControl
- [ ] Animals.
- [ ] Interact wheel (pick up, place, craft).
- [ ] Inventory panel.
