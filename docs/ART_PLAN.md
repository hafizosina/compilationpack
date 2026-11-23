# Art plan: redraw everything in the Birds Eye style

The goal is to redraw every asset the game shows (modules 9–12) in the style of the author's RimWorld mod
`~/Project/Rimworld-Mod/BirdsEyePawns`, with Indo-Malay content (Majapahit, Srivijaya). This is a plan for review;
the decisions waiting on you are in **§6**.

## 1. The style we're copying (BirdsEyePawns)

Seen in `BirdsEyePawns/Textures/TopDown` and its sources in `tools/birdseye/`:

- **Straight top-down view.** A tree is mostly its canopy. An animal is one continuous silhouette, head up.
- **One thick, even ink outline** (`#1e1a18`), about 3 px on a 128 px texture, round every separate part. Inner
  detail (veins, planks, fur) uses thin, semi-transparent ink lines clipped inside the shape.
- **Flat shading.** Each shape is filled darker, then a lighter copy is shifted up-left (light from the top-left).
  No gradients and no noise.
- **A soft shadow cast down-right** under anything that stands up (trees, animals, tall furniture).
- **Silhouette first.** Species are told apart by outline shape, not only colour: palm fronds vs bamboo sprays vs
  teak star-leaves vs round broadleaf clumps.
- **Layers where things change.** Trees are built in stages (sapling to full, plus leafless). Pawns are built from a
  greyscale body, head, clothing and hair, each tinted in game.

It is the same family as the `flat-vector-assets` skill (`flatvec.py`), because the skill was taken from this mod.
So the pipeline we already use (Python → SVG → Inkscape → Pillow atlas) stays. What changes is resolution, outline
weight, shadows, and drawing everything instead of 25 pieces.

**Reusable from the mod as is** (the same draw code, rethemed colours):

| Mod source | Gives us |
|---|---|
| `svgdemo11_trees.py`: `palm`, `bamboo`, `teak`, `cocoa`, `cecropia`, `broadleaf`, `sapling`, `leafless` | coconut palm, bamboo clump, teak, fruit tree, a banyan/rain tree from `cecropia`/`broadleaf`, growth stages |
| `svgdemo11_plants.py`: `bush`, `berry_bush`, `grass`, `tall_grass`, `alocasia`, `frond`, `moss`, `cap`; the mod's `Plant_Rice` textures | bushes, herb bush, reeds, taro/alocasia, ferns, mushrooms, rice crop stages |
| `tools/birdseye/recipes/vector.toml` + `generators/vector.py` (animals) | cow → **water buffalo**, chicken, pig, dog → wild dog, cat, deer; base for monkey, rabbit, crocodile |
| `core/shapes.py` pawn pipeline (body, head, garment, hair, tinted greyscale) | villagers and the player, in sarong, kain, headcloth |

## 2. What the game shows today

| Sheet | Pieces | Used by | State |
|---|---|---|---|
| `art/placeholder/objects.png` | 19 (bed, table, chair, chest, well, crop, tree…) | module 10/12 blueprints | PIL boxes |
| `furniture.png` | 24 (forge, anvil, oven, millstone, pew, altar…) | module 10 rooms | PIL boxes; several European pieces now unused |
| `nodes.png` | 15 (oak, pine, birch, fruit tree, bushes, reeds, rocks, ore veins, clay pit) | terrain resources | PIL circles |
| `outdoor.png` | 14 (fence, stall, boat, mine, shrine, water wheel…) | module 12 works | PIL boxes |
| `indomalay.png` | 19 Indo-Malay furniture | module 12 rooms | flat vector, thin outline |
| `indomalay_outdoor.png` | 6 (bench, lamp, garden bed, coop, banana tree, pyre) | module 12 dressing | flat vector, thin outline |
| `attachments.png`, `door_states.png` | 6 wall attachments, 4 door states | module 10 | PIL |
| terrain ×6, floor ×5, wall ×3, `roof.png` | dual-grid / wall tile sheets (6×3) | module 10/12 | PIL with noise |
| `Global/Asset/Animal/*` | rabbit, monkey, crocodile, dog | module 9 | old hand art, other style |
| `Global/Asset/character.png`, `11. EcsControl/art/*` | player, dummy, fireball, burst, thorns | module 11 | old art |

About 110 pieces and 15 tile sheets, plus new content the town now needs (below).

**New pieces the Indo-Malay towns need:** water buffalo, chicken, goat; coconut palm, bamboo clump, banyan, nipa palm,
mangrove; rice paddy (sawah) stages and terrain; perahu (boat), bamboo fence, thatched market stall, rice stack,
stilt-house posts, attap (palm thatch) roof; villagers.

## 3. Technical changes

### 3.1 Resolution (decision D1)

Cells are 32 px (`EcsTownGrid.CELL`). The mod's style needs room for a 3 px outline and a shadow; at 32 px the
outline drops to about 1 px and detail turns to mush (the current Indo-Malay sheets show this).

Proposal: **draw at 128 units per tile, export atlases at 64 px per tile, and draw them at half scale**, so the
world stays 32 units per cell and zooming in stays sharp. Code change: a texture density next to `tile_size` in
`EcsDualGrid.make_tile_set` / `make_source`, and the same for entity sprite atlases (`EcsTileComponent.atlas` stays a
cell coordinate; only the region size changes). Measure memory and FPS before and after (town stress scene).

### 3.2 Things bigger than their cell (decision D2)

A tree's crown and a buffalo's body spill over their cell in the mod, and that is a large part of the look. Today
objects are atlas tiles clipped to their footprint. Proposal: an object may carry a **draw size larger than its
footprint** (e.g. a tree is 1×1 to walk round but drawn 2×2, centred), drawn above floors and below roofs. Shadows
come baked into the sprite, down-right.

### 3.3 One shared art toolkit

The art script moves from `10. Town Generator/art/flatvec/` to `Global/Asset/art/` (modules 9, 10, 11 and 12 all
use it), with:
- `flatvec.py` with the mod's outline weight, shadow and palette as constants;
- `palette.py`: one set of Indo-Malay colours (teak, bamboo, attap, terracotta, brass, sawah green, river water);
- `trees.py`, `plants.py`, `animals.py`, `people.py` ported from the mod's tools;
- one script per sheet writing the atlas plus a contact sheet at real size on the game's ground colour;
- `build.py` building all sheets (or just the named ones), skipping unchanged ones.

### 3.4 Ground and floors

Terrain is drawn like RimWorld's (done, decision above): large seamless textures behind a per-cell map, with
ragged soft edges, no dual grid. Floors and roofs keep the dual-grid 6×3 layout and get flat vector sheets in
phase 2 (`art/flatvec/ground.py` holds a first mock-up of them).

## 4. Phases

Each phase: a mock-up of 4–6 pieces for you to steer → the whole sheet → into the game → run the viewer and the
module's tests → commit.

| # | Phase | Pieces | Why this order |
|---|---|---|---|
| 0 | Groundwork | D1 resolution, D2 oversize objects, shared toolkit, palette; one test piece (a palm) in game at both zooms | everything after depends on it |
| 1 | Nature | trees (palm, bamboo, teak, banyan, fruit tree, nipa, mangrove) with stages, bushes, reeds, rocks, ore veins, clay pit | most of the screen; the mod's designs are already approved |
| 2 | Ground | grass, dirt, sand, water, rock, forest floor, sawah (new), dirt path, road, wood/stone floors | objects need a ground to be judged on |
| 3 | Buildings | walls (bamboo, wood, brick, stone), doors, attap and tile roofs, stilt posts | the town's outline |
| 4 | Town outdoors | perahu, bamboo fence, stall, rice stack, notice board, shrine, mine, water wheel, mooring post, dock, plus redrawing the 6 dressing pieces at the new weight | retheme of `outdoor.png` |
| 5 | Furniture | redraw the 19 Indo-Malay pieces at the new weight; redraw the kept workshop pieces (forge, anvil, quench barrel, tool rack, crate, sack, lumber pile…); attachments | rooms |
| 6 | Animals | buffalo, chicken, goat (town); rabbit, monkey, crocodile, wild dog (module 9) | from the mod's animal recipes |
| 7 | People | villager and player: body, head, sarong/kain/baju, headcloth, hair, tinted per person | largest job; module 9/11 need one sprite per person |
| 8 | Effects and HUD | module 11's fireball, burst, thorns, dummy; skill icons | last; the HUD theme is its own job |

## 5. Out of scope for now

Animation frames (walk cycles), roofs that fade when someone goes inside, night lighting, and UI theme work.

## 6. Decisions taken

- **D1 Resolution (2026-11-23):** 64 px a tile, shown at half scale (`EcsTownGrid.ART`). Done; module 10 HANDOFF §13e.
- **Ground (2026-11-23):** like RimWorld: one large seamless texture per terrain, shown by a shader with a ragged
  edge and a short soft fade; terrain left the dual grid. Done; module 10 HANDOFF §13e. Floors keep the dual grid.

## 7. Decisions still open

- **D2 Oversize objects:** may trees and animals draw beyond their cell (recommended), or stay inside it?
- **D3 Unused European pieces** (oven, millstone, pew, altar, high seat, kneading table, flour sack, chapel-era
  items): delete them, or redraw them anyway?
- **D4 Order:** start with nature (recommended), or with buildings and furniture since the town is the current
  focus?
- **D5 Toolkit home:** `Global/Asset/art/` (recommended), or keep it in module 10?
- **D6 Colour mood:** the mod's muted RimWorld palette, or a little warmer and greener for the tropics?
