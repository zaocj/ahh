extends Node
## Combat event bus: gameplay reports what happened, presentation reacts.
##
## The plugin has its own bus (`AbilityEventBus`), but its damage payload carries
## the instigator and the amount - not the victim or a position - and feedback
## needs to know *where* to draw or play something. So this is the game's own,
## deliberately tiny hub.
##
## Direction of the dependency matters: gameplay code (entities, routers, the match
## director) only ever *reports*; it never knows about damage numbers, sounds or
## camera shake. Feedback nodes subscribe here, so adding a new effect means adding
## a subscriber, not touching gameplay (AGENTS.md: presentation reacts to gameplay).
##
## Registered as the `CombatEvents` autoload, see project.godot.

## `victim` lost health. `amount` is the damage that actually got through.
signal damaged(victim: Node2D, amount: float, source: Node)
## `entity` died; its removal may follow in the same frame.
signal died(entity: Node2D, source: Node)
## A caster successfully activated an ability.
signal ability_cast(caster: Node2D, ability_id: StringName)
## The match reached a result; `result` is a MatchDirector.Result value (kept as
## int so this bus does not depend on core/battle).
signal match_finished(result: int)

func report_damage(victim: Node2D, amount: float, source: Node = null) -> void:
	# Healing and blocked hits must not produce hit feedback.
	if amount <= 0.0:
		return
	damaged.emit(victim, amount, source)

func report_death(entity: Node2D, source: Node = null) -> void:
	died.emit(entity, source)

func report_cast(caster: Node2D, ability_id: StringName) -> void:
	ability_cast.emit(caster, ability_id)

func report_match_finished(result: int) -> void:
	match_finished.emit(result)
