extends GameplayEffect
class_name GE_Dash2D
## Moves the target along the cast direction, as a plugin effect.
##
## The plugin ships GE_SingleFrameMotion, but it drives a CharacterBody3D. This is
## the 2D counterpart: the caster keeps owning its own movement (collision,
## velocity), the effect only asks for the dash.

enum DirectionMode {
	CONTEXT_DIRECTION, ## The aim direction the preview strategy resolved.
	FORWARD, ## The target's current facing.
}

@export var distance: float = 168.0
@export var duration: float = 0.16
@export var direction_mode: DirectionMode = DirectionMode.CONTEXT_DIRECTION

func _apply(target: Node, instigator: Node, context: Dictionary) -> void:
	var body: Node = target if target is Node2D else instigator
	if not is_instance_valid(body) or not body.has_method("dash"):
		push_warning("GE_Dash2D needs a Node2D target with dash(direction, distance, duration).")
		return

	var direction := _resolve_direction(body, context)
	if direction == Vector2.ZERO:
		return
	body.call("dash", direction, distance, duration)

func _resolve_direction(body: Node, context: Dictionary) -> Vector2:
	if direction_mode == DirectionMode.CONTEXT_DIRECTION:
		var aimed: Variant = context.get("target_direction")
		if aimed is Vector2 and (aimed as Vector2) != Vector2.ZERO:
			return (aimed as Vector2).normalized()
	if "facing" in body:
		var facing: Vector2 = body.facing
		if facing != Vector2.ZERO:
			return facing.normalized()
	return Vector2.ZERO
