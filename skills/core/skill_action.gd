class_name SkillAction
extends Resource
## Base class for one reusable step of a skill.
##
## Configuration lives in exported properties, behaviour lives in execute().
## A skill is a list of these, so new skills should not need new classes.

## Runs this step. `context` carries caster, direction, spawn point and scratch data.
func execute(_context: SkillContext) -> void:
	push_warning("%s did not override execute()." % get_script().resource_path)
