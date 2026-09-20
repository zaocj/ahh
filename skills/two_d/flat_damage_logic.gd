extends DamageLogicStrategy
class_name FlatDamageLogic
## Flat damage, for projectile/skill payloads that should always deal the same
## amount regardless of attack/defense attributes.
##
## The plugin's default strategy is attribute based (SimpleDamageLogic); skills
## pick this one through GE_ApplyDamage.damage_strategy.

@export var damage_amount: float = 10.0

func calculate(_target: Node, _instigator: Node, context: Dictionary) -> float:
	return maxf(0.0, damage_amount * float(context.get("damage_multiplier", 1.0)))
