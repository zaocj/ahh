class_name DashAction
extends SkillAction
## Moves the caster a fixed distance along the cast direction.
##
## The caster performs the movement because only it knows about collision and
## velocity, so any entity exposing dash(direction, distance, duration) can use
## this action.

@export var distance: float = 168.0
@export var duration: float = 0.16

func execute(context: SkillContext) -> void:
	var caster := context.caster
	if caster == null or not caster.has_method("dash"):
		push_warning("DashAction needs a caster with dash(direction, distance, duration).")
		return
	caster.dash(context.direction, distance, duration)
