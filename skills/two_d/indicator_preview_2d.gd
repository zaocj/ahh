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
##
## Two targeting modes:
##   DIRECTION  arrows and bullets: only the drag's *angle* matters, the effect
##              reaches out to `max_range` (the classic tap-to-auto-aim shot)
##   POSITION   thrown/ground skills (grenade, sigil): the drag's *length* is the
##              throw distance, so the player picks a spot inside the reach ring
##              and the result context carries `target_position`
##
## Lifecycle invariant: the strategy owns its indicator nodes (one for DIRECTION,
## plus a reach ring for POSITION) and only `cancel()` (or a new `begin()`) frees
## them. The plugin never ends a preview on its own and keeps one `_indicator`
## reference per definition, so any second `begin()` without a `cancel()` in
## between would orphan the previous nodes on the map permanently - hence the
## defensive release at the top of `begin()`.

enum Targeting {
	DIRECTION, ## Aim a direction; the effect travels `max_range`.
	POSITION, ## Pick a landing point inside the reach ring.
}

enum DefaultAim {
	FACING, ## Where the caster is already looking.
	TO_TARGET, ## Towards the nearest member of `target_group`.
	AWAY_FROM_TARGET, ## Away from it, e.g. a disengage dash.
}

@export_group("Visuals")
## Indicator look; the same generic resource the project always used.
@export var indicator_data: SkillIndicatorData
## Reach ring drawn around the caster for POSITION skills (a CIRCLE whose radius is
## `max_range`); leave empty for direction skills.
@export var range_indicator_data: SkillIndicatorData

@export_group("Targeting")
@export var targeting: Targeting = Targeting.DIRECTION
## Pointer offset (pixels) that means a full-distance throw, so the conversion
## stays independent of the HUD button's size.
@export var full_drag_pixels: float = 240.0

@export_group("Default Direction")
@export var default_aim: DefaultAim = DefaultAim.TO_TARGET
@export var target_group: StringName = &"enemies"
## Direction skills reach this far; POSITION skills may be aimed inside this radius.
@export var max_range: float = 480.0

## NOTE: the plugin keeps preview state on the definition resource, so a strategy
## instance can only serve one caster at a time. `AbilityLoadout2D.private_definition()`
## therefore gives every caster its own copy of the definition and of this strategy
## (see AGENTS.md pitfall 21); the state below is what that isolation protects.
var _caster: Node2D = null
var _indicator: SkillIndicator = null
## Reach ring for POSITION skills (centred on the caster); null for direction skills.
var _range_indicator: SkillIndicator = null
var _direction: Vector2 = Vector2.RIGHT
## Landing point for POSITION skills, kept inside `max_range` of the caster.
var _target_position: Vector2 = Vector2.ZERO
var _active: bool = false
var _cancelled: bool = false

func begin(caster: Node, _ability_instance: GameplayAbilityInstance, _extra_context: Dictionary = {}) -> void:
	# Re-begin without a cancel would leak the previous indicator (the field below
	# would be overwritten), so release whatever we still own first.
	_release_indicator()
	_caster = caster as Node2D
	_active = _caster != null
	_cancelled = false
	_direction = _default_direction()
	_target_position = _default_target_position()
	_indicator = _create_indicator(_caster)
	if targeting == Targeting.POSITION and range_indicator_data != null:
		_range_indicator = _create_indicator(_caster)
	_refresh_indicator()

func update(_delta: float, input_context: Dictionary = {}) -> void:
	if not _active:
		return
	var aimed: Variant = input_context.get("aim_direction", Vector2.ZERO)
	if aimed is Vector2 and (aimed as Vector2) != Vector2.ZERO:
		var offset := aimed as Vector2
		_direction = offset.normalized()
		if targeting == Targeting.POSITION and is_instance_valid(_caster):
			# Drag length = throw distance: `full_drag_pixels` of drag is max_range.
			var reach := clampf(offset.length() / maxf(full_drag_pixels, 1.0), 0.0, 1.0) * max_range
			_target_position = _clamp_to_range(_caster.global_position + _direction * reach)
	_refresh_indicator()

func is_targeting() -> bool:
	return _active

## Not overridden: the base class returns true, which is the right answer for a
## controller-driven preview - the result context is always available and the
## game decides when to confirm it. Reporting `_active` here would instead claim
## the preview is finished the moment it starts.

func is_cancelled() -> bool:
	return _cancelled

func cancel() -> void:
	_active = false
	_cancelled = true
	_release_indicator()

## Drops every runtime field without touching nodes.
##
## Called on a freshly duplicated strategy: `Resource.duplicate()` can bring the
## source's `_indicator`/`_caster` references along, and a copy that "owns"
## another caster's indicator would free it on its first begin().
func forget_state() -> void:
	_caster = null
	_indicator = null
	_range_indicator = null
	_direction = Vector2.RIGHT
	_target_position = Vector2.ZERO
	_active = false
	_cancelled = false

## Handed to the ability as its activation context; the behavior tree reads
## target_direction.
##
## `targets` is always present (empty) because AbilityNodeBase._get_target_list
## assigns context[target_key] into a typed Array[Node]: a missing key (null)
## aborts that tick. Aiming does not pick targets, the tree's target search does.
func get_result_context() -> Dictionary:
	var targets: Array[Node] = []
	if targeting == Targeting.POSITION and is_instance_valid(_caster):
		return {
			"target_position": _target_position,
			# Derived, so a position skill that fires a straight projectile still works.
			"target_direction": (_target_position - _caster.global_position).normalized(),
			"target_type": "position",
			"targets": targets,
		}
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
	# Named and grouped so a stray indicator is visible in the debugger and can be
	# asserted on: `skill_indicators` must be empty whenever nothing is aiming.
	indicator.name = "SkillIndicator"
	indicator.add_to_group(&"skill_indicators")
	# Lives in world space (top_level), so add it next to the arena, not to the caster.
	# `force_readable_name`: the previous indicator may still be waiting for its
	# deferred free, and the live one should keep the readable name, not the
	# dying one.
	caster.get_tree().current_scene.add_child(indicator, true)
	return indicator

## Frees the indicators, if any. The single place that ends their life.
func _release_indicator() -> void:
	for indicator: SkillIndicator in [_indicator, _range_indicator]:
		if is_instance_valid(indicator):
			indicator.hide_indicator()
			indicator.queue_free()
	_indicator = null
	_range_indicator = null

## Clamps `point` into the reach ring around the caster.
func _clamp_to_range(point: Vector2) -> Vector2:
	if not is_instance_valid(_caster):
		return point
	var offset := point - _caster.global_position
	var distance := offset.length()
	if distance <= max_range or distance <= 0.0:
		return point
	return _caster.global_position + offset / distance * max_range

## Where a tap lands. For POSITION skills aiming at a target that is the target's own
## position (so a tap drops the blast on it), otherwise the far edge of the reach.
func _default_target_position() -> Vector2:
	if not is_instance_valid(_caster):
		return Vector2.ZERO
	if targeting == Targeting.POSITION and default_aim == DefaultAim.TO_TARGET:
		var offset := Targets.offset_to_nearest(_caster, target_group)
		if offset != Vector2.ZERO:
			return _clamp_to_range(_caster.global_position + offset)
	return _clamp_to_range(_caster.global_position + _default_direction() * max_range)

func _refresh_indicator() -> void:
	if _indicator == null or not is_instance_valid(_indicator):
		return
	# A caster that left the tree (death, respawn) can no longer aim: drop the
	# preview instead of leaving a frozen indicator behind.
	if not is_instance_valid(_caster) or not _caster.is_inside_tree():
		cancel()
		return
	if targeting == Targeting.POSITION:
		# Two visuals: where the effect lands, and how far the player may reach.
		_indicator.rotation = 0.0
		_indicator.global_position = _target_position
		_indicator.show_indicator(indicator_data)
		if _range_indicator != null and is_instance_valid(_range_indicator):
			_range_indicator.rotation = 0.0
			_range_indicator.global_position = _caster.global_position
			_range_indicator.show_indicator(range_indicator_data)
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
