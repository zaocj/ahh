class_name SkillContext
extends RefCounted
## One skill cast's worth of context.
##
## Actions only see the world through this object, so the same action can be
## reused by any caster (hero, minion, turret) without referencing it directly.

## Who cast the skill; skill actions reach the caster through this.
var caster: Node2D
## The skill being executed.
var skill: SkillData
## World-space point the skill starts from.
var origin: Vector2 = Vector2.ZERO
## Normalized cast direction.
var direction: Vector2 = Vector2.RIGHT
## Node that newly spawned entities are parented to (the arena / world root).
var world: Node
## Scratch space so actions can pass values down the chain (spawned entities,
## resolved targets, chosen damage, ...).
var data: Dictionary = {}

## Convenience for actions that need a parent for spawned entities.
func spawn_parent() -> Node:
	return world if world != null else caster
