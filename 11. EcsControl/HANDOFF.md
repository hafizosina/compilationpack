# Module 11 — EcsControl: state of the build

Module 7's touch controls driving a player in module 9's ECS. Module 7 had the HUD with nothing
behind it (an attack only printed); module 9 had combat that only animals could start. Here **the
player is an entity whose brain is the player**: input is recorded on a singleton, and
`EcsPlayerControlSystem` turns it into what module 9's brain writes — movement and intent flags —
so module 9's executors fight for it unchanged. Module 9 is borrowed, never copied; it changed
only by one approved hook (`steer`, module 9 HANDOFF §30). Module 7 is untouched; its HUD was copied.

```bash
"$GODOT" --path . "res://11. EcsControl/main.tscn"   # play; F1 toggles the overlay
# 26 checks; exit 0 only if all pass.
"$GODOT" --headless --path . "res://11. EcsControl/tests/control_test.tscn"
```

**Controls** (module 7's): left stick or WASD moves, analog; Sprint (button or Shift) runs, a
double-tap dashes. Right side: Basic Attack stick — drag to aim and let go, or tap for the nearest
target; the four skill sticks around it cast slots 1–4. Hold the switch button to swap to the
interact wheel (does nothing yet). The mouse drives the sticks on a desktop.

---

## 1. Layout

| Path | Role |
|---|---|
| `singletons/` | `EcsPlayerInputSingleton` — this tick's input |
| `components/` | `EcsPlayerComponent` (the controlled entity and its tuning), `EcsRespawnComponent` |
| `systems/` | `EcsPlayerControlSystem` (the player's brain), `EcsRespawnSystem`, `EcsPlayerViewSystem` (camera, sprite facing, status bar, skill cooldowns; read only) |
| `ui/` | `ui.tscn` — module 7's HUD, copied; `ui.gd` (`EcsControlHud`) sends abilities as signals |
| `camera_follow.gd` | `EcsFollowCamera`, module 7's lead camera, fed a target |
| `defs/` | `entity_catalog.tres`; `blueprints/` player, dummy, dummy_wreck; `skills/player_dash.tres` |
| `art/dummy.png` | Placeholder dummy |
| `tests/` | `control_test.tscn` |

Pipeline (`main.gd`, every tick):
`lifecycle > control > skill > attack > health > danger > movement > collision > sensor > remains > respawn > node_sync > debug > player_view`.
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
- **Skills**: stick N casts `skill_slots[N]` (dash, scan, hide, empty). A timed skill's
  `EcsCastIntentFlag` lasts one tick; a held one (duration 0, like hide) stays until the same stick
  is used again, which ends it. A double-tap of Sprint casts `dash_skill`. Whether a skill may
  start is the skill's (`can_start`): hide out of cover is refused there.
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

## 4. The view

`EcsPlayerViewSystem` reads only: it feeds the camera the player's position and facing (module 7's
vertical lead), turns the player's sprite to its facing, sends health (and dash readiness as
stamina) to module 7's status bar over `EventBus`, and dims each skill stick by its slot's cooldown.
Turning the sprite is the one per-tick node write outside node sync; it is the player's view only.

**Not yet, by decision:** the interact wheel (pick up, place, craft) and the inventory panel;
animals; potions; the player's hunger, energy and thirst; swing animations and damage numbers.
The hit feedback is the target's health bar on the overlay — module 9's bite mark needs the
intent to outlive the hit, and here it lasts one tick.

**Tests** (`control_test.tscn`, 26): a full stick covers `speed` a second, half a stick follows the
curve, sprint is faster, letting go stops; one sprint press is not a dash, a double-tap dashes in
the same tick at dash speed and ends; stunned, it neither moves nor casts; an aimed attack lands in
the tick of its input, its intent is gone the next tick, a press while cooling does nothing, an aim
outside the cone or a dummy out of reach is not hit, the facing follows the aim, a tap takes the
nearest; a dummy hit to 0 becomes a wreck and is back after 3 s at full health; a skill stick casts
its slot's skill in the same tick, a timed cast lasts one tick, an empty slot casts nothing, hide
out of cover is refused.
