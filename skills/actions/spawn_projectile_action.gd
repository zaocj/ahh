class_name SpawnProjectileAction
extends SkillAction
## Spawns projectile scenes and hands them their launch parameters.
##
## The projectile entity owns movement, collision and lifetime; this action only
## decides that (and in which direction) one should exist.

@export var projectile_scene: PackedScene
@export var speed: float = 520.0
## Self-destruct distance; keep it in sync with the skill's indicator length.
@export var max_distance: float = 480.0
## Shots per cast; more than one spreads them across `spread_degrees`.
@export var count: int = 1
@export var spread_degrees: float = 0.0

func execute(context: SkillContext) -> void:
	if projectile_scene == null:
		push_warning("SpawnProjectileAction has no projectile_scene.")
		return
	var parent := context.spawn_parent()
	if parent == null:
		push_warning("SpawnProjectileAction has nowhere to spawn into.")
		return
	var spawned: Array[Node] = []
	for direction in _directions(context.direction):
		var projectile := projectile_scene.instantiate()
		parent.add_child(projectile)
		if projectile is Node2D:
			(projectile as Node2D).global_position = context.origin
		if projectile.has_method("launch"):
			projectile.launch(direction, speed, max_distance, context.caster)
		else:
			push_warning("SpawnProjectileAction: projectile lacks launch().")
		spawned.append(projectile)
	context.data["projectiles"] = spawned

## Evenly spreads `count` shots around the aim direction.
func _directions(base: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if base == Vector2.ZERO:
		base = Vector2.RIGHT
	if count <= 1 or is_zero_approx(spread_degrees):
		result.append(base.normalized())
		return result
	var spread := deg_to_rad(spread_degrees)
	var step := spread / float(count - 1)
	var first := base.angle() - spread * 0.5
	for i in count:
		result.append(Vector2.from_angle(first + step * float(i)))
	return result
