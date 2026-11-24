class_name WorldSeedBar
extends Control

## L3's seed slip, drawn like the map key: the seed as text, a die that rolls a new one, and Generate. Sized
## for touch; Enter in the field generates too.

signal generate(seed_text: String)

const PAD := 10.0
const TALL := 52.0
const FIELD := 220.0
const DIE := 52.0
const BUTTON := 128.0
const STRIP := 10.0
const SYLLABLES: Array[String] = ["ka", "ma", "ra", "ja", "pa", "ta", "sa", "wi", "lu", "nu", "sri", "ba",
	"da", "ga", "ha", "la", "na", "ti", "ru", "ko", "se", "mu", "pu", "ya"]

var _field: LineEdit
var _rng := RandomNumberGenerator.new()

## The seed in the field.
var text: String:
	get:
		return _field.text
	set(value):
		_field.text = value

func _init() -> void:
	_rng.randomize()
	_field = LineEdit.new()
	_field.placeholder_text = "Seed"
	_field.position = Vector2(PAD, PAD + STRIP)
	_field.size = Vector2(FIELD, TALL)
	_field.text_submitted.connect(func(t: String) -> void:
		_field.release_focus()
		generate.emit(t))
	add_child(_field)
	custom_minimum_size = Vector2(PAD * 4.0 + FIELD + DIE + BUTTON, PAD * 2.0 + STRIP + TALL)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP

## Whether the field has the keyboard.
var editing: bool:
	get:
		return _field.has_focus()

func stop_editing() -> void:
	_field.release_focus()

## A new seed: a made-up name of two to four syllables.
func roll() -> String:
	var name := ""
	for k in _rng.randi_range(2, 4):
		name += SYLLABLES[_rng.randi() % SYLLABLES.size()]
	return name.capitalize()

func _die_rect() -> Rect2:
	return Rect2(Vector2(PAD * 2.0 + FIELD, PAD + STRIP), Vector2(DIE, TALL))

func _button_rect() -> Rect2:
	return Rect2(Vector2(PAD * 3.0 + FIELD + DIE, PAD + STRIP), Vector2(BUTTON, TALL))

func _gui_input(event: InputEvent) -> void:
	var at := Vector2(-1, -1)
	# Touch only: the project turns a click into a touch too, so the click itself would count twice.
	if event is InputEventScreenTouch and event.pressed:
		at = event.position
	if _die_rect().has_point(at):
		accept_event()
		_field.text = roll()
	elif _button_rect().has_point(at):
		accept_event()
		_field.release_focus()
		generate.emit(_field.text)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(rect.position + Vector2(4, 5), rect.size), Color(0, 0, 0, 0.3))
	draw_rect(rect, WorldMapKey.PAPER)
	draw_rect(rect.grow(-3.0), WorldMapKey.SEPIA, false, 2.0)
	var x0 := 6.0
	var k := 0
	while x0 + STRIP <= size.x - 6.0:
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 6.0), Vector2(x0 + STRIP, 6.0), Vector2(x0 + STRIP * 0.5, 6.0 + STRIP)]),
			WorldMapKey.INDIGO if k % 2 == 0 else WorldMapKey.OCHRE)
		x0 += STRIP
		k += 1
	_draw_die(_die_rect())
	var button := _button_rect()
	draw_rect(button, WorldMapKey.PAPER_DARK)
	draw_rect(button, WorldMapKey.SEPIA, false, 1.6)
	var font := get_theme_font(&"font", &"Label")
	var font_size := get_theme_font_size(&"font_size", &"Label") + 2
	var label := "Generate"
	var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, button.position + Vector2((button.size.x - wide) * 0.5, button.size.y * 0.5 + font_size * 0.35),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, WorldMapKey.SEPIA)

## A die showing five, on a darker slip.
func _draw_die(slot: Rect2) -> void:
	draw_rect(slot, WorldMapKey.PAPER_DARK)
	draw_rect(slot, WorldMapKey.SEPIA, false, 1.6)
	var face := Rect2(slot.get_center() - Vector2(15, 15), Vector2(30, 30))
	draw_rect(face, Color(0.96, 0.93, 0.85))
	draw_rect(face, WorldMapKey.SEPIA, false, 1.6)
	for pip: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]:
		draw_circle(face.get_center() + pip * 8.0, 2.6, WorldMapKey.OCHRE if pip == Vector2.ZERO else WorldMapKey.SEPIA)
