class_name EcsSingleton
extends EcsComponent

## Base for world singletons: data that belongs to the world, not to any
## entity — an inbox a system writes a note into and a later stage drains.
##
## Neither a component (it is not part of what any entity is) nor a flag (it is
## not true of any entity). It still extends EcsComponent so
## `EcsWorld.add_singleton()` / `get_singleton()` store and find it unchanged;
## the base class exists so the kind is visible at the declaration.
