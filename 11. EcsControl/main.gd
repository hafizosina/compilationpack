extends Node2D

## Module 11: module 7's touch controls driving a player entity in module 9's ECS. Input is
## recorded on EcsPlayerInputSingleton each physics tick; EcsPlayerControlSystem turns it into
## steering and intent flags, and module 9's systems carry them out. F1 toggles the overlay.

## Half the arena's side, in px.
const ARENA: float = 900.0
## Grid line spacing on the ground.
const GRID: float = 64.0

@export var catalog: EcsEntityCatalog
## Training dummies in a ring around the player.
@export var dummies: int = 6
@export var ring_radius: float = 260.0

@onready var _entities_root: Node2D = $World/Entities
@onready var _overlay: EcsDebugOverlay = $World/DebugOverlay
@onready var _camera: EcsFollowCamera = $Camera2D
@onready var _hud: EcsControlHud = $UI

var _world: EcsWorld
var _scheduler: EcsScheduler
var _manager: EcsEntityManager
var _input: EcsPlayerInputSingleton

func _ready() -> void:
	_manager = EcsEntityManager.new(_entities_root)
	_hud.ability_released.connect(func(ability: StringName, aim: Vector2) -> void: _record(ability, aim, false))
	_hud.ability_tapped.connect(func(ability: StringName) -> void: _record(ability, Vector2.ZERO, true))
	_build()
	queue_redraw()

func _physics_process(delta: float) -> void:
	_input.move = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down", 0.05)
	_input.aim = Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	_input.sprint = Input.is_action_pressed("sprint")
	_input.sprint_pressed = Input.is_action_just_pressed("sprint")
	_scheduler.run_all(_world, delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F1:
		_overlay.visible = not _overlay.visible
		get_viewport().set_input_as_handled()

func _record(ability: StringName, aim: Vector2, tapped: bool) -> void:
	_input.actions.append({"ability": ability, "aim": aim, "tapped": tapped})

## A new world: the player in the middle, dummies around it, and the pipeline.
func _build() -> void:
	_manager.clear()
	_world = EcsWorld.new()
	_input = EcsPlayerInputSingleton.new()
	_world.add_singleton(_input)
	var inbox := EcsLifecycleSingleton.new()
	_world.add_singleton(inbox)
	_world.add_singleton(EcsCombatSingleton.new())
	_world.add_singleton(EcsHealthSingleton.new())
	_ask(inbox, &"player", Vector2.ZERO)
	for k in dummies:
		_ask(inbox, &"dummy", Vector2.RIGHT.rotated(TAU * k / dummies) * ring_radius)
	_scheduler = EcsScheduler.new()
	_scheduler \
		.add(EcsLifecycleSystem.new(_manager, catalog)) \
		.add(EcsPlayerControlSystem.new()) \
		.add(EcsSkillSystem.new()) \
		.add(EcsAttackSystem.new()) \
		.add(EcsHealthSystem.new()) \
		.add(EcsDangerSystem.new()) \
		.add(EcsMovementSystem.new()) \
		.add(EcsCollisionSystem.new(_manager)) \
		.add(EcsSensorSystem.new(_manager)) \
		.add(EcsRemainsSystem.new()) \
		.add(EcsRespawnSystem.new()) \
		.add(EcsNodeSyncSystem.new(_manager)) \
		.add(EcsDebugSystem.new(_overlay)) \
		.add(EcsPlayerViewSystem.new(_manager, _camera, _hud))

func _ask(inbox: EcsLifecycleSingleton, type_id: StringName, at: Vector2) -> void:
	var note := EcsSpawnRequest.new()
	note.type_id = type_id
	note.position = at
	inbox.spawn_requests.append(note)

func _draw() -> void:
	draw_rect(Rect2(-ARENA, -ARENA, ARENA * 2.0, ARENA * 2.0), Color(0.29, 0.36, 0.22))
	var line := Color(0.0, 0.0, 0.0, 0.15)
	var x := -ARENA
	while x <= ARENA:
		draw_line(Vector2(x, -ARENA), Vector2(x, ARENA), line)
		draw_line(Vector2(-ARENA, x), Vector2(ARENA, x), line)
		x += GRID
