class_name Teams
extends RefCounted
## The two sides of a 3v3 match, and the single place that decides who may hit whom.
##
## Teams used to be implied twice over: by the `players` / `enemies` groups and by
## hand-filled `target_group` fields on every projectile/field data file. That meant
## a new skill could silently friendly-fire, and an AI teammate could not exist
## without duplicating a scene. Now an entity knows its `team` and asks here.

enum Id { BLUE, RED }

## Group every unit of a team joins: AI target search and survivor counting use it.
static func group_of(team: int) -> StringName:
	return &"team_blue" if team == Id.BLUE else &"team_red"

## Group of the team `team` is allowed to attack.
static func enemy_group_of(team: int) -> StringName:
	return group_of(Id.RED if team == Id.BLUE else Id.BLUE)

static func is_hostile(a: int, b: int) -> bool:
	if a == b:
		return false
	return _is_known(a) and _is_known(b)

## Base colour of a team's bodies, health bars and scoreboard chips.
static func color_of(team: int) -> Color:
	return Color(0.3, 0.74, 1.0) if team == Id.BLUE else Color(0.95, 0.36, 0.36)

static func display_name(team: int) -> String:
	return "Blue" if team == Id.BLUE else "Red"

## `team` of a node, or -1 when it has none (scenery, an effect without an owner).
static func team_of(node: Node) -> int:
	if node == null or not is_instance_valid(node):
		return -1
	var value: Variant = node.get("team")
	return int(value) if value is int else -1

## True when `source` may damage `target`. This is the whole friendly-fire rule:
## projectile payloads, ground fields and anything else that damages an entity asks
## it instead of filtering by hand. Nodes without a team keep the old behaviour
## (anything damageable), so scenery and teamless effects still work.
static func can_damage(source: Node, target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	var mine := team_of(source)
	var theirs := team_of(target)
	if mine < 0 or theirs < 0:
		return true
	return is_hostile(mine, theirs)

static func _is_known(team: int) -> bool:
	return team == Id.BLUE or team == Id.RED
