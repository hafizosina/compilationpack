class_name SimDebugComponent
extends SimComponent

## Development overlay: draws an entity's name, the component slots it carries,
## its wander leash and its current destination.
##
## This is the only way to tell a working factory from a stuck one, so it is
## injected by SimEntityFactory whenever Constant.DEBUG is on rather than
## authored into a blueprint — it is a dev tool, not content.

## How much each overlay draws. LEASHES is the per-instance override proof but
## is deliberately not the default — one circle per creature is unreadable with
## a whole population on screen.
enum Mode { OFF, LABELS, LEASHES }

## Shared across every overlay in the scene, cycled by main.gd (F1).
static var mode: Mode = Mode.LABELS

const TEXT_COLOR := Color(0.09, 0.08, 0.1, 1)
const TEXT_OUTLINE_COLOR := Color(1, 1, 1, 0.85)
const TEXT_OUTLINE_SIZE := 4
const LEASH_COLOR := Color(0.15, 0.55, 0.75, 0.45)
const TARGET_COLOR := Color(1, 0.85, 0.3, 0.6)
## Sized for the default camera zoom (0.55) — world-space text shrinks with it.
const FONT_SIZE := 24
const LABEL_ORIGIN := Vector2(-52.0, -72.0)

var _wander: SimWanderComponent
var _movement: SimMovementComponent
var _drawn_mode: Mode = Mode.LABELS

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
	if mode != Mode.OFF or _drawn_mode != Mode.OFF:
		_drawn_mode = mode
		queue_redraw()

func _draw() -> void:
	if mode == Mode.OFF or entity == null:
		return
	_draw_label(LABEL_ORIGIN, entity.name)
	_draw_label(LABEL_ORIGIN + Vector2(0.0, FONT_SIZE + 4.0), _slot_label())

	if _movement != null and _movement.is_moving():
		draw_line(Vector2.ZERO, to_local(_movement.target()), TARGET_COLOR, 2.0)

	# The leash circle is the per-instance override proof: two type1s carrying a
	# radius override must draw visibly different circles from the default.
	if mode == Mode.LEASHES and _wander != null:
		draw_arc(to_local(entity.home_position), _wander.radius, 0.0, TAU, 64, LEASH_COLOR, 2.0)

## The map is near-white and the sprites are pale, so the label needs an outline
## to stay readable against either.
func _draw_label(at: Vector2, text: String) -> void:
	var font := ThemeDB.fallback_font
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
		TEXT_OUTLINE_SIZE, TEXT_OUTLINE_COLOR)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)

func _slot_label() -> String:
	var names: Array[String] = []
	for key in entity.component_slots():
		if key != &"debug":
			names.append(String(key))
	return "[%s]" % ", ".join(names)
