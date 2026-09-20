extends Resource
class_name AbilityLoadout2D
## The abilities a caster has, in HUD slot order.
##
## Keeps "which skills does this entity have" in data (and out of the router),
## and gives per-slot presentation a place to grow later.

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
