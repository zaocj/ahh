extends AbilityNodeBase
class_name AbilityNodeSpawnProjectile2D
## Behavior-tree action that fires a 2D projectile.
##
## The plugin ships AbilityNodeSpawnProjectile, but it is 3D only (Node3D,
## Transform3D, ProjectileBase). This is the 2D counterpart: it reads the aim
## direction the preview strategy put in the context and hands it to the scene.
##
## Config comes from ProjectileData2D so several skills can share one bullet.

@export var projectile_data: ProjectileData2D
## Shots per cast; more than one spreads them across `spread_degrees`.
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
## Blackboard/context key holding the aim direction (Vector2).
@export var direction_key: String = "target_direction"

func _tick(instance: GAS_BTInstance, _delta: float) -> int:
	var context := _get_context(instance)
	var instigator: Node = context.get("instigator")
	if not is_instance_valid(instigator):
		push_warning("AbilityNodeSpawnProjectile2D: instigator is missing.")
		return Status.FAILURE
	if not is_instance_valid(projectile_data) or not is_instance_valid(projectile_data.projectile_scene):
		push_warning("AbilityNodeSpawnProjectile2D: projectile_data/scene is not set.")
		return Status.FAILURE

	var direction := _resolve_direction(instance, context, instigator)
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT

	# Projectiles live next to the caster so they y-sort with the world.
	var parent: Node = instigator.get_parent()
	if parent == null:
		parent = instigator.get_tree().current_scene

	for shot_direction in _spread(direction):
		var projectile: Node = projectile_data.projectile_scene.instantiate()
		parent.add_child(projectile)
		if projectile is Node2D:
			(projectile as Node2D).global_position = _muzzle_position(instigator, shot_direction)
		if projectile.has_method("launch"):
			projectile.launch(shot_direction, projectile_data.speed, projectile_data.max_distance)
		else:
			push_warning("AbilityNodeSpawnProjectile2D: projectile has no launch().")
		if "payload_effects" in projectile:
			projectile.payload_effects = projectile_data.payload_effects.duplicate()
		if "instigator" in projectile:
			projectile.instigator = instigator

	context["projectiles_spawned"] = true
	return Status.SUCCESS

func _resolve_direction(instance: GAS_BTInstance, context: Dictionary, instigator: Node) -> Vector2:
	var aimed: Variant = context.get(direction_key)
	if aimed is Vector2 and (aimed as Vector2) != Vector2.ZERO:
		return (aimed as Vector2).normalized()
	# No aim provided: fall back to the caster's facing.
	if "facing" in instigator:
		var facing: Vector2 = instigator.facing
		if facing != Vector2.ZERO:
			return facing.normalized()
	return Vector2.RIGHT

## Spawn point keeps the shot out of the caster's own collision shape.
func _muzzle_position(instigator: Node2D, direction: Vector2) -> Vector2:
	return instigator.global_position + direction * MUZZLE_OFFSET

const MUZZLE_OFFSET: float = 22.0

func _spread(base: Vector2) -> Array[Vector2]:
	var directions: Array[Vector2] = []
	if projectile_count <= 1 or is_zero_approx(spread_degrees):
		directions.append(base)
		return directions
	var spread := deg_to_rad(spread_degrees)
	var step := spread / float(projectile_count - 1)
	var first := base.angle() - spread * 0.5
	for i in projectile_count:
		directions.append(Vector2.from_angle(first + step * float(i)))
	return directions
