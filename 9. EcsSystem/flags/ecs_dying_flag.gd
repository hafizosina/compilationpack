class_name EcsDyingFlag
extends EcsFlag

## Destroy at the next lifecycle stage. Until then, executors that eat or take
## refuse anything carrying it, so one item can't be claimed twice in a tick.
## Its cause and detail pick what EcsRemainsSystem leaves behind.

const HEALTH := &"health"
const EATEN := &"eaten"
const TAKEN := &"taken"
const ROTTED := &"rotted"
const REMOVED := &"removed"

## What ended it: one of the constants above, or empty.
var cause: StringName = &""
## For a death by health, what took the last of it: &"hit", &"starved", &"parched",
## &"bled", &"poisoned", &"collapsed"; empty otherwise.
var detail: StringName = &""
