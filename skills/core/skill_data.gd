class_name SkillData
extends Resource
## Static configuration of one skill: cooldown, action list, aiming indicator.
##
## What a skill does is the composition of its actions - there is no script per
## skill. Add behaviour by adding/parameterising actions instead.

@export var skill_id: StringName = &""
@export var display_name: String = ""
@export var cooldown: float = 1.0
## Aiming indicator; null means "this skill shows no indicator while holding".
@export var indicator: SkillIndicatorData
## Placeholder colour for the HUD button until real icons exist.
@export var icon_color: Color = Color(0.24, 0.78, 0.94)
## Steps executed in order by SkillExecutor.
@export var actions: Array[SkillAction] = []
