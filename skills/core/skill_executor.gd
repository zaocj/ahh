class_name SkillExecutor
extends RefCounted
## Runs a SkillData's action list in order.
##
## Stateless and node-free on purpose: the same entry point can later run on a
## server for authoritative casts.

static func execute(skill: SkillData, context: SkillContext) -> void:
	if skill == null or context == null:
		push_warning("SkillExecutor.execute() needs both a skill and a context.")
		return
	context.skill = skill
	for action in skill.actions:
		if action == null:
			continue
		action.execute(context)
