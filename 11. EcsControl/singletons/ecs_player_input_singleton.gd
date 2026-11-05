class_name EcsPlayerInputSingleton
extends EcsSingleton

## This tick's player input. Written by main.gd only, before the pipeline runs; read and
## emptied by EcsPlayerControlSystem.

## Ability names the HUD sends.
const ATTACK := &"attack"
const SKILLS: Array[StringName] = [&"skill_1", &"skill_2", &"skill_3", &"skill_4"]

## The movement stick, length 0 to 1.
var move: Vector2 = Vector2.ZERO
## The aim stick while one is held, length 0 to 1.
var aim: Vector2 = Vector2.ZERO
## Sprint held.
var sprint: bool = false
## Sprint pressed this tick.
var sprint_pressed: bool = false
## Abilities let go of since the last tick: {ability: StringName, aim: Vector2, tapped: bool}.
var actions: Array[Dictionary] = []

func key() -> StringName:
	return &"player_input"
