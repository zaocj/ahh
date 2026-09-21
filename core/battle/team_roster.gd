class_name TeamRoster
extends Resource
## Who plays a 3v3 match.
##
## `blue[0]` is the seat the local player takes when no hero was picked on the
## character select screen (tests rely on that default), the rest are AI teammates.

## Every hero the character select screen offers, in display order.
@export var selectable: Array[HeroData] = []
@export var blue: Array[HeroData] = []
@export var red: Array[HeroData] = []

## Roster of a team, with the local player's pick substituted into the first slot.
func lineup_for(team: int, human_hero: HeroData) -> Array[HeroData]:
	var heroes := blue if team == Teams.Id.BLUE else red
	var lineup: Array[HeroData] = []
	for hero in heroes:
		if is_instance_valid(hero):
			lineup.append(hero)
	if team == Teams.Id.BLUE and is_instance_valid(human_hero):
		if lineup.is_empty():
			lineup.append(human_hero)
		else:
			lineup[0] = human_hero
	return lineup
