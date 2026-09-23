class_name EcsDebugOverlay
extends Node2D

## World-space debug gizmos, drawn on the entities themselves: the name, a
## velocity arrow, a dashed line to the spot the brain picked, hunger and health
## as bars, and a badge on the sprite's shoulder when it is carrying something.
##
## Shapes rather than numbers, because these are readings you scan a crowd for
## rather than ones you read. A dozen creatures' worth of "hunger 43%" and
## "v(62, -34) 151°" is a wall of text parsed one entity at a time; a dozen
## part-filled bars is a picture taken in at a glance, which is the whole job of
## an overlay. Where a number is genuinely wanted — the exact velocity, the
## exact hunger — the inspector has it for the one entity you click, and a
## vector is better read as the arrow anyway.
##
## It does NOT draw bodies. EcsBodyComponent's radius reaches the screen as a
## real CollisionShape2D under World/Bodies now, so Godot's own Debug > Visible
## Collision Shapes draws it, and a second hand-rolled circle would only be a
## copy that can disagree with the shape the physics server is actually using.
##
## Dumb on purpose. It holds rows and draws them — it never queries the world,
## never reads a component and never decides anything. EcsDebugSystem hands it
## a fresh snapshot each frame, exactly as EcsNodeSyncSystem hands the Sprite2Ds
## their values. The overlay is a view, like the sprites are.

## Half the drawn height of the ~128px art at EcsConst.SPRITE_SCALE — how far a
## label must sit from an entity's centre to clear its sprite.
const SPRITE_HALF := 64.0 * EcsConst.SPRITE_SCALE

const NAME_COLOR := Color(1.0, 0.98, 0.9, 0.95)
const BAG_COLOR := Color(0.65, 1.0, 0.55, 0.95)
const BADGE_INK := Color(0.09, 0.07, 0.05, 0.95)
const VELOCITY_COLOR := Color(0.35, 0.9, 1.0)
const DESTINATION_COLOR := Color(1.0, 0.45, 0.85)

## Bar colours, taken from the project palette so the overlay reads as part of
## the same game: health is the palette's blood red, hunger its brass. Hunger
## *fills* as it climbs, so a full bar is the warning, which is the opposite
## direction to health and deliberately so — both bars are full of bad news at
## opposite ends, and the colour is what tells them apart at a glance.
const BAR_BACK := Color(0.165, 0.125, 0.086, 0.7)
const BAR_EDGE := Color(0.0, 0.0, 0.0, 0.5)
const HUNGER_COLOR := Color(0.725, 0.541, 0.196)
const HEALTH_COLOR := Color(0.62, 0.169, 0.145)

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
	var left := -110.0 * px
	var width := 220.0 * px

	# Bars sit directly under the sprite, above the text, centred on the entity.
	var bar_width := 46.0 * px
	var bar_height := 5.0 * px
	var bar_left := -bar_width * 0.5
	var bar_top := SPRITE_HALF + 3.0 * px

	for row in _rows:
		var pos: Vector2 = row["pos"]

		_label(pos + Vector2(left, above), String(row["name"]), 13.0 * px, width, NAME_COLOR)

		# Only what the entity actually has. A berry carries neither bar and a
		# bush carries no bag, and each simply draws nothing — the absence is
		# the statement, the same way the missing velocity line below is.
		var stacked := bar_top
		var hunger: float = row["hunger"]
		if hunger >= 0.0:
			_bar(pos + Vector2(bar_left, stacked), hunger, bar_width, bar_height,
				HUNGER_COLOR, px)
			stacked += bar_height + 2.0 * px
		var health: float = row["health"]
		if health >= 0.0:
			_bar(pos + Vector2(bar_left, stacked), health, bar_width, bar_height,
				HEALTH_COLOR, px)

		# A badge on the sprite's top-left shoulder, and only when there is
		# something in the bag: an empty one is the common case and a "0" on
		# every creature is noise. Nothing shown therefore means either empty
		# hands or no inventory at all, which for scanning a crowd is the same
		# fact — neither one is carrying anything.
		var carried: int = row["carried"]
		if carried > 0:
			_badge(pos + Vector2(-SPRITE_HALF, -SPRITE_HALF), carried, px)

		if not row["has_movement"]:
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

		# Which way it is actually moving. The arrow *is* the vector — its
		# direction is the heading and its length is the speed — so the numbers
		# that used to sit under it said nothing the picture did not.
		var velocity: Vector2 = row["velocity"]
		if velocity.length() > 0.01:
			var head := pos + velocity * 0.35
			draw_line(pos, head, VELOCITY_COLOR, 2.0 * px)
			var barb := -velocity.normalized() * 11.0 * px
			draw_line(head, head + barb.rotated(0.45), VELOCITY_COLOR, 2.0 * px)
			draw_line(head, head + barb.rotated(-0.45), VELOCITY_COLOR, 2.0 * px)

## One bar: a dark trough, a fill proportional to `ratio`, and an outline to
## keep it legible over pale ground. Sizes arrive already scaled for the camera.
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
	# draw_string puts the baseline on `at`, so nudge down by roughly a third of
	# the glyph height to sit the digit in the middle of the disc.
	_label(at + Vector2(-radius, size * 0.36), str(count), size, radius * 2.0, BADGE_INK)

## One line of centred text. Sizes arrive already scaled for the camera.
func _label(at: Vector2, text: String, size: float, width: float, color: Color) -> void:
	draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_CENTER, width, roundi(size), color)
