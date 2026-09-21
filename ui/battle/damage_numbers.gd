class_name DamageNumbers
extends Node
## Spawns floating damage text for combat events.
##
## One subscriber for the whole match: it turns `CombatEvents.damaged` into a
## world-space `DamageNumber` above the victim. Gameplay never calls this.

## Scene of the floating number itself (ui/battle/damage_number.tscn).
@export var number_scene: PackedScene
## Random sidestep range, so several hits in the same instant stay readable.
@export var jitter: Vector2 = Vector2(14.0, 6.0)
## Colour follows the victim's team (the single source of team colours), brightened
## so the number stays readable on the dark arena.
@export var team_tint: float = 0.28

var _jitter_rng := RandomNumberGenerator.new()

func _ready() -> void:
	_jitter_rng.randomize()
	CombatEvents.damaged.connect(_on_damaged)

func _on_damaged(victim: Node2D, amount: float, _source: Node) -> void:
	if number_scene == null or not is_instance_valid(victim):
		return
	var number := number_scene.instantiate() as DamageNumber
	if number == null:
		return
	add_child(number)
	# Health bars sit ~30px above the body (Player/Enemy BAR_OFFSET): start above them.
	number.global_position = victim.global_position + Vector2(0.0, -38.0)
	number.setup(amount, _color_for(victim),
		Vector2(
			_jitter_rng.randf_range(-jitter.x, jitter.x),
			_jitter_rng.randf_range(-jitter.y, jitter.y)))

## Damage dealt to a unit is tinted by *its* team, so a 3v3 reads at a glance.
func _color_for(victim: Node) -> Color:
	var team := Teams.team_of(victim)
	if team < 0:
		return Color(1.0, 0.92, 0.55)
	return Teams.color_of(team).lightened(team_tint)
