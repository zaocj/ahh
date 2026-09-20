extends Node
class_name AiAbilityRouter
## Drives a caster's ability loadout without pointer input: casts what it has at
## the nearest member of `target_group` as soon as the ability is off cooldown.
##
## The AI counterpart of AbilityInputRouter, and deliberately not a skill: it only
## decides *when* and *in which direction*, while the ability's features (cooldown)
## and behavior tree decide what actually happens. Both routers therefore hand the
## plugin the same context shape, and a new AI caster is a loadout + this node.
##
## It never requests an aim preview - an AI aims with its own logic, not with a
## player-facing indicator - which as a bonus keeps it away from the preview
## strategy resource that is shared by every caster of one ability definition
## (see AGENTS.md pitfall 15).
##
## Threat/facing state stays with the entity: this node reads `facing` on the
## caster if it has one, and never writes game state other than the cast itself.

## Emitted after an ability was successfully activated.
signal ability_activated(ability_id: StringName)

## Abilities this caster may use; slot order is also the try order.
@export var loadout: AbilityLoadout2D
## Group the caster shoots at.
@export var target_group: StringName = &"players"
## Only cast when the target is inside this distance; 0 = no range limit.
@export var cast_range: float = 420.0
## Seconds before the first cast, so a match does not open with a shot in the face.
@export var initial_delay: float = 0.8
## Random aim error in degrees; 0 makes the AI perfectly accurate (deterministic).
@export var aim_spread_degrees: float = 0.0
## Statuses that stop the caster from acting - counterplay: a frozen caster cannot
## shoot, which is what makes the frost skill worth casting on it.
@export var silence_statuses: Array[StringName] = [&"frozen"]

const STATUS_COMPONENT: String = "GameplayStatusComponent"

var _caster: Node2D = null
var _component: GameplayAbilityComponent = null
## Live copy of the loadout, so swapping data at runtime never edits the .tres.
var _equipped: Array[GameplayAbilityDefinition] = []
var _elapsed: float = 0.0

func _ready() -> void:
	_caster = get_parent() as Node2D
	if _caster == null:
		push_warning("AiAbilityRouter: parent is not a Node2D, AI casting disabled.")
		return
	_component = GameplayAbilitySystem.get_component_by_interface(_caster, "GameplayAbilityComponent") as GameplayAbilityComponent
	if _component == null:
		push_warning("AiAbilityRouter: %s has no GameplayAbilityComponent." % _caster.name)
		return
	if loadout != null:
		# Per-caster copies, like the player router: an AI that later gets a
		# previewing ability must not share the strategy with other casters
		# (AGENTS.md pitfall 21).
		_equipped = loadout.private_definitions(loadout.abilities)
	for ability in _equipped:
		if is_instance_valid(ability):
			_component.learn_ability(ability)

## False once the caster is defeated; mirrors AbilityInputRouter, because the
## plugin's disable_ability() does not actually disable anything (AGENTS.md
## pitfall 16).
func _caster_can_act() -> bool:
	if _caster == null:
		return false
	if _caster.has_method("is_alive"):
		return bool(_caster.call("is_alive"))
	return true

func _process(_delta: float) -> void:
	if _component == null or _caster == null:
		return
	if not _caster_can_act():
		return
	_elapsed += _delta
	if _elapsed < initial_delay or is_silenced():
		return
	var target := Targets.nearest(_caster, target_group)
	if target == null:
		return
	var offset := target.global_position - _caster.global_position
	if cast_range > 0.0 and offset.length() > cast_range:
		return
	cast_at(offset)

## Casts the first equipped ability that is off cooldown, aiming `offset`.
## Returns true when something was cast; also usable by tests and cutscenes.
func cast_at(offset: Vector2) -> bool:
	if _component == null or offset == Vector2.ZERO:
		return false
	var direction := offset.normalized()
	if not is_zero_approx(aim_spread_degrees):
		direction = direction.rotated(deg_to_rad(randf_range(-aim_spread_degrees, aim_spread_degrees)))
	if _caster != null and "facing" in _caster:
		_caster.set("facing", direction)

	# `targets` must always be present (empty is fine): the plugin's
	# AbilityNodeBase assigns context[target_key] into a typed Array[Node], and a
	# missing key aborts that tick (AGENTS.md pitfall 10).
	var targets: Array[Node] = []
	var context := {"target_direction": direction, "targets": targets}
	for ability in _equipped:
		if not is_instance_valid(ability):
			continue
		# can_activate_ability first: the plugin push_errors when it is skipped.
		if _component.can_activate_ability(ability.ability_id) \
				and _component.try_activate_ability(ability.ability_id, context):
			CombatEvents.report_cast(_caster, ability.ability_id)
			ability_activated.emit(ability.ability_id)
			return true
	return false

## True while a status in `silence_statuses` is on the caster.
func is_silenced() -> bool:
	if _caster == null:
		return false
	var statuses := _caster.get_node_or_null(STATUS_COMPONENT) as GameplayStatusComponent
	if statuses == null:
		return false
	for status in silence_statuses:
		if statuses.has_status(status):
			return true
	return false

## Abilities currently equipped (read-only convenience for the HUD/debugging).
func equipped_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for ability in _equipped:
		if is_instance_valid(ability):
			ids.append(ability.ability_id)
	return ids
