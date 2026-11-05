class_name EcsPlayerViewSystem
extends EcsSystem

## Read only. Shows the player: the camera follows it, its sprite turns to its facing, its
## weapon takes the pose EcsWeaponSystem wrote, the status bar gets its health, stamina (the
## energy bar) and mana, the HUD each skill slot's cooldown.

var _manager: EcsEntityManager
var _camera: EcsFollowCamera
var _hud: EcsControlHud
var _weapon_view: EcsWeaponView
var _health_sent: float = -1.0
var _stamina_sent: float = -1.0
var _mana_sent: float = -1.0

func _init(manager: EcsEntityManager, camera: EcsFollowCamera, hud: EcsControlHud,
		weapon_view: EcsWeaponView = null) -> void:
	_manager = manager
	_camera = camera
	_hud = hud
	_weapon_view = weapon_view

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
	var weapon := world.get_component(id, EcsWeaponComponent) as EcsWeaponComponent
	if _weapon_view != null and weapon != null:
		_weapon_view.show_pose(place.position, weapon)

	var health := world.get_component(id, EcsHealthComponent) as EcsHealthComponent
	if health != null:
		_send_health(100.0 * health.value / maxf(health.max_health, 0.01))
	var stamina := world.get_component(id, EcsStaminaComponent) as EcsStaminaComponent
	if stamina != null:
		_send_stamina(100.0 * stamina.value / maxf(stamina.max_value, 0.01))
	var mana := world.get_component(id, EcsManaComponent) as EcsManaComponent
	if mana != null:
		_send_mana(100.0 * mana.value / maxf(mana.max_value, 0.01))
	var known := world.get_component(id, EcsSkillsComponent) as EcsSkillsComponent
	if known == null:
		return
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

func _send_mana(value: float) -> void:
	if not is_equal_approx(value, _mana_sent):
		_mana_sent = value
		EventBus.mana_change.emit(value)

func _send_stamina(value: float) -> void:
	if not is_equal_approx(value, _stamina_sent):
		_stamina_sent = value
		EventBus.stamina_change.emit(value)
