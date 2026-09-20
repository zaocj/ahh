extends Node
## One-off authoring scene for the ability data of this project.
##
## The plugin's abilities are nested resources (features + preview strategy +
## behavior tree), so they are generated here instead of being hand-written.
## Run:  godot --headless --path . res://skills/data/build/generate_ability_data.tscn
##
## It must run as a *scene* (not --script): the plugin's scripts use its autoload
## singletons as global identifiers, which only resolve in a normal project run.
##
## After the first run the .tres files are normal project resources: edit them in
## the editor. Re-running this scene overwrites them.

const ROOT := "res://skills/data/"
const PROJECTILE_SCENE := "res://entities/projectile/projectile.tscn"
const FIELD_SCENE := "res://entities/magic_field/magic_field.tscn"

# shared
const HEALTH_VITAL := ROOT + "shared/vitals/health.tres"
const MAX_HEALTH_ATTR := ROOT + "shared/attributes/max_health.tres"

func _ready() -> void:
	_generate_attributes_and_vitals()
	_generate_effects_and_statuses()
	_generate_tags()
	_generate_shot()
	_generate_dash()
	_generate_frost()
	_generate_bomb()
	_generate_field()
	_generate_heal()
	_generate_loadout()
	_generate_enemy_bolt()
	_generate_enemy_loadout()
	print("generate_ability_data: done")
	get_tree().quit(0)

#region ========== attributes / vitals ==========
func _generate_attributes_and_vitals() -> void:
	var max_health := GameplayAttribute.new()
	max_health.attribute_id = &"max_health"
	max_health.attribute_display_name = "Max Health"
	max_health.min_value = 0.0
	_save(max_health, MAX_HEALTH_ATTR)

	var attack := GameplayAttribute.new()
	attack.attribute_id = &"attack"
	attack.attribute_display_name = "Attack"
	attack.min_value = 0.0
	_save(attack, ROOT + "shared/attributes/attack.tres")

	var defense := GameplayAttribute.new()
	defense.attribute_id = &"defense"
	defense.attribute_display_name = "Defense"
	defense.min_value = 0.0
	_save(defense, ROOT + "shared/attributes/defense.tres")

	var health := HealthVital.new()
	health.vital_id = &"health"
	health.display_name = "Health"
	health.max_value_attribute = &"max_health"
	_save(health, HEALTH_VITAL)

	# Entity stat blocks: attributes + vitals for the plugin's vitals component.
	_save(_stat_block(max_health, health), ROOT + "shared/vitals/enemy_stats.tres")
	_save(_stat_block(max_health, health), ROOT + "shared/vitals/player_stats.tres")

func _stat_block(max_health: GameplayAttribute, health: HealthVital) -> StatBlock2D:
	var attributes := GameplayAttributeSet.new()
	attributes.attributes = {max_health: 100.0}
	var stats := StatBlock2D.new()
	var sets: Array[GameplayAttributeSet] = [attributes]
	var vitals: Array[GameplayVital] = [health]
	stats.attribute_sets = sets
	stats.vitals = vitals
	return stats
#endregion

#region ========== tags ==========
## The project's tag vocabulary. Status data references these ids
## ("status.frozen"), and the plugin's TagManager only knows the tags it was
## given: unregistered ones make add_tag/remove_tag warn and do nothing, which
## would also break any effect filter looking for them. main.gd registers this
## directory at startup.
##
## Flat on purpose - no parent_tag_id: the plugin's initialize() marks itself
## initialized *before* registering, so a child can be registered before its
## parent and lose the link (plus a warning). See AGENTS.md pitfall 17.
func _generate_tags() -> void:
	_save(_tag(&"status", "Status"), ROOT + "shared/tags/status.tres")
	_save(_tag(&"status.frozen", "Frozen"), ROOT + "shared/tags/status.frozen.tres")
	_save(_tag(&"state", "State"), ROOT + "shared/tags/state.tres")
	_save(_tag(&"state.frozen", "Frozen"), ROOT + "shared/tags/state.frozen.tres")

func _tag(id: StringName, display_name: String) -> GameplayTag:
	var tag := GameplayTag.new()
	tag.id = id
	tag.display_name = display_name
	return tag
#endregion

#region ========== effects / statuses ==========
func _generate_effects_and_statuses() -> void:
	var flat_10 := FlatDamageLogic.new()
	flat_10.damage_amount = 10.0
	_save(flat_10, ROOT + "shared/effects/flat_damage_10.tres")

	var flat_5 := FlatDamageLogic.new()
	flat_5.damage_amount = 5.0
	_save(flat_5, ROOT + "shared/effects/flat_damage_5.tres")

	var flat_8 := FlatDamageLogic.new()
	flat_8.damage_amount = 8.0
	_save(flat_8, ROOT + "shared/effects/flat_damage_8.tres")

	var flat_25 := FlatDamageLogic.new()
	flat_25.damage_amount = 25.0
	_save(flat_25, ROOT + "shared/effects/flat_damage_25.tres")

	_save(_damage_effect(flat_10), ROOT + "shared/effects/bullet_damage.tres")
	_save(_damage_effect(flat_5), ROOT + "shared/effects/frost_damage.tres")
	_save(_damage_effect(flat_8), ROOT + "shared/effects/field_damage.tres")
	_save(_damage_effect(flat_25), ROOT + "shared/effects/explosion_damage.tres")

	var heal := GE_ModifyVital.new()
	heal.vital_id = &"health"
	heal.amount = 30.0
	_save(heal, ROOT + "shared/effects/heal_30.tres")

	# Freeze: the enemy stops walking while it has this status (see enemy.gd).
	var frozen := GameplayStatusData.new()
	frozen.status_id = &"frozen"
	frozen.status_display_name = "Frozen"
	frozen.status_description = "Cannot move."
	frozen.duration = 1.5
	frozen.tags = [&"status.frozen", &"state.frozen"]
	_save(frozen, ROOT + "shared/statuses/frozen.tres")

	var apply_frozen := GE_ApplyStatus.new()
	apply_frozen.status_data = frozen
	apply_frozen.stacks = 1
	_save(apply_frozen, ROOT + "shared/effects/apply_frozen.tres")

func _damage_effect(strategy: DamageLogicStrategy) -> GE_ApplyDamage:
	var effect := GE_ApplyDamage.new()
	effect.damage_strategy = strategy
	effect.vital_id = &"health"
	return effect
#endregion

#region ========== skills ==========
func _generate_shot() -> void:
	var bullet := ProjectileData2D.new()
	bullet.speed = 520.0
	bullet.max_distance = 480.0
	bullet.projectile_scene = load(PROJECTILE_SCENE)
	var payload: Array[GameplayEffect] = [load(ROOT + "shared/effects/bullet_damage.tres")]
	bullet.payload_effects = payload
	_save(bullet, ROOT + "player/shot/bullet.tres")

	_save(_arrow_indicator(480.0, 14.0, Color(0.98, 0.72, 0.25, 0.2), Color(1.0, 0.85, 0.45, 0.9)),
		ROOT + "player/shot/indicator.tres")
	_save(_directional_preview(ROOT + "player/shot/indicator.tres", IndicatorPreview2D.DefaultAim.TO_TARGET, 480.0),
		ROOT + "player/shot/preview.tres")

	_save(_ability(&"shot", "Shot", "Bullet straight ahead; tap auto-aims at the nearest enemy.",
		1.0, [ROOT + "player/shot/preview.tres"], _tree([_commit_cooldown(), _spawn_projectile(bullet)])),
		ROOT + "player/shot/shot.tres")

func _generate_dash() -> void:
	_save(_arrow_indicator(168.0, 8.0, Color(0.42, 0.86, 0.55, 0.2), Color(0.55, 0.95, 0.68, 0.9)),
		ROOT + "player/dash/indicator.tres")
	_save(_directional_preview(ROOT + "player/dash/indicator.tres", IndicatorPreview2D.DefaultAim.AWAY_FROM_TARGET, 168.0),
		ROOT + "player/dash/preview.tres")

	var move := GE_Dash2D.new()
	move.distance = 168.0
	move.duration = 0.16
	var dash_effects: Array[GameplayEffect] = [move]

	_save(_ability(&"dash", "Dash", "Short dash along the aim; tap dashes away from the nearest enemy.",
		2.0, [ROOT + "player/dash/preview.tres"],
		_tree([_commit_cooldown(), _self_target_search(), _apply_effects("targets", dash_effects)])),
		ROOT + "player/dash/dash.tres")

func _generate_frost() -> void:
	var bolt := ProjectileData2D.new()
	bolt.speed = 560.0
	bolt.max_distance = 480.0
	bolt.projectile_scene = load(PROJECTILE_SCENE)
	var payload: Array[GameplayEffect] = [
		load(ROOT + "shared/effects/frost_damage.tres"),
		load(ROOT + "shared/effects/apply_frozen.tres"),
	]
	bolt.payload_effects = payload
	_save(bolt, ROOT + "player/frost/bolt.tres")

	_save(_arrow_indicator(480.0, 12.0, Color(0.55, 0.8, 1.0, 0.22), Color(0.75, 0.92, 1.0, 0.95)),
		ROOT + "player/frost/indicator.tres")
	_save(_directional_preview(ROOT + "player/frost/indicator.tres", IndicatorPreview2D.DefaultAim.TO_TARGET, 480.0),
		ROOT + "player/frost/preview.tres")

	_save(_ability(&"frost", "Frost", "Icy bolt: 5 damage and freezes the target for 1.5s.",
		1.5, [ROOT + "player/frost/preview.tres"], _tree([_commit_cooldown(), _spawn_projectile(bolt)])),
		ROOT + "player/frost/frost.tres")

func _generate_bomb() -> void:
	# The grenade: a lobbed throw that lands on the spot the player picked inside
	# the reach ring, then blasts a short-lived damage field (the same MagicField2D
	# used as a lasting zone, only shorter and louder).
	const THROW_RANGE := 420.0
	var explosion := MagicFieldData2D.new()
	explosion.duration = 0.3
	explosion.tick_interval = 0.0
	# Blast radius: the "small area" the player aims at inside the reach ring.
	explosion.radius = 95.0
	explosion.color = Color(1.0, 0.55, 0.2, 0.3)
	explosion.target_group = &"enemies"
	explosion.field_scene = load(FIELD_SCENE)
	var blast: Array[GameplayEffect] = [load(ROOT + "shared/effects/explosion_damage.tres")]
	explosion.payload_effects = blast
	_save(explosion, ROOT + "player/bomb/explosion.tres")

	var bomb := ProjectileData2D.new()
	bomb.speed = 520.0
	bomb.max_distance = THROW_RANGE
	bomb.projectile_scene = load(PROJECTILE_SCENE)
	bomb.impact_field = explosion
	# Lobbed: it sails over whatever is in the way and only goes off on landing.
	bomb.lob = true
	bomb.lob_height = 32.0
	bomb.spin_speed = 15.0
	_save(bomb, ROOT + "player/bomb/bomb.tres")

	# Blast circle: where the blast will land (radius = blast radius).
	var indicator := SkillIndicatorData.new()
	indicator.shape = SkillIndicatorData.Shape.CIRCLE
	indicator.length = 95.0
	indicator.fill_color = Color(1.0, 0.55, 0.2, 0.14)
	indicator.outline_color = Color(1.0, 0.65, 0.3, 0.95)
	_save(indicator, ROOT + "player/bomb/indicator.tres")

	# Reach ring: the radius the player may choose a spot inside, drawn around the
	# caster while aiming. Faint, because it is only a range hint.
	var reach := SkillIndicatorData.new()
	reach.shape = SkillIndicatorData.Shape.CIRCLE
	reach.length = THROW_RANGE
	reach.fill_color = Color(0.98, 0.72, 0.25, 0.05)
	reach.outline_color = Color(0.98, 0.78, 0.4, 0.35)
	_save(reach, ROOT + "player/bomb/range.tres")

	_save(_ground_preview(ROOT + "player/bomb/indicator.tres", ROOT + "player/bomb/range.tres", THROW_RANGE),
		ROOT + "player/bomb/preview.tres")

	_save(_ability(&"bomb", "Bomb", "Throw a grenade: pick a spot inside the ring (tap = nearest enemy), it lands there and blasts 25 damage in 95px.",
		2.0, [ROOT + "player/bomb/preview.tres"],
		_tree([_commit_cooldown(), _spawn_projectile(bomb, "target_position")])),
		ROOT + "player/bomb/bomb_skill.tres")

func _generate_field() -> void:
	var zone := MagicFieldData2D.new()
	zone.duration = 5.0
	zone.tick_interval = 0.8
	zone.radius = 110.0
	zone.color = Color(0.55, 0.35, 0.95, 0.25)
	zone.target_group = &"enemies"
	zone.field_scene = load(FIELD_SCENE)
	var ticks: Array[GameplayEffect] = [load(ROOT + "shared/effects/field_damage.tres")]
	zone.payload_effects = ticks
	_save(zone, ROOT + "player/field/zone.tres")

	var indicator := SkillIndicatorData.new()
	indicator.shape = SkillIndicatorData.Shape.CIRCLE
	indicator.length = 110.0
	indicator.fill_color = Color(0.55, 0.35, 0.95, 0.18)
	indicator.outline_color = Color(0.75, 0.55, 1.0, 0.95)
	_save(indicator, ROOT + "player/field/indicator.tres")
	_save(_directional_preview(ROOT + "player/field/indicator.tres", IndicatorPreview2D.DefaultAim.TO_TARGET, 380.0),
		ROOT + "player/field/preview.tres")

	_save(_ability(&"field", "Sigil", "Place a magic sigil: 8 damage every 0.8s for 5s inside 110px.",
		6.0, [ROOT + "player/field/preview.tres"], _tree([_commit_cooldown(), _spawn_field(zone)])),
		ROOT + "player/field/field.tres")

func _generate_heal() -> void:
	var heal_effects: Array[GameplayEffect] = [load(ROOT + "shared/effects/heal_30.tres")]
	# No preview strategy: healing yourself needs no aiming, so the router casts it
	# straight from a button tap (the instant path).
	_save(_ability(&"heal", "Heal", "Restore 30 health to yourself.", 4.0, [],
		_tree([_commit_cooldown(), _self_target_search(), _apply_effects("targets", heal_effects)])),
		ROOT + "player/heal/heal.tres")
#endregion

#region ========== loadout (slot 0 is swappable from the drawer) ==========
func _generate_loadout() -> void:
	var shot := load(ROOT + "player/shot/shot.tres") as GameplayAbilityDefinition
	var dash := load(ROOT + "player/dash/dash.tres") as GameplayAbilityDefinition
	var frost := load(ROOT + "player/frost/frost.tres") as GameplayAbilityDefinition
	var bomb := load(ROOT + "player/bomb/bomb_skill.tres") as GameplayAbilityDefinition
	var field := load(ROOT + "player/field/field.tres") as GameplayAbilityDefinition
	var heal := load(ROOT + "player/heal/heal.tres") as GameplayAbilityDefinition

	var loadout := AbilityLoadout2D.new()
	var equipped: Array[GameplayAbilityDefinition] = [shot, dash]
	var inventory: Array[GameplayAbilityDefinition] = [shot, frost, bomb, field, heal]
	loadout.abilities = equipped
	loadout.inventory = inventory
	_save(loadout, ROOT + "player/loadout.tres")
#endregion

#region ========== enemy skills (cast by AiAbilityRouter, never previewed) ==========
func _generate_enemy_bolt() -> void:
	var bolt := ProjectileData2D.new()
	# Slower than the player's bullet: the player is meant to dodge it.
	bolt.speed = 330.0
	bolt.max_distance = 560.0
	bolt.projectile_scene = load(PROJECTILE_SCENE)
	# Enemy fire only hurts the player: an Area2D cannot tell friend from foe, so
	# the projectile filters the bodies it may damage by group.
	bolt.target_group = &"players"
	var payload: Array[GameplayEffect] = [load(ROOT + "shared/effects/bullet_damage.tres")]
	bolt.payload_effects = payload
	_save(bolt, ROOT + "enemy/bolt/bolt.tres")

	# No preview strategy: an AI aims through the cast context, so it never touches
	# the preview strategy resource that every caster of a definition shares.
	_save(_ability(&"bolt", "Bolt", "Enemy shot: 10 damage to whoever it hits.",
		1.4, [], _tree([_commit_cooldown(), _spawn_projectile(bolt)])),
		ROOT + "enemy/bolt/bolt_skill.tres")

func _generate_enemy_loadout() -> void:
	var bolt := load(ROOT + "enemy/bolt/bolt_skill.tres") as GameplayAbilityDefinition
	var loadout := AbilityLoadout2D.new()
	var equipped: Array[GameplayAbilityDefinition] = [bolt]
	loadout.abilities = equipped
	loadout.inventory = equipped
	_save(loadout, ROOT + "enemy/loadout.tres")
#endregion

#region ========== builders ==========
func _ability(id: StringName, name: String, description: String, cooldown: float,
		preview_paths: Array, tree: GAS_BTNode) -> GameplayAbilityDefinition:
	var cooldown_feature := CooldownFeature.new()
	cooldown_feature.cooldown_duration = cooldown
	var features: Array[GameplayAbilityFeature] = [cooldown_feature]

	var ability := GameplayAbilityDefinition.new()
	ability.ability_id = id
	ability.ability_name = name
	ability.description = description
	ability.preview_strategy = load(preview_paths[0]) if not preview_paths.is_empty() else null
	ability.features = features
	ability.execution_tree = tree
	return ability

func _tree(children: Array[GAS_BTNode]) -> GAS_BTSequence:
	var sequence := GAS_BTSequence.new()
	sequence.node_id = &"ability_sequence"
	sequence.children = children
	return sequence

func _commit_cooldown() -> AbilityNodeCommitCooldown:
	var commit := AbilityNodeCommitCooldown.new()
	commit.node_id = &"commit_cooldown"
	return commit

func _self_target_search() -> AbilityNodeTargetSearch:
	var search := AbilityNodeTargetSearch.new()
	search.node_id = &"self_target"
	search.strategy = SelfTargetingStrategy.new()
	search.write_to_key = "targets"
	search.fail_if_empty = true
	return search

func _apply_effects(target_key: String, effects: Array[GameplayEffect]) -> AbilityNodeApplyEffect:
	var apply := AbilityNodeApplyEffect.new()
	apply.node_id = &"apply_effect"
	apply.effects = effects
	apply.target_key = target_key
	return apply

func _spawn_projectile(data: ProjectileData2D, landing_key: String = "") -> AbilityNodeSpawnProjectile2D:
	var spawn := AbilityNodeSpawnProjectile2D.new()
	spawn.node_id = &"spawn_projectile"
	spawn.projectile_data = data
	spawn.direction_key = "target_direction"
	# Thrown skills land on the point the preview picked; shots just fly a direction.
	spawn.target_position_key = landing_key
	return spawn

func _spawn_field(data: MagicFieldData2D) -> AbilityNodeSpawnMagicField2D:
	var spawn := AbilityNodeSpawnMagicField2D.new()
	spawn.node_id = &"spawn_field"
	spawn.field_data = data
	return spawn

func _arrow_indicator(length: float, width: float, fill: Color, outline: Color) -> SkillIndicatorData:
	var indicator := SkillIndicatorData.new()
	indicator.shape = SkillIndicatorData.Shape.ARROW
	indicator.length = length
	indicator.width = width
	indicator.head_length = maxf(24.0, length * 0.2)
	indicator.fill_color = fill
	indicator.outline_color = outline
	return indicator

## Preview for a thrown/ground skill: a reach ring around the caster plus a blast
## circle the player places inside it (POSITION targeting).
func _ground_preview(indicator_path: String, range_path: String, max_range: float) -> IndicatorPreview2D:
	var preview := IndicatorPreview2D.new()
	preview.targeting = IndicatorPreview2D.Targeting.POSITION
	preview.indicator_data = load(indicator_path)
	preview.range_indicator_data = load(range_path)
	preview.default_aim = IndicatorPreview2D.DefaultAim.TO_TARGET
	preview.target_group = &"enemies"
	preview.max_range = max_range
	return preview

func _directional_preview(indicator_path: String, aim: int, max_range: float) -> IndicatorPreview2D:
	var preview := IndicatorPreview2D.new()
	preview.indicator_data = load(indicator_path)
	preview.default_aim = aim
	preview.target_group = &"enemies"
	preview.max_range = max_range
	return preview
#endregion

func _save(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# Keep the uid this path already had. The editor (and every .tscn/.tres that
	# references this file as uid://...) knows that id, but ResourceSaver outside the
	# editor writes **no** uid for a plain resource - which is how referencing files
	# end up with "invalid UID ... using text path instead" warnings after a
	# regeneration. The uid lives in the file header, so it survives a fresh clone.
	var uid := ResourceLoader.get_resource_uid(path)
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		push_error("Failed to save %s (%d)" % [path, error])
		return
	if uid != ResourceUID.INVALID_ID:
		_restore_uid(path, ResourceUID.id_to_text(uid))
	print("  wrote ", path)

## Puts ` uid="uid://..."` back into the `[gd_resource ...]` header line.
func _restore_uid(path: String, uid: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var lines := file.get_as_text().split("\n")
	file.close()
	if lines.is_empty() or not lines[0].begins_with("[gd_resource") or lines[0].contains("uid=\""):
		return
	if not lines[0].ends_with("]"):
		return
	lines[0] = lines[0].substr(0, lines[0].length() - 1) + " uid=\"%s\"]" % uid
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		push_warning("Could not restore the uid of %s" % path)
		return
	out.store_string("\n".join(lines))
	out.close()
