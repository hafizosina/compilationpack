class_name SimDebugComponent
extends SimComponent

## Development overlay: draws an entity's name, the component slots it carries,
## its wander leash and its current destination.
##
## This is the only way to tell a working factory from a stuck one, so it is
## injected by SimEntityFactory whenever Constant.DEBUG is on rather than
## authored into a blueprint — it is a dev tool, not content.

## Shared toggle for every overlay in the scene, flipped by main.gd (F1).
static var overlay_visible: bool = true

const TEXT_COLOR := Color(1, 1, 1, 0.85)
const LEASH_COLOR := Color(0.4, 0.9, 1, 0.3)
const TARGET_COLOR := Color(1, 0.85, 0.3, 0.6)
const FONT_SIZE := 11
const LABEL_ORIGIN := Vector2(-46.0, -42.0)

var _wander: SimWanderComponent
var _movement: SimMovementComponent
var _was_visible: bool = true

## Adds an overlay to `entity` and registers it. Called by the factory.
static func attach(entity: SimEntity) -> SimDebugComponent:
	var component := SimDebugComponent.new()
	component.name = "DebugComponent"
	entity.add_child(component)
	entity.register_component(component.slot(), component)
	return component

func slot() -> StringName:
	return &"debug"

func _ready() -> void:
	super()
	z_index = 100
	if entity == null:
		return
	_wander = entity.get_component(&"wander") as SimWanderComponent
	_movement = entity.get_component(&"movement") as SimMovementComponent

func _process(_delta: float) -> void:
	# The entity moves under the overlay every frame, and one extra redraw is
	# needed on the frame the overlay is switched off.
	if overlay_visible or _was_visible:
		_was_visible = overlay_visible
		queue_redraw()

func _draw() -> void:
	if not overlay_visible or entity == null:
		return
	var font := ThemeDB.fallback_font
	draw_string(font, LABEL_ORIGIN, entity.name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	draw_string(font, LABEL_ORIGIN + Vector2(0.0, FONT_SIZE + 2.0), _slot_label(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)

	# The leash circle is the per-instance override proof: two type1s carrying
	# a radius override must draw visibly different circles from the default.
	if _wander != null:
		draw_arc(to_local(entity.home_position), _wander.radius, 0.0, TAU, 64, LEASH_COLOR, 1.0)
	if _movement != null and _movement.is_moving():
		draw_line(Vector2.ZERO, to_local(_movement.target()), TARGET_COLOR, 1.0)

func _slot_label() -> String:
	var names: Array[String] = []
	for key in entity.component_slots():
		if key != &"debug":
			names.append(String(key))
	return "[%s]" % ", ".join(names)
