class_name EcsRandomSingleton
extends EcsSingleton

## The world's one random number generator. Every system rolls on it, and a save
## keeps its state, so the same seed and inputs play out the same.

var rng := RandomNumberGenerator.new()

func key() -> StringName:
	return &"random"

## `world`'s generator; an unseeded shared one if the world has none.
static func of(world: EcsWorld) -> RandomNumberGenerator:
	var random := world.get_singleton(EcsRandomSingleton) as EcsRandomSingleton
	if random != null:
		return random.rng
	if _fallback == null:
		_fallback = RandomNumberGenerator.new()
	return _fallback

static var _fallback: RandomNumberGenerator
