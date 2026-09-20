extends Resource
class_name AbilityLoadout2D
## The abilities a caster has, in HUD slot order.
##
## Keeps "which skills does this entity have" in data (and out of the router),
## and gives per-slot presentation a place to grow later.
##
## It is also where a caster's abilities are *instantiated* for that caster: the
## plugin keeps the aim preview (indicator node, caster, aim direction) on the
## definition's `preview_strategy` resource, and a .tres holds one shared
## instance - so two casters of the same ability would fight over one indicator.
## `private_definition()` hands every caster its own copy, see AGENTS.md pitfall 21.

## Equipped abilities, slot order (slot 0 is the swappable one).
@export var abilities: Array[GameplayAbilityDefinition] = []
## Everything the player may equip from the drawer.
@export var inventory: Array[GameplayAbilityDefinition] = []

## Definition of `ability_id` in the inventory, or null.
func find_in_inventory(ability_id: StringName) -> GameplayAbilityDefinition:
	for ability in inventory:
		if is_instance_valid(ability) and ability.ability_id == ability_id:
			return ability
	return null

## A copy of `definition` that exactly one caster owns.
##
## The copy is shallow on purpose: the behavior tree, features (their cooldown
## timers live on the ability *instance* blackboard), effects, scenes and the
## indicator look stay shared resources. Only the strategy is copied, because
## that is where the plugin stashes per-caster runtime state.
func private_definition(definition: GameplayAbilityDefinition) -> GameplayAbilityDefinition:
	if not is_instance_valid(definition):
		return null
	var copy := definition.duplicate() as GameplayAbilityDefinition
	var strategy := definition.preview_strategy
	if strategy != null:
		var private_strategy := strategy.duplicate()
		# duplicate() may carry runtime fields of the source into the copy; a stale
		# indicator reference there would free another caster's node on its first
		# begin(), so game-side strategies expose `forget_state()`.
		if private_strategy.has_method("forget_state"):
			private_strategy.call("forget_state")
		copy.preview_strategy = private_strategy
	return copy

## `private_definition()` for a whole slot list.
func private_definitions(definitions: Array[GameplayAbilityDefinition]) -> Array[GameplayAbilityDefinition]:
	var copies: Array[GameplayAbilityDefinition] = []
	for definition in definitions:
		if is_instance_valid(definition):
			copies.append(private_definition(definition))
	return copies
