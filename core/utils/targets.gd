class_name Targets
extends RefCounted
## Target lookup shared by skill auto-aim and enemy AI, so "the nearest thing in
## group X" exists once instead of in every consumer.

## Nearest node of `group` to `from`; null when the group is empty.
static func nearest(from: Node2D, group: StringName) -> Node2D:
	if from == null or not from.is_inside_tree():
		return null
	var best: Node2D = null
	var best_distance := INF
	for node in from.get_tree().get_nodes_in_group(group):
		var candidate := node as Node2D
		if candidate == null or candidate == from:
			continue
		var distance := from.global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best

## Vector from `from` towards the nearest node of `group`; ZERO when there is none.
static func offset_to_nearest(from: Node2D, group: StringName) -> Vector2:
	var target := nearest(from, group)
	return Vector2.ZERO if target == null else target.global_position - from.global_position
