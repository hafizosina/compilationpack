# TODO

Plans noted for later across modules 9, 10 and 11.

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

## Module 11 — EcsControl
- [ ] Animals.
- [ ] Interact wheel (pick up, place, craft).
- [ ] Inventory panel.
