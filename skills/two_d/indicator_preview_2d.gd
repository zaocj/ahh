extends AbilityPreviewStrategy
class_name IndicatorPreview2D
## 2D aiming indicator for the ability system.
##
## The plugin's own preview strategies are 3D only (Node3D + Vector3 mouse), so a
## 2D game needs its own strategy - that is what this extension point is for. It
## reuses the project's SkillIndicator for drawing and the plugin's preview
## lifecycle (begin / update / confirm / cancel) for timing.
##
## Aim input comes from the game through `input_context["aim_direction"]`
## (Vector2); while the player has not dragged, the skill's default direction is
## used, which is what gives us auto-aim on a tap.

enum DefaultAim {
	FACING, ## Where the caster is already looking.
	TO_TARGET, ## Towards the nearest member of `target_group`.
	AWAY_FROM_TARGET, ## Away from it, e.g. a disengage dash.
}

@export_group("Visuals")
## Indicator look; the same generic resource the project always used.
@export var indicator_data: SkillIndicatorData

@export_group("Default Direction")
@export var default_aim: DefaultAim = DefaultAim.TO_TARGET
@export var target_group: StringName = &"enemies"
## Range the result context reports; keep it in sync with the skill's reach.
@export var max_range: float = 480.0

## NOTE: the plugin keeps preview state on the definition resource, so one
## strategy instance is shared by every caster of this ability. Fine while a
## single entity previews at a time (the player); revisit for AI casting.
var _caster: Node2D = null
var _indicator: SkillIndicator = null
var _direction: Vector2 = Vector2.RIGHT
var _active: bool = false
var _cancelled: bool = false

func begin(caster: Node, _ability_instance: GameplayAbilityInstance, _extra_context: Dictionary = {}) -> void:
	_caster = caster as Node2D
	_active = _caster != null
	_cancelled = false
	_direction = _default_direction()
	_indicator = _create_indicator(_caster)
	_refresh_indicator()

func update(_delta: float, input_context: Dictionary = {}) -> void:
	if not _active:
		return
	var aimed: Variant = input_context.get("aim_direction", Vector2.ZERO)
	if aimed is Vector2 and (aimed as Vector2) != Vector2.ZERO:
		_direction = (aimed as Vector2).normalized()
	_refresh_indicator()

func is_targeting() -> bool:
	return _active

func is_finished() -> bool:
	return _active

func is_cancelled() -> bool:
	return _cancelled

func cancel() -> void:
	_active = false
	_cancelled = true
	if is_instance_valid(_indicator):
		_indicator.queue_free()
	_indicator = null

## Handed to the ability as its activation context; the behavior tree reads
## target_direction.
##
## `targets` is always present (empty) because AbilityNodeBase._get_target_list
## assigns context[target_key] into a typed Array[Node]: a missing key (null)
## aborts that tick. Aiming does not pick targets, the tree's target search does.
func get_result_context() -> Dictionary:
	var targets: Array[Node] = []
	return {
		"target_direction": _direction,
		"target_position": (_caster.global_position + _direction * max_range) if is_instance_valid(_caster) else Vector2.ZERO,
		"target_type": "direction",
		"targets": targets,
	}

func _create_indicator(caster: Node2D) -> SkillIndicator:
	if caster == null or not caster.is_inside_tree():
		return null
	var indicator := SkillIndicator.new()
	# Lives in world space (top_level), so add it next to the arena, not to the caster.
	caster.get_tree().current_scene.add_child(indicator)
	return indicator

func _refresh_indicator() -> void:
	if _indicator == null or not is_instance_valid(_indicator) or _caster == null:
		return
	# Circles are area previews: they sit where the effect will land (clamped to
	# max_range) and their radius is the area. Arrows/targets are directional:
	# they grow out of the caster.
	if indicator_data != null and indicator_data.shape == SkillIndicatorData.Shape.CIRCLE:
		_indicator.rotation = 0.0
		_indicator.global_position = _caster.global_position + _direction * max_range
	else:
		_indicator.global_position = _caster.global_position
		_indicator.set_direction(_direction)
	_indicator.show_indicator(indicator_data)

func _default_direction() -> Vector2:
	if default_aim == DefaultAim.FACING or _caster == null:
		return _caster_facing()
	var offset := Targets.offset_to_nearest(_caster, target_group)
	if offset == Vector2.ZERO:
		return _caster_facing()
	var towards := offset.normalized()
	return towards if default_aim == DefaultAim.TO_TARGET else -towards

func _caster_facing() -> Vector2:
	if _caster != null and "facing" in _caster:
		var facing: Vector2 = _caster.facing
		if facing != Vector2.ZERO:
			return facing.normalized()
	return Vector2.RIGHT
