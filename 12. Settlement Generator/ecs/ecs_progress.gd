class_name EcsProgress
extends RefCounted

## What a worker is doing and how far along it is, written by the worker and read by the viewer
## each frame; a mutex keeps the two apart. A job is split into spans: `within` maps the reports
## that follow onto a share of the whole.

var _mutex := Mutex.new()
var _stage: String = ""
var _done: float = 0.0
var _from: float = 0.0
var _to: float = 1.0

## Later reports fill `from`–`to` of the whole job.
func within(from: float, to: float) -> void:
	_mutex.lock()
	_from = from
	_to = to
	_mutex.unlock()

## The stage running now, and how far through its span, 0–1.
func report(stage: String, part: float = 0.0) -> void:
	_mutex.lock()
	_stage = stage
	_done = lerpf(_from, _to, clampf(part, 0.0, 1.0))
	_mutex.unlock()

## [stage, done 0–1].
func read() -> Array:
	_mutex.lock()
	var out := [_stage, _done]
	_mutex.unlock()
	return out

## Reports on `progress` when there is one: the stages' callers needn't check.
static func say(progress: EcsProgress, stage: String, part: float = 0.0) -> void:
	if progress != null:
		progress.report(stage, part)
