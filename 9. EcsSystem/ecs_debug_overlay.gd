class_name EcsDebugOverlay
extends Node2D

## Debug drawing on each entity: name, velocity arrow, line to destination,
## fullness/energy/health bars, a carried-count badge and a sleep icon.
## Draws only what EcsDebugSystem sends; never reads the world.

## Half the sprite's drawn height at the default scale.
const SPRITE_HALF := 64.0 * EcsConst.SPRITE_SCALE

const NAME_COLOR := Color(1.0, 0.98, 0.9, 0.95)
const GOAL_COLOR := Color(0.95, 0.85, 0.55, 0.9)
const BAG_COLOR := Color(0.65, 1.0, 0.55, 0.95)
const BADGE_INK := Color(0.09, 0.07, 0.05, 0.95)
const VELOCITY_COLOR := Color(0.35, 0.9, 1.0)
const DESTINATION_COLOR := Color(1.0, 0.45, 0.85)

## Bar colours, from the project palette.
const BAR_BACK := Color(0.165, 0.125, 0.086, 0.7)
const BAR_EDGE := Color(0.0, 0.0, 0.0, 0.5)
const HUNGER_COLOR := Color(0.725, 0.541, 0.196)
const ENERGY_COLOR := Color(0.369, 0.541, 0.18)
const HEALTH_COLOR := Color(0.62, 0.169, 0.145)
const DANGER_COLOR := Color(0.85, 0.4, 0.85)

## Sleep icon tint: parchment when asleep, red when collapsed.
const ASLEEP_COLOR := Color(0.906, 0.839, 0.675, 0.95)
const COLLAPSED_COLOR := Color(0.85, 0.25, 0.2, 0.95)

## The sleep icon. `_ready` makes a white copy so it can be tinted.
const SLEEP_ICON := preload("res://Global/Asset/Icon/sleep.png")
const SLEEP_ICON_SIZE := 64

## Snapshot rows from EcsDebugSystem. See that file for the keys.
var _rows: Array[Dictionary] = []
var _font: Font = ThemeDB.fallback_font
var _sleep_icon: Texture2D

func _ready() -> void:
	var image := SLEEP_ICON.get_image()
	image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(SLEEP_ICON_SIZE, SLEEP_ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	for y in SLEEP_ICON_SIZE:
		for x in SLEEP_ICON_SIZE:
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, image.get_pixel(x, y).a))
	_sleep_icon = ImageTexture.create_from_image(image)

## Takes this frame's rows and redraws.
func show_rows(rows: Array[Dictionary]) -> void:
	_rows = rows
	queue_redraw()

func clear() -> void:
	_rows = []
	queue_redraw()

func _draw() -> void:
	# Divide sizes by the zoom so text and bars stay the same size on screen.
	var zoom := get_viewport_transform().get_scale().x
	if zoom <= 0.0:
		zoom = 1.0
	var px := 1.0 / zoom

	# Offsets clear the sprite, plus a small screen-space gap.
	var above := -SPRITE_HALF - 10.0 * px
	var left := -110.0 * px
	var width := 220.0 * px

	# Bars under the sprite, above the text.
	var bar_width := 46.0 * px
	var bar_height := 5.0 * px
	var bar_left := -bar_width * 0.5
	var bar_top := SPRITE_HALF + 3.0 * px

	for row in _rows:
		var pos: Vector2 = row["pos"]

		# The planner's goal sits under the name, just above the sprite.
		var goal := String(row["goal"])
		var name_at := above - (12.0 * px if goal != "" else 0.0)
		_label(pos + Vector2(left, name_at), String(row["name"]), 13.0 * px, width, NAME_COLOR)
		if goal != "":
			_label(pos + Vector2(left, above), goal, 10.0 * px, width, GOAL_COLOR)

		# Draw only the bars the entity has.
		var stacked := bar_top
		var hunger: float = row["hunger"]
		if hunger >= 0.0:
			_bar(pos + Vector2(bar_left, stacked), hunger, bar_width, bar_height,
				HUNGER_COLOR, px)
			stacked += bar_height + 2.0 * px
		var energy: float = row["energy"]
		if energy >= 0.0:
			_bar(pos + Vector2(bar_left, stacked), energy, bar_width, bar_height,
				ENERGY_COLOR, px)
			stacked += bar_height + 2.0 * px
		var health: float = row["health"]
		if health >= 0.0:
			_bar(pos + Vector2(bar_left, stacked), health, bar_width, bar_height,
				HEALTH_COLOR, px)
			stacked += bar_height + 2.0 * px
		# Danger shows only while there is some.
		var danger: float = row["danger"]
		if danger > 0.0:
			_bar(pos + Vector2(bar_left, stacked), danger, bar_width, bar_height,
				DANGER_COLOR, px)

		# Carried-count badge on the sprite's top-left corner, only when carrying.
		var shoulder := SPRITE_HALF * float(row["sprite_scale"])
		var carried: int = row["carried"]
		if carried > 0:
			_badge(pos + Vector2(-shoulder, -shoulder), carried, px)

		# Sleep icon left of the badge, below the name.
		var sleep: int = row["sleep"]
		if sleep > 0 and _sleep_icon != null:
			# Sized in world units, so it zooms with the sprite.
			var icon := shoulder * 0.9
			var icon_at := pos + Vector2(-shoulder * 1.25 - icon, -shoulder * 1.3)
			draw_texture_rect(_sleep_icon, Rect2(icon_at, Vector2(icon, icon)), false,
				COLLAPSED_COLOR if sleep == 2 else ASLEEP_COLOR)

		if not row["has_movement"]:
			continue

		# Dashed line and ring at the destination.
		if row["has_destination"]:
			var dest: Vector2 = row["destination"]
			draw_dashed_line(pos, dest, DESTINATION_COLOR, 1.0 * px, 6.0 * px)
			draw_arc(dest, 9.0 * px, 0.0, TAU, 20, DESTINATION_COLOR, 1.5 * px)
			draw_line(dest + Vector2(-13.0 * px, 0.0), dest + Vector2(13.0 * px, 0.0),
				DESTINATION_COLOR, 1.0 * px)
			draw_line(dest + Vector2(0.0, -13.0 * px), dest + Vector2(0.0, 13.0 * px),
				DESTINATION_COLOR, 1.0 * px)

		# Velocity arrow.
		var velocity: Vector2 = row["velocity"]
		if velocity.length() > 0.01:
			var head := pos + velocity * 0.35
			draw_line(pos, head, VELOCITY_COLOR, 2.0 * px)
			var barb := -velocity.normalized() * 11.0 * px
			draw_line(head, head + barb.rotated(0.45), VELOCITY_COLOR, 2.0 * px)
			draw_line(head, head + barb.rotated(-0.45), VELOCITY_COLOR, 2.0 * px)

## One bar filled to `ratio`. Sizes are already zoom-scaled.
func _bar(at: Vector2, ratio: float, width: float, height: float,
		fill: Color, px: float) -> void:
	var box := Rect2(at, Vector2(width, height))
	draw_rect(box, BAR_BACK, true)
	if ratio > 0.0:
		draw_rect(Rect2(at, Vector2(width * ratio, height)), fill, true)
	draw_rect(box, BAR_EDGE, false, 1.0 * px)

## A small disc carrying a count, sat on the given corner of the sprite.
func _badge(at: Vector2, count: int, px: float) -> void:
	var radius := 9.0 * px
	draw_circle(at, radius, BAG_COLOR)
	draw_arc(at, radius, 0.0, TAU, 16, BADGE_INK, 1.0 * px)
	var size := 10.0 * px
	# Nudge down to centre the digit on the disc.
	_label(at + Vector2(-radius, size * 0.36), str(count), size, radius * 2.0, BADGE_INK)

## One line of centred text. Sizes arrive already scaled for the camera.
func _label(at: Vector2, text: String, size: float, width: float, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, roundi(size), color)
