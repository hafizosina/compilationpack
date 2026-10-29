class_name EcsLifecycleSingleton
extends EcsSingleton

## Spawn requests raised this tick, handled by EcsEntityManager at the next
## lifecycle stage. Deaths use EcsDyingFlag instead.

## Pending spawn requests.
var spawn_requests: Array[EcsSpawnRequest] = []

func key() -> StringName:
	return &"lifecycle"
