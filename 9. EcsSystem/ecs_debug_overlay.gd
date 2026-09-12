class_name EcsDebugOverlay
extends Node2D

## World-space debug gizmos, drawn on the entities themselves: the name, the
## position, the velocity vector with its heading, and a dashed line to the spot
## the low brain picked.
##
## Dumb on purpose. It holds rows and draws them — it never queries the world,
## never reads a component and never decides anything. EcsDebugSystem hands it
## a fresh snapshot each frame, exactly as EcsRenderSystem hands the Sprite2Ds
## their values. The overlay is a view, like the sprites are.

## Half the drawn height of the ~128px art at EcsConst.SPRITE_SCALE — how far a
## label must sit from an entity's centre to clear its sprite.
const SPRITE_HALF := 64.0 * EcsConst.SPRITE_SCALE

const BODY_COLOR := Color(0.45, 1.0, 0.6, 0.6)
const NAME_COLOR := Color(1.0, 0.98, 0.9, 0.95)
const POSITION_COLOR := Color(0.74, 0.78, 0.82, 0.9)
const VELOCITY_COLOR := Color(0.35, 0.9, 1.0)
const DESTINATION_COLOR := Color(1.0, 0.45, 0.85)
const PAUSED_COLOR := Color(1.0, 0.85, 0.35, 0.9)

## Snapshot rows from EcsDebugSystem. See that file for the keys.
var _rows: Array[Dictionary] = []
var _font: Font = ThemeDB.fallback_font

## Takes this frame's snapshot and asks for a redraw. The only entry point.
func show_rows(rows: Array[Dictionary]) -> void:
	_rows = rows
	queue_redraw()

func clear() -> void:
	_rows = []
	queue_redraw()

func _draw() -> void:
	# Text and gizmo furniture are sized in world units, so zooming out would
	# shrink them away. Dividing by the camera's scale keeps them a constant
	# size on screen at any zoom. The velocity arrow's *length* is deliberately
	# left alone: it is the velocity, and shrinking with the view is honest.
	var zoom := get_viewport_transform().get_scale().x
	if zoom <= 0.0:
		zoom = 1.0
	var px := 1.0 / zoom

	# Vertical offsets clear the sprite (a world-space distance) and then add a
	# small screen-space gap, so a label neither overlaps the art when zoomed in
	# nor floats away from it when zoomed out.
	var above := -SPRITE_HALF - 10.0 * px
	var first := SPRITE_HALF + 14.0 * px
	var second := first + 13.0 * px
	var left := -110.0 * px
	var width := 220.0 * px

	for row in _rows:
		var pos: Vector2 = row["pos"]

		# The body, at its true size. Only the line *width* is zoom-compensated:
		# the radius is the entity's actual extent, not a label about it, so it
		# has to scale with the view like the sprite does.
		var radius: float = row["radius"]
		if radius > 0.0:
			draw_arc(pos, radius, 0.0, TAU, 32, BODY_COLOR, 1.5 * px)

		_label(pos + Vector2(left, above), String(row["name"]), 13.0 * px, width, NAME_COLOR)
		_label(pos + Vector2(left, first), "(%d, %d)" % [roundi(pos.x), roundi(pos.y)],
			10.0 * px, width, POSITION_COLOR)

		if not row["has_movement"]:
			_label(pos + Vector2(left, second), "no movement component",
				10.0 * px, width, PAUSED_COLOR)
			continue

		# Where it is heading: dashed line to the destination, ring on the spot.
		if row["has_destination"]:
			var dest: Vector2 = row["destination"]
			draw_dashed_line(pos, dest, DESTINATION_COLOR, 1.0 * px, 6.0 * px)
			draw_arc(dest, 9.0 * px, 0.0, TAU, 20, DESTINATION_COLOR, 1.5 * px)
			draw_line(dest + Vector2(-13.0 * px, 0.0), dest + Vector2(13.0 * px, 0.0),
				DESTINATION_COLOR, 1.0 * px)
			draw_line(dest + Vector2(0.0, -13.0 * px), dest + Vector2(0.0, 13.0 * px),
				DESTINATION_COLOR, 1.0 * px)

		# Which way it is actually moving. The arrow is the vector; the text
		# under the entity is the same thing in numbers.
		var velocity: Vector2 = row["velocity"]
		if velocity.length() > 0.01:
			var head := pos + velocity * 0.35
			draw_line(pos, head, VELOCITY_COLOR, 2.0 * px)
			var barb := -velocity.normalized() * 11.0 * px
			draw_line(head, head + barb.rotated(0.45), VELOCITY_COLOR, 2.0 * px)
			draw_line(head, head + barb.rotated(-0.45), VELOCITY_COLOR, 2.0 * px)
			_label(pos + Vector2(left, second),
				"v(%d, %d)  %d°" % [roundi(velocity.x), roundi(velocity.y), int(row["heading"])],
				10.0 * px, width, VELOCITY_COLOR)
		else:
			_label(pos + Vector2(left, second), "pausing %.1fs" % row["pause_left"],
				10.0 * px, width, PAUSED_COLOR)

## One line of centred text. Sizes arrive already scaled for the camera.
func _label(at: Vector2, text: String, size: float, width: float, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, roundi(size), color)
