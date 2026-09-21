class_name HeroData
extends Resource
## One playable character: everything that differs between the 3v3 participants.
##
## A hero is *data*, not a scene or a script: the same `entities/base/unit.tscn` is
## instantiated for every seat of the match, and this resource supplies the look, the
## stats and the skill loadout. That is what turns "5 different skills" into
## "5 characters" without five copies of the entity.

@export var hero_id: StringName = &""
@export var display_name: String = "Hero"
@export_multiline var description: String = ""
## Body / health-bar / scoreboard colour (the team tint is applied on top).
@export var color: Color = Color(0.6, 0.8, 1.0)
## Signature skill shown on the character select screen.
@export var skill_name: String = ""

@export_group("Gameplay")
## Abilities this hero learns: slot 0 is the signature skill, slot 1 the shared dash.
@export var loadout: AbilityLoadout2D
## Attributes + vitals handed to the plugin's vital component.
@export var stats: StatBlock2D

## Slot 0 of the loadout, i.e. the skill that defines the hero.
func signature() -> GameplayAbilityDefinition:
	if loadout == null or loadout.abilities.is_empty():
		return null
	return loadout.abilities[0]
