class_name EcsPlayerViewSystem
extends EcsSystem

## Read only. Shows the player: the camera follows it, its sprite turns to its facing, the
## status bar gets its health and dash readiness, the HUD each skill slot's cooldown.

var _manager: EcsEntityManager
var _camera: EcsFollowCamera
var _hud: EcsControlHud
var _health_sent: float = -1.0
var _stamina_sent: float = -1.0

func _init(manager: EcsEntityManager, camera: EcsFollowCamera, hud: EcsControlHud) -> void:
	_manager = manager
	_camera = camera
	_hud = hud

func label() -> StringName:
	return &"player_view"

func run(world: EcsWorld, _delta: float) -> void:
	var players := world.query([EcsPlayerComponent, EcsPositionComponent])
	if players.is_empty():
		return
	var id: int = players[0]
	var player := world.get_component(id, EcsPlayerComponent) as EcsPlayerComponent
	var place := world.get_component(id, EcsPositionComponent) as EcsPositionComponent
	if _camera != null:
		_camera.follow(place.position, player.facing)
	var sprite := _manager.node_for(id, EcsConst.NODE_SPRITE) if _manager != null else null
	if sprite != null:
		sprite.rotation = player.facing.angle()

	var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
	if health != null:
		_send_health(100.0 * health.value / maxf(health.max_health, 0.01))
	var known := world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent
	if known == null:
		return
	_send_stamina(100.0 * (1.0 - _cooling(known, player.dash_skill)))
	if _hud != null:
		var ratios: Array[float] = []
		for skill in player.skill_slots:
			ratios.append(_cooling(known, skill) if skill != &"" else 1.0)
		_hud.show_cooldowns(ratios)

## 1 just used, 0 ready.
func _cooling(known: EcsSkillsComponent, skill: StringName) -> float:
	if known.active_left.has(skill):
		return 1.0
	var def := EcsSkillDef.find(known.skills, skill)
	if def == null or def.cooldown <= 0.0:
		return 0.0
	return clampf(float(known.cooldown_left.get(skill, 0.0)) / def.cooldown, 0.0, 1.0)

func _send_health(value: float) -> void:
	if not is_equal_approx(value, _health_sent):
		_health_sent = value
		EventBus.health_change.emit(value)

func _send_stamina(value: float) -> void:
	if not is_equal_approx(value, _stamina_sent):
		_stamina_sent = value
		EventBus.stamina_change.emit(value)
