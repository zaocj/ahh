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
## Hits on the player read differently from hits the player deals.
@export var player_color: Color = Color(1.0, 0.42, 0.42)
@export var enemy_color: Color = Color(1.0, 0.9, 0.5)
## Group that counts as "the player" for colouring.
@export var player_group: StringName = &"players"

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
	number.setup(amount, player_color if victim.is_in_group(player_group) else enemy_color,
		Vector2(
			_jitter_rng.randf_range(-jitter.x, jitter.x),
			_jitter_rng.randf_range(-jitter.y, jitter.y)))
