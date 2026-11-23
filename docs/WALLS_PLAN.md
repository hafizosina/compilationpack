# Walls, doors, gates and fences: plan

Phase 3 of `docs/ART_PLAN.md`, taken first. Redraw walls and doors in RimWorld's art style at 64 px, and make fences and
gates real, joined pieces. Indo-Malay content, English names. The decisions waiting on you are in **§5**.

## 1. What exists

| Thing | How it works today | Problems |
|---|---|---|
| **Walls** | 4 wall types (`defs/wall/`): wood (author's `WoodWall.png`), stone (author's `BaseWall.png`), bamboo and brick (PIL placeholders). Each sheet holds the 16 join shapes; the tile sync picks the shape from which neighbours are walls of the same building. Building types pick a wall per wealth: poor bamboo, middling wood, rich wood or brick. | Old 32 px pixel art, two styles mixed. No stone or brick that reads as Majapahit. |
| **Doors** | 2 door types: wood (`WoodenDoor.png`), stone (`BaseDoor.png`), both opening into `door_states.png`. A tile is 1.5 cells, drawn over the wall gap; horizontal or vertical by the wall around it. | Old art. A "stone door" doesn't fit; no bamboo door for bamboo walls. |
| **Fences** | One `fence` piece, a furniture tile with rails along x, turned a quarter for vertical runs. Placed round fields, pens, yards and rich compounds (module 12 `ecs_town_builder.gd`). | **Fence pieces don't join**: corners show a rail going one way, and runs are separate tiles. Only one fence for every use. |
| **Gates** | None: a gate is a **gap** left in the fence (2 cells for fields and pens, at the door for yards and compounds). | Nothing marks the way in; a rich compound has no gateway. |

## 2. What we want (content)

**Walls** (the same 4 keys, so building types and saves keep working):

| Key | Look | Used for |
|---|---|---|
| `bamboo` | woven bamboo panels (gedek) between bamboo posts | poor houses, huts, sheds |
| `wood` | timber planks between teak posts | middling houses, workshops, taverns |
| `brick` | red Majapahit brick (Trowulan), courses visible on top | rich houses, halls, manors |
| `stone` | grey andesite blocks (candi stone) | temples |

**Doors** (`stone` becomes `carved`, the key mapped in building types):

| Key | Look | Used for |
|---|---|---|
| `bamboo` (new) | lashed bamboo leaf | bamboo walls |
| `wood` | plank door | wood walls |
| `carved` (was `stone`) | carved teak double leaf, a brass ring | brick and stone walls, rich and temple |

Each drawn closed and open, horizontal and vertical, as today.

**Fences and gates** (new, a fence type and its gate together):

| Fence | Gate | Used for |
|---|---|---|
| `bamboo_rail`: split-bamboo rails on posts | swing gate of rails | fields and pens |
| `woven`: woven bamboo screen | woven leaf gate | middling yards |
| `hedge`: living hedge (hibiscus) | an opening framed by two clipped posts | poor yards |
| `brick_wall`: low brick wall with a coping | **split gate** (candi bentar: two brick towers, an opening between) | rich compounds, temples |

## 3. Technical changes

**3.1 Joined pieces (`link`).** A fence must join like a wall, but it cannot be a wall: walls close rooms (room
detection, roofs, doors), and a fenced field must not become a room. So a fence stays a piece (furniture layer, its
own blueprint) and gains **`EcsTileComponent.link`**, a group name. The tile sync draws a linked piece by its join
mask, from which of its four neighbours hold a piece of the same link group, from a 16-shape sheet in the wall
layout (`EcsDualGrid.side_layout`, already read from pixels). RimWorld does fences the same way. The turn the
generator now sets on a fence is no longer needed.

**3.2 Gates are pieces.** A gate is a blueprint in its fence's link group (so the fence joins into it), walkable,
placed where today's gap is: a 2-cell field gate is two leaves, a compound's gate is a 3-cell gateway. Drawn
closed; open (a villager passing, like a door) it is drawn see-through. A villager walks through it like a door.

**3.3 Which fence where is data.** `EcsSettlementDef` names the fence for fields, pens, yards by wealth, compounds
and temples (as `yard_fence` already holds chances by wealth). Module 12's builder stops choosing turns and places
the fence and gate the def names.

**3.4 Walls and doors drawn by one script.** `art/flatvec/walls.py` builds each wall's 16-shape sheet from one
recipe (posts, panels between them, material lines), and the same code draws the fence sheets (thinner, lower) and
the hedge (clustered leaves along the arms). Doors: 4 states per type on one sheet. All at 64 px a cell
(`cell_pixels = 64`, so no resize on load), written to `Global/Asset/Structure/`. The author's old sheets stay in
module 10's placeholder folder.

## 4. Steps

Each step: a mock-up for you to review (in-engine screenshot, before and after), then into the game, tests, commit.

| # | Step | Shows |
|---|---|---|
| 1 | Wall look: one wall type (`wood`) in RimWorld's style (§5 D1, D2) | a small house with its walls, before and after |
| 2 | All 4 walls | one building of each wall type |
| 3 | Doors: bamboo, wood, carved, closed and open | doors in their walls |
| 4 | Joined pieces (`link`) + `bamboo_rail` fence and its gate | a fenced field with a joined corner and a gate |
| 5 | The other fences and gates (woven, hedge, brick wall + split gate) | a yard of each, a rich compound |
| 6 | Module 12 places them from the settlement def | a whole town |

## 5. Decisions (2026-11-23)

- **D1 Wall view:** straight from above, **drawn in RimWorld's art style** (its material textures, soft shading,
  a dark edge), not the ink-outlined vector style.
- **D2 Structure:** walls keep today's core structure (a whole cell, the 16 join shapes); only the art follows
  RimWorld.
- **D3 Doors:** 1.5 cells wide over the wall gap, for now.
- **D4 Gates:** drawn closed; an open gate is drawn see-through (transparent), no swing animation for now.
- **D5 Fences:** the four in §2.
- **D6 Files:** old art lives in `10. Town Generator/art/placeholder/` (the author's `WoodWall`, `BaseWall`,
  `WoodenDoor`, `BaseDoor`, `WoodFloor`, `grassTileset` moved there); **new art goes in `Global/Asset/`**: the
  ground textures are in `Global/Asset/Ground/`, walls, doors, fences and gates will go in `Global/Asset/Structure/`.
