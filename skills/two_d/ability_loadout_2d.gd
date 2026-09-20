extends Resource
class_name AbilityLoadout2D
## The abilities a caster has, in HUD slot order.
##
## Keeps "which skills does this entity have" in data (and out of the router),
## and gives per-slot presentation a place to grow later.

@export var abilities: Array[GameplayAbilityDefinition] = []
