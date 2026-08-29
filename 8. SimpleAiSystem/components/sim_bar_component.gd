class_name SimBarComponent
extends SimComponent

## Base for the 0–100 need bars: Health, Hunger, Fatigue. Each is a dumb state
## holder that drains over time and reports itself; what the numbers *mean* is
## the brain's business.
##
## Bars report to the inspector's MAIN tab via describe_summary() rather than
## claiming a tab each — three tabs holding one number apiece would bury the
## things that need a tab.

## Emitted on every change, carrying the new value.
signal changed(value: float)
## Emitted the moment the bar reaches zero.
signal emptied()

var max_value: float = 100.0
var value: float = 100.0
## Units lost per second with the entity standing still.
var drain_per_second: float = 0.0

## PROTOTYPE ONLY — REMOVE BEFORE INTEGRATING WITH OTHER SYSTEMS (same reasoning
## as the inventory carry badge: a component holding state should not render it).
## Row under the sprite to draw this bar in; -1 draws nothing.
var bar_row: int = -1
var bar_colour: Color = Color.WHITE

const BAR_WIDTH := 34.0
const BAR_HEIGHT := 4.0
const BAR_TOP := 22.0
const BAR_SPACING := 6.0
const BAR_BACKING := Color(0.09, 0.08, 0.1, 0.75)

var _emptied_sent := false

func _ready() -> void:
	super()
	z_index = 50

## Key this bar appears under in the inspector. Defaults to the slot name.
func bar_label() -> String:
	return String(slot())

func _process(delta: float) -> void:
	var rate := drain_per_second + extra_drain()
	if rate != 0.0:
		spend(rate * delta)

## Extra drain beyond the idle rate — Fatigue overrides this to charge for
## movement. Returns units per second.
func extra_drain() -> float:
	return 0.0

func fraction() -> float:
	return 0.0 if max_value <= 0.0 else clampf(value / max_value, 0.0, 1.0)

func is_empty() -> bool:
	return value <= 0.0

## Reduces the bar, clamped at zero. Emits `emptied` once on the way down.
func spend(amount: float) -> void:
	_set_value(value - amount)

## Refills the bar, clamped at max.
func restore(amount: float) -> void:
	_set_value(value + amount)

func _set_value(next: float) -> void:
	var clamped := clampf(next, 0.0, max_value)
	if is_equal_approx(clamped, value):
		return
	value = clamped
	changed.emit(value)
	queue_redraw()
	if value <= 0.0 and not _emptied_sent:
		_emptied_sent = true
		emptied.emit()
	elif value > 0.0:
		_emptied_sent = false

func describe_summary() -> Dictionary:
	return {bar_label(): "%d / %d" % [roundi(value), roundi(max_value)]}

## PROTOTYPE ONLY. A small bar under the sprite, in world space so it scales with
## the entity and stays put relative to it.
func _draw() -> void:
	if bar_row < 0:
		return
	var top := BAR_TOP + bar_row * BAR_SPACING
	var origin := Vector2(-BAR_WIDTH * 0.5, top)
	draw_rect(Rect2(origin - Vector2(1.0, 1.0),
		Vector2(BAR_WIDTH + 2.0, BAR_HEIGHT + 2.0)), BAR_BACKING)
	draw_rect(Rect2(origin, Vector2(BAR_WIDTH * fraction(), BAR_HEIGHT)), bar_colour)
