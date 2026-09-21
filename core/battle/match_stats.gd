class_name MatchStats
extends Node
## Per-unit match record: kills and damage dealt, fed by `CombatEvents`.
##
## It subscribes to the same bus the feedback layer uses, so gameplay code knows
## nothing about scoreboards, and the end screen only reads rows. Rows are keyed by
## instance id, so they survive a unit leaving the scene (a dead unit is kept in the
## world for the score, but the record does not depend on that).

signal changed

## Row keys: name, team, hero_color, kills, damage, alive.
var _rows: Dictionary = {}

func _ready() -> void:
	CombatEvents.damaged.connect(_on_damaged)
	CombatEvents.died.connect(_on_died)

## Registers a unit before the match starts, so it shows up even with 0 damage.
## `is_human` marks the local player's row ("(you)" on the scoreboard).
func register(unit: Node, hero: HeroData, team: int, is_human: bool = false) -> void:
	var row := _row_for(unit)
	if hero != null:
		row["name"] = hero.display_name
		row["hero_color"] = hero.color
	row["team"] = team
	row["alive"] = true
	row["human"] = is_human

func reset() -> void:
	_rows.clear()
	changed.emit()

## Scoreboard rows, best (damage, then kills) first.
func rows() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key in _rows:
		list.append(_rows[key])
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["damage"]) != int(b["damage"]):
			return int(a["damage"]) > int(b["damage"])
		return int(a["kills"]) > int(b["kills"]))
	return list

func kills_of(unit: Node) -> int:
	return int(_row_for(unit)["kills"])

func damage_of(unit: Node) -> int:
	return int(_row_for(unit)["damage"])

func _row_for(unit: Node) -> Dictionary:
	var key := _key_of(unit)
	if not _rows.has(key):
		_rows[key] = {
			"name": unit.name if is_instance_valid(unit) else "?",
			"team": Teams.team_of(unit),
			"hero_color": Color.WHITE,
			"kills": 0,
			"damage": 0,
			"alive": true,
			"human": false,
		}
	return _rows[key]

func _key_of(unit: Node) -> int:
	return unit.get_instance_id() if is_instance_valid(unit) else 0

func _on_damaged(victim: Node2D, amount: float, source: Node) -> void:
	# Only damage between opposing teams counts for the scoreboard.
	if is_instance_valid(source) and Teams.can_damage(source, victim):
		var row := _row_for(source)
		row["damage"] = int(row["damage"]) + roundi(amount)
	_changed()

func _on_died(entity: Node2D, source: Node) -> void:
	_row_for(entity)["alive"] = false
	if is_instance_valid(source) and Teams.can_damage(source, entity):
		var row := _row_for(source)
		row["kills"] = int(row["kills"]) + 1
	_changed()

func _changed() -> void:
	changed.emit()
