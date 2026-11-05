# Module 11 — EcsControl: state of the build

Module 7's touch controls driving a player in module 9's ECS. Module 7 had the HUD with nothing
behind it (an attack only printed); module 9 had combat that only animals could start. Here **the
player is an entity whose brain is the player**: input is recorded on a singleton, and
`EcsPlayerControlSystem` turns it into what module 9's brain writes — movement and intent flags —
so module 9's executors fight for it unchanged. Module 9 is borrowed, never copied; it changed
only by one approved hook (`steer`, module 9 HANDOFF §30). Module 7 is untouched; its HUD was copied.

```bash
"$GODOT" --path . "res://11. EcsControl/main.tscn"   # play; F1 toggles the overlay
# 59 checks; exit 0 only if all pass.
"$GODOT" --headless --path . "res://11. EcsControl/tests/control_test.tscn"
```

**Controls** (module 7's): left stick or WASD moves, analog; Sprint (button or Shift) runs, a
double-tap dashes. Right side: Basic Attack stick — drag to aim and let go, or tap for the nearest
target; the four skill sticks around it cast block, cleave, whirlwind and fireball. Hold the switch
button to swap to the interact wheel (does nothing yet). The mouse drives the sticks on a desktop.
The status bar shows health, stamina (the energy bar) and mana. Thorn bushes hurt to stand in.

---

## 1. Layout

| Path | Role |
|---|---|
| `singletons/` | `EcsPlayerInputSingleton` — this tick's input |
| `flags/` | `EcsSwingFlag` (a swing in progress); skill effects `EcsStrikeFlag`, `EcsLaunchFlag`, `EcsBlockingFlag` |
| `skills/` | Skill defs on module 9's `EcsSkillDef`: `EcsStrikeSkill` (melee), `EcsProjectileSkill` (spells), `EcsBlockSkill` |
| `components/` | `EcsPlayerComponent` (the controlled entity, its tuning and skill costs), `EcsWeaponComponent` (what it holds, its swing, its pose), `EcsPoolComponent` → `EcsStaminaComponent`, `EcsManaComponent`; `EcsProjectileComponent`, `EcsLifetimeComponent`, `EcsThornsComponent`, `EcsRespawnComponent` |
| `systems/` | `EcsPlayerControlSystem` (the player's brain), `EcsPoolSystem`, `EcsStrikeSystem`, `EcsLaunchSystem`, `EcsProjectileSystem`, `EcsThornsSystem`, `EcsBlockSystem`, `EcsLifetimeSystem`, `EcsWeaponSystem`, `EcsRespawnSystem`, `EcsPlayerViewSystem` (camera, sprite facing, weapon, status bar, skill cooldowns; read only) |
| `ui/` | `ui.tscn` — module 7's HUD, copied; `ui.gd` (`EcsControlHud`) sends abilities as signals |
| `camera_follow.gd` | `EcsFollowCamera`, module 7's lead camera, fed a target |
| `weapon_view.gd` | `EcsWeaponView`, draws the weapon at the pose it is handed, and the swing's trail |
| `defs/` | `entity_catalog.tres`; `blueprints/` player, player_grave, dummy, dummy_wreck, thorns, fireball, fireball_burst; `skills/` player_dash, block, cleave, whirlwind, fireball |
| `art/` | Placeholders: dummy, thorns, fireball, burst |
| `tests/` | `control_test.tscn` |

Pipeline (`main.gd`, every tick):
`lifecycle > control > pool > skill > strike > launch > projectile > thorns > attack > block > health > danger > movement > collision > sensor > remains > respawn > lifetime > weapon > node_sync > debug > player_view`.
`danger` is there because it clears `EcsHurtFlag`; `debug` is module 9's overlay (names, health bars).

---

## 2. Input to action, in one tick

`main.gd` writes the sticks and Sprint onto `EcsPlayerInputSingleton` in `_physics_process`, just
before the pipeline; the HUD's `ability_released(ability, aim)` / `ability_tapped(ability)` append
to its `actions`. `control` runs second, and skill, attack and movement after it, so **an input is
carried out in the tick it arrives**, as fast as module 7's direct code — pinned by tests. Intent
flags are not a queue for later; they hand the work to the one executor that owns it, so cooldown,
reach, crits, stun, and skill timers stay module 9's and are not repeated here. The only older
input is `EcsActionComponent.reached`, filled by the sensor at the end of the previous tick:
module 9's accepted one-tick reach.

**Control, the player's brain** (the only writer of the player's intent flags):
- **Moving**: `steer = stick × pow(len, speed_curve)`, or `stick × sprint_multiplier` while
  sprinting; zero when let go. `facing` is the aim while aiming, else the way it moves.
- **Attack**: let go aimed, the nearest reached entity with health inside `aim_cone` of the aim;
  tapped (or let go unaimed), the nearest at all. `EcsAttackIntentFlag` names it **for one tick**;
  `EcsAttackSystem` refuses it if the attack is cooling, the target out of reach, or the player
  stunned.
- **Skills**: stick N casts `skill_slots[N]` (block, cleave, whirlwind, fireball). It casts only
  a skill that would start now — known, not running, not cooling, its `can_start` true — and that
  it can pay for, and pays (§6). A timed skill's `EcsCastIntentFlag` lasts one tick; a held one
  (duration 0, like module 9's hide) stays until the same stick is used again, which ends it. A
  double-tap of Sprint casts `dash_skill`.
- **Blocking**: steer times `block_move_scale`.
- **Stunned or collapsed**: steer zero, and no action is taken.

**Movement is module 9's**, through the `steer` hook: non-zero, movement moves by
`steer × speed × dash scale` and ignores destinations. So movement stays the only writer of
position, soft collision pushes the player off dummies, and node sync draws it every tick.

**The dash** is module 9's `EcsDashSkill` with the player's own values (`player_dash.tres`, via
`EcsSkillsComponent.swaps`): 0.15 s at 4× speed, 0.6 s cooldown, and a hit landed while dashing
stuns for 1 s, as module 9's pounce.

## 3. Dummies

A dummy is a solid body with health, a sprite and `EcsRemainsComponent.leaves {health: dummy_wreck}`.
At 0 health, module 9's health and remains systems leave a darkened wreck where it stood. The wreck
carries `EcsRespawnComponent {blueprint: dummy, after: 3}`; `EcsRespawnSystem` counts it down, asks
lifecycle for a dummy there and marks the wreck dying (cause removed). Every birth and death goes
through lifecycle.

## 4. The weapon and attack skills (2026-11-05)

**Animation is data.** The player holds a weapon: `EcsWeaponComponent` names its texture and how
it swings (`swing_arc`, `swing_time`, `hold`, `rest_angle`), and carries its **pose** — `angle`,
`trail_from`, `progress` — as runtime data. A swing in progress is **`EcsSwingFlag`**
`{direction, arc, duration, elapsed}`. **`EcsWeaponSystem`** is the animation: each tick it
advances the flag, writes the pose (resting beside the facing, or sweeping the arc, eased) and
removes the flag when the swing is done. The view only copies the pose onto `EcsWeaponView`, which
keeps no clock and no tween — so a swing can be tested, paused or saved like any data.

Who starts a swing raises the flag: **control**, when an attack is let go while the attack is
ready (a miss swings too; module 9 starts the attack cooldown only on a hit, so a miss can swing
again at once, one swing at a time); **strike**, for an attack skill, replacing any swing running;
**launch**, a short thrust for a spell.
`EcsWeaponSystem` is the only one that ends it.

**Attack skills** are module 9 skills: `EcsStrikeSkill` extends `EcsSkillDef`, so `EcsSkillSystem`
runs their cooldown and duration and adds and removes their effect, `EcsStrikeFlag`. A module 11
**`EcsStrikeSystem`** carries a strike out once, in the tick it starts: a hit (attacker's damage ×
`damage_scale`, crit rolled as an attack) on every reached entity with health inside `arc` around
the facing, sent through module 9's combat inbox, and the skill's own swing. The player has two,
added through `EcsSkillsComponent.swaps`:

| Skill | Damage | Arc | Swing | Cooldown |
|---|---|---|---|---|
| cleave | 2× | 160° in front | 0.3 s wide sweep | 2.5 s |
| whirlwind | 1.5× | 360°, everything in reach | 0.4 s full spin | 5 s |

The weapon is `Global/Asset/Items/weapon_longsword.png`; the axe, pole and axe-blades textures
there work the same way, by changing `EcsWeaponComponent.texture` on the player blueprint.

## 5. Block, the fireball (2026-11-05)

**Block** (stick 1) is `EcsBlockSkill`: for 1.2 s its effect `EcsBlockingFlag {reduction 0.8, arc
140°}` is on. **`EcsBlockSystem`** runs between the hits being made (strike, projectile, thorns,
attack) and module 9's health applying them, on the combat inbox: a hit on a guard from inside its
arc around the facing loses 80% of its damage and all its stun, bleeding and poison. Module 9's
health is untouched. While guarding the player moves at 0.4×, and `EcsWeaponSystem` holds the
weapon across the body (`guard_angle`) and writes the guarded arc into the pose, which the view
draws. Dash stays on the Sprint double-tap.

**Fireball** (stick 4) is `EcsProjectileSkill`: its effect `EcsLaunchFlag` makes
**`EcsLaunchSystem`** ask lifecycle, once, for a `fireball` just ahead of the caster with
`EcsProjectileComponent {direction: facing, owner, damage: caster's damage × 1.75}` as overrides,
and start a short thrust. A fireball is an ordinary entity: module 9's movement flies it (its
**`EcsProjectileSystem`** sets `steer` to its direction — the projectile's brain), module 9's
sensor fills its reach, and the first entity with health it reaches that isn't its owner takes the
hit, through the combat inbox, as the owner's. It then dies with detail `impact`, and module 9's
remains leave a `fireball_burst` (`leaves {impact: fireball_burst}`). **`EcsLifetimeSystem`** ends
what has lived its `seconds`: a fireball at its range (1.2 s, ~500 px) with no burst, a burst after
0.3 s.

## 6. Stamina, mana and thorns (2026-11-05)

The status bar's three bars are real: health, **stamina** (the energy bar) and **mana**.
`EcsStaminaComponent` and `EcsManaComponent` share `EcsPoolComponent {max_value, value, regen,
regen_delay}`. **`EcsPoolSystem` is the only writer of `value`**, as module 9's health is of health:
others ask by adding to `spent`, and it pays, then refills after `regen_delay` without spending.
It runs right after control, so a cost is paid in the tick it's asked. Stamina is named so because
module 9's `EcsEnergyComponent` is sleep.

What a skill costs is the player's, `EcsPlayerComponent.skill_costs` (x stamina, y mana): dash 25,
block 15, cleave 20, whirlwind 35, fireball 30 mana. Control casts only what it can pay for.
Sprinting drains `sprint_drain` stamina a second; with none left it can't sprint. Stamina refills
20/s after 0.8 s, mana 8/s after 1.5 s.

**Thorn bushes** are an entity, `thorns.tres`, placed by `main.gd`: a non-solid body, reach, module
9's `EcsDamageComponent` (8 every 0.7 s) and `EcsThornsComponent`. **`EcsThornsSystem`** hits
everything with health its reach touches when its attack is ready; module 9's attack counts the
cooldown down. Nothing in module 9 hurts by touch — its attack fires only at a target a brain named.
A thorn's hit comes from the bush, so blocking toward it softens it.

**The player can fall.** It carries `EcsRemainsComponent {health: player_grave}`; the grave carries
`EcsRespawnComponent {player, 3 s}`, as a dummy's wreck does. It comes back where it fell, with
full pools; the camera and HUD follow the new player.

## 7. The view

`EcsPlayerViewSystem` reads only: it feeds the camera the player's position and facing (module 7's
vertical lead), turns the player's sprite to its facing, sends health, stamina and mana to module
7's status bar over `EventBus`, and dims each skill stick by its slot's cooldown.
Turning the sprite is the one per-tick node write outside node sync; it is the player's view only.

**Not yet, by decision:** the interact wheel (pick up, place, craft) and the inventory panel;
animals; potions; the player's hunger and thirst; damage numbers; the bow (the fireball's
projectile is the way). Hit feedback is the swing and the target's health bar on the overlay.

**Tests** (`control_test.tscn`, 59) — also: a fireball costs its mana in its tick, flies out as an
entity, hits a dummy for 1.75×, is gone leaving a burst that fades; one that hits nothing ends at
its range without a burst; without the mana it isn't cast, and mana refills after its delay;
sprinting drains stamina at `sprint_drain`, with none left it can't sprint, and stamina refills;
block raises a guard and holds the weapon across the body, a hit from in front loses 80%, one from
behind lands in full, blocking slows, the guard ends; standing in thorns hurts, at 0 the player
falls and leaves a grave, and is back after its time. And: the weapon rests beside the facing; an attack at
nothing swings in the same tick, starting at one edge of its arc and ending after `swing_time` at
the other, then rests; a hit swings and starts the cooldown, and a press while cooling doesn't
swing; cleave hits both dummies in front at 2× and not the one behind, with its own swing, once
per cast, and cools down; whirlwind hits all three around and spins a full turn. The first 26: a full stick covers `speed` a second, half a stick follows the
curve, sprint is faster, letting go stops; one sprint press is not a dash, a double-tap dashes in
the same tick at dash speed and ends; stunned, it neither moves nor casts; an aimed attack lands in
the tick of its input, its intent is gone the next tick, a press while cooling does nothing, an aim
outside the cone or a dummy out of reach is not hit, the facing follows the aim, a tap takes the
nearest; a dummy hit to 0 becomes a wreck and is back after 3 s at full health; a skill stick casts
its slot's skill in the same tick, a timed cast lasts one tick, an empty slot casts nothing.
