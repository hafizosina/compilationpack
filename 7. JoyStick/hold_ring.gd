class_name HoldRing
extends Control

## Radial "charge" ring drawn over a button to show a hold-to-activate progress.
## Set progress 0..1 (usually via a Tween); it sweeps clockwise from the top.

@export_range(0.0, 1.0) var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()

## Ring color (defaults to the theme's gold accent).
@export var color: Color = Color(0.831, 0.702, 0.392)
## Thickness of the ring stroke, in pixels.
@export var width: float = 6.0

func _draw() -> void:
	if progress <= 0.0:
		return
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - width * 0.5
	var start := -PI * 0.5  # 12 o'clock
	draw_arc(center, radius, start, start + TAU * progress, 48, color, width, true)
