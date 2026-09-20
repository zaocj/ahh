extends AbilityNodeBase
class_name AbilityNodeSpawnMagicField2D
## Behavior-tree action that drops a 2D magic field at the aimed position.
##
## The plugin's AbilityNodeSpawnMagicField is 3D (MagicFieldBase/Area3D); this is
## the 2D counterpart. Aim comes from the preview strategy's context
## (`target_position`), which the indicator clamps to the skill's range.

@export var field_data: MagicFieldData2D

func _tick(instance: GAS_BTInstance, _delta: float) -> int:
	if not is_instance_valid(field_data) or not is_instance_valid(field_data.field_scene):
		push_warning("AbilityNodeSpawnMagicField2D: field_data/scene is not set.")
		return Status.FAILURE

	var context := _get_context(instance)
	var instigator: Node = context.get("instigator")
	if not is_instance_valid(instigator):
		push_warning("AbilityNodeSpawnMagicField2D: instigator is missing.")
		return Status.FAILURE

	var parent: Node = instigator.get_parent()
	if parent == null:
		parent = instigator.get_tree().current_scene

	var field: Node = field_data.field_scene.instantiate()
	parent.add_child(field)
	if field.has_method("start"):
		field.start(field_data, instigator, _target_position(context, instigator))
	else:
		push_warning("AbilityNodeSpawnMagicField2D: field scene has no start().")
	context["fields_spawned"] = true
	return Status.SUCCESS

func _target_position(context: Dictionary, instigator: Node) -> Vector2:
	var aimed: Variant = context.get("target_position")
	if aimed is Vector2:
		return aimed as Vector2
	if instigator is Node2D and "facing" in instigator:
		return (instigator as Node2D).global_position + (instigator.facing as Vector2) * 120.0
	return (instigator as Node2D).global_position if instigator is Node2D else Vector2.ZERO
